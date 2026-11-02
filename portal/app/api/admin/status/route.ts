import { NextRequest, NextResponse } from 'next/server';
import { isAdminAuthenticated } from '@/lib/adminAuth';
import { getConfig, getActiveDownloads } from '@/lib/downloadManager';
import os from 'os';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  if (!isAdminAuthenticated(request)) {
    return NextResponse.json(
      { success: false, message: 'غير مصرح بالوصول. يرجى تسجيل الدخول.' },
      { status: 401 }
    );
  }

  const config = getConfig();
  const activeDownloads = getActiveDownloads();

  return NextResponse.json({
    success: true,
    config,
    activeDownloads,
    system: {
      uptime: Math.floor(os.uptime()),
      freeMemMB: Math.floor(os.freemem() / (1024 * 1024)),
      totalMemMB: Math.floor(os.totalmem() / (1024 * 1024)),
      serverTime: new Date().toISOString(),
    },
  });
}
