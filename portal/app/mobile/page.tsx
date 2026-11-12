'use client';

import React, { useRef } from 'react';
import TopStrip from '../../components/TopStrip';
import { useToast } from '../../components/Toast';
import GooglePlayIcon from '../../components/GooglePlayIcon';
import ProtectedDownloadButton from '../../components/ProtectedDownloadButton';
import { Download } from 'lucide-react';

export default function MobileGuidePage() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const { showToast } = useToast();

  const handleSeek = (time: number, label: string) => {
    if (videoRef.current) {
      videoRef.current.currentTime = time;
      videoRef.current.play().catch(() => {});
      videoRef.current.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      showToast(`تم الانتقال إلى: ${label}`);
    }
  };

  return (
    <>
      <TopStrip text="الدليل الإرشادي المعتمد لإدارة وتشغيل تطبيق الهواتف الذكية" />

      {/* Doc Hero */}
      <section className="doc-hero">
        <div className="container">
          <h2>دليل تثبيت وتشغيل تطبيق الموبايل (Android)</h2>
          <p>
            دليل إرشادي بالصور والفيديو لضبط ملف الـ APK، وتفعيل الإشعارات في الخلفية لضمان عدم تفويت أي رسالة.
          </p>
        </div>
      </section>

      {/* Main Content */}
      <main className="doc-layout">
        <div className="container">
          {/* Embedded Video Tutorial */}
          <div className="step-card-apple" style={{ padding: '24px' }}>
            <div className="step-header">
              <div className="step-num-pill" style={{ background: 'var(--apple-green)' }}>▶</div>
              <h4>الفيديو العملي لشرح تطبيق الموبايل</h4>
            </div>
            <p>شاهد خطوات تثبيت الـ APK وتفعيل الإشعارات في دقيقة ونصف:</p>

            <div className="video-screen" style={{ borderRadius: 'var(--r-md)', overflow: 'hidden', marginBottom: '16px' }}>
              <video
                ref={videoRef}
                id="vidMobileGuide"
                controls
                preload="metadata"
                poster="/assets/images/logo.png"
                playsInline
              >
                <source src="/downloads/iSmart%20Messenger%20Mobile.mp4" type="video/mp4" />
                متصفحك لا يدعم تشغيل الفيديو مباشرة.
              </video>
            </div>

            <div className="chapter-pills">
              {[
                { time: 0, label: '00:00 فتح ملف APK' },
                { time: 25, label: '00:25 أذونات الأمان' },
                { time: 50, label: '00:50 تسجيل الدخول' },
                { time: 90, label: '01:30 استثناء البطارية' },
              ].map((ch, idx) => (
                <button
                  key={idx}
                  type="button"
                  className="chapter-btn"
                  onClick={() => handleSeek(ch.time, ch.label)}
                >
                  {ch.label}
                </button>
              ))}
            </div>
          </div>

          {/* Step 1 */}
          <div className="step-card-apple">
            <div className="step-header">
              <div className="step-num-pill" style={{ background: 'var(--apple-green)' }}>1</div>
              <h4>اختيار طريقة التثبيت (Google Play أو ملف APK)</h4>
            </div>
            <p>
              يمكنك تثبيت التطبيق مباشرة وبأسهل طريقة عبر <strong>متجر Google Play</strong> الرسمي، أو تحميل ملف <code>iSmart-Messenger.apk</code> المباشر وتثبيته يدوياً:
            </p>
            <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap', margin: '16px 0' }}>
              <a
                href="https://play.google.com/store/apps/details?id=com.ismart.messenger"
                target="_blank"
                rel="noopener noreferrer"
                className="btn-apple-download playstore-download"
                style={{ width: 'auto', padding: '11px 22px', fontSize: '0.9rem' }}
              >
                <GooglePlayIcon size={19} />
                <span>تثبيت من Google Play</span>
              </a>
              <ProtectedDownloadButton
                fileType="mobile"
                className="btn-apple-download mobile-download"
                style={{ width: 'auto', padding: '11px 22px', fontSize: '0.9rem' }}
              >
                <Download size={18} />
                <span>تنزيل ملف APK المباشر</span>
              </ProtectedDownloadButton>
            </div>
            <div className="callout-box">
              📲 <strong>في حال التثبيت عبر ملف APK يدوياً:</strong> قد تظهر رسالة تفيد بأن <em>&quot;الملف قد يكون ضاراً&quot; (File might be harmful)</em>. اضغط على <strong>&quot;تنزيل على أي حال&quot; (Download anyway)</strong> لأن الملف آمن ومعتمد داخلياً من الشركة.
            </div>
          </div>

          {/* Step 2 */}
          <div className="step-card-apple">
            <div className="step-header">
              <div className="step-num-pill" style={{ background: 'var(--apple-green)' }}>2</div>
              <h4>السماح بالتثبيت من هذا المصدر (Install Unknown Apps)</h4>
            </div>
            <p>
              عند فتح الملف لأول مرة، يطلب نظام الأندرويد إذناً لتثبيت التطبيقات من خارج متجر Play:
            </p>
            <ol style={{ marginRight: '20px', lineHeight: 1.8, color: 'var(--label-secondary)' }}>
              <li>اضغط على <strong>الإعدادات (Settings)</strong> في النافذة المنبثقة.</li>
              <li>قم بتفعيل خيار <strong>السماح بتثبيت التطبيقات من هذا المصدر (Allow from this source)</strong>.</li>
              <li>اضغط على زر <strong>تثبيت (Install)</strong>.</li>
            </ol>
          </div>

          {/* Step 3: Crucial Battery Optimization Table */}
          <div className="step-card-apple">
            <div className="step-header">
              <div className="step-num-pill" style={{ background: 'var(--apple-green)' }}>3</div>
              <h4>الخطوة الأهم: ضبط الإشعارات حسب نوع هاتفك</h4>
            </div>
            <p>
              لتصلك إشعارات الرسائل فوراً حتى لو كان الموبايل مغلقاً أو التطبيق مقفولاً، اتبع مسار هاتفك في الجدول التالي:
            </p>

            <div style={{ overflowX: 'auto' }}>
              <table className="doc-table">
                <thead>
                  <tr>
                    <th>نوع الهاتف</th>
                    <th>خطوات ضبط البطارية والإشعارات</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td><strong>سامسونج (Samsung)</strong></td>
                    <td>الضبط ➔ التطبيقات ➔ iSmart Messenger ➔ البطارية ➔ حدد خيار <strong>&quot;غير مقيد&quot; (Unrestricted)</strong>.</td>
                  </tr>
                  <tr>
                    <td><strong>شاومي (Xiaomi / Redmi)</strong></td>
                    <td>الإعدادات ➔ التطبيقات ➔ إدارة التطبيقات ➔ iSmart Messenger ➔ فعل <strong>&quot;التشغيل التلقائي&quot; (Autostart)</strong> + موفر البطارية ➔ <strong>&quot;لا توجد قيود&quot;</strong>.</td>
                  </tr>
                  <tr>
                    <td><strong>هواوي (Huawei / Honor)</strong></td>
                    <td>الإعدادات ➔ البطارية ➔ تشغيل التطبيقات ➔ iSmart Messenger ➔ أغلق الإدارة التلقائية وفعل <strong>&quot;التشغيل في الخلفية&quot;</strong>.</td>
                  </tr>
                  <tr>
                    <td><strong>أوبو / ريلمي (Oppo / Realme)</strong></td>
                    <td>الإعدادات ➔ إدارة التطبيقات ➔ iSmart Messenger ➔ استخدام البطارية ➔ فعل <strong>&quot;السماح بنشاط الخلفية&quot;</strong> و <strong>&quot;التشغيل التلقائي&quot;</strong>.</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          {/* Download Bottom Box */}
          <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', gap: '14px', flexWrap: 'wrap', marginTop: '34px' }}>
            <a
              href="https://play.google.com/store/apps/details?id=com.ismart.messenger"
              target="_blank"
              rel="noopener noreferrer"
              className="btn-apple-download playstore-download"
              style={{ width: 'auto', padding: '13px 28px', fontSize: '0.96rem' }}
            >
              <GooglePlayIcon size={19} />
              <span>تثبيت من Google Play</span>
            </a>
            <ProtectedDownloadButton
              fileType="mobile"
              className="btn-apple-download mobile-download"
              style={{ width: 'auto', padding: '13px 28px', fontSize: '0.96rem' }}
            >
              <Download size={18} />
              <span>تحميل مباشر (ملف APK)</span>
            </ProtectedDownloadButton>
          </div>
        </div>
      </main>
    </>
  );
}
