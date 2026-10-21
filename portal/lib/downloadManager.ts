import fs from 'fs';
import path from 'path';
import { NextRequest } from 'next/server';

export interface FileConfig {
  enabled: boolean;
  version: string;
  fileName: string;
  fileSize: string;
  filePath: string;
  directPath: string;
  googlePlayUrl?: string;
  customUrl?: string;
}

export interface VpnPolicy {
  maxConcurrentPerBranch: number;
  maxConcurrentPerIp: number;
  speedLimitKBps: number; // 0 = unlimited, otherwise KB/s
  subnetMask: string;     // '24' for 192.168.x.0/24, '16' for 192.168.0.0/16
  whitelistedSubnets: string[];
  whitelistedIps: string[];
}

export interface PortalConfig {
  adminPin: string;
  globalDownloadsEnabled: boolean;
  maintenanceMessage: string;
  windows: FileConfig;
  mobile: FileConfig;
  vpnPolicy: VpnPolicy;
  branches: Record<string, string>; // subnet -> branch name
}

export interface ActiveDownloadSession {
  id: string;
  ip: string;
  subnet: string;
  branchName: string;
  fileKey: 'windows' | 'mobile';
  fileName: string;
  startedAt: number;
  lastActiveAt: number;
  bytesTransferred: number;
  totalBytes: number;
  speedLimitKBps: number;
  status: 'downloading' | 'completed' | 'aborted';
}

const CONFIG_PATH = path.join(process.cwd(), 'data', 'portal-config.json');

// Default Fallback Config
const DEFAULT_CONFIG: PortalConfig = {
  adminPin: 'ismart@2026',
  globalDownloadsEnabled: true,
  maintenanceMessage: '',
  windows: {
    enabled: true,
    version: '1.1.15',
    fileName: 'iSmart Messenger Setup 1.1.15.exe',
    fileSize: '69.5 MB',
    filePath: 'downloads/iSmart Messenger Setup 1.1.15.exe',
    directPath: 'public/downloads/iSmart Messenger Setup 1.1.15.exe',
    customUrl: '',
  },
  mobile: {
    enabled: true,
    version: '1.0.2',
    fileName: 'iSmart Messenger.apk',
    fileSize: '64.5 MB',
    filePath: 'downloads/iSmart Messenger.apk',
    directPath: 'public/downloads/iSmart Messenger.apk',
    googlePlayUrl: 'https://play.google.com/store/apps/details?id=com.ismart.messenger',
    customUrl: '',
  },
  vpnPolicy: {
    maxConcurrentPerBranch: 1,
    maxConcurrentPerIp: 1,
    speedLimitKBps: 2048, // 2 MB/s safe limit for VPN
    subnetMask: '24',
    whitelistedSubnets: ['127.0.0.1/32'],
    whitelistedIps: ['127.0.0.1'],
  },
  branches: {
    '192.168.10.0/24': 'فرع 1',
    '192.168.11.0/24': 'فرع 2',
    '192.168.12.0/24': 'فرع 3',
  },
};

// Global in-memory map for active download sessions
// Persists across Next.js API re-evaluations via globalThis
declare global {
  // eslint-disable-next-line no-var
  var __portalActiveSessions: Map<string, ActiveDownloadSession> | undefined;
}

if (!globalThis.__portalActiveSessions) {
  globalThis.__portalActiveSessions = new Map<string, ActiveDownloadSession>();
}
const activeSessions = globalThis.__portalActiveSessions;

// Clean up stale sessions periodically (every 30s)
if (typeof setInterval !== 'undefined') {
  setInterval(() => {
    cleanupStaleSessions();
  }, 30000);
}

export function cleanupStaleSessions(): void {
  const now = Date.now();
  for (const [id, session] of Array.from(activeSessions.entries())) {
    // If no progress for more than 45 seconds, assume disconnected
    if (now - session.lastActiveAt > 45000) {
      activeSessions.delete(id);
    }
  }
}

export function getConfig(): PortalConfig {
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      const data = fs.readFileSync(CONFIG_PATH, 'utf8');
      return { ...DEFAULT_CONFIG, ...JSON.parse(data) };
    }
  } catch (err) {
    console.error('Error reading portal-config.json:', err);
  }
  return DEFAULT_CONFIG;
}

export function saveConfig(newConfig: PortalConfig): void {
  try {
    const dir = path.dirname(CONFIG_PATH);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(newConfig, null, 2), 'utf8');
  } catch (err) {
    console.error('Error writing portal-config.json:', err);
    throw err;
  }
}

export function cleanIp(ip: string): string {
  if (!ip) return '127.0.0.1';
  let clean = ip.trim();
  if (clean.startsWith('::ffff:')) {
    clean = clean.replace('::ffff:', '');
  }
  if (clean === '::1') {
    clean = '127.0.0.1';
  }
  return clean;
}

export function getClientIp(request: NextRequest): string {
  const forwarded = request.headers.get('x-forwarded-for');
  if (forwarded) {
    const first = forwarded.split(',')[0];
    return cleanIp(first);
  }
  const realIp = request.headers.get('x-real-ip');
  if (realIp) {
    return cleanIp(realIp);
  }
  const cfConnectingIp = request.headers.get('cf-connecting-ip');
  if (cfConnectingIp) {
    return cleanIp(cfConnectingIp);
  }
  return '127.0.0.1';
}

export function getSubnet(ip: string, mask: string = '24'): string {
  const parts = ip.split('.');
  if (parts.length === 4) {
    if (mask === '16') {
      return `${parts[0]}.${parts[1]}.0.0/16`;
    }
    // Default to /24
    return `${parts[0]}.${parts[1]}.${parts[2]}.0/24`;
  }
  return `${ip}/32`;
}

export function getBranchName(subnet: string, config: PortalConfig): string {
  if (config.branches && config.branches[subnet]) {
    return config.branches[subnet];
  }
  return `فرع (${subnet})`;
}

export interface CheckDownloadResult {
  allowed: boolean;
  reason?: 'disabled' | 'device_busy' | 'branch_busy' | 'maintenance';
  message?: string;
  busyIp?: string;
  busyBranch?: string;
  fileConfig?: FileConfig;
}

export function checkDownloadAllowed(
  ip: string,
  fileKey: 'windows' | 'mobile',
  config: PortalConfig
): CheckDownloadResult {
  cleanupStaleSessions();

  // 1. Global Downloads Check
  if (!config.globalDownloadsEnabled) {
    return {
      allowed: false,
      reason: 'maintenance',
      message: config.maintenanceMessage || 'تم إيقاف التحميلات مؤقتاً لأعمال الصيانة والتحديثات من قبل الإدارة.',
    };
  }

  // 2. Specific File Enabled Check
  const fileConf = fileKey === 'windows' ? config.windows : config.mobile;
  if (!fileConf || !fileConf.enabled) {
    return {
      allowed: false,
      reason: 'disabled',
      message: `تم إيقاف تحميل ${fileKey === 'windows' ? 'نسخة الكمبيوتر' : 'نسخة الموبايل'} مؤقتاً من قبل الإدارة.`,
    };
  }

  // 3. Check Whitelists
  const isIpWhitelisted = config.vpnPolicy.whitelistedIps?.includes(ip);
  const subnet = getSubnet(ip, config.vpnPolicy.subnetMask);
  const isSubnetWhitelisted = config.vpnPolicy.whitelistedSubnets?.includes(subnet);

  if (isIpWhitelisted || isSubnetWhitelisted) {
    return { allowed: true, fileConfig: fileConf };
  }

  // 4. Same Device Check (Don't allow same IP to start multiple concurrent downloads)
  const activeForIp = Array.from(activeSessions.values()).filter(
    (s) => s.ip === ip && s.status === 'downloading'
  );
  if (activeForIp.length >= config.vpnPolicy.maxConcurrentPerIp) {
    return {
      allowed: false,
      reason: 'device_busy',
      busyIp: ip,
      message: 'جهازك يقوم بالتحميل حالياً! يرجى الانتظار حتى اكتمال التحميل الأول لتجنب استهلاك سعة الاتصال.',
    };
  }

  // 5. Same Branch (Subnet) Check
  const activeForSubnet = Array.from(activeSessions.values()).filter(
    (s) => s.subnet === subnet && s.status === 'downloading'
  );
  if (activeForSubnet.length >= config.vpnPolicy.maxConcurrentPerBranch) {
    const busySession = activeForSubnet[0];
    const branchName = getBranchName(subnet, config);
    return {
      allowed: false,
      reason: 'branch_busy',
      busyIp: busySession.ip,
      busyBranch: branchName,
      message: `يوجد جهاز آخر في فرعك (${busySession.ip}) يقوم بالتحميل حالياً. تم حظر التحميل المتزامن لحماية شبكة الـ VPN من البطء. برجاء الانتظار حتى يكتمل تحميله.`,
    };
  }

  return { allowed: true, fileConfig: fileConf };
}

export function registerDownloadSession(
  ip: string,
  fileKey: 'windows' | 'mobile',
  fileName: string,
  totalBytes: number,
  config: PortalConfig
): ActiveDownloadSession {
  cleanupStaleSessions();

  const id = `dl_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
  const subnet = getSubnet(ip, config.vpnPolicy.subnetMask);
  const branchName = getBranchName(subnet, config);

  const session: ActiveDownloadSession = {
    id,
    ip,
    subnet,
    branchName,
    fileKey,
    fileName,
    startedAt: Date.now(),
    lastActiveAt: Date.now(),
    bytesTransferred: 0,
    totalBytes,
    speedLimitKBps: config.vpnPolicy.speedLimitKBps || 0,
    status: 'downloading',
  };

  activeSessions.set(id, session);
  return session;
}

export function updateSessionProgress(sessionId: string, bytesChunk: number): void {
  const session = activeSessions.get(sessionId);
  if (session) {
    session.bytesTransferred += bytesChunk;
    session.lastActiveAt = Date.now();
  }
}

export function releaseDownloadSession(sessionId: string, finalStatus: 'completed' | 'aborted' = 'completed'): void {
  const session = activeSessions.get(sessionId);
  if (session) {
    session.status = finalStatus;
    session.lastActiveAt = Date.now();
    // Remove from active list after 5 seconds to let UI see completion
    setTimeout(() => {
      activeSessions.delete(sessionId);
    }, 5000);
  }
}

export function killDownload(sessionId: string): boolean {
  if (activeSessions.has(sessionId)) {
    const session = activeSessions.get(sessionId)!;
    session.status = 'aborted';
    activeSessions.delete(sessionId);
    return true;
  }
  return false;
}

export function getActiveDownloads(): ActiveDownloadSession[] {
  cleanupStaleSessions();
  return Array.from(activeSessions.values());
}
