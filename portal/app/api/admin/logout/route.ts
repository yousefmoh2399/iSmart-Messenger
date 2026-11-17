import { NextRequest, NextResponse } from 'next/server';
import { revokeAdminSession } from '@/lib/adminAuth';

export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest) {
  const cookieToken = request.cookies.get('ismart_admin_session')?.value;
  const headerToken = request.headers.get('x-admin-token');
  revokeAdminSession(cookieToken || headerToken);

  const response = NextResponse.json({
    success: true,
    message: 'تم تسجيل الخروج بنجاح.',
  });

  response.cookies.delete('ismart_admin_session');
  return response;
}
