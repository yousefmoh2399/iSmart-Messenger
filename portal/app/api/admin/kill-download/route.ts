import { NextRequest, NextResponse } from 'next/server';
import { isAdminAuthenticated } from '@/lib/adminAuth';
import { killDownload, getActiveDownloads } from '@/lib/downloadManager';

export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest) {
  if (!isAdminAuthenticated(request)) {
    return NextResponse.json(
      { success: false, message: 'غير مصرح بالوصول.' },
      { status: 401 }
    );
  }

  try {
    const { sessionId } = await request.json();
    if (!sessionId) {
      return NextResponse.json(
        { success: false, message: 'معرف الجلسة مطلوب.' },
        { status: 400 }
      );
    }

    const killed = killDownload(sessionId);
    return NextResponse.json({
      success: true,
      message: killed
        ? 'تم إنهاء التحميل وفك قفل الفرع بنجاح.'
        : 'الجلسة غير نشطة أو انتهت بالفعل.',
      activeDownloads: getActiveDownloads(),
    });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, message: 'حدث خطأ أثناء إنهاء الجلسة.' },
      { status: 500 }
    );
  }
}
