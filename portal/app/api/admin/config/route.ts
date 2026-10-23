import { NextRequest, NextResponse } from 'next/server';
import { isAdminAuthenticated } from '@/lib/adminAuth';
import { getConfig, saveConfig, PortalConfig } from '@/lib/downloadManager';

export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest) {
  if (!isAdminAuthenticated(request)) {
    return NextResponse.json(
      { success: false, message: 'غير مصرح بالوصول.' },
      { status: 401 }
    );
  }

  try {
    const updates = await request.json();
    const currentConfig = getConfig();

    const newConfig: PortalConfig = {
      ...currentConfig,
      ...updates,
      windows: {
        ...currentConfig.windows,
        ...(updates.windows || {}),
      },
      mobile: {
        ...currentConfig.mobile,
        ...(updates.mobile || {}),
      },
      vpnPolicy: {
        ...currentConfig.vpnPolicy,
        ...(updates.vpnPolicy || {}),
      },
      branches: {
        ...currentConfig.branches,
        ...(updates.branches || {}),
      },
    };

    saveConfig(newConfig);

    return NextResponse.json({
      success: true,
      message: 'تم حفظ الإعدادات وتطبيقها بنجاح.',
      config: newConfig,
    });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, message: err?.message || 'حدث خطأ أثناء حفظ الإعدادات.' },
      { status: 500 }
    );
  }
}
