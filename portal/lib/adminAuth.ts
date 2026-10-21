import { NextRequest } from 'next/server';

export function isAdminAuthenticated(request: NextRequest): boolean {
  const session = request.cookies.get('ismart_admin_session');
  const tokenHeader = request.headers.get('x-admin-token');
  return session?.value === 'authenticated_admin' || tokenHeader === 'authenticated_admin';
}
