import React from 'react';
import Link from 'next/link';
import TopStrip from '../components/TopStrip';
import ServerIpBar from '../components/ServerIpBar';
import VideoPlayer from '../components/VideoPlayer';
import GooglePlayIcon from '../components/GooglePlayIcon';
import { Download } from 'lucide-react';

export default function HomePage() {
  return (
    <>
      {/* Top Branch Announcement Strip */}
      <TopStrip />

      {/* Hero Section */}
      <section className="hero-wrapper" id="downloads">
        <div className="container">
          <h2 className="hero-headline">
            منظومة المراسلات الآمنة والموحدة <br />
            <span>لكافة فروع الشركة</span>
          </h2>

          {/* THE 2 BIG APPLE DOWNLOAD CARDS */}
          <div className="download-section-grid">
            {/* WINDOWS DESKTOP CARD */}
            <div className="apple-card">
              <div className="card-top">
                <span className="card-badge">أجهزة المكاتب واللابتوب</span>
                <span style={{ fontSize: '0.78rem', color: 'var(--apple-blue)', fontWeight: 700 }}>
                  Windows 7 / 10 / 11
                </span>
              </div>

              <div className="card-icon-title">
                <div className="app-icon-squircle win-icon">💻</div>
                <div className="card-heading">
                  <h3>نسخة الكمبيوتر (Desktop)</h3>
                  <p>تطبيق سطح المكتب المتكامل للموظفين</p>
                </div>
              </div>

              <div className="spec-row">
                <span className="spec-pill">الإصدار: <strong>1.1.15</strong></span>
                <span className="spec-pill">الحجم: <strong>66.3 MB</strong></span>
                <span className="spec-pill">النوع: <strong>Setup EXE</strong></span>
              </div>

              <ul className="feature-check-list">
                <li>إرسال واستقبال ملفات وفواتير إكسيل وPDF بالحجم الأصلي</li>
                <li>تنبيهات صوتية وإشعارات سطح المكتب للرسائل العاجلة</li>
                <li>أخذ لقطات شاشة (Screenshots) ومشاركتها فورياً</li>
                <li>بدء تشغيل تلقائي مع تشغيل نظام الويندوز</li>
              </ul>

              <a
                href="/downloads/iSmart%20Messenger%20Setup%201.1.15.exe"
                className="btn-apple-download windows-download"
                download
              >
                <Download size={18} />
                <span>تحميل برنامج الكمبيوتر (EXE)</span>
              </a>

              <Link href="/windows" className="sub-link">
                عرض الدليل التوضيحي المفصل لنسخة الكمبيوتر ←
              </Link>
            </div>

            {/* ANDROID MOBILE CARD */}
            <div className="apple-card mobile-card">
              <div className="card-top">
                <span className="card-badge">الهواتف والأجهزة اللوحية</span>
                <span style={{ fontSize: '0.78rem', color: 'var(--apple-green)', fontWeight: 700 }}>
                  Android 8.0+
                </span>
              </div>

              <div className="card-icon-title">
                <div className="app-icon-squircle mob-icon">📱</div>
                <div className="card-heading">
                  <h3>نسخة الموبايل (Android)</h3>
                  <p>تطبيق الهاتف الذكي للاتصال المتنقل</p>
                </div>
              </div>

              <div className="spec-row">
                <span className="spec-pill">الإصدار: <strong>1.0.2</strong></span>
                <span className="spec-pill">الحجم: <strong>56.9 MB</strong></span>
                <span className="spec-pill">النوع: <strong>Google Play & APK</strong></span>
              </div>

              <ul className="feature-check-list">
                <li>إشعارات فورية في الخلفية حتى مع إغلاق الشاشة تماماً</li>
                <li>تسجيلات صوتية واضحة ومكالمات مشفرة بدون تقطيع</li>
                <li>إرسال صور المعاملات مباشرة عبر الكاميرا</li>
                <li>مزامنة سريعة ولحظية مع حساب الكمبيوتر المكتبي</li>
              </ul>

              <div className="download-btn-group">
                <a
                  href="https://play.google.com/store/apps/details?id=com.ismart.messenger"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="btn-apple-download playstore-download"
                >
                  <GooglePlayIcon size={19} />
                  <span>تثبيت من Google Play</span>
                </a>

                <a
                  href="/downloads/iSmart-Messenger.apk"
                  className="btn-apple-download mobile-download"
                  download
                >
                  <Download size={18} />
                  <span>تحميل مباشر (ملف APK)</span>
                </a>
              </div>

              <Link href="/mobile" className="sub-link" style={{ color: 'var(--apple-green)' }}>
                عرض الدليل التوضيحي المفصل لتطبيق الموبايل ←
              </Link>
            </div>
          </div>

          {/* Inset Server Configuration Bar */}
          <ServerIpBar />
        </div>
      </section>

      {/* Video Training Section */}
      <section
        className="section-wrapper"
        id="videos-section"
        style={{
          background: 'var(--bg-card)',
          borderTop: '1px solid var(--hairline)',
          borderBottom: '1px solid var(--hairline)',
        }}
      >
        <div className="container">
          <div className="section-title-wrap">
            <span className="section-small-tag">الفيديوهات الإرشادية</span>
            <h3 className="section-main-heading">
              شرح بالفيديو لكل من الكمبيوتر والموبايل
            </h3>
            <p className="section-sub-heading">
              شاهد خطوات التثبيت وضبط الاتصال بالسيرفر في مقاطع فيديو سريعة ومباشرة.
            </p>
          </div>

          <div className="video-grid-apple">
            {/* Windows Video */}
            <VideoPlayer
              id="vidWindows"
              src="/downloads/iSmart%20Messenger%20Windows.mp4"
              poster="/assets/images/logo.png"
              tag="💻 شرح الكمبيوتر"
              tagType="win"
              title="دليل تثبيت وضبط برنامج الويندوز"
              description="يشرح خطوة بخطوة فتح ملف التثبيت، ضبط خادم الشركة، تسجيل الدخول، واستخدام المحادثات والملفات."
              chapters={[
                { time: 0, label: '00:00 التثبيت' },
                { time: 30, label: '00:30 السيرفر' },
                { time: 65, label: '01:05 تسجيل الدخول' },
                { time: 120, label: '02:00 المحادثات' },
              ]}
              guideLink="/windows"
              guideLinkLabel="قراءة الدليل المكتوب لنسخة الكمبيوتر"
              downloadLink="/downloads/iSmart%20Messenger%20Setup%201.1.15.exe"
              downloadLinkLabel="تنزيل الملف (EXE)"
            />

            {/* Mobile Video */}
            <VideoPlayer
              id="vidMobile"
              src="/downloads/iSmart%20Messenger%20Mobile.mp4"
              poster="/assets/images/logo.png"
              tag="📱 شرح الموبايل"
              tagType="mob"
              title="دليل تثبيت وضبط تطبيق الأندرويد"
              description="يشرح تثبيت ملف APK، السماح بالمصادر الخارجية، تسجيل الدخول، وأهم خطوة لتفعيل الإشعارات بالخلفية."
              chapters={[
                { time: 0, label: '00:00 فتح الـ APK' },
                { time: 25, label: '00:25 أمان الأندرويد' },
                { time: 50, label: '00:50 تسجيل الدخول' },
                { time: 90, label: '01:30 استثناء البطارية' },
              ]}
              guideLink="/mobile"
              guideLinkLabel="قراءة الدليل المكتوب لنسخة الموبايل"
              downloadLink="/downloads/iSmart-Messenger.apk"
              downloadLinkLabel="تنزيل الملف (APK)"
            />
          </div>
        </div>
      </section>

      {/* Inset Grouped Enterprise Features */}
      <section className="section-wrapper">
        <div className="container">
          <div className="section-title-wrap">
            <span className="section-small-tag">الأمان والاعتمادية</span>
            <h3 className="section-main-heading">
              مميزات بيئة العمل الموحدة بالفروع
            </h3>
          </div>

          <div className="inset-group">
            <div className="inset-row">
              <div className="inset-icon icon-blue">🔒</div>
              <div className="inset-content">
                <h5>تشفير كامل وحفظ محلي للبيانات</h5>
                <p>
                  كافة الرسائل والمستندات مخزنة داخل خوادم الشركة المحلية دون خروج أي معلومة لخوادم خارجية.
                </p>
              </div>
            </div>

            <div className="inset-row">
              <div className="inset-icon icon-green">⚡</div>
              <div className="inset-content">
                <h5>تزامن لحظي متعدد الأجهزة</h5>
                <p>
                  يمكنك فتح حسابك على كمبيوتر المكتب والموبايل بالتوازي مع تحديث المحادثات لحظياً.
                </p>
              </div>
            </div>

            <div className="inset-row">
              <div className="inset-icon icon-indigo">📁</div>
              <div className="inset-content">
                <h5>مشاركة غير مقيدة للمستندات</h5>
                <p>
                  إرسال مستندات الـ PDF وجداول الـ Excel والفواتير بحجمها الكامل دون تشويه أو ضغط.
                </p>
              </div>
            </div>

            <div className="inset-row">
              <div className="inset-icon icon-orange">🔔</div>
              <div className="inset-content">
                <h5>إشعارات وتنبيهات فورية في الخلفية</h5>
                <p>
                  تنبيهات صوتية فورية على الكمبيوتر وإشعارات فورية على الموبايل حتى مع قفل الشاشة.
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>
    </>
  );
}
