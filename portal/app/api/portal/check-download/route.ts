import { NextRequest, NextResponse } from 'next/server';
import {
  getConfig,
  getClientIp,
  getSubnet,
  getBranchName,
  checkDownloadAllowed,
} from '@/lib/downloadManager';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const fileKey = (searchParams.get('file') || 'windows') as 'windows' | 'mobile';

  const clientIp = getClientIp(request);
  const config = getConfig();
  const subnet = getSubnet(clientIp, config.vpnPolicy.subnetMask);
  const branchName = getBranchName(subnet, config);

  const check = checkDownloadAllowed(clientIp, fileKey, config);

  return NextResponse.json({
    allowed: check.allowed,
    clientIp,
    subnet,
    branchName,
    reason: check.reason,
    message: check.message,
    busyIp: check.busyIp,
    busyBranch: check.busyBranch,
    downloadUrl: check.allowed ? `/api/portal/download?file=${fileKey}` : null,
  });
}
