import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';
import {
  getConfig,
  getClientIp,
  checkDownloadAllowed,
  registerDownloadSession,
  updateSessionProgress,
  releaseDownloadSession,
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
      }),
      {
        status: 429,
        headers: { 'Content-Type': 'application/json; charset=utf-8' },
      }
    );
  }

  const fileConf = fileKey === 'windows' ? config.windows : config.mobile;
  
  // Resolve absolute file path
  let absoluteFilePath = path.join(process.cwd(), fileConf.directPath || `public/downloads/${fileConf.fileName}`);
  if (!fs.existsSync(absoluteFilePath)) {
    // Try downloads directory
    absoluteFilePath = path.join(process.cwd(), 'downloads', fileConf.fileName);
  }
  if (!fs.existsSync(absoluteFilePath)) {
    // Try public downloads directory
    absoluteFilePath = path.join(process.cwd(), 'public', 'downloads', fileConf.fileName);
  }

  if (!fs.existsSync(absoluteFilePath)) {
    return new NextResponse(
      JSON.stringify({ error: 'file_not_found', message: 'الملف المطلوب غير موجود على الخادم حالياً.' }),
      { status: 404, headers: { 'Content-Type': 'application/json; charset=utf-8' } }
    );
  }

  const fileStats = fs.statSync(absoluteFilePath);
  const totalFileSize = fileStats.size;

  // 2. Register Active Download Session
  const session = registerDownloadSession(clientIp, fileKey, fileConf.fileName, totalFileSize, config);

  // 3. Handle Range Requests if present
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

  // 4. Create Web ReadableStream with pacing
  const stream = new ReadableStream({
    async start(controller) {
      let fileHandle: fs.promises.FileHandle | null = null;
      try {
        fileHandle = await fs.promises.open(absoluteFilePath, 'r');
        const buffer = Buffer.alloc(chunkSize);
        let currentPos = start;

        while (currentPos <= end) {
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
        controller.close();
      } catch (err) {
        cleanup('aborted');
        controller.error(err);
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
