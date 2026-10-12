import React from 'react';

export default function TopStrip({ text }: { text?: string }) {
  return (
    <div className="top-strip">
      <div className="container top-strip-inner">
        <span className="branch-pill">شبكة الفروع الرسمية (50 فرعاً)</span>
        <span>{text || 'المنظومة المعتمدة للمراسلات وتداول الملفات بين الإدارة العامة وكافة الفروع'}</span>
      </div>
    </div>
  );
}
