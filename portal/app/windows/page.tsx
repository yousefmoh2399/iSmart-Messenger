'use client';

import React, { useRef } from 'react';
import TopStrip from '../../components/TopStrip';
import { useToast } from '../../components/Toast';
import { Download, Copy, Check } from 'lucide-react';

export default function WindowsGuidePage() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const { showToast } = useToast();
  const [copied, setCopied] = React.useState(false);

  const serverIp = 'http://172.17.100.253:5000';

  const handleSeek = (time: number, label: string) => {
    if (videoRef.current) {
      videoRef.current.currentTime = time;
      videoRef.current.play().catch(() => {});
      videoRef.current.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      showToast(`تم الانتقال إلى: ${label}`);
    }
  };

  const handleCopyIp = () => {
    if (navigator.clipboard) {
      navigator.clipboard.writeText(serverIp).then(() => {
        setCopied(true);
        showToast('تم نسخ عنوان السيرفر بنجاح!');
        setTimeout(() => setCopied(false), 2000);
      });
    }
  };

  return (
    <>
      <TopStrip text="الدليل الإرشادي المعتمد لإدارة وتشغيل برنامج سطح المكتب" />

      {/* Doc Hero */}
      <section className="doc-hero">
        <div className="container">
          <h2>دليل تثبيت وتشغيل برنامج الكمبيوتر (Windows)</h2>
          <p>
            شرح تنفيذي خطوة بخطوة بالصور والفيديو لضبط البرنامج، وتفادي أخطاء الشبكة، وبدء المراسلات المؤسسية.
          </p>
        </div>
      </section>

      {/* Main Content */}
      <main className="doc-layout">
        <div className="container">
          {/* Specifications Table */}
          <div className="step-card-apple" style={{ padding: '24px' }}>
            <h4 style={{ fontSize: '1.05rem', fontWeight: 800, marginBottom: '14px', color: 'var(--label-primary)' }}>
              📋 المتطلبات الفنية للتشغيل
            </h4>
            <div style={{ overflowX: 'auto' }}>
              <table className="doc-table">
                <thead>
                  <tr>
                    <th>المعيار</th>
                    <th>الحد الأدنى المطلوب</th>
                    <th>الموصى به للعمل المؤسسي</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td>نظام التشغيل</td>
                    <td>Windows 7 (32-bit)</td>
                    <td>Windows 10 / 11 (64-bit) أحدث تحديث</td>
                  </tr>
                  <tr>
                    <td>المعالج (CPU)</td>
                    <td>Intel / AMD ثنائي النواة 2.0 GHz</td>
                    <td>معالج رباعي النواة حديث أو أعلى</td>
                  </tr>
                  <tr>
                    <td>الذاكرة العشوائية (RAM)</td>
                    <td>2 GB RAM</td>
                    <td>4 GB RAM فما فوق</td>
                  </tr>
                  <tr>
                    <td>المساحة التخزينية</td>
                    <td>300 MB مساحة فارغة</td>
                    <td>1 GB مساحة فارغة (لحفظ الملفات المؤقتة والمستندات)</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          {/* Embedded Video Tutorial */}
          <div className="step-card-apple" style={{ padding: '24px' }}>
            <div className="step-header">
              <div className="step-num-pill">▶</div>
              <h4>الفيديو العملي لشرح برنامج الكمبيوتر</h4>
            </div>
            <p>شاهد الفيديو لتتعلم خطوات تثبيت وضبط السيرفر في دقيقة ونصف:</p>

            <div className="video-screen" style={{ borderRadius: 'var(--r-md)', overflow: 'hidden', marginBottom: '16px' }}>
              <video
                ref={videoRef}
                id="vidWindowsGuide"
                controls
                preload="metadata"
                poster="/assets/images/logo.png"
                playsInline
              >
                <source src="/downloads/iSmart%20Messenger%20Windows.mp4" type="video/mp4" />
                متصفحك لا يدعم تشغيل الفيديو مباشرة.
              </video>
            </div>

            <div className="chapter-pills">
              {[
                { time: 0, label: '00:00 فتح ملف التثبيت' },
                { time: 30, label: '00:30 عنوان الخادم (Host)' },
                { time: 65, label: '01:05 تسجيل الدخول' },
                { time: 120, label: '02:00 إرسال الملفات' },
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
              <div className="step-num-pill">1</div>
              <h4>تشغيل ملف التثبيت المعتمد (Installation)</h4>
            </div>
            <p>
              قم بالنقر المزدوج على ملف <code>iSmart Messenger Setup 1.1.15.exe</code>. ستبدأ عملية التثبيت الصامتة والسريعة، وسيتم إنشاء اختصار مباشر للبرنامج على سطح المكتب وفي قائمة Start.
            </p>
            <div className="callout-box warn">
              ⚠️ <strong>تنبيه شاشة الأمان (Windows SmartScreen):</strong> في حال ظهرت لك نافذة زرقاء تذكر &quot;Windows protected your PC&quot;، اضغط على رابط <strong>More info</strong>، ثم اضغط على زر <strong>Run anyway</strong> للمتابعة.
            </div>
          </div>

          {/* Step 2 */}
          <div className="step-card-apple">
            <div className="step-header">
              <div className="step-num-pill">2</div>
              <h4>ضبط عنوان خادم الشركة (Server Connection)</h4>
            </div>
            <p>
              عند تشغيل البرنامج لأول مرة، تظهر نافذة ضبط الخادم. اكتب عنوان خادم المراسلات المعتمد لفرعك:
            </p>
            <div
              style={{
                background: 'var(--bg-system)',
                padding: '12px 18px',
                borderRadius: '8px',
                display: 'inline-flex',
                alignItems: 'center',
                gap: '12px',
                marginBottom: '12px',
                border: '1px solid var(--hairline)',
              }}
            >
              <code style={{ fontFamily: 'monospace', fontSize: '1rem', color: 'var(--apple-blue)', fontWeight: 700 }}>
                {serverIp}
              </code>
              <button
                className="btn-mini-copy"
                onClick={handleCopyIp}
                type="button"
                style={{ display: 'inline-flex', alignItems: 'center', gap: '5px' }}
              >
                {copied ? <Check size={14} /> : <Copy size={14} />}
                <span>{copied ? 'تم النسخ' : 'نسخ العنوان'}</span>
              </button>
            </div>
            <p>
              ثم اضغط على زر <strong>الاتصال (Connect)</strong>. في حال ظهور علامة صح خضراء، يعني ذلك أن جهاز الفرع متصل بنجاح بالسيرفر الرئيسي.
            </p>
          </div>

          {/* Step 3 */}
          <div className="step-card-apple">
            <div className="step-header">
              <div className="step-num-pill">3</div>
              <h4>تسجيل الدخول وبدء العمل</h4>
            </div>
            <p>
              أدخل اسم المستخدم (Username) وكلمة المرور المسلمة لك من إدارة الفرع أو قسم تكنولوجيا المعلومات، وضع علامة على <strong>Remember Me</strong> لحفظ الجلسة تلقائياً.
            </p>
          </div>

          {/* Shortcuts & Best Practices */}
          <div className="step-card-apple">
            <div className="step-header">
              <div className="step-num-pill">⌨</div>
              <h4>أهم اختصارات لوحة المفاتيح لتسريع العمل</h4>
            </div>
            <div style={{ overflowX: 'auto' }}>
              <table className="doc-table">
                <thead>
                  <tr>
                    <th>الاختصار</th>
                    <th>الوظيفة</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td><code>Enter</code></td>
                    <td>إرسال الرسالة المكتوبة فوراً</td>
                  </tr>
                  <tr>
                    <td><code>Shift + Enter</code></td>
                    <td>نزول سطر جديد دون إرسال الرسالة</td>
                  </tr>
                  <tr>
                    <td><code>Ctrl + F</code></td>
                    <td>البحث السريع في الرسائل أو جهات الاتصال</td>
                  </tr>
                  <tr>
                    <td><code>Ctrl + V</code></td>
                    <td>لصق صورة من الحافظة مباشرة في صندوق المحادثة لإرسالها</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          {/* Download Bottom Box */}
          <div style={{ textAlign: 'center', marginTop: '34px' }}>
            <a
              href="/downloads/iSmart%20Messenger%20Setup%201.1.15.exe"
              className="nav-cta-btn"
              style={{ padding: '13px 32px', fontSize: '0.96rem' }}
              download
            >
              <Download size={18} />
              <span>تحميل برنامج الكمبيوتر الآن (1.1.15 EXE)</span>
            </a>
          </div>
        </div>
      </main>
    </>
  );
}
