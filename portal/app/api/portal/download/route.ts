import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';
import {
  getConfig,
  getClientIp,
  checkDownloadAllowed,
  findDownloadFile,
  registerDownloadSession,
  updateSessionProgress,
  releaseDownloadSession,
  isSessionAborted,
} from '@/lib/downloadManager';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const fileKey = (searchParams.get('file') || 'windows') as 'windows' | 'mobile';

  const clientIp = getClientIp(request);
  const config = getConfig();

  // 1. Verify download permissions & concurrency
  const check = checkDownloadAllowed(clientIp, fileKey, config);
  if (!check.allowed) {
    return new NextResponse(
      JSON.stringify({
        error: check.reason,
        message: check.message,
        busyIp: check.busyIp,
        busyBranch: check.busyBranch,
      }),
      {
        status: 429,
        headers: { 'Content-Type': 'application/json; charset=utf-8' },
      }
    );
  }

  const fileConf = fileKey === 'windows' ? config.windows : config.mobile;

  // 2. Resolve absolute file path safely on disk
  const absoluteFilePath = findDownloadFile(
    fileConf.directPath || fileConf.filePath,
    fileConf.fileName,
    fileKey
  );

  if (!absoluteFilePath || !fs.existsSync(absoluteFilePath)) {
    return new NextResponse(
      JSON.stringify({
        error: 'file_not_found',
        message: 'الملف المطلوب غير موجود على الخادم حالياً. يرجى مراجعة إدارة النظام.',
      }),
      { status: 404, headers: { 'Content-Type': 'application/json; charset=utf-8' } }
    );
  }

  const fileStats = fs.statSync(absoluteFilePath);
  const totalFileSize = fileStats.size;

  // 3. Register Active Download Session in Admin Monitor
  const session = registerDownloadSession(
    clientIp,
    fileKey,
    path.basename(absoluteFilePath) || fileConf.fileName,
    totalFileSize,
    config
  );

  // 4. Handle Range Requests if present
  let start = 0;
  let end = totalFileSize - 1;
  const rangeHeader = request.headers.get('range');
  let isPartial = false;

  if (rangeHeader && rangeHeader.startsWith('bytes=')) {
    const parts = rangeHeader.replace(/bytes=/, '').split('-');
    const partialStart = parseInt(parts[0], 10);
    const partialEnd = parts[1] ? parseInt(parts[1], 10) : end;
    if (!isNaN(partialStart) && partialStart >= 0 && partialStart < totalFileSize) {
      start = partialStart;
    }
    if (!isNaN(partialEnd) && partialEnd >= start && partialEnd < totalFileSize) {
      end = partialEnd;
    }
    isPartial = true;
  }

  const contentLength = end - start + 1;
  const speedLimitBytesPerSec = (config.vpnPolicy.speedLimitKBps || 0) * 1024;
  const chunkSize = 64 * 1024; // 64 KB per chunk
  const delayMsPerChunk =
    speedLimitBytesPerSec > 0 ? (chunkSize / speedLimitBytesPerSec) * 1000 : 0;

  let isCleanedUp = false;
  const cleanup = (status: 'completed' | 'aborted') => {
    if (!isCleanedUp) {
      isCleanedUp = true;
      releaseDownloadSession(session.id, status);
    }
  };

  // 5. Create Web ReadableStream using pull() with native backpressure
  // Each chunk allocates its own buffer to prevent buffer aliasing / stream corruption.
  let fileHandle: fs.promises.FileHandle | null = null;
  let currentPos = start;

  const stream = new ReadableStream({
    async start() {
      fileHandle = await fs.promises.open(absoluteFilePath, 'r');
    },

    async pull(controller) {
      if (currentPos > end) {
        cleanup('completed');
        try {
          controller.close();
        } catch {}
        if (fileHandle) {
          await fileHandle.close().catch(() => {});
          fileHandle = null;
        }
        return;
      }

      // Check if session was killed or downloads were disabled by admin
      const liveConfig = getConfig();
      if (!liveConfig.globalDownloadsEnabled) {
        cleanup('aborted');
        controller.error(new Error('Emergency Stop: تم إيقاف التحميل من قبل الإدارة المركزية'));
        if (fileHandle) {
          await fileHandle.close().catch(() => {});
          fileHandle = null;
        }
        return;
      }

      const liveFileConf = fileKey === 'windows' ? liveConfig.windows : liveConfig.mobile;
      if (!liveFileConf.enabled) {
        cleanup('aborted');
        controller.error(new Error('تم إيقاف هذا التحميل من قبل الإدارة'));
        if (fileHandle) {
          await fileHandle.close().catch(() => {});
          fileHandle = null;
        }
        return;
      }

      if (isSessionAborted(session.id)) {
        cleanup('aborted');
        controller.error(new Error('تم إنهاء جلسة التحميل وفك قفل الفرع من قبل الإدارة'));
        if (fileHandle) {
          await fileHandle.close().catch(() => {});
          fileHandle = null;
        }
        return;
      }

      try {
        if (!fileHandle) {
          fileHandle = await fs.promises.open(absoluteFilePath, 'r');
        }

        const toRead = Math.min(chunkSize, end - currentPos + 1);
        // Allocate a dedicated buffer for this chunk so it cannot be overwritten before sending
        const buffer = Buffer.alloc(toRead);
        const { bytesRead } = await fileHandle.read(buffer, 0, toRead, currentPos);

        if (bytesRead === 0) {
          cleanup('completed');
          try {
            controller.close();
          } catch {}
          if (fileHandle) {
            await fileHandle.close().catch(() => {});
            fileHandle = null;
          }
          return;
        }

        currentPos += bytesRead;
        updateSessionProgress(session.id, bytesRead);

        // Enqueue independent chunk (clean Uint8Array pointing only to this dedicated buffer)
        controller.enqueue(new Uint8Array(buffer.buffer, buffer.byteOffset, bytesRead));

        // Bandwidth Throttling delay to protect VPN connection
        if (delayMsPerChunk > 0 && currentPos <= end) {
          await new Promise((res) => setTimeout(res, delayMsPerChunk));
        }
      } catch (err) {
        cleanup('aborted');
        try {
          controller.error(err);
        } catch {}
        if (fileHandle) {
          await fileHandle.close().catch(() => {});
          fileHandle = null;
        }
      }
    },

    async cancel() {
      cleanup('aborted');
      if (fileHandle) {
        await fileHandle.close().catch(() => {});
        fileHandle = null;
      }
    },
  });

  const fileNameToServe = path.basename(absoluteFilePath) || fileConf.fileName;
  const safeAsciiName = fileNameToServe.replace(/[^\w.-]/g, '_');
  const encodedName = encodeURIComponent(fileNameToServe);

  const headers: Record<string, string> = {
    'Content-Type': 'application/octet-stream',
    'Content-Disposition': `attachment; filename="${safeAsciiName}"; filename*=UTF-8''${encodedName}`,
    'Content-Length': contentLength.toString(),
    'Accept-Ranges': 'bytes',
    'Content-Encoding': 'identity',
    'Cache-Control': 'no-store, no-cache, must-revalidate, proxy-revalidate',
    'Pragma': 'no-cache',
    'Expires': '0',
    'X-Content-Type-Options': 'nosniff',
  };

  if (isPartial) {
    headers['Content-Range'] = `bytes ${start}-${end}/${totalFileSize}`;
    return new NextResponse(stream, { status: 206, headers });
  }

  return new NextResponse(stream, { status: 200, headers });
}
