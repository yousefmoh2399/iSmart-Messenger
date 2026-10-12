import React from 'react';
import Link from 'next/link';

export default function SiteFooter() {
  return (
    <footer className="site-footer-apple">
      <div className="container">
        <ul className="footer-nav">
          <li>
            <Link href="/">الرئيسية والتحميل</Link>
          </li>
          <li>
            <Link href="/windows">دليل الكمبيوتر</Link>
          </li>
          <li>
            <Link href="/mobile">دليل الموبايل</Link>
          </li>
          <li>
            <Link href="/faq">الدعم الفني</Link>
          </li>
        </ul>
        <p>
          جميع الحقوق محفوظة &copy; 2026 iSmart Messenger Network — منظومة المراسلات المعتمدة لشبكة الفروع.
        </p>
      </div>
    </footer>
  );
}
