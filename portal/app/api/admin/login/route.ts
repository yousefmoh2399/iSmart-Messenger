import { NextRequest, NextResponse } from 'next/server';
import { getConfig } from '@/lib/downloadManager';

export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest) {
  try {
    const { pin } = await request.json();
    const config = getConfig();

    if (!pin || String(pin).trim() !== String(config.adminPin).trim()) {
      return NextResponse.json(
        { success: false, message: 'رمز الدخول (PIN) غير صحيح!' },
        { status: 401 }
      );
    }

    // Set secure authentication cookie (secure: false for internal HTTP intranet/VPN networks)
    const response = NextResponse.json({
      success: true,
      token: 'authenticated_admin',
      message: 'تم تسجيل الدخول بنجاح.',
    });

    response.cookies.set('ismart_admin_session', 'authenticated_admin', {
      httpOnly: true,
      secure: false, // Internal HTTP network compatibility
      sameSite: 'lax',
      path: '/',
      maxAge: 60 * 60 * 24 * 7, // 7 days
    });

    return response;
  } catch (err: any) {
    return NextResponse.json(
      { success: false, message: 'حدث خطأ أثناء معالجة الطلب.' },
      { status: 500 }
    );
  }
}
