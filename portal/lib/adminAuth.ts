import { NextRequest } from 'next/server';
import crypto from 'crypto';

interface AdminSession {
  token: string;
  createdAt: number;
  lastSeen: number;
}

declare global {
  // eslint-disable-next-line no-var
  var __portalAdminSessions: Map<string, AdminSession> | undefined;
}

if (!globalThis.__portalAdminSessions) {
  globalThis.__portalAdminSessions = new Map<string, AdminSession>();
}

const adminSessions = globalThis.__portalAdminSessions;

function cleanupExpiredSessions(): void {
  const maxAge = 24 * 60 * 60 * 1000; // 24 hours
  const now = Date.now();
  for (const [token, session] of Array.from(adminSessions.entries())) {
    if (now - session.createdAt > maxAge) {
      adminSessions.delete(token);
    }
  }
}

export function createAdminSession(): string {
  cleanupExpiredSessions();
  const token = `adm_${Date.now()}_${crypto.randomBytes(16).toString('hex')}`;
  adminSessions.set(token, {
    token,
    createdAt: Date.now(),
    lastSeen: Date.now(),
  });
  return token;
}

export function revokeAdminSession(token?: string | null): void {
  if (token && adminSessions.has(token)) {
    adminSessions.delete(token);
  }
}

export function isAdminAuthenticated(request: NextRequest): boolean {
  cleanupExpiredSessions();
  const sessionCookie = request.cookies.get('ismart_admin_session')?.value;
  const tokenHeader = request.headers.get('x-admin-token');
  const token = sessionCookie || tokenHeader;

  if (!token || typeof token !== 'string') {
    return false;
  }

  const trimmedToken = token.trim();
  if (adminSessions.has(trimmedToken)) {
    const session = adminSessions.get(trimmedToken)!;
    session.lastSeen = Date.now();
    return true;
  }

  return false;
}
