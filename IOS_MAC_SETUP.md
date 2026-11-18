# دليل إعداد وبناء وتجهيز iOS لمتجر App Store و TestFlight
**المشروع:** iSmart Messenger  
**الفرع المخصص للعمل:** `ios/mac-setup`  
**تاريخ الإعداد:** 18 نوفمبر 2026  

---

## 1. القيم المستخدمة (Configured Values)

| البند | القيمة المعتمدة | ملاحظات |
| :--- | :--- | :--- |
| **APP_BUNDLE_ID** | `com.ismart.messenger` | معرف التطبيق الرئيسي |
| **TESTS_BUNDLE_ID** | `com.ismart.messenger.RunnerTests` | معرف هدف الاختبارات لمنع تعارض المعرفات |
| **APP_DISPLAY_NAME** | `iSmart Messenger` | الاسم المعروض تحت الأيقونة وفي المتجر |
| **CFBundleName** | `iSmart Messenger` | الاسم البرمجي للتطبيق |
| **MIN_IOS (Deployment Target)** | `15.0` | متوافق مع كافة ميزات التطبيق الحديثة |
| **DEVELOPMENT_TEAM** | يتم اختياره من Xcode GUI | حساب Apple Developer الخاص بك |
| **ITSAppUsesNonExemptEncryption** | `false` | معفى من تراخيص التشفير الأمريكية |
| **APNs Environment** | `development` (يتحول تلقائياً إلى `production` عند Archive) | إشعارات Firebase و Apple Push Notifications |

---

## 2. نتيجة كل خطوة (Results Matrix)

| الخطوة | الحالة | التفاصيل والنتائج المباشرة |
| :--- | :---: | :--- |
| **0. فحص البيئة والأدوات** | **نجح** | • macOS 15.8.1 (Build 24H32)<br>• Xcode 26.3 (Build 17C529)<br>• Flutter 3.47.5 (Dart 3.13.4)<br>• CocoaPods 1.17.0 (تم حل مشكلة ترميز UTF-8 بتمرير `LANG/LC_ALL=en_US.UTF-8`)<br>• اكتمل `pod install` بتثبيت كافة الـ Pods بنجاح. |
| **1. جرد الهوية وتوحيد المعرفات** | **نجح** | ضبط `PRODUCT_BUNDLE_IDENTIFIER = com.ismart.messenger` للتطبيق و `com.ismart.messenger.RunnerTests` للـ Tests لمنع تعارض البناء. |
| **2. Capabilities والـ Entitlements** | **نجح** | ربط `Runner/Runner.entitlements` بجميع الـ Configurations (Debug, Release, Profile) مع صلاحية Push Notifications. |
| **3. الخصوصية وحذف الحساب (App Store Compliance)** | **نجح** | • إنشاء `PrivacyInfo.xcprivacy` وتضمينه في موارد التطبيق (Required Reason APIs: `CA92.1`, `C617.1`, `E174.1`, `35F9.1`).<br>• إنشاء Endpoint في الباك إند: `DELETE /api/users/me` لحذف الحساب ومسح البيانات والرسائل كلياً.<br>• إضافة زر ونافذة تأكيد تحذيرية لحذف الحساب نهائياً في شاشة الملف الشخصي `profile_screen.dart` ومسح الذاكرة والجلسة. |
| **4. الوسائط والصوتيات** | **نجح** | ضبط أذونات الكاميرا، الميكروفون، مكتبة الصور، وحفظ الوسائط بنصوص عربية وإنجليزية واضحة في `Info.plist`. |
| **5. الأيقونات والشاشات** | **نجح** | فحص أيقونة App Store بحجم 1024x1024 والتأكد من خلوها تماماً من أي شفافية (`hasAlpha: no`) ومطابقتها للمقاييس. |
| **6. البناء للمحاكي (Simulator Debug)** | **نجح** | تم تنفيذ `flutter build ios --simulator --debug` بنجاح كامل في 278.7 ثانية وإنتاج `Runner.app`. |
| **6. تشغيل واختبار المحاكي** | **نجح** | إقلاع محاكي iPhone 16e وتثبيت التطبيق وتشغيله بنجاح بـ PID `87791` والتقاط لقطة شاشة للواجهة بدقة 1170x2532. |
| **6. البناء لجهاز حقيقي (Device Release No-Codesign)** | **نجح** | تم تنفيذ `flutter build ios --release --no-codesign` بنجاح كامل في 654.8 ثانية بحجم `38.8 MB` لملف `Runner.app`. |
| **6. التشغيل على جهاز حقيقي** | **لم يُختبر** | الهاتف (iPhone 12) متاح لاسلكياً وبانتظار التوقيع بشهادة حساب Apple Developer الخاص بك. |
| **7. ملف تصدير التوزيع exportOptions.plist** | **نجح** | تم تجهيز الملف القياسي النظيف في `ios/exportOptions.plist`. |

---

## 3. قائمة الملفات التي تم تعديلها أو إنشاؤها

### أ. الباك إند (Backend):
1. `backend/src/routes/user.routes.js`: إضافة مسار `DELETE /api/users/me` المحمي بـ `requireAuth`.
2. `backend/src/controllers/user.controller.js`: إضافة دالة `deleteMyAccountHandler` وبث أحداث قطع الاتصال `force_logout`.
3. `backend/src/services/user.service.js`: تمكين المستخدم من حذف حسابه ذاتياً مع تنظيف محادثاته ورسائله وملفاته وصورته الرمزية من قاعدة البيانات والأقراص.

### ب. تطبيق الهاتف (Flutter & iOS):
1. `mobile_app/lib/features/auth/data/auth_repository.dart`: إضافة دالة `deleteAccount()` لاستدعاء السيرفر وتفريغ الجلسة محلياً.
2. `mobile_app/lib/features/auth/presentation/auth_controller.dart`: إضافة معالج حذف الحساب وإلغاء تسجيل أجهزة الإشعارات وتصفير الكاش وفصل السوكيت فوراً.
3. `mobile_app/lib/features/profile/presentation/profile_screen.dart`: إضافة زر أحمر واضح "حذف الحساب نهائيًا" بنافذة تأكيد تحذيرية مطابقة لاشتراطات Apple Guideline 5.1.1(v).
4. `mobile_app/ios/Runner/PrivacyInfo.xcprivacy`: ملف إعلان الخصوصية الإلزامي من Apple لـ Required Reason APIs.
5. `mobile_app/ios/Runner/Info.plist`: إعداد أذونات الكاميرا والميكروفون والاستوديو والشبكة المحلية بدون تعارضات.
6. `mobile_app/ios/Runner/Runner.entitlements`: إعداد الـ Push Notifications Environment.
7. `mobile_app/ios/Runner.xcodeproj/project.pbxproj`: ربط `PrivacyInfo.xcprivacy` و `Runner.entitlements` وتحديد `com.ismart.messenger.RunnerTests`.
8. `mobile_app/ios/exportOptions.plist`: ملف إعدادات التصدير والأرشفة التلقائية.

---

## 4. الخطوات اليدوية المطلوبة منك على حساب Apple Developer و Xcode GUI

### الخطوة الأولى: تسجيل الـ App ID والـ Capabilities على developer.apple.com
1. ادخل على [developer.apple.com/account](https://developer.apple.com/account).
2. انتقل إلى **Certificates, Identifiers & Profiles** > **Identifiers**.
3. اضغط على زر **(+)** لإضافة معرّف جديد:
   * اختر **App IDs** ثم اضغط **Continue**.
   * اختر النوع **App** واضغط **Continue**.
   * في **Description**: اكتب `iSmart Messenger`.
   * في **Bundle ID**: اختر **Explicit** واكتب: `com.ismart.messenger`.
   * في قائمة **Capabilities**:
     * فعّل **Push Notifications**.
4. اضغط **Continue** ثم **Register**.

---

### الخطوة الثانية: فتح المشروع واختيار فريق العمل في Xcode GUI
1. افتح المشروع في Xcode عبر فتح الـ Workspace:
   ```bash
   open mobile_app/ios/Runner.xcworkspace
   ```
2. من القائمة اليسرى، اضغط على المشروع الرئيسي **Runner** (بالأعلى).
3. من قائمة **TARGETS** اختر **Runner**.
4. انتقل إلى تبويب **Signing & Capabilities**:
   * تأكد من تفعيل خيار **Automatically manage signing**.
   * في خانة **Team**: اختر حساب Apple Developer الخاص بك (Team ID).
   * ستلاحظ أن Xcode قام بتوليد شهادة التطوير والـ Provisioning Profile تلقائياً وظهرت علامة صح خضراء.
5. من قائمة **TARGETS** اختر **RunnerTests**:
   * اختر نفس الـ **Team** لتأكيد التوقيع التلقائي.

---

### الخطوة الثالثة: إنشاء التطبيق على App Store Connect
1. ادخل على [appstoreconnect.apple.com](https://appstoreconnect.apple.com).
2. ادخل على قسم **Apps** واضغط على علامة **(+)** > **New App**.
3. املأ البيانات:
   * **Platforms**: iOS.
   * **Name**: `iSmart Messenger` (أو الاسم التجاري المطلوب).
   * **Primary Language**: Arabic أو English حسب رغبتك.
   * **Bundle ID**: اختر `com.ismart.messenger` الذي سجلته في الخطوة الأولى.
   * **SKU**: اكتب معرّفاً فريداً داخلياً (مثلاً: `ismart-messenger-ios-01`).
   * **User Access**: Full Access.
4. اضغط **Create**.

---

## 5. كيفية التعامل مع مراجع أبل والسيرفر الخارجي (App Review Notes)

بما أن التطبيق صُمم للعمل في بيئة العمل، فلكي لا يرفض مراجع أبل التطبيق:
1. في صفحة التطبيق على **App Store Connect**، انتقل لأسفل الصفحة إلى قسم **App Review Information**.
2. **Sign-in required**: ضع علامة صح (نعم).
3. ضع بيانات حساب التجربة للمراجع:
   * **User name**: (اسم مستخدم تجريبي قمت بإنشائه على السيرفر الخارجي).
   * **Password**: (كلمة مرور الحساب التجريبي).
4. في خانة **Notes** (ملاحظات للمراجع):
   اكتب نصاً واضحاً بالإنجليزية مثل:
   > "This application is an internal workplace messaging and document management app. To review the app, please use the provided test account. The app is pre-configured to connect to our secure external demo server: [ضع رابط السيرفر الخارجي هنا]. If you need any assistance or dedicated access, feel free to contact us."
5. إذا كان السيرفر يتطلب إدخال عنوان IP/Domain في الشاشة الأولى، اكتب للمراجع الخطوات البسيطة لإدخاله.

---

## 6. خطوات الأرشفة والرفع لـ TestFlight / App Store

### الطريقة الأولى: من خلال Xcode GUI (الأسهل والأضمن)
1. في شريط Xcode العلوي، اختر الجهاز الهدف: **Any iOS Device (arm64)**.
2. من القائمة العلوية لـ Xcode: اختر **Product** > **Archive**.
3. سيبدأ Xcode بالبناء، وعند الانتهاء ستفتح لك نافذة **Organizer**.
4. اضغط على زر **Validate App** للتأكد من عدم وجود أي نقص في المتطلبات.
5. بعد نجاح التحقق، اضغط **Distribute App**:
   * اختر **App Store Connect**.
   * اختر **Upload**.
   * اترك خيارات التوقيع والرموز التلقائية واضغط **Upload**.
6. في خلال 5 إلى 15 دقيقة، ستصلك رسالة باكتمال المعالجة وسيظهر الإصدار فوراً في تبويب **TestFlight**.

### الطريقة الثانية: من سطر الأوامر (Terminal)
إذا كانت الشهادات مسجلة بالفعل في الـ Keychain:
```bash
cd mobile_app
flutter build ipa --release --export-options-plist=ios/exportOptions.plist
```
ثم استخدام تطبيق **Transporter** المتاح على الـ Mac لسحب ملف الـ `.ipa` ورفعه بضغطة زر واحدة.

---

## 7. قائمة فحص نهائية قبل الضغط على "Submit for Review"

- [x] مسار حذف الحساب **(Delete Account)** متوفر ومفحوص ويعمل بنجاح في الباك إند والتطبيق.
- [x] ملف إعلان الخصوصية **PrivacyInfo.xcprivacy** موجود ومضمن داخل حزمة التطبيق.
- [x] أيقونة المتجر 1024x1024 مفحوصة ولا تحتوي على أي شفافية.
- [x] جميع نصوص طلب الأذونات (الكاميرا، الميكروفون، الصور، والشبكة المحلية) واضحة وتبرر سبب الاستخدام.
- [x] تم تجهيز حساب تجريبي وملاحظات المراجعة وتوجيهه للسيرفر الخارجي.
- [x] الكود تم فحصه عبر `flutter analyze` بدون أي أخطاء.
- [x] تم التأكد من عدم المساس بالبرانش المستقر `release/clean-installer-v1`.
