import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs';
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
    fileConf.fileName,
    totalFileSize,
    config
  );

  // 4. Handle Range Requests if present
  let start = 0;
  let end = totalFileSize - 1;
  const rangeHeader = request.headers.get('range');
  let isPartial = false;

  if (rangeHeader) {
    const parts = rangeHeader.replace(/bytes=/, '').split('-');
    const partialStart = parseInt(parts[0], 10);
    const partialEnd = parts[1] ? parseInt(parts[1], 10) : end;
    if (!isNaN(partialStart)) {
      start = partialStart;
    }
    if (!isNaN(partialEnd)) {
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

  // 5. Create Web ReadableStream with live kill & pause checks
  const stream = new ReadableStream({
    async start(controller) {
      let fileHandle: fs.promises.FileHandle | null = null;
      try {
        fileHandle = await fs.promises.open(absoluteFilePath, 'r');
        const buffer = Buffer.alloc(chunkSize);
        let currentPos = start;

        while (currentPos <= end) {
          // Check if session was killed or downloads were disabled by admin
          const liveConfig = getConfig();
          if (!liveConfig.globalDownloadsEnabled) {
            cleanup('aborted');
            controller.error(new Error('Emergency Stop: تم إيقاف التحميل من قبل الإدارة المركزية'));
            break;
          }

          const liveFileConf = fileKey === 'windows' ? liveConfig.windows : liveConfig.mobile;
          if (!liveFileConf.enabled) {
            cleanup('aborted');
            controller.error(new Error('تم إيقاف هذا التحميل من قبل الإدارة'));
            break;
          }

          if (isSessionAborted(session.id)) {
            cleanup('aborted');
            controller.error(new Error('تم إنهاء جلسة التحميل وفك قفل الفرع من قبل الإدارة'));
            break;
          }

          const toRead = Math.min(chunkSize, end - currentPos + 1);
          const { bytesRead } = await fileHandle.read(buffer, 0, toRead, currentPos);
          if (bytesRead === 0) {
            break;
          }

          currentPos += bytesRead;
          updateSessionProgress(session.id, bytesRead);

          // Enqueue chunk as Uint8Array
          const chunkData = new Uint8Array(buffer.buffer, buffer.byteOffset, bytesRead);
          controller.enqueue(chunkData);

          // Bandwidth Throttling delay to protect VPN connection
          if (delayMsPerChunk > 0 && currentPos <= end) {
            await new Promise((res) => setTimeout(res, delayMsPerChunk));
          }
        }

        cleanup('completed');
        try {
          controller.close();
        } catch {}
      } catch (err) {
        cleanup('aborted');
        try {
          controller.error(err);
        } catch {}
      } finally {
        if (fileHandle) {
          await fileHandle.close().catch(() => {});
        }
      }
    },
    cancel() {
      cleanup('aborted');
    },
  });

  const headers: Record<string, string> = {
    'Content-Type': 'application/octet-stream',
    'Content-Disposition': `attachment; filename="${encodeURIComponent(fileConf.fileName)}"`,
    'Content-Length': contentLength.toString(),
    'Accept-Ranges': 'bytes',
    'Cache-Control': 'no-store, no-cache, must-revalidate',
    'X-Content-Type-Options': 'nosniff',
  };

  if (isPartial) {
    headers['Content-Range'] = `bytes ${start}-${end}/${totalFileSize}`;
    return new NextResponse(stream, { status: 206, headers });
  }

  return new NextResponse(stream, { status: 200, headers });
}
