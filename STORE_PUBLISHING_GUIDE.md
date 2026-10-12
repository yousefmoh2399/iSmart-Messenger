# دليل النشر الشامل والمفصل: Google Play Store & Apple App Store
## تطبيق آي سمارت ماسنجر | iSmart Messenger
**دليل الإطلاق الشامل للحصول على القبول من المراجعة الأولى بدون رفض**  
*تاريخ التحديث: 12 أكتوبر 2026*

---

## فهرس المحتويات
1. [الاستعدادات التقنية وحل أسباب الرفض الشائعة](#1-الاستعدادات-التقنية-وحل-أسباب-الرفض-الشائعة)
2. [تقليل حجم التطبيق وأثره على الأداء والوظائف](#2-تقليل-حجم-التطبيق-وأثره-على-الأداء-والوظائف)
3. [إنشاء مفتاح التوقيع الرقمي (Release Keystore)](#3-إنشاء-مفتاح-التوقيع-الرقمي-release-keystore)
4. [خطوات النشر على Google Play Console بالتفصيل الممل](#4-خطوات-النشر-على-google-play-console-بالتفصيل-الممل)
   - [أ. إنشاء التطبيق ومعلومات المتجر الأساسية](#أ-إنشاء-التطبيق-ومعلومات-المتجر-الأساسية)
   - [ب. استبيان أمان البيانات (Data Safety) خطوة بخطوة](#ب-استبيان-أمان-البيانات-data-safety-خطوة-بخطوة)
   - [ج. وصول التطبيق وبيانات فاحص جوجل (App Access) - هام جداً](#ج-وصول-التطبيق-وبيانات-فاحص-جوجل-app-access---هام-جداً)
   - [د. التصنيف العمري وسياسات المحتوى](#د-التصنيف-العمري-وسياسات-المحتوى)
   - [هـ. الأصول الرسومية المطلوبة لمتجر جوجل](#هـ-الأصول-الرسومية-المطلوبة-لمتجر-جوجل)
   - [و. بناء ورفع حزمة الـ App Bundle (.aab)](#و-بناء-ورفع-حزمة-الـ-app-bundle-aab)
5. [خطوات النشر على Apple App Store (App Store Connect) بالتفصيل](#5-خطوات-النشر-على-apple-app-store-app-store-connect-بالتفصيل)
   - [أ. الشهادات والـ Identifiers في حساب المطور](#أ-الشهادات-والـ-identifiers-في-حساب-المطور)
   - [ب. إعداد التطبيق في App Store Connect](#ب-إعداد-التطبيق-في-app-store-connect)
   - [ج. ملصقات الخصوصية (App Privacy Nutrition Labels)](#ج-ملصقات-الخصوصية-app-privacy-nutrition-labels)
   - [د. تعليمات مراجع آبل (App Review Information) - سر القبول من أول مرة](#د-تعليمات-مراجع-آبل-app-review-information---سر-القبول-من-أول-مرة)
   - [هـ. بناء ورفع الـ Build عبر Xcode / IPA](#هـ-بناء-ورفع-الـ-build-عبر-xcode--ipa)
6. [نصوص الوصف والبيانات الجاهزة للنسخ واللصق](#6-نصوص-الوصف-والبيانات-الجاهزة-للنسخ-واللصق)

---

## 1. الاستعدادات التقنية وحل أسباب الرفض الشائعة

لقد قمنا بتجهيز وضبط المشروع بالكامل لتفادي أي ثغرات قد تسبب رفض التطبيق:

| سبب الرفض المعتاد في المتاجر | كيف تم حله وتجهيزه في التطبيق؟ |
| :--- | :--- |
| **اسم الحزمة الافتراضي `com.example.*`** | تم تحديث معرف التطبيق في الأندرويد والـ iOS إلى `com.ismart.messenger`، لأن جوجل ترفض أي تطبيق يحتوي على `com.example`. |
| **صلاحية `REQUEST_INSTALL_PACKAGES`** | تم حذف هذه الصلاحية الخطيرة من `AndroidManifest.xml` نهائيًا لأن متجر جوجل بلاي يحظر التطبيقات التي تقوم بتنزيل وتثبيت تحديثات خارج المتجر. |
| **نقص صلاحيات الصوت والميكروفون** | تم إضافة `RECORD_AUDIO` و `VIBRATE` و `ACCESS_NETWORK_STATE` وأذونات الوسائط لضمان عمل التسجيلات والإشعارات دون انهيار التطبيق. |
| **عدم توفر سياسة الخصوصية داخل التطبيق** | تم إضافة رابط مباشر لسياسة الخصوصية في شاشة تسجيل الدخول وشاشة الملف الشخصي، وإتاحة صفحة ويب نشطة عبر السيرفر. |
| **طلب فاحص المتجر تسجيل دخول دون معرفة السيرفر** | تم إضافة زر واضح لضبط الخادم في شاشة الدخول مع إعداد سيرفر افتراضي نشط ودليل تفصيلي لكتابته في ملاحظات المراجعة. |
| **استبيان التشفير لآبل (US Export Compliance)** | تم ضبط `<key>ITSAppUsesNonExemptEncryption</key><false/>` في `Info.plist` لتخطي أسئلة التشفير المعقدة تلقائيًا. |

---

## 2. تقليل حجم التطبيق وأثره على الأداء والوظائف

### الإجابة المباشرة: هل يمكن تقليل الحجم؟ وهل يؤثر على الوظائف؟
**نعم، يمكن تقليله بنسبة تفوق 60% إلى 65%، ولن يؤثر نهائياً على أي وظيفة من وظائف التطبيق!**

### كيف يتم ذلك عملياً؟
1. **رفع Android App Bundle (`.aab`) بدلاً من Universal APK**:
   - التطبيق يحتوي على مكتبة معالجة الصور ومسح المستندات القوية **OpenCV** بحجمها الطبيعي.
   - ملف الـ APK الشامل يجمع ملفات تشغيل كافة المعالجات (`arm64-v8a` + `armeabi-v7a` + `x86_64`) فينتج حجم كبير يتجاوز 130 ميجابايت.
   - عندما تقوم برفع بصيغة **App Bundle (`.aab`)**، يقوم متجر جوجل بلاي بتقسيم التطبيق تلقائيًا (Dynamic Delivery)، بحيث يحمّل هاتف المستخدم فقط النسخة المتوافقة مع معالجه (وهي `arm64-v8a` لمعظم الهواتف الحديثة).
   - **النتيجة**: حجم التنزيل على هاتف المستخدم في المتجر ينخفض إلى حوالي **35 إلى 45 ميجابايت فقط!**

2. **تفعيل تقليص الكود والموارد الميتة (R8 & Resource Shrinking)**:
   - تم تفعيل `isMinifyEnabled = true` و `isShrinkResources = true` في `mobile_app/android/app/build.gradle.kts`.
   - تم ضبط ملف `proguard-rules.pro` بعناية فائقة لحماية جميع دوال OpenCV، و CameraX، و Firebase، والواجهات الأصلية حتى لا يتأثر المسح الضوئي أو المحادثات إطلاقًا.

---

## 3. إنشاء مفتاح التوقيع الرقمي (Release Keystore)

قبل رفع التطبيق لمتجر جوجل، يجب توليد مفتاح توقيع مشفر والاحتفاظ به في مكان آمن جدًا (إذا ضاع هذا المفتاح فلن تتمكن من تحديث تطبيقك في المستقبل).

### خطوة 1: توليد المفتاح عبر موجه الأوامر (Terminal)
قم بفتح PowerShell في جهازك ونفذ الأمر التالي في سطر واحد:

```powershell
keytool -genkey -v -keystore "f:\iSmart New Github\iSmart-Messenger\mobile_app\upload-keystore.jks" -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

> سيطلب منك إدخال كلمة مرور (اختر كلمة مرور قوية واحفظها)، ثم يسألك عن الاسم والشركة، ثم اضغط Enter.

### خطوة 2: ربط المفتاح بالمشروع
قم بإنشاء ملف باسم `key.properties` داخل مجلد `mobile_app/android/`:

```properties
storePassword=كلمة_المرور_التي_اخترتها
keyPassword=كلمة_المرور_التي_اخترتها
keyAlias=upload
storeFile=../upload-keystore.jks
```

> **ملاحظة أمان**: ملف `upload-keystore.jks` و `key.properties` تمت إضافتهما بالفعل إلى `.gitignore` حتى لا يتم رفعهما على مستودع GitHub العام بالخطأ.

---

## 4. خطوات النشر على Google Play Console بالتفصيل الممل

رابط اللوحة: [Google Play Console](https://play.google.com/console)

### أ. إنشاء التطبيق ومعلومات المتجر الأساسية
1. ادخل إلى حسابك في Google Play Console واضغط على زر **Create app** (إنشاء تطبيق).
2. **App name**: اكتب اسم التطبيق: `iSmart Messenger`.
3. **Default language**: اختر اللغة الافتراضية (العربية `ar` أو الإنجليزية `en-US`).
4. **App or game**: اختر **App**.
5. **Free or paid**: اختر **Free**.
6. وافق على شروط وإقرارات المطور واضغط **Create app**.

---

### ب. استبيان أمان البيانات (Data Safety) خطوة بخطوة
توجه في القائمة الجانبية إلى **Policy and programs** > **App content** > **Data safety** واضغط Start:

1. **Does your app collect or share any of the required user data types?**  
   -> اختر **Yes** (نعم).
2. **Is all of the user data collected by your app encrypted in transit?**  
   -> اختر **Yes** (نعم - كافة الاتصالات مشفرة عبر HTTPS و WSS).
3. **Do you provide a way for users to request that their data be deleted?**  
   -> اختر **Yes** (نعم).
4. **Add a link that users can use to request their data deletion**:  
   -> ضع الرابط: `https://ismartdbacd.dpdns.org/privacy-policy` أو بريد الدعم.

#### تحديد أنواع البيانات (Data Types):
- **Location (الموقع الجغرافي)**: لا تجمع بيانات موقع (اختر No).
- **Personal info (البيانات الشخصية)**:
  - حدد: **Name** و **User IDs**.
  - الإجابة لكل منهما: Collected: Yes | Shared: No | Ephemeral: No | Is this data required: Yes | Purpose: Account management & App functionality.
- **Photos and videos (الصور والفيديوهات)**:
  - حدد: **Photos** و **Videos**.
  - Collected: Yes | Shared: No | Ephemeral: No | Purpose: App functionality (Document scanning & Chat attachments).
- **Audio files (الملفات الصوتية)**:
  - حدد: **Voice or sound recordings**.
  - Collected: Yes | Shared: No | Ephemeral: No | Purpose: App functionality (Chat voice notes).
- **Device or other IDs (معرفات الأجهزة)**:
  - حدد: **Device or other IDs** (خاصة بإشعارات Firebase).
  - Purpose: App functionality / Analytics.

---

### ج. وصول التطبيق وبيانات فاحص جوجل (App Access) - هام جداً
> **تحذير**: هذا هو السبب رقم 1 لرفض التطبيقات التي تتطلب تسجيل دخول! فاحص جوجل يجب أن يتمكن من الدخول واستعراض كافة الميزات.

1. ادخل إلى **App content** > **App access**.
2. اختر **All or some functionality is restricted** (جميع الوظائف أو بعضها مقيد).
3. اضغط على **+ Add instructions** (إضافة تعليمات).
4. املأ البيانات كالتالي بالضبط:
   - **Title**: `Reviewer Demo Login`
   - **User name / phone number**: `demo_user` (أو الحساب الذي تنشئه للمراجع)
   - **Password**: `demo_password123`
   - **Any other instructions (التعليمات الإضافية)**:
     انسخ النص التالي بالإنجليزية والصقه في الحقل:
     ```text
     1. Open the application.
     2. On the login screen, verify that the Server URL is set to: https://ismartdbacd.dpdns.org
     3. If you need to change or verify the server address, tap "إعدادات الخادم" (Server Settings) at the bottom, enter: https://ismartdbacd.dpdns.org and tap "حفظ وتطبيق" (Save).
     4. Enter Username: demo_user
     5. Enter Password: demo_password123
     6. Tap "تسجيل الدخول" (Login) to access the complete workspace, scanner, and chat features.
     ```

---

### د. التصنيف العمري وسياسات المحتوى
1. **Privacy Policy (سياسة الخصوصية)**:
   - الرابط: `https://ismartdbacd.dpdns.org/privacy-policy`
2. **Ads (الإعلانات)**:
   - اختر **No, my app does not contain ads** (تطبيقي لا يحتوي على إعلانات).
3. **Target audience and content (الجمهور المستهدف)**:
   - اختر الفئة العمرية: **18 and over** (18 سنة فما فوق).
   - "Could your store listing appeal to children?": اختر **No**.
4. **News apps (تطبيقات الأخبار)**: اختر **No**.
5. **COVID-19 contact tracing**: اختر **My app is not a COVID-19 tracing app**.
6. **Financial features**: اختر **My app doesn't provide any financial features**.
7. **Government apps**: اختر **No**.
8. **Content Rating (IARC Questionnaire)**:
   - أدخل بريدك الإلكتروني.
   - الفئة: **Utility, Productivity, Communication, or other**.
   - أجب بـ **No** على أسئلة العنف، والمخدرات، والشتائم، والقمار.
   - سيمنحك المتجر تصنيف **Everyone / 3+**.

---

### هـ. الأصول الرسومية المطلوبة لمتجر جوجل (Store Listing Assets)

توجه إلى **Store presence** > **Main store listing**:
1. **App icon**:
   - المقاس: `512 x 512` بكسل بصيغة PNG (شفاف أو بخلفية)، حجم أقل من 1 ميجابايت.
2. **Feature graphic (الرسم المميز)**:
   - المقاس: `1024 x 500` بكسل بصيغة PNG أو JPG.
3. **Phone screenshots (لقطات الشاشة للهاتف)**:
   - الحد الأدنى 4 صور والأفضل 6-8 صور.
   - الأبعاد المقترحة: `1080 x 2400` أو `1080 x 1920` بكسل.
   - اللقطات المقترحة:
     1. شاشة تسجيل الدخول الأنيقة.
     2. شاشة الماسح الضوئي وتحديد الأطراف تلقائيًا.
     3. شاشة معاينة المستندات الممسوحة وفلاتر الوضوح.
     4. شاشة المحادثات الفورية والرسائل الصوتية.
     5. شاشة جرد ومسح أصول تقنية المعلومات (QR / Barcode).

---

### و. بناء ورفع حزمة الـ App Bundle (.aab)

افتح موجه الأوامر في مسار المشروع ونفذ:

```bash
cd mobile_app
flutter clean
flutter pub get
flutter build appbundle --release
```

- ستجد الملف الناتج جاهزاً في المسار:  
  `mobile_app/build/app/outputs/bundle/release/app-release.aab`
- توجه إلى Google Play Console > **Production** > **Create new release**.
- اسحب ملف `app-release.aab` وأفلته في المربع.
- اكتب اسم الإصدار وملاحظات الإصدار (Release notes) مثل:  
  `الإصدار الأول لمنظومة iSmart Messenger للمحادثات ومسح المستندات.`
- اضغط **Save** ثم **Review release** ثم **Start rollout to Production**!

---

## 5. خطوات النشر على Apple App Store (App Store Connect) بالتفصيل

رابط اللوحة: [App Store Connect](https://appstoreconnect.apple.com)

### أ. الشهادات والـ Identifiers في حساب المطور
1. ادخل إلى [developer.apple.com/account](https://developer.apple.com/account).
2. في قسم **Certificates, Identifiers & Profiles** > **Identifiers**:
   - اضغط `+` وأنشئ **App ID**.
   - حدد نوعه App، ثم ضع:
     - **Description**: `iSmart Messenger`
     - **Bundle ID**: حدد Explicit واكتب `com.ismart.messenger`
   - فعّل ميزة **Push Notifications** واضغط Save.
3. أنشئ **Apple Distribution Certificate** و **Provisioning Profile (App Store)**.

---

### ب. إعداد التطبيق في App Store Connect
1. في App Store Connect اضغط على **My Apps** ثم علامة `+` > **New App**.
2. **Platforms**: اختر **iOS**.
3. **Name**: `iSmart Messenger`.
4. **Primary Language**: العربية أو الإنجليزية.
5. **Bundle ID**: اختر `com.ismart.messenger` الذي أنشأته.
6. **SKU**: اكتب كوداً فريداً مثل `ISMART-MSG-001`.
7. **User Access**: Full Access.

---

### ج. ملصقات الخصوصية (App Privacy Nutrition Labels)
توجه في القائمة الجانبية إلى **App Privacy**:
1. ضع رابط سياسة الخصوصية: `https://ismartdbacd.dpdns.org/privacy-policy`.
2. اضغط على **Get Started** للإجابة على الأسئلة:
   - **Data Collection**: نعم نجمع بيانات.
   - **Contact Info**: Name (الاسم) -> App Functionality | Linked to User: Yes | Tracking: No.
   - **User Content**: Photos or Videos + Audio Data (للمسح الصوتي والمرفقات) -> App Functionality | Linked to User: Yes | Tracking: No.
   - **Identifiers**: User ID (لمصادقة الحساب) -> App Functionality | Linked to User: Yes | Tracking: No.
   - **Diagnostics**: Crash Data -> App Functionality | Not Linked to User.
3. اضغط **Publish** لنشر ملصق الخصوصية.

---

### د. تعليمات مراجع آبل (App Review Information) - سر القبول من أول مرة
> **تنبيه حاسم من سياسات آبل (Guideline 2.1 - App Completeness)**: مراجعو شركة آبل يقومون بفتح التطبيق على أجهزة آيفون حقيقية في مقر الشركة. إذا لم يتمكنوا من تسجيل الدخول فوراً أو لم يعمل السيرفر فسيتم رفض التطبيق في غضون دقائق!

في صفحة بيانات الإصدار تحت قسم **App Review Information**:
1. حدد مربع **Sign-in required** (يتطلب تسجيل دخول).
2. **User Name**: `demo_user` (أنشئ هذا الحساب في قاعدة البيانات لديك).
3. **Password**: `demo_password123`.
4. في مربع **Notes (ملاحظات للمراجع)** اكتب النص الإنجليزي التالي حرفيًا:

```text
Dear Apple Review Team,

This application is an internal workplace messaging and document scanning solution for businesses.

To review the application:
1. Open the app on the login screen.
2. The app is pre-configured to connect to our live secure testing server: https://ismartdbacd.dpdns.org
3. If you need to view or re-test the server configuration, tap "إعدادات الخادم" (Server Settings) at the bottom of the screen.
4. Enter the test credentials:
   - Username: demo_user
   - Password: demo_password123
5. Tap "تسجيل الدخول" (Login).
6. Once logged in, you can test:
   - Live Camera scanning with OpenCV edge detection and PDF compilation.
   - Workplace chat messaging and voice note recordings (Microphone).
   - IT Asset inventory scanning via QR/Barcode.

Our live privacy policy is accessible at:
https://ismartdbacd.dpdns.org/privacy-policy

If you have any questions or require additional credentials, please contact us at support@ismart.com.
```

5. **Attachment (مرفق اختياري ومستحسن)**:
   - سجل فيديو شاشة مدته 30 ثانية لهاتف آيفون يوضح عملية تسجيل الدخول وتجربة الماسح والمحادثة وارفعه هنا لضمان قبول سريع.

---

### هـ. بناء ورفع الـ Build عبر Xcode / IPA

من جهاز Mac أو بيئة CI/CD:

```bash
cd mobile_app
flutter clean
flutter pub get
flutter build ipa --release
```

ثم استخدام **Transporter App** أو **Xcode Organizer** لرفع الأرشيف مباشرة إلى App Store Connect. بعد اكتمال معالجة النسخة، اختر الـ Build في صفحة الإصدار واضغط **Submit for Review**!

---

## 6. نصوص الوصف والبيانات الجاهزة للنسخ واللصق

### اسم التطبيق (App Name):
`iSmart Messenger`

### الوصف القصير (Short Description - حتى 80 حرفاً):
`منظومة العمل الذكية للمراسلة الفورية، مسح المستندات، وإدارة الأصول.`

### الوصف الكامل (Full Description):
```text
تطبيق iSmart Messenger هو الحل المؤسسي المتكامل لإدارة التواصل والمهام الميدانية والمكتبية داخل الشركات والمؤسسات.

أبرز مميزات التطبيق:
• مسح المستندات الذكي: معالجة متقدمة لصور المستندات باستخدام تقنيات الذكاء الاصطناعي وOpenCV، مع كشف تلقائي دقيق لأطراف الورقة، وتطبيق فلاتر التوضيح، وتجميع المستندات في ملفات PDF عالية الدقة.
• المحادثات المؤسسية الآمنة: غرف دردشة فردية وجماعية مع دعم الرسائل النصية، والملاحظات الصوتية المباشرة، ومشاركة الصور والمستندات والملفات الكبيرة بسرعة فائقة.
• جرد وأصول تقنية المعلومات (IT Assets): مسح سريع لأكواد QR والباركود للتعرف الفوري على عهد وأجهزة الشركة ومتابعة حالتها وموقعها الجغرافي المسجل.
• مرونة الاتصال بالخوادم: إمكانية تخصيص رابط السيرفر المباشر للربط مع خوادم شركتك المحلية أو السحابية مع تشفير كامل لكافة المراسلات.
• أمان وسرية البيانات: حماية متكاملة للبيانات وحفظ محلي آمن في الذاكرة المشفرة للهاتف، دون أي إعلانات ودون تتبع تجاري.

للاستفسارات والدعم الفني:
support@ismart.com
```

---

## 7. فحص الجاهزية النهائي (Pre-Launch Checklist)

- [x] تم حذف إذن `REQUEST_INSTALL_PACKAGES` لمنع رفض جوجل بلاي التلقائي.
- [x] تم تفعيل وضبط `RECORD_AUDIO` و `CAMERA` وأذونات الوسائط الحديثة.
- [x] تم تحديث معرف التطبيق (Bundle ID) إلى `com.ismart.messenger`.
- [x] تم تفعيل تصغير حجم الكود والموارد عبر R8 Proguard وقواعد حماية OpenCV.
- [x] تم إنشاء سياسة الخصوصية ونشرها برابط مباشر يعمل على السيرفر والإنترنت.
- [x] تم إضافة رابط سياسة الخصوصية في شاشتي الدخول والملف الشخصي.
- [x] تم توفير حساب تجريبي وتفاصيل الخادم باللغة الإنجليزية في تعليمات الفاحص.
- [x] تم ضبط خيار التشفير المعفى لآبل `ITSAppUsesNonExemptEncryption`.

**تطبيقك الآن جاهز تماماً 100% للبناء والرفع والقبول بإذن الله من المرة الأولى!**
