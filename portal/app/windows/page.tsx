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
      <TopStrip text="الدليل الإرشادي المعتمد لإدارة وتشغيل برنامج سطح المكتب لكافة الفروع" />

      {/* Doc Hero */}
      <section className="doc-hero">
        <div className="container">
          <h2>دليل تثبيت وتشغيل برنامج الكمبيوتر (Windows)</h2>
          <p>
            شرح تنفيذي خطوة بخطوة بالصور والفيديو لكافة إمكانيات البرنامج: الماسح الضوئي المباشر، نظام التذاكر، إدارة الملفات والمجلدات، والمراسلات المؤسسية بين الفروع والإدارة.
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

          {/* Step 1: Installation */}
          <div className="step-card-apple">
            <div className="step-header">
              <div className="step-num-pill">1</div>
              <h4>تشغيل ملف التثبيت المعتمد (Installation)</h4>
            </div>
            <p>
              قم بالنقر المزدوج على ملف <code>iSmart Messenger Setup 1.1.15.exe</code>. ستبدأ عملية التثبيت الصامتة والسريعة، وسيتم إنشاء اختصار مباشر للبرنامج على سطح المكتب وفي قائمة Start.
            </p>
            <div className="callout-box warn">
              ⚠️ <strong>تنبيه شاشة الأمان (Windows SmartScreen):</strong> في حال ظهرت لك نافذة زرقاء تذكر &quot;Windows protected your PC&quot;، اضغط على رابط <strong>More info</strong>، ثم اضغط على زر <strong>Run anyway</strong> للمتابعة لأن الملف آمن ومعتمد داخلياً من الشركة.
            </div>
          </div>

          {/* Step 2: Server Connection */}
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

          {/* Step 3: Login */}
          <div className="step-card-apple">
            <div className="step-header">
              <div className="step-num-pill">3</div>
              <h4>تسجيل الدخول وبدء العمل</h4>
            </div>
            <p>
              أدخل اسم المستخدم (Username) وكلمة المرور المسلمة لك من إدارة الفرع أو قسم تكنولوجيا المعلومات، وضع علامة على <strong>Remember Me</strong> لحفظ الجلسة تلقائياً.
            </p>
          </div>

          {/* Step 4: Native Document Scanner */}
          <div className="step-card-apple">
            <div className="step-header">
              <div className="step-num-pill" style={{ background: 'var(--apple-blue)' }}>4</div>
              <h4>استخدام الماسح الضوئي المباشر (Native Scanner) للفواتير والأوراق</h4>
            </div>
            <p>
              يوفر البرنامج ميزة فريدة تتيح سحب الفواتير والمستندات الورقية من أي جهاز سكانر متصل بجهاز الكمبيوتر مباشرة بدون الحاجة لفتح برامج خارجية:
            </p>
            <ol style={{ marginRight: '20px', lineHeight: 1.8, color: 'var(--label-secondary)', marginBottom: '14px' }}>
              <li>تأكد من توصيل جهاز الماسح الضوئي (Scanner) بجهاز الكمبيوتر عبر كابل USB أو الشبكة وتشغيله.</li>
              <li>من داخل أي محادثة أو من قسم المستندات، اضغط على أيقونة <strong>الماسح الضوئي (Scanner 🖨️)</strong>.</li>
              <li>سيتعرف البرنامج تلقائياً على الماسح الضوئي الخاص بك؛ حدد وضع السحب (ملون أو رمادي) ودقة المسح (DPI) ثم اضغط <strong>بدء المسح (Scan Document)</strong>.</li>
              <li>تظهر معاينة فورية للصفحة؛ يمكنك تدويرها أو إضافة صفحات أخرى لتكوين مستند متعدد الصفحات.</li>
              <li>اضغط <strong>"إرسال كـ PDF"</strong>؛ سيتم تحويل الصفحات لمستند PDF أصلي وإرساله فوراً للمستلم أو الحسابات مع توثيق لحظة الإرسال.</li>
            </ol>
            <div className="callout-box">
              💡 <strong>فائدة هامة للفرع:</strong> لن تحتاج بعد اليوم لحفظ الأوراق على سطح المكتب ثم إعادة رفعها، أو إرسال فواتير مصورة بالموبايل مشوهة أو غير واضحة.
            </div>
          </div>

          {/* Step 5: Ticketing & Issues System */}
          <div className="step-card-apple">
            <div className="step-header">
              <div className="step-num-pill" style={{ background: 'var(--apple-orange)' }}>5</div>
              <h4>فتح ومتابعة تذاكر الدعم والأعطال (Ticketing System)</h4>
            </div>
            <p>
              لضمان عدم ضياع أي عطل أو طلب في فرعك، تم تضمين نظام تذاكر رسمي متكامل:
            </p>
            <ol style={{ marginRight: '20px', lineHeight: 1.8, color: 'var(--label-secondary)', marginBottom: '14px' }}>
              <li>من القائمة الجانبية في البرنامج، اضغط على قسم <strong>"التذاكر" (Tickets 🎫)</strong>.</li>
              <li>اضغط على زر <strong>"إنشاء تذكرة جديدة" (New Ticket)</strong>.</li>
              <li>اختر القسم المسؤول عن الطلب (دعم تكنولوجيا المعلومات IT، إدارة الصيانة والتشغيل، الحسابات والماليات، أو المشتريات).</li>
              <li>اكتب عنواناً واضحاً وموجزاً، واشرح التفاصيل بدقة، مع تحديد الأولوية (عادي، متوسط، عاجل جداً).</li>
              <li>يمكنك إرفاق صور المشكلة أو الفواتير المسحوبة بالسكانر بضغطة زر واحدة.</li>
              <li>بمجرد الإرسال، تحصل التذكرة على رقم مرجعي رسمي (مثل <code>#TK-2041</code>)، وسيتم إشعارك فور قيام الإدارة بالرد أو تغيير الحالة إلى "قيد المعالجة" أو "مكتملة".</li>
            </ol>
            <div className="callout-box">
              🎯 <strong>توثيق رسمي:</strong> كل تذكرة تعتبر مستنداً رسمياً يثبت وقت الإبلاغ ووقت الاستجابة وتفاصيل الحل من قبل الإدارة.
            </div>
          </div>

          {/* Step 6: File & Folder Management */}
          <div className="step-card-apple">
            <div className="step-header">
              <div className="step-num-pill" style={{ background: 'var(--apple-indigo)' }}>6</div>
              <h4>إدارة وتنظيم المستندات في مجلدات (Files & Folders)</h4>
            </div>
            <p>
              يمتلك البرنامج مستودع ملفات رقمياً ذكياً يساعدك على أرشفة كافة المعاملات الورقية والإلكترونية:
            </p>
            <ol style={{ marginRight: '20px', lineHeight: 1.8, color: 'var(--label-secondary)', marginBottom: '14px' }}>
              <li>افتح قسم <strong>"الملفات" (Files 📁)</strong> من القائمة الجانبية.</li>
              <li>اضغط على <strong>"إنشاء مجلد جديد"</strong> وقسم ملفاتك (مثل: مجلد "فواتير شهر أكتوبر"، مجلد "كشوف المرتبات"، مجلد "أذونات الاستلام").</li>
              <li>يدعم النظام <strong>السحب والإفلات (Drag & Drop)</strong>؛ اسحب أي ملف من الكمبيوتر وضعه في المجلد المطلوب مباشرة.</li>
              <li>استخدم خيار التبديل بين <strong>عرض الشبكة (Grid View)</strong> أو <strong>عرض القائمة (List View)</strong> حسب رغبتك.</li>
              <li>للبحث عن أي فاتورة قديمة، اكتب اسم الفاتورة في شريط البحث الذكي لتظهر أمامك في لحظتها.</li>
              <li>اضغط كليك يمين على أي ملف لاختيار <strong>"طباعة مباشرة"</strong> لإرساله إلى طابعة الفرع بضغطة واحدة.</li>
            </ol>
          </div>

          {/* Step 7: Screen Capture Tool */}
          <div className="step-card-apple">
            <div className="step-header">
              <div className="step-num-pill" style={{ background: 'var(--apple-red)' }}>7</div>
              <h4>أداة لقطات الشاشة السريعة (Instant Screen Capture)</h4>
            </div>
            <p>
              عند مواجهة أي رسالة خطأ في النظام المحاسبي أو طلب استفسار سريع:
            </p>
            <ul style={{ marginRight: '20px', lineHeight: 1.8, color: 'var(--label-secondary);' }}>
              <li>اضغط على أيقونة <strong>الكاميرا / لقطة الشاشة (📸)</strong> في شريط كتابة الرسائل.</li>
              <li>سيتم تجميد الشاشة مؤقتاً؛ حدد بالماوس المستطيل أو الجزء المطلوب تصويره من الشاشة.</li>
              <li>يمكنك استخدام أدوات التظليل أو الأسهم لتحديد موضع الخطأ، ثم الضغط على علامة الصح الخضراء لتنزل لقطة الشاشة فوراً داخل المحادثة.</li>
            </ul>
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
                    <td>البحث السريع في الرسائل أو جهات الاتصال أو الملفات</td>
                  </tr>
                  <tr>
                    <td><code>Ctrl + V</code></td>
                    <td>لصق صورة من الحافظة مباشرة في صندوق المحادثة لإرسالها</td>
                  </tr>
                  <tr>
                    <td><code>Esc</code></td>
                    <td>إلغاء لقطة الشاشة أو إغلاق نوافذ المعاينة المنبثقة</td>
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
