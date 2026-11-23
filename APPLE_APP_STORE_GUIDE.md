# الدليل الشامل والنهائي لإطلاق تطبيق **iSmart Messenger** على متجر Apple App Store و TestFlight

**المشروع:** iSmart Messenger  
**الفرع المخصص:** `ios/mac-setup`  
**الإصدار:** `1.2.9+13`  

---

## 1. الهوية النهائية المعتمدة في مشروع iOS

تم توحيد جميع المعرّفات والإعدادات في Xcode و Dart والباك إند لتطابق حساب المطور الخاص بك:

| البند | القيمة النهائية المعتمدة | الملف المرجعي |
| :--- | :--- | :--- |
| **App Bundle ID (Main Target)** | `com.ismartmessenger.app` | `mobile_app/ios/Runner.xcodeproj/project.pbxproj` |
| **Tests Bundle ID** | `com.ismartmessenger.app.RunnerTests` | `mobile_app/ios/Runner.xcodeproj/project.pbxproj` |
| **Apple Development Team ID** | `9SGAUMPF23` | `mobile_app/ios/Runner.xcodeproj/project.pbxproj` |
| **Display Name & Bundle Name** | `iSmart Messenger` | `mobile_app/ios/Runner/Info.plist` |
| **Version / Build Number** | `1.2.9` (`13`) | `mobile_app/pubspec.yaml` + `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)` |
| **Minimum iOS Deployment Target** | `15.0` | `mobile_app/ios/Podfile` + `project.pbxproj` |
| **Supported Device Family** | `1,2` (**iPhone & iPad**) | `mobile_app/ios/Runner.xcodeproj/project.pbxproj` |
| **Supported Localizations** | `ar`, `en` | `mobile_app/ios/Runner/Info.plist` (`CFBundleLocalizations`) |
| **Export Compliance (`ITSAppUsesNonExemptEncryption`)** | `false` | `mobile_app/ios/Runner/Info.plist` |
| **APNs Entitlement (`aps-environment`)** | `development` (يتحول تلقائياً إلى `production` عند Archive للرفع) | `mobile_app/ios/Runner/Runner.entitlements` |
| **Export Method** | `app-store-connect` / `automatic` Signing | `mobile_app/ios/exportOptions.plist` |

> [!IMPORTANT]
> لا تقم أبداً برفع ملفات الشهادات أو مفاتيح Apple أو Firebase الخاصة (`.p8`، `.p12`، `.mobileprovision`، `GoogleService-Info.plist`، أو ملف `firebase-adminsdk-*.json`) إلى مستودع Git العام.

---

## 2. الدليل التفصيلي الكامل لربط الإشعارات مع Firebase و Apple (APNs)

تم تجهيز كود Flutter iOS والباك إند ونغمات `.caf` بالكامل ليدعم إشعارات iOS (في الواجهة Foreground، وفي الخلفية Background، وعند إغلاق التطبيق Terminated). ولكي تصل الإشعارات فعلياً لأجهزة الآيفون من Firebase، يجب إتمام خطوات الربط التالية بين **Apple Developer Portal** و **Firebase Console**:

### الخطوة 2.1: إنشاء مفتاح APNs Authentication Key (`.p8`) في Apple Developer
1. افتح [developer.apple.com/account](https://developer.apple.com/account) وسجّل الدخول بحساب الفريق `9SGAUMPF23`.
2. من القائمة الجانبية ادخل إلى **Certificates, Identifiers & Profiles**.
3. اختر **Keys** من القائمة اليسرى، ثم اضغط على علامة **(+)** لإنشاء مفتاح جديد.
4. في خانة **Key Name** اكتب اسماً واضحاً مثل: `iSmart Messenger APNs Key`.
5. فعّل خيار **Apple Push Notifications service (APNs)** (واختر Sandbox & Production إذا طُلب منك Scope).
6. اضغط **Continue** ثم **Register**.
7. اضغط **Download** لتنزيل الملف بصيغة `AuthKey_XXXXXXXXXX.p8`.
   - **تنبيه حرج:** تسمح Apple بتنزيل ملف `.p8` **مرة واحدة فقط**. احفظه في مكان آمن على جهازك (خارج مجلد Git)، وانسخ **Key ID** الظاهر أمامك (10 أحرف/أرقام) وكذلك **Team ID** الخاص بك (`9SGAUMPF23`).

### الخطوة 2.2: تسجيل App ID وتفعيل Push Notifications على Apple Developer
1. من **Certificates, Identifiers & Profiles** اختر **Identifiers** ثم اضغط **(+)**.
2. اختر **App IDs** > **Continue**، ثم اختر **App** > **Continue**.
3. املأ البيانات:
   - **Description**: `iSmart Messenger`
   - **Bundle ID**: اختر **Explicit** واكتب بالضبط: `com.ismartmessenger.app`
4. مرّر لأسفل في قائمة **Capabilities** وفعّل:
   - **Push Notifications** (تأكد من وجود علامة صح أمامه — بدون Configure إضافي لأننا نستخدم مفتاح `.p8` الحديث وليس شهادة `.p12` القديمة).
5. اضغط **Continue** ثم **Register**.

### الخطوة 2.3: إضافة تطبيق iOS في Firebase Console وربط `GoogleService-Info.plist`
> [!WARNING]
> كود [firebase_options.dart](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/lib/firebase_options.dart) يحتوي حالياً على `iosBundleId: 'com.ismartmessenger.app'` لمشروع `ismart-messenger` (رقم المرسل `1039491251685`)، لكن `appId` و `apiKey` الحاليين كانا مسجلين وقت إنشاء المشروع السابق، ولا يوجد حالياً ملف `GoogleService-Info.plist` داخل `mobile_app/ios/Runner/`. لذلك هذه الخطوة إلزامية قبل اختبار الإشعارات على جهاز حقيقي.

1. افتح [console.firebase.google.com](https://console.firebase.google.com) وادخل إلى مشروع **`ismart-messenger`**.
2. من **Project Overview** اضغط على **+ Add app** واختر أيقونة **iOS (Apple)** (أو ادخل **Project Settings > General > Your apps > Add app**).
3. في خانة **Apple bundle ID** اكتب بالضبط:
   ```text
   com.ismartmessenger.app
   ```
   - **App nickname (اختياري):** `iSmart Messenger iOS`
   - **App Store ID (اختياري الآن):** اتركه فارغاً أو أضفه لاحقاً بعد إنشاء التطبيق على App Store Connect.
4. اضغط **Register app**.
5. قم بتنزيل ملف **`GoogleService-Info.plist`**.
6. لإضافته بالطريقة الصحيحة إلى مشروع Xcode (لكي يُضمّن تلقائياً في Bundle التطبيق):
   - افتح المشروع في Xcode:
     ```bash
     open mobile_app/ios/Runner.xcworkspace
     ```
   - اسحب ملف `GoogleService-Info.plist` وأفلته داخل مجلد **`Runner`** (بجانب `Info.plist` في شجرة الملفات اليسرى).
   - في نافذة التأكيد: فعّل **Copy items if needed** وتأكد أن الهدف المحدد في **Add to targets** هو **`Runner`** فقط.
7. **(الأفضل والأضمن) تحديث `firebase_options.dart` تلقائياً عبر FlutterFire CLI:**
   ```bash
   cd mobile_app
   flutterfire configure --project=ismart-messenger --platforms=ios --ios-bundle-id=com.ismartmessenger.app
   ```
   > سيتأكد هذا الأمر من مطابقة `apiKey` و `appId` و `iosBundleId` داخل `lib/firebase_options.dart` مع التطبيق المسجل في Firebase Console ومع ملف `GoogleService-Info.plist`.

### الخطوة 2.4: رفع مفتاح `.p8` داخل Firebase Console (Cloud Messaging)
1. داخل Firebase Console لمشروع `ismart-messenger`، افتح **Project Settings** (علامة الترس) > تبويب **Cloud Messaging**.
2. مرّر لأسفل إلى قسم **Apple app configuration** واضغط على تطبيق `com.ismartmessenger.app`.
3. تحت **APNs Authentication Key** اضغط **Upload**:
   - **APNs Auth Key:** ارفع ملف `AuthKey_XXXXXXXXXX.p8` الذي حملته في الخطوة 2.1.
   - **Key ID:** أدخل Key ID المكون من 10 خانات.
   - **Team ID:** أدخل **`9SGAUMPF23`**.
4. اضغط **Upload**. بهذا يصبح خادم Firebase قادراً على توجيه إشعارات FCM إلى خوادم Apple APNs لكل من بيئة التطوير (Debug / Xcode المباشر) والإنتاج (TestFlight / App Store).

### الخطوة 2.5: تجهيز الباك إند (Firebase Admin SDK) وميزات إشعارات iOS المدمجة
1. تأكد أن سيرفر الإنتاج الخارجي لديه مفتاح حساب الخدمة (Service Account JSON) لمشروع **`ismart-messenger`** مضبوطاً عبر أحد متغيرات البيئة في [push-notification.service.js](file:///Users/yousef/Desktop/iSmart-Messenger/backend/src/services/push-notification.service.js):
   - `FIREBASE_SERVICE_ACCOUNT_PATH=/secure/path/ismart-messenger-firebase-adminsdk.json`
   - أو `FIREBASE_SERVICE_ACCOUNT_JSON` / `FIREBASE_SERVICE_ACCOUNT_BASE64`.
2. **ما تم تجهيزه برمجياً في هذا الإصدار للباك إند و iOS:**
   - تحويل النغمات المخصصة إلى صيغة Apple الأصلية **CAF (`LEI16@44100`)** وتضمينها داخل حزمة `Runner`:
     - `default_tone.caf` (2.04 ثانية)
     - `chime_tone.caf` (0.50 ثانية)
     - `alert_tone.caf` (1.85 ثانية)
   - يقوم الباك إند عبر `groupPushDevicesByAndroidChannel` بتجميع أجهزة iOS حسب النغمة المختارة (`notificationToneId`) وتكوين حمولة `apns` عبر `buildApnsPayload`:
     - `headers`: `apns-push-type: "alert"`، و `apns-priority: "10"`، و `apns-collapse-id`.
     - `payload.aps`: `sound` (`default_tone.caf` / `chime_tone.caf` / `alert_tone.caf` أو صامت عند `silent`)، و `threadId` لتجميع محادثات كل غرفة معاً، و `mutableContent: true`، و `contentAvailable: true`، و `category: "chat_reply_category"`.
   - في التطبيق (`AppDelegate.swift` + `main.dart` + `push_notification_service.dart` + `local_notification_service.dart`):
     - تهيئة Firebase مبكراً قبل تسجيل `firebaseMessagingBackgroundHandler`.
     - تسجيل `GeneratedPluginRegistrant.register(with: self)` قبل `application.registerForRemoteNotifications()` وتعيين `UNUserNotificationCenter.current().delegate`.
     - تصفير شارة (Badge) أيقونة التطبيق تلقائياً عند فتح التطبيق في `applicationDidBecomeActive`.
     - الانتظار الذكي لـ `getAPNSToken()` على iOS (حتى 8 محاولات بفارق ثانية) قبل طلب `getToken()` من FCM ثم التسجيل في `/api/users/me/push-devices` مع إرسال `appVersion`.
     - إلغاء التقديم التلقائي المزدوج من FCM في الواجهة (`alert: false, badge: false, sound: false`) ليتولى `LocalNotificationService` عرض التنبيه أو كتمه حسب تفضيلات المستخدم (كتم الصوت، إخفاء المعاينة، المحادثة المفتوحة حالياً، أو إلغاء التكرار عبر `messageId`).
     - دعم تصنيف الرد السريع `chat_reply_category` (`DarwinNotificationCategoryAction` + `DarwinNotificationAction.text`) وفحص الصلاحية الفعلي عبر `checkPermissions()` بدون إرجاع `true` وهمياً.

### الخطوة 2.6: قائمة التحقق والاختبار على جهاز iPhone حقيقي
> [!NOTE]
> لا يُصدر **iOS Simulator** رمز APNs حقيقي ولا تصل إليه إشعارات Apple البعيدة، لذلك يجب تنفيذ هذا الاختبار على **جهاز iPhone حقيقي** (وليس المحاكي) بعد ربط `.p8` و `GoogleService-Info.plist`.

1. وصّل جهاز iPhone بالكمبيوتر وافتح التطبيق من Xcode أو عبر:
   ```bash
   cd mobile_app && flutter run --release -d <DEVICE_ID>
   ```
2. عند ظهور نافذة طلب إذن الإشعارات، اضغط **Allow / السماح**.
3. سجّل الدخول بحساب فعلي ثم تحقق في Console Xcode أو قاعدة بيانات السيرفر من وصول طلب `POST /api/users/me/push-devices` بقيمة `platform: "ios"` و `token` غير فارغ و `appVersion`.
4. اختبر الحالات الأربع:
   - **إشعار محلي تجريبي:** من شاشة الإعدادات > الإشعارات > اضغط **اختبار إشعار** وتأكد من سماع النغمة `.caf` المختارة.
   - **التطبيق في الواجهة (Foreground):** أرسل رسالة من حساب آخر وتأكد من ظهور إشعار واحد فقط (بدون تكرار) وصمت إذا كانت المحادثة مفتوحة حالياً.
   - **التطبيق في الخلفية (Background):** اضغط Home وأرسل رسالة وتأكد من ظهور البنر وتجميع الرسائل بنفس المحادثة (`threadId`) وظهور خيار الرد السريع بالضغط المطول.
   - **التطبيق مغلق بالكامل (Terminated):** اسحب التطبيق لإغلاقه وأرسل رسالة، ثم اضغط على الإشعار وتأكد من فتح المحادثة مباشرة.

---

## 3. الدليل التفصيلي لإنشاء التطبيق والرفع إلى TestFlight و App Store Connect

### الخطوة 3.1: إنشاء سجل التطبيق على App Store Connect
1. ادخل إلى [appstoreconnect.apple.com](https://appstoreconnect.apple.com) وسجّل الدخول بنفس حساب الفريق `9SGAUMPF23`.
2. افتح قسم **Apps** واضغط زر **(+)** > **New App**.
3. أدخل القيم التالية:
   - **Platforms:** `iOS`
   - **Name:** `iSmart Messenger` *(أو الاسم المتاح إذا كان محجوزاً؛ يمكنك مثلاً `iSmart Messenger App` مع الإبقاء على Display Name داخل الهاتف `iSmart Messenger`)*
   - **Primary Language:** `Arabic` (أو `English (U.S.)` حسب لغتك الأساسية في المتجر، مع إضافة الترجمة الأخرى في صفحة الإصدار)
   - **Bundle ID:** اختر **`com.ismartmessenger.app`** (الذي سجلته في الخطوة 2.2)
   - **SKU:** معرّف داخلي فريد مثل `ismart-messenger-ios-2026`
   - **User Access:** `Full Access`
4. اضغط **Create**.

### الخطوة 3.2: ضبط التوقيع (Signing) في Xcode قبل الأرشفة
1. افتح الـ Workspace (وليس `.xcodeproj` أبداً):
   ```bash
   open mobile_app/ios/Runner.xcworkspace
   ```
2. في الشريط الأيسر، اضغط على مشروع **Runner**.
3. اختر الهدف (**TARGET**) **`Runner`** > تبويب **Signing & Capabilities**:
   - فعّل **Automatically manage signing**.
   - تأكد أن **Team** مضبوط على فريقك **`9SGAUMPF23`**.
   - تأكد أن **Bundle Identifier** هو **`com.ismartmessenger.app`**.
   - تأكد من وجود Capability باسم **Push Notifications** أسفل التبويب (وإذا لم تكن مضافة اضغط **+ Capability** وأضف **Push Notifications**).
4. اختر الهدف (**TARGET**) **`RunnerTests`** > تبويب **Signing & Capabilities**:
   - فعّل **Automatically manage signing**.
   - تأكد أن **Team** مضبوط على **`9SGAUMPF23`** و **Bundle Identifier** هو **`com.ismartmessenger.app.RunnerTests`**.

### الخطوة 3.3: الأرشفة والتحقق والرفع إلى TestFlight و App Store

#### الطريقة الأولى: عبر Xcode GUI (الموصى بها — الأوضح في معالجة الشهادات)
1. قبل الأرشفة، يفضّل تشغيل تحضير Flutter لضمان أحدث كود Dart و `Release.xcconfig`:
   ```bash
   export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
   cd mobile_app
   flutter pub get
   flutter build ios --release --config-only
   ```
2. في أعلى نافذة Xcode بجانب زر التشغيل، غيّر الجهاز الهدف إلى: **`Any iOS Device (arm64)`**.
3. من الشريط العلوي لـ Mac اختر: **Product** > **Archive**.
4. عند انتهاء البناء، ستفتح نافذة **Organizer** تلقائياً:
   - اضغط **Validate App** أولاً للتحقق من الشهادات والـ Entitlements والأيقونة والخصوصية قبل الرفع.
   - بعد ظهور علامة النجاح الخضراء، اضغط **Distribute App**.
   - اختر **App Store Connect** > **Upload** > اترك خيارات التوقيع التلقائية ورموز التصحيح (**Upload your app's symbols** مفعّل) > اضغط **Upload**.
5. خلال 5 إلى 20 دقيقة سيصلك بريد من Apple باكتمال معالجة البناء (**Build 13 / v1.2.9**) وسيظهر داخل تبويب **TestFlight** في App Store Connect.

#### الطريقة الثانية: عبر Terminal + تطبيق Transporter
تُستخدم إذا كانت شهادات التوزيع مثبتة مسبقاً في Keychain:
```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
cd mobile_app
flutter pub get
flutter build ipa --release --export-options-plist=ios/exportOptions.plist
```
سيتم إنتاج ملف `.ipa` داخل `mobile_app/build/ios/ipa/`. اسحب الملف إلى تطبيق **Transporter** (المجاني من Mac App Store) واضغط **Deliver**.

### الخطوة 3.4: خطوات النشر عبر TestFlight للمختبرين
1. في App Store Connect > تبويب **TestFlight**:
   - عند ظهور البناء `1.2.9 (13)` ستظهر بجواره حالة **Manage** للـ Export Compliance: تم ضبط `ITSAppUsesNonExemptEncryption = false` مسبقاً في `Info.plist` فتتخطاها Apple تلقائياً أو بموافقة فورية.
   - في **Internal Testing**: أضف أعضاء فريقك لتجربة التطبيق فوراً خلال دقائق.
   - في **External Testing**: أضف مجموعة خارجية واملأ "What to Test" وبيانات حساب الاختبار لإرسال النسخة لمراجعة TestFlight السريعة (عادة أقل من 24 ساعة).

---

## 4. بيانات المتجر الجاهزة للنسخ واللصق (Metadata & Assets)

### 4.1 بيانات المتجر الأساسية (عربي — Arabic)
- **App Name (الاسم — 30 حرفاً كحد أقصى):**
  `iSmart Messenger`
- **Subtitle (العنوان الفرعي — 30 حرفاً كحد أقصى):**
  `المراسلة المؤسسية ومسح الوثائق`
- **Promotional Text (النص الترويجي — 170 حرفاً كحد أقصى):**
  `منظومة تواصل مؤسسي متكاملة للمحادثات الآمنة، تسجيل الملاحظات الصوتية، مسح المستندات بدقة عالية، وإدارة أصول وتذاكر العمل من جوالك بسهولة.`
- **Keywords (الكلمات المفتاحية — 100 حرف كحد أقصى بدون مسافات بعد الفاصلة):**
  `مراسلة,شركات,دردشة,ماسح ضوئي,PDF,أعمال,تواصل,ملفات,QR,فرق العمل,إشعارات`
- **Support URL:**
  `https://ismartdbacd.dpdns.org`
- **Marketing URL (اختياري):**
  `https://ismartdbacd.dpdns.org`
- **Privacy Policy URL (إلزامي):**
  `https://ismartdbacd.dpdns.org/privacy-policy`
- **Copyright:**
  `© 2026 Yousef Mohamed`

- **Description (الوصف الكامل — عربي):**
```text
تطبيق iSmart Messenger هو المنظومة المؤسسية المتكاملة لإدارة التواصل اليومي والمهام الميدانية والمكتبية بين فرق العمل والأقسام داخل الشركات والمؤسسات.

أبرز الإمكانات والمميزات:
• محادثات مؤسسية فورية وآمنة: تواصل مباشر مع زملائك أو داخل مجموعات الأقسام والفروع مع إشعارات فورية موثوقة ومزامنة لحظية لحالة الاتصال والرسائل المقروءة.
• الرسائل الصوتية والوسائط: سجّل وأرسل الملاحظات الصوتية بوضوح داخل المحادثات، وشارك المستندات والصور والملفات مع زملائك بضغطة واحدة.
• ماسح المستندات الاحترافي (PDF): التقط صوراً للمستندات والفواتير مع اكتشاف الحواف وتحسين التباين تلقائياً وتجميع عدة صفحات في ملف PDF عالي الجودة جاهز للإرسال أو الطباعة.
• مركز الملفات والطباعة: أدر ملفاتك المرفوعة وقائمة الانتظار واطلب طباعة المستندات على طابعات العمل المعتمدة بسهولة.
• مسح أصول تقنية المعلومات (IT Assets): امسح أكواد QR والباركود للتحقق الفوري من عُهد الشركة والأجهزة وتحديث حالتها أو متابعة التذاكر.
• مرونة اتصال متقدمة: يتيح التطبيق ربط جهازك بالخادم الخارجي المعتمد أو خادم شبكتك الداخلية داخل بيئة العمل مع حفظ آمن لبيانات الجلسة عبر iOS Keychain.
• خصوصية كاملة والتحكم بالبيانات: بدون إعلانات وبدون تتبع، مع إتاحة استعراض سياسة الخصوصية وحذف الحساب والبيانات نهائياً مباشرة من داخل التطبيق.

ملاحظة: يتطلب التطبيق حساب عمل صادر من مؤسستك أو الاتصال بخادم المؤسسة المعتمد.
للدعم الفني: support@ismart.com
```

### 4.2 بيانات المتجر الأساسية (إنجليزي — English U.S. — يفضّل إضافتها لتحسين القبول العالمي)
- **Subtitle:** `Secure Team Chat & Doc Scanner`
- **Promotional Text:** `Unified enterprise messaging, voice notes, smart multi-page PDF document scanning, file sharing, and IT asset QR workflows in one fast iOS app.`
- **Keywords:** `enterprise,chat,messenger,scanner,pdf,workplace,team,files,qr,voice,business`
- **Description:**
```text
iSmart Messenger is an all-in-one workplace communication and document workflow app built for organizations and teams.

Key Features:
• Instant Workplace Messaging: Real-time direct, group, and department conversations with read receipts, presence indicators, and push notifications.
• Voice Notes & File Sharing: Record voice messages and share PDFs, scanned paperwork, and media seamlessly on iPhone and iPad.
• Smart Document Scanner: Capture multi-page documents and receipts using iOS VisionKit/camera scanning and export crisp PDF files.
• Operations & Print Hub: Track uploaded documents, manage print queues, and scan IT asset QR codes or manage workplace tickets.
• Flexible Server Connection: Connect securely to your organization’s external HTTPS server or internal workplace network with encrypted token storage via iOS Keychain.
• Privacy First: Zero ads, zero cross-app tracking, built-in offline privacy policy viewer, and direct in-app account deletion.

Note: Requires an active organizational account on your company server. Support: support@ismart.com
```

### 4.3 خريطة رفع الأصول الرسومية ولقطات الشاشة من `app_store_assets/`
تم تجهيز كافة الصور واللقطات في مجلد [`app_store_assets/`](file:///Users/yousef/Desktop/iSmart-Messenger/app_store_assets) بصيغة PNG 24-bit خالية تماماً من قناة الشفافية (`hasAlpha: no`):

| الحقل في App Store Connect | المسار المحلي في المشروع | المقاس المطلوب | الحالة |
| :--- | :--- | :--- | :--- |
| **App Store Icon** | [`app_store_assets/icons/AppIcon-1024x1024-AppStore.png`](file:///Users/yousef/Desktop/iSmart-Messenger/app_store_assets/icons/AppIcon-1024x1024-AppStore.png) | `1024 × 1024` | مدمجة أيضاً تلقائياً داخل Xcode `AppIcon.appiconset` |
| **iPhone 6.9" Display (إلزامي)** | [`app_store_assets/iphone_6.9_inch_1320x2868/`](file:///Users/yousef/Desktop/iSmart-Messenger/app_store_assets/iphone_6.9_inch_1320x2868) | `1320 × 2868` | 6 شاشات مرتبة من `01` إلى `06` |
| **iPhone 6.5" Display (اختياري/بديل)** | [`app_store_assets/iphone_6.5_inch_1284x2778/`](file:///Users/yousef/Desktop/iSmart-Messenger/app_store_assets/iphone_6.5_inch_1284x2778) | `1284 × 2778` | 6 شاشات مرتبة من `01` إلى `06` |
| **iPad 13" Display (إلزامي لأن التطبيق يدعم iPad)** | [`app_store_assets/ipad_13_inch_2064x2752/`](file:///Users/yousef/Desktop/iSmart-Messenger/app_store_assets/ipad_13_inch_2064x2752) | `2064 × 2752` | 6 شاشات مرتبة من `01` إلى `06` |

### 4.4 ملصقات الخصوصية (App Privacy Nutrition Labels)
في صفحة **App Privacy** داخل App Store Connect، يجب أن تطابق إجاباتك البيانات التي يعالجها التطبيق فعلياً في `PrivacyInfo.xcprivacy` والباك إند:
- **هل يجمع التطبيق بيانات؟** اختر **Yes, we collect data from this app**.
- البيانات المطلوب التصريح بها (وكلها لأغراض **App Functionality** فقط — **Linked to the user's identity: Yes** — **Used for tracking: No**):
  1. **Contact Info > Name** (الاسم الكامل والوظيفي المعروض داخل المحادثات — App Functionality، Linked to User، Not Tracking).
  2. **Identifiers > User ID** (معرف المستخدم ورمز الجهاز Push Device Token لتوصيل الرسائل والإشعارات — App Functionality، Linked to User، Not Tracking).
  3. **User Content > Emails or Text Messages / Photos or Videos / Audio Data / Other User Content** (الرسائل النصية، الصور والمستندات الممسوحة، الرسائل الصوتية التي يرسلها المستخدم عبر التطبيق — App Functionality، Linked to User، Not Tracking).
- **Diagnostics:** ليس لدى التطبيق حالياً Crashlytics أو تحليلات طرف ثالث؛ وإذا اكتفيت بعدم تفعيلها لا تُضف بيانات تتبع أو تحليلات.
- تأكد أن **Tracking** مضبوط على **No** (يطابق `<key>NSPrivacyTracking</key><false/>` في `PrivacyInfo.xcprivacy`).

### 4.5 التصنيف العمري وإقرار التشفير
- **Age Rating:** أجب بـ **No / None** على كل محتوى العنف والألفاظ والمقامرة والوصول غير المقيد للإنترنت > النتيجة **`4+`**.
- **Pricing & Availability:** مجاني (**Free - USD 0.00**) ومتاح في الدول المستهدفة (أو جميع الدول).
- **App Encryption Documentation:** تم تعيين `ITSAppUsesNonExemptEncryption = false` في `Info.plist`، لذا لن تطلب منك Apple رفع مستندات تصدير التشفير المعقدة (مع اختيار "Standard HTTPS/TLS encryption only" إذا ظهر سؤال تأكيد).

---

## 5. تعليمات وملاحظات مراجع Apple (App Review Information) — جاهزة للنسخ

> [!CAUTION]
> **قبل إرسال التطبيق للمراجعة (`Submit for Review`)، تأكد من الخطوتين التاليتين على السيرفر الخارجي `https://ismartdbacd.dpdns.org`:**
> 1. أن السيرفر الخارجي يعمل ومتاح على الإنترنت العام من الولايات المتحدة (لأن مراجعي Apple يختبرون التطبيق من كاليفورنيا، وأي توقف للسيرفر يؤدي لرفض فوري تحت **Guideline 2.1 - App Completeness**).
> 2. أنك أنشأت حساباً تجريبياً **غير إداري (Non-admin / عادي)** لمراجع Apple، لأنه في النهاية قد يجرب الضغط على **حذف الحساب نهائياً**! (لقد أصلحنا مشكلة منع حذف آخر Admin في السيرفر، لكن وجود حساب تجريبي عادي مخصص للمراجعة يمنح المراجع تجربة نظيفة وآمنة دون المساس بحساب الإدارة الرئيسي).

في قسم **App Review Information**:
- فعّل علامة **Sign-in required**.
- أدخل اسم المستخدم وكلمة المرور للحساب التجريبي الذي أنشأته على الخادم الخارجي (استبدل `<DEMO_USERNAME>` و `<DEMO_PASSWORD>` قبل الحفظ).
- فعّل بيانات الاتصال الخاصة بك (الاسم، الهاتف بصيغة دولية مثل `+20...`، والبريد الإلكتروني).
- في خانة **Notes** الصق النص الإنجليزي التالي بعد استبدال `<DEMO_USERNAME>` و `<DEMO_PASSWORD>`:

```text
Dear Apple App Review Team,

Thank you for reviewing iSmart Messenger.

1. Enterprise / Workplace Architecture & Sign in with Apple Exemption (Guideline 4.8):
iSmart Messenger is an enterprise messaging, document scanning, and IT workflow client designed exclusively for organizations using self-hosted or dedicated company servers. Accounts are provisioned privately by organization IT administrators rather than open public registration; therefore, third-party consumer social logins (Sign in with Apple / Google) are excluded per App Review Guideline 4.8 exemptions for enterprise/organization-managed accounts.

2. Test Environment & Demo Account:
- Pre-configured HTTPS test server: https://ismartdbacd.dpdns.org
- If you want to verify or inspect the server URL on the login screen, tap the server pill badge at the top of the screen ("ismartdbacd.dpdns.org" with the pencil icon).
- Demo Username: <DEMO_USERNAME>
- Demo Password: <DEMO_PASSWORD>

3. Features You Can Test Immediately:
- Workplace Chat & Voice Notes: Open any conversation to send messages and test the microphone permission by recording a voice note.
- Document Scanner (Camera & Photo Library): Open the Scanner tab to scan documents with iOS VisionKit/camera or import images from the Photo Library, compile multi-page PDFs, and share via the native iOS share sheet (supported on both iPhone and iPad).
- Notifications & In-App Privacy Policy: Available directly in Settings/Profile and from the Login screen (works even if offline).
- Account Deletion (Guideline 5.1.1(v)): Log in with the demo account, go to Profile / Settings (الملف الشخصي والإعدادات), scroll to the bottom, and tap the red "حذف الحساب نهائيًا" (Delete Account Permanently) button to test immediate account and data deletion.

4. Network Security (ATS):
While our public demo server uses HTTPS (https://ismartdbacd.dpdns.org), customer organizations may deploy iSmart Messenger on private internal LAN servers using local IPs or internal hostnames, which is why Local Network permission and flexible internal networking are configured.

Best regards,
iSmart Messenger Team
support@ismart.com
```

---

## 6. تقرير الفحص الشامل: كل ما تم اكتشافه وإصلاحه لمنع رفض Apple ولتشغيل كافة الميزات

تم فحص مشروع iOS و Flutter والباك إند بالكامل واكتشاف **14 مشكلة حرجة** كانت ستسبب رفضاً مباشراً من Apple أو تعطلًا أو انهياراً على iPhone / iPad، وتم حلها بالكامل:

| # | المشكلة المكتشفة قبل الفحص | خطر الرفض أو العطل على iOS | الحل الذي تم تطبيقه وتأكيده |
| :-: | :--- | :--- | :--- |
| **1** | **أيقونة Flutter الافتراضية** في `AppIcon.appiconset` + أيقونات `LaunchImage` و `simple_splash_view` قديمة أو شفافة | رفض تلقائي تحت **Guideline 4.3 / 2.3** بسبب أيقونة Flutter الافتراضية أو وجود قناة Alpha | إنشاء [`generate_ios_icons.py`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/scripts/generate_ios_icons.py) لتوليد كل المقاسات الـ 19 من شعار التطبيق الرسمي بامتداد بدون شفافية (`hasAlpha: no`) وبملء كامل للإطار دون حدود مزدوجة، مع تحديث صور الـ Launch Screen والـ Splash |
| **2** | **تعطل `Share.shareXFiles` على iPad بدون `sharePositionOrigin`** في 4 مواضع | انهيار فوري (Crash `NSInvalidArgumentException`) على iPad أثناء المراجعة ورفض مؤكد (**Guideline 2.1 / iPad compatibility**) | إنشاء [`resolveSharePositionOrigin`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/lib/core/utils/share_origin.dart) وتمريره في جميع استدعاءات `Share.shareXFiles` داخل `my_files_screen.dart` و `pending_uploads_screen.dart` و `upload_summary_screen.dart` |
| **3** | **غياب دعم `UIBackgroundModes` الصحيح** (وجود `audio` و `fetch` بدون استخدام فعلي) | رفض من مراجعي Apple تحت **Guideline 2.5.4** لطلب تشغيل صوت/جلب خلفي غير مبرر | إزالة `audio` و `fetch` من [`Info.plist`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/ios/Runner/Info.plist) والإبقاء فقط على `remote-notification`، وإضافة `CFBundleLocalizations` (`ar`, `en`) |
| **4** | **`deleteAccount()` يمسح الجلسة محلياً حتى لو فشل السيرفر** (مثل خطأ شبكة أو آخر مدير HTTP 400) | مخالفة **Guideline 5.1.1(v)**: قد يظهر للمستخدم أنه خرج بينما حسابه ما زال موجوداً على الخادم | تعديل [`deleteAccount()`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/lib/features/auth/data/auth_repository.dart) و [`AuthController`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/lib/features/auth/presentation/auth_controller.dart) ليتم تنفيذ طلب `DELETE /api/users/me` أولاً وإعادة رمي الخطأ المترجم عند الفشل قبل مسح أي جلسة أو كاش |
| **5** | **فتح سياسة الخصوصية بالمتصفح فقط** قد يفشل لو السيرفر الخارجي غير متصل لحظياً | رفض تحت **Guideline 5.1.1** إذا تعذر عرض سياسة الخصوصية قبل أو بعد الدخول | إنشاء شاشة أصلية تعمل بدون إنترنت [`PrivacyPolicyScreen`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/lib/features/profile/presentation/privacy_policy_screen.dart) وربطها في شاشة الدخول والملف الشخصي وتحديث قسم حذف الحساب في `PRIVACY_POLICY.md` و `privacy-policy.html` |
| **6** | **وجود Android MethodChannel (`app.installer`) وأكواد نصوص وتحديثات أندرويد** داخل iOS | رفض محتمل تحت **Guideline 2.5.2** (إيحاء بتثبيت حزم أو إشارة لمنصة منافسة مثل "من أندرويد") | تنظيف [`AppDelegate.swift`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/ios/Runner/AppDelegate.swift)، وتخطي `_updateAgent` على `Platform.isIOS` في [`mobile_app.dart`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/lib/app/mobile_app.dart)، وتعديل النصوص في [`notification_settings_screen.dart`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/lib/features/profile/presentation/notification_settings_screen.dart) إلى صياغة عامة متوافقة مع iOS |
| **7** | **ترتيب `registerForRemoteNotifications()` قبل `GeneratedPluginRegistrant.register`** في `AppDelegate.swift` + شاشة Splash 5.8 ثانية + ملف `SplashViewController.swift` يتيم | قد يتسبب في ضياع APNs Token الأول أو بطء إقلاع مبالغ فيه عند المراجع (5.8 ثانية انتظار) | إعادة ترتيب التهيئة في [`AppDelegate.swift`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/ios/Runner/AppDelegate.swift)، خفض مدة Splash إلى `1.4` ثانية، إضافة تصفير الـ Badge في `applicationDidBecomeActive`، وحذف `SplashViewController.swift` اليتيم |
| **8** | **`firebase_options.dart` كان يحمل Bundle ID قديماً (`com.simplesplashview.mobile.app`)** ولا يتم تهيئة Firebase في `main.dart` قبل Background Handler | فشل تسجيل FCM Token على iOS أو استثناء `FirebaseApp` غير مهيأ | تحديث `iosBundleId` إلى `com.ismartmessenger.app` في [`firebase_options.dart`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/lib/firebase_options.dart) وتنفيذ `Firebase.initializeApp` مبكراً في [`main.dart`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/lib/main.dart) و [`PushNotificationService`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/lib/shared/services/push_notification_service.dart) مع انتظار `getAPNSToken()` |
| **9** | **الاعتماد على أصوات `.mp3`/`.wav` غير المدعومة كصوت إشعار iOS وغياب إعدادات `Darwin` كاملة** | الإشعارات المخصصة تأتي صامتة أو بنغمة النظام الافتراضية، وظهور إشعارين (من FCM ومن LocalNotification) | تحويل النغمات الثلاث إلى `.caf` (`default_tone.caf`, `chime_tone.caf`, `alert_tone.caf`) وإضافتها إلى موارد `Runner` في [`project.pbxproj`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/ios/Runner.xcodeproj/project.pbxproj) |
| **10** | **تكرار إشعار Summary على iOS وفحص إذن الإشعارات الوهمي (`areNotificationsEnabled` يعيد `true` دائماً على iOS)** | ظهور تنبيهين متكررين لنفس المحادثة على iOS وعجز الشاشة عن معرفة هل أغلق المستخدم الإشعارات من إعدادات الآيفون | تحديث [`LocalNotificationService`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/lib/shared/services/local_notification_service.dart) بـ `DarwinInitializationSettings` مع تصنيف الرد السريع `chat_reply_category`، منع Summary المكرر على iOS، إزالة التكرار بـ `_recentMessageIds`، دعم وضع `soundOnly`، وفحص الصلاحية الحقيقي عبر `checkPermissions()` |
| **11** | **إرسال الباك إند إشعارات iOS بصيغة Android Channel بدون `apns.payload.aps`** | تجاهل APNs لتجميع المحادثات أو النغمات المخصصة على iOS | إضافة `iosSoundForToneId` و `buildApnsPayload` في [`push-notification.service.js`](file:///Users/yousef/Desktop/iSmart-Messenger/backend/src/services/push-notification.service.js) وتجميع أجهزة iOS حسب النغمة، وتحسين مرونة [`DELETE /me/push-devices`](file:///Users/yousef/Desktop/iSmart-Messenger/backend/src/routes/user.routes.js) |
| **12** | **تعارض Team/Bundle ID في هدف `RunnerTests` ومعرّف عنوان `MaterialApp.title`** | فشل التوقيع عند الأرشفة أو Archive Verification | توحيد `PRODUCT_BUNDLE_IDENTIFIER = com.ismartmessenger.app.RunnerTests` و `DEVELOPMENT_TEAM = 9SGAUMPF23` في جميع Configurations، وتعديل `MaterialApp.title` إلى `'iSmart Messenger'` |
| **13** | **ملاحظات النسخ والاختبار لمتطلبات iPad / iPhone App Store Screenshots** | عدم توفر لقطات بمقاسات Apple المطلوبة (`6.9"` و `iPad 13"`) | كتابة [`generate_app_store_screenshots.py`](file:///Users/yousef/Desktop/iSmart-Messenger/mobile_app/scripts/generate_app_store_screenshots.py) والتقاط شاشات حية من المحاكي وتوليد 18 صورة كاملة خالية من Alpha |
| **14** | **تحديد إعفاء Sign in with Apple (Guideline 4.8) واتصال الشبكات المحلية (Local Network)** | تساؤل المراجع عن عدم وجود زر Sign in with Apple أو وجود ATS للشبكات الداخلية | التطبيق لا يحتوي على تسجيل دخول اجتماعي (Google/Facebook) بل حسابات موظفين خاصة تدار من مسؤول النظام، وهذا معفى رسمياً تحت **Guideline 4.8** عند توضيحه في App Review Notes كما في القسم 5 أعلاه |
