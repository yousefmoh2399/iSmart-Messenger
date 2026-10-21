import React from 'react';
import Link from 'next/link';
import TopStrip from '../components/TopStrip';
import ServerIpBar from '../components/ServerIpBar';
import VideoPlayer from '../components/VideoPlayer';
import GooglePlayIcon from '../components/GooglePlayIcon';
import ProtectedDownloadButton from '../components/ProtectedDownloadButton';
import { Download } from 'lucide-react';
import { getConfig } from '../lib/downloadManager';

export const dynamic = 'force-dynamic';

export default function HomePage() {
  const config = getConfig();
  const downloadsDisabled = !config.globalDownloadsEnabled;

  return (
    <>
      {/* Top Branch Announcement Strip */}
      <TopStrip />

      {/* Global Maintenance Alert Banner if downloads are disabled */}
      {downloadsDisabled && (
        <div
          style={{
            backgroundColor: 'rgba(255, 59, 48, 0.1)',
            borderBottom: '1px solid rgba(255, 59, 48, 0.25)',
            padding: '12px 16px',
            textAlign: 'center',
            color: 'var(--apple-red, #ff3b30)',
            fontWeight: 800,
            fontSize: '0.92rem',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '8px',
          }}
        >
          <span>🛑</span>
          <span>
            {config.maintenanceMessage ||
              'تنبيه: تم إيقاف كافة التحميلات مؤقتاً لأعمال الصيانة والتحديثات من قبل الإدارة المركزية.'}
          </span>
        </div>
      )}

      {/* Hero Section */}
      <section className="hero-wrapper" id="downloads">
        <div className="container">
          <h2 className="hero-headline">
            منظومة العمل والمراسلات الآمنة <br />
            <span>المعتمدة لكافة فروع الشركة (50 فرعاً)</span>
          </h2>
          <p style={{ maxWidth: '720px', margin: '-16px auto 32px', color: 'var(--label-secondary)', fontSize: '0.94rem', lineHeight: 1.6 }}>
            المنصة الموحدة لإدارة الفروع: سحب الفواتير الورقية بالسكانر مباشرة، فتح ومتابعة تذاكر الأعطال والطلبات، تنظيم ومشاركة المستندات، والتواصل الفوري المشفر بين الفروع والإدارة العامة.
          </p>

          {/* THE 2 BIG APPLE DOWNLOAD CARDS */}
          <div className="download-section-grid">
            {/* WINDOWS DESKTOP CARD */}
            <div className="apple-card">
              <div className="card-top">
                <span className="card-badge">أجهزة المكاتب واللابتوب بالفروع</span>
                <span style={{ fontSize: '0.78rem', color: 'var(--apple-blue)', fontWeight: 700 }}>
                  Windows 7 / 10 / 11
                </span>
              </div>

              <div className="card-icon-title">
                <div className="app-icon-squircle win-icon">💻</div>
                <div className="card-heading">
                  <h3>نسخة الكمبيوتر (Desktop)</h3>
                  <p>تطبيق سطح المكتب المتكامل للموظفين ومديري الفروع</p>
                </div>
              </div>

              <div className="spec-row">
                <span className="spec-pill">الإصدار: <strong>1.1.15</strong></span>
                <span className="spec-pill">الحجم: <strong>66.3 MB</strong></span>
                <span className="spec-pill">النوع: <strong>Setup EXE</strong></span>
              </div>

              <ul className="feature-check-list">
                <li><strong>الماسح الضوئي المباشر (Native Scanner):</strong> سحب الفواتير والمستندات الورقية من جهاز السكانر بضغطة زر وتحويلها فوراً لـ PDF وإرسالها للإدارة.</li>
                <li><strong>نظام التذاكر الموحد (Ticketing):</strong> فتح تذاكر رسمية للأعطال وطلبات الصيانة والمشتريات ومتابعة حالتها خطوة بخطوة.</li>
                <li><strong>مستودع المجلدات والملفات:</strong> تنظيم الفواتير والمستندات في مجلدات خاصة وعامة مع دعم السحب والإفلات والطباعة.</li>
                <li><strong>محادثات وقنوات رسمية:</strong> تواصل فوري بين الفرع وكافة الإدارات (الحسابات، المبيعات، الـ IT، الإدارة العليا).</li>
                <li><strong>أداة لقطات الشاشة (Screenshots):</strong> تصوير شاشة الكمبيوتر وتحديد الملاحظات لمشاركتها مع الدعم الفني في ثانية.</li>
                <li><strong>تنبيهات عاجلة وبدء تلقائي:</strong> إشعارات صوتية لسطح المكتب وتشغيل تلقائي فور فتح جهاز الكمبيوتر.</li>
              </ul>

              <ProtectedDownloadButton
                fileType="windows"
                className="btn-apple-download windows-download"
              >
                <Download size={18} />
                <span>تحميل برنامج الكمبيوتر (EXE)</span>
              </ProtectedDownloadButton>

              <Link href="/windows" className="sub-link">
                عرض الدليل التوضيحي المفصل والشامل لنسخة الكمبيوتر ←
              </Link>
            </div>

            {/* ANDROID MOBILE CARD */}
            <div className="apple-card mobile-card">
              <div className="card-top">
                <span className="card-badge">الهواتف الذكية والأجهزة اللوحية</span>
                <span style={{ fontSize: '0.78rem', color: 'var(--apple-green)', fontWeight: 700 }}>
                  Android 8.0+
                </span>
              </div>

              <div className="card-icon-title">
                <div className="app-icon-squircle mob-icon">📱</div>
                <div className="card-heading">
                  <h3>نسخة الموبايل (Android)</h3>
                  <p>تطبيق الهاتف الذكي للاتصال والمتابعة المتنقلة</p>
                </div>
              </div>

              <div className="spec-row">
                <span className="spec-pill">الإصدار: <strong>1.0.2</strong></span>
                <span className="spec-pill">الحجم: <strong>56.9 MB</strong></span>
                <span className="spec-pill">النوع: <strong>Google Play & APK</strong></span>
              </div>

              <ul className="feature-check-list">
                <li><strong>متابعة الفروع أثناء التنقل:</strong> متابعة التذاكر العاجلة والمحادثات من هاتفك في أي وقت دون الحاجة للبقاء أمام الكمبيوتر.</li>
                <li><strong>تصوير المستندات بالكاميرا:</strong> التقاط صور الفواتير والأوراق وإرسالها فورياً إلى المحادثات أو سجل التذاكر.</li>
                <li><strong>إشعارات في الخلفية:</strong> تنبيهات فورية للأخبار والمراسلات العاجلة حتى عندما تكون شاشة الهاتف مقفولة تماماً.</li>
                <li><strong>مزامنة لحظية وتامة:</strong> تعمل بتوافق كامل مع حساب الكمبيوتر بنفس البيانات دون تعارض.</li>
                <li><strong>رسائل صوتية واضحة:</strong> تسجيل محادثات صوتية عالية الدقة بدون تشويش وبدون قيود زمنية.</li>
                <li><strong>خيارات تثبيت مرنة:</strong> تثبيت مباشر بضغطة زر من متجر Google Play الرسمي أو تحميل ملف الـ APK.</li>
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

                <ProtectedDownloadButton
                  fileType="mobile"
                  className="btn-apple-download mobile-download"
                >
                  <Download size={18} />
                  <span>تحميل مباشر (ملف APK)</span>
                </ProtectedDownloadButton>
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

      {/* Comprehensive Core Capabilities Showcase (Bento Grid) */}
      <section className="section-wrapper" id="core-features">
        <div className="container">
          <div className="section-title-wrap">
            <span className="section-small-tag">منظومة العمل الشاملة</span>
            <h3 className="section-main-heading">
              كل ما يقدمه لك البرنامج قبل التحميل
            </h3>
            <p className="section-sub-heading">
              منصة متكاملة صُممت خصيصاً لتلبية متطلبات الـ 50 فرعاً والقضاء على الروتين وضياع المعاملات.
            </p>
          </div>

          <div className="features-bento-grid">
            {/* Bento Card 1: Scanner */}
            <div className="feature-bento-card">
              <div className="bento-icon-badge-row">
                <div className="bento-icon-squircle win-icon">🖨️</div>
                <span className="bento-badge badge-blue">الماسح الضوئي الذكي</span>
              </div>
              <h4 className="bento-card-title">سحب ومسح الفواتير بالسكانر المباشر</h4>
              <p className="bento-card-desc">
                اسحب الفواتير والمستندات الورقية من أي جهاز سكانر متصل بالكمبيوتر بضغطة زر واحدة داخل البرنامج، مع تحويلها فورياً لملفات PDF واضحة وإرسالها للإدارة العامة في لحظات.
              </p>
              <ul className="bento-highlights">
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-blue)' }} /> كشف تلقائي لأجهزة الماسح الضوئي (TWAIN/WIA)</li>
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-blue)' }} /> معاينة وتعديل وتدوير الصفحات قبل الإرسال</li>
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-blue)' }} /> إرسال فوري للحسابات لتسريع دورات الصرف</li>
              </ul>
            </div>

            {/* Bento Card 2: Tickets */}
            <div className="feature-bento-card">
              <div className="bento-icon-badge-row">
                <div className="bento-icon-squircle icon-orange">🎫</div>
                <span className="bento-badge badge-orange">نظام التذاكر الرسمي</span>
              </div>
              <h4 className="bento-card-title">إدارة بلاغات الأعطال وطلبات الفروع</h4>
              <p className="bento-card-desc">
                افتح تذكرة رسمية برقم تسلسلي موثق لأي عطل صيانة، مشتريات، دعم فني IT، أو استفسار مالي. تابع خطوات التنفيذ خطوة بخطوة مع سجل كامل للردود لضمان عدم ضياع أي طلب.
              </p>
              <ul className="bento-highlights">
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-orange)' }} /> رقم تذكرة مرجعي يضمن متابعة طلبك حتى النهاية</li>
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-orange)' }} /> تحديد درجة الأولوية (عادي، متوسط، عاجل جداً)</li>
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-orange)' }} /> إشعار فوري عند قيام الإدارة بالرد على التذكرة</li>
              </ul>
            </div>

            {/* Bento Card 3: Files & Folders */}
            <div className="feature-bento-card">
              <div className="bento-icon-badge-row">
                <div className="bento-icon-squircle icon-indigo">📁</div>
                <span className="bento-badge badge-indigo">مستودع المستندات</span>
              </div>
              <h4 className="bento-card-title">تنظيم وأرشفة الملفات في مجلدات</h4>
              <p className="bento-card-desc">
                نظام تخزين سحابي داخلي يتيح لك إنشاء مجلدات خاصة لفرعك ومجلدات عامة مشتركة، مع إمكانية تنظيم المستندات بالسحب والإفلات (Drag & Drop) والبحث السريع والطباعة المباشرة.
              </p>
              <ul className="bento-highlights">
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-indigo)' }} /> إرسال ملفات Excel و PDF بالحجم الأصلي دون ضغط</li>
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-indigo)' }} /> تنظيم شجري للمجلدات مع سحب وإفلات فوري</li>
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-indigo)' }} /> معاينة وطباعة المستندات مباشرة بضغطة زر</li>
              </ul>
            </div>

            {/* Bento Card 4: Official Chat */}
            <div className="feature-bento-card">
              <div className="bento-icon-badge-row">
                <div className="bento-icon-squircle icon-blue">💬</div>
                <span className="bento-badge badge-blue">مراسلات مؤسسية</span>
              </div>
              <h4 className="bento-card-title">قنوات تواصل رسمية بين الفروع والإدارات</h4>
              <p className="bento-card-desc">
                غرف محادثة مخصصة لكل فرع، قنوات رسمية للتعميمات الإدارية، ومحادثات فردية مشفرة بين الموظفين. استغناء كامل عن فوضى مجموعات الواتساب غير الرسمية وتشتت الرسائل.
              </p>
              <ul className="bento-highlights">
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-blue)' }} /> تسجيلات صوتية عالية النقاء بدون حد أقصى للوقت</li>
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-blue)' }} /> تثبيت القرارات والتعميمات الهامة بأعلى القنوات</li>
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-blue)' }} /> علامات تسليم وقراءة وتأكيد استلام التعليمات</li>
              </ul>
            </div>

            {/* Bento Card 5: Screen Capture */}
            <div className="feature-bento-card">
              <div className="bento-icon-badge-row">
                <div className="bento-icon-squircle icon-red">📸</div>
                <span className="bento-badge badge-red">لقطات الشاشة</span>
              </div>
              <h4 className="bento-card-title">التقاط شاشة الكمبيوتر وتحديد المشكلة</h4>
              <p className="bento-card-desc">
                أداة تصوير شاشة سريعة ومدمجة تتيح لك اقتصاص أي جزء من شاشة الكمبيوتر، كتابة ملاحظات وتحديد الأخطاء بالماوس، وإرسالها فوراً في المحادثة أو إرفاقها بالتذكرة للدعم الفني.
              </p>
              <ul className="bento-highlights">
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-red)' }} /> تصوير فوري بضغطة زر واحدة دون برامج مساعدة</li>
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-red)' }} /> أدوات تظليل ورسم لتوضيح الخطأ المطلوب حله</li>
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-red)' }} /> لصق مباشر من الحافظة (Ctrl + V) داخل المحادثة</li>
              </ul>
            </div>

            {/* Bento Card 6: Mobile Sync */}
            <div className="feature-bento-card">
              <div className="bento-icon-badge-row">
                <div className="bento-icon-squircle mob-icon">📱</div>
                <span className="bento-badge badge-green">مزامنة الموبايل</span>
              </div>
              <h4 className="bento-card-title">متابعة الفرع وإشعارات الخلفية أينما كنت</h4>
              <p className="bento-card-desc">
                تطبيق أندرويد متزامن لحظياً مع كمبيوتر المكتب. يمكنك من متابعة التذاكر العاجلة، تصوير المستندات الورقية عبر كاميرا الهاتف، واستقبال إشعارات فورية حتى والشاشة مغلقة.
              </p>
              <ul className="bento-highlights">
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-green)' }} /> متوفر في Google Play مع خيار التحميل المباشر APK</li>
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-green)' }} /> إشعارات فورية عبر خوادم الشركة والـ Firebase</li>
                <li><span className="bento-bullet-dot" style={{ background: 'var(--apple-green)' }} /> نفس بيانات الدخول دون الحاجة لحساب جديد</li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* Value & ROI Section: What does the system save for your branch? */}
      <section
        className="section-wrapper"
        style={{
          background: 'var(--bg-card)',
          borderTop: '1px solid var(--hairline)',
          borderBottom: '1px solid var(--hairline)',
        }}
      >
        <div className="container">
          <div className="section-title-wrap">
            <span className="section-small-tag">القيمة والفائدة العملية</span>
            <h3 className="section-main-heading">
              ماذا يوفر برنامج iSmart Messenger لفرعك يومياً؟
            </h3>
            <p className="section-sub-heading">
              نقلة نوعية في كفاءة إدارة الفروع الخمسين، تقضي على التأخير والتواصل غير المنظم.
            </p>
          </div>

          <div className="value-roi-grid">
            {/* ROI 1 */}
            <div className="value-roi-card">
              <div className="roi-card-icon" style={{ background: 'var(--apple-blue-soft)', color: 'var(--apple-blue)' }}>
                ⏱️
              </div>
              <div className="roi-card-content">
                <h4>توفير 80% من وقت الفروع الضائع في الاتصالات</h4>
                <p>
                  بدلاً من إضاعة الوقت في الاتصالات الهاتفية المتكررة والانتظار لمعرفة وصول فاتورة أو حل مشكلة في الفرع، تصل رسالتك ومستنداتك للقسم المعني فورياً مع توثيق لحظي للاستلام.
                </p>
              </div>
            </div>

            {/* ROI 2 */}
            <div className="value-roi-card">
              <div className="roi-card-icon" style={{ background: 'var(--apple-green-soft)', color: 'var(--apple-green)' }}>
                📑
              </div>
              <div className="roi-card-content">
                <h4>إنهاء تأخير وتسليم الفواتير الورقية</h4>
                <p>
                  بمجرد استلام الفاتورة في الفرع، يتم سحبها بالسكانر المدمج وإرسالها للإدارة العامة في نفس اللحظة، مما يسرع دورة التسويات المالية ومراجعة الحسابات دون انتظار البريد أو المندوب.
                </p>
              </div>
            </div>

            {/* ROI 3 */}
            <div className="value-roi-card">
              <div className="roi-card-icon" style={{ background: 'rgba(255, 149, 0, 0.12)', color: 'var(--apple-orange)' }}>
                🎯
              </div>
              <div className="roi-card-content">
                <h4>صفر طلبات أو مشاكل تائهة (Zero Lost Requests)</h4>
                <p>
                  كل عطل صيانة، طلب مستلزمات، أو استفسار إداري مسجل بتذكرة مرقمة واضحة ومسندة لمسؤول محدد يتابعها حتى إنهائها، مما يضمن حق الفرع ويوثق تواريخ التنفيذ بدقة.
                </p>
              </div>
            </div>

            {/* ROI 4 */}
            <div className="value-roi-card">
              <div className="roi-card-icon" style={{ background: 'rgba(88, 86, 214, 0.12)', color: 'var(--apple-indigo)' }}>
                🔒
              </div>
              <div className="roi-card-content">
                <h4>أمان وسرية تامة لمعاملات الشركة</h4>
                <p>
                  جميع الملفات والفواتير والبيانات مخزنة محلياً على سيرفرات الشركة الخاصة بدون خروج أي معلومة لمنصات خارجية، مع صلاحيات محددة لكل موظف وفرع لضمان أعلى درجات الخصوصية.
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Video Training Section */}
      <section className="section-wrapper" id="videos-section">
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
              downloadLink="/api/portal/download?file=windows"
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
              downloadLink="/api/portal/download?file=mobile"
              downloadLinkLabel="تنزيل الملف (APK)"
            />
          </div>
        </div>
      </section>

      {/* Inset Grouped Enterprise Features */}
      <section
        className="section-wrapper"
        style={{
          background: 'var(--bg-card)',
          borderTop: '1px solid var(--hairline)',
        }}
      >
        <div className="container">
          <div className="section-title-wrap">
            <span className="section-small-tag">الأمان والاعتمادية</span>
            <h3 className="section-main-heading">
              مميزات البنية التحتية الموحدة بالفروع
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
