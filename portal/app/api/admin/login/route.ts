import { NextRequest, NextResponse } from 'next/server';
import { getConfig } from '@/lib/downloadManager';
import { createAdminSession } from '@/lib/adminAuth';

export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest) {
  try {
    const { pin } = await request.json();
    const config = getConfig();

    const expectedPin = String(config.adminPin || 'ismart@2026').trim();
    const providedPin = String(pin || '').trim();

    if (!providedPin || providedPin !== expectedPin) {
      return NextResponse.json(
        { success: false, message: 'رمز الدخول (PIN) غير صحيح! تأكد من الرمز وحاول مرة أخرى.' },
        { status: 401 }
      );
    }

    // Generate real secure session token
    const token = createAdminSession();

    const response = NextResponse.json({
      success: true,
      token,
      message: 'تم تسجيل الدخول بنجاح.',
    });

    response.cookies.set('ismart_admin_session', token, {
      httpOnly: true,
      secure: false, // Internal HTTP network compatibility
      sameSite: 'lax',
      path: '/',
      maxAge: 60 * 60 * 24, // 24 hours
    });

    return response;
  } catch (err: any) {
    return NextResponse.json(
      { success: false, message: 'حدث خطأ أثناء معالجة الطلب.' },
      { status: 500 }
    );
  }
}
