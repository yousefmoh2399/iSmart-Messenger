import { NextResponse } from 'next/server';
import { getConfig } from '@/lib/downloadManager';

export const dynamic = 'force-dynamic';

export async function GET() {
  const config = getConfig();
  
  // Return public safe configuration (omit admin PIN)
  return NextResponse.json({
    success: true,
    globalDownloadsEnabled: config.globalDownloadsEnabled,
    maintenanceMessage: config.maintenanceMessage,
    windows: {
      enabled: config.windows.enabled,
      version: config.windows.version,
      fileName: config.windows.fileName,
      fileSize: config.windows.fileSize,
      customUrl: config.windows.customUrl,
    },
    mobile: {
      enabled: config.mobile.enabled,
      version: config.mobile.version,
      fileName: config.mobile.fileName,
      fileSize: config.mobile.fileSize,
      googlePlayUrl: config.mobile.googlePlayUrl,
      customUrl: config.mobile.customUrl,
    },
    vpnProtectionActive: true,
    speedLimitMBps: config.vpnPolicy.speedLimitKBps ? (config.vpnPolicy.speedLimitKBps / 1024).toFixed(1) : 'unlimited',
  });
}
