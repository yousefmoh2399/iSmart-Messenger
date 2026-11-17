import { NextRequest, NextResponse } from 'next/server';
import { isAdminAuthenticated } from '@/lib/adminAuth';
import { getConfig, saveConfig } from '@/lib/downloadManager';
import fs from 'fs';
import path from 'path';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

export async function POST(request: NextRequest) {
  if (!isAdminAuthenticated(request)) {
    return NextResponse.json(
      { success: false, message: 'غير مصرح بالوصول.' },
      { status: 401 }
    );
  }

  try {
    const formData = await request.formData();
    const file = formData.get('file') as File | null;
    const type = (formData.get('type') as string) || 'windows'; // 'windows' | 'mobile'
    const version = (formData.get('version') as string) || '';

    if (!file) {
      return NextResponse.json(
        { success: false, message: 'لم يتم اختيار أي ملف للرفع.' },
        { status: 400 }
      );
    }

    const originalName = file.name;
    const bytes = await file.arrayBuffer();
    const buffer = Buffer.from(bytes);

    const downloadsDir = path.join(process.cwd(), 'public', 'downloads');
    if (!fs.existsSync(downloadsDir)) {
      fs.mkdirSync(downloadsDir, { recursive: true });
    }

    const destinationPath = path.join(downloadsDir, originalName);
    fs.writeFileSync(destinationPath, buffer);

    const config = getConfig();
    const formattedSize = formatBytes(buffer.length);

    if (type === 'windows') {
      config.windows.fileName = originalName;
      config.windows.fileSize = formattedSize;
      config.windows.directPath = `public/downloads/${originalName}`;
      config.windows.filePath = `downloads/${originalName}`;
      if (version.trim()) {
        config.windows.version = version.trim();
      }
    } else {
      config.mobile.fileName = originalName;
      config.mobile.fileSize = formattedSize;
      config.mobile.directPath = `public/downloads/${originalName}`;
      config.mobile.filePath = `downloads/${originalName}`;
      if (version.trim()) {
        config.mobile.version = version.trim();
      }
    }

    saveConfig(config);

    return NextResponse.json({
      success: true,
      message: `تم رفع ملف ${originalName} (${formattedSize}) وتحديث النظام بنجاح!`,
      config,
    });
  } catch (err: any) {
    console.error('File upload error:', err);
    return NextResponse.json(
      { success: false, message: err?.message || 'حدث خطأ أثناء رفع الملف.' },
      { status: 500 }
    );
  }
}
