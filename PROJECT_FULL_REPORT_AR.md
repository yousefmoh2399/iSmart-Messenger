# تقرير شامل عن مشروع CS Scanner

تاريخ التقرير: 28 يوليو 2026

## 1. الملخص التنفيذي

المشروع عبارة عن نظام داخلي متكامل لإدارة أعمال الـIT والملفات داخل الشركة. النظام ليس مجرد تطبيق Scanner، لكنه منصة كاملة مكونة من:

- Backend مركزي مبني بـNode.js وExpress وMongoDB.
- تطبيق كمبيوتر Flutter موجه للموظفين والإدارة على Windows، مع دعم Web/Electron.
- تطبيق موبايل Flutter موجه للمسح الضوئي، الملفات، الشات، التذاكر، الإشعارات، ومسح أصول الـIT.

النظام يخدم عدة احتياجات في مكان واحد:

- مسح المستندات وتحويلها إلى PDF ورفعها.
- إدارة الملفات والمستندات.
- شات داخلي لحظي بين الموظفين والأقسام والمجموعات.
- إدارة المستخدمين والأقسام والفروع والصلاحيات.
- تذاكر دعم فني وشكاوى واقتراحات.
- مراقبة الطابعات واستهلاك الورق والتونر والتقارير.
- إدارة أصول الـIT وقطع الغيار والجرد والحركات والتقارير.
- طلبات شراء بمسار موافقات متعدد.
- إعلانات داخلية تظهر للمستخدمين.
- نسخ احتياطي واستعادة.
- نظام تحديثات لتطبيق الديسكتوب والموبايل.
- صفحة سيرفرات داخلية ومتصفح WebView مدمج في تطبيق الكمبيوتر.

## 2. هيكل المشروع

```text
backend/
  Node.js + Express + MongoDB API

desktop_app/
  Flutter desktop app

mobile_app/
  Flutter mobile app

README.md
PROJECT_OVERVIEW.md
SYSTEM_OVERVIEW.md
CHAT_MODULE.md
backend_runtime.md
```

## 3. المعمارية العامة

تطبيق الموبايل وتطبيق الكمبيوتر يتصلان بنفس الـBackend من خلال:

- REST APIs للعمليات العادية مثل تسجيل الدخول، الملفات، المستخدمين، التذاكر، الطابعات، أصول IT، وطلبات الشراء.
- Socket.IO للوظائف اللحظية مثل الشات، حالة الاتصال، مؤشرات الكتابة، إشعارات التذاكر، أوامر الطباعة ونقل الملفات.
- MongoDB كمصدر بيانات رئيسي.
- Disk Storage لتخزين الملفات المرفوعة مثل PDF، مرفقات الشات، الصور الشخصية، مرفقات IT، وملفات التحديثات.
- Redis اختياري لتحسين rate limiting والتعامل مع الضغط، مع fallback آمن لو Redis غير متاح.

## 4. التقنيات المستخدمة

### Backend

- Node.js
- Express.js
- MongoDB + Mongoose
- Socket.IO
- JWT authentication
- bcryptjs لتشفير كلمات المرور
- multer لرفع الملفات
- helmet وcors وcompression للحماية والأداء
- express-rate-limit وRedis rate limit
- Firebase Admin لإرسال Push Notifications
- net-snmp لمراقبة الطابعات عبر SNMP
- pdfkit وexceljs لتصدير التقارير PDF وExcel
- archiver/unzipper للنسخ الاحتياطي والتحديثات

### Desktop App

- Flutter SDK 3.9.2
- Riverpod لإدارة الحالة
- Dio للـHTTP
- Socket.IO Client
- flutter_local_notifications
- file_picker وopen_filex
- screen_capturer للسكرين شوت
- webview_windows للمتصفح الداخلي
- just_audio للأصوات
- shared_preferences وpath_provider للتخزين المحلي
- Lottie وanimated_emoji للـchat reactions

### Mobile App

- Flutter SDK 3.9.2
- Riverpod
- Dio
- Socket.IO Client
- Firebase Core/Messaging
- flutter_secure_storage
- google_mlkit_document_scanner
- image وpdf لبناء ملفات PDF من الصور
- connectivity_plus لدعم offline/sync
- permission_handler
- record وjust_audio للرسائل الصوتية
- mobile_scanner لمسح QR/Barcodes
- share_plus وgal وopen_filex

## 5. الـBackend

الـBackend هو مركز النظام بالكامل. نقطة التشغيل الرئيسية:

- `backend/src/server.js`
- `backend/src/app.js`

عند بدء التشغيل يقوم بـ:

- الاتصال بقاعدة MongoDB.
- إنشاء الأدوار الافتراضية.
- إنشاء فهارس دليل الشات.
- إنشاء حسابات Bootstrap Admin للطوارئ عند تفعيلها.
- تشغيل Socket.IO.
- تشغيل Scheduler خاص بمراقبة الطابعات.
- التعامل مع الإغلاق الآمن للـserver وقاعدة البيانات وRedis.

### أهم الـAPI Modules

- `/api/auth`: تسجيل الدخول، refresh token، الخروج، بيانات المستخدم الحالي.
- `/api/users` و`/api/admin/users`: الملف الشخصي، الصور، إدارة المستخدمين.
- `/api/documents`: رفع وإدارة المستندات.
- `/api/chat`: الشات والمحادثات والرسائل والمرفقات والحضور.
- `/api/tickets`: تذاكر الدعم والشكاوى والاقتراحات.
- `/api/printers`: مراقبة الطابعات والفروع والتقارير.
- `/api/it-assets`: أصول IT وقطع الغيار والجرد والحركات.
- `/api/purchase-requests`: طلبات الشراء ومسار الموافقات.
- `/api/announcements`: الإعلانات الداخلية.
- `/api/admin/backup`: النسخ الاحتياطي والاستعادة.
- `/api/admin/updates` و`/api/updates`: إدارة تحديثات التطبيقات.
- `/api/app-settings` و`/api/admin/app-settings`: إعدادات عامة يقرأها الديسكتوب والموبايل.

### الأمان والاستقرار

- JWT access token وrefresh token.
- كلمات المرور مشفرة بـbcrypt.
- صلاحيات role-based لكل موديول.
- Middleware للتحقق من تسجيل الدخول والصلاحيات.
- Rate limiting عام على `/api` وRate limit خاص برسائل الشات.
- Helmet وCORS وCompression.
- Logging منظم.
- Audit logs للعمليات الإدارية والحساسة.
- System error logs يمكن للإدارة مراجعتها.
- إخفاء tokens من logs.
- مهلات أطول للعمليات الثقيلة مثل رفع التحديثات والنسخ الاحتياطي ونقل الملفات.

## 6. تطبيق الكمبيوتر Desktop App

تطبيق الكمبيوتر هو واجهة العمل الأساسية للموظفين والإدارة. نقطة الدخول:

- `desktop_app/lib/main.dart`
- `desktop_app/lib/app/desktop_app.dart`
- `desktop_app/lib/app/desktop_workspace_shell.dart`

### الأقسام الرئيسية في الديسكتوب

الواجهة تستخدم Workspace جانبي وتنقل داخلي بين:

- الشات.
- الملفات.
- السيرفرات والمتصفح الداخلي.
- الملف الشخصي.
- مراقبة الطابعات.
- أصول IT.
- طلبات الشراء.
- Snipe-IT.
- التذاكر.
- الإدارة حسب صلاحيات المستخدم.
- مركز التحديثات.

### مميزات الكمبيوتر

- تسجيل دخول واسترجاع جلسة المستخدم تلقائياً.
- تغيير رابط السيرفر من شاشة الإعدادات عند تعذر الاتصال.
- شات كامل بمحادثات مباشرة وجروبات وأقسام وبث.
- Presence: online / idle / offline.
- إشعارات محلية للرسائل.
- التقاط Screenshot من سطح المكتب وإرساله في الشات.
- إدارة الملفات السحابية وتنزيل/فتح الملفات.
- نقل ملفات بين الديسكتوب والموبايل عبر Socket.IO/LAN transfer.
- دعم الطباعة من الموبايل عبر الديسكتوب.
- حفظ ملفات واردة من الموبايل على جهاز الكمبيوتر.
- إدارة المستخدمين والأقسام والفروع والغرف والصلاحيات.
- إدارة الإعلانات العامة.
- Backup screen للنسخ الاحتياطي.
- Update management لإدارة إصدارات الديسكتوب.
- Update center للعميل نفسه.
- System tray، حالة الظهور، إخفاء إلى Tray، وتشغيل مع بدء Windows.
- منع فتح أكثر من نسخة من التطبيق على Windows.
- واجهة عربية RTL مع Light/Dark/System theme.

### متصفح السيرفرات الداخلي

يوجد موديول متقدم في:

- `desktop_app/lib/features/servers/presentation/servers_screen.dart`

يدعم:

- قائمة سيرفرات الشركة.
- فحص المنافذ المتاحة لكل سيرفر.
- قياس latency وترتيب المنافذ الأفضل.
- حفظ آخر منفذ ناجح.
- تنبيه عند انتقال سيرفر من UP إلى DOWN.
- WebView داخلي بدل فتح المتصفح الخارجي.
- Tabs متعددة مع restore بعد إعادة فتح التطبيق.
- Pinned tabs لا يتم إغلاقها إلا بعد فك التثبيت.
- شريط عنوان ونسخ URL.
- History وBookmarks.
- Find in page.
- Download manager.
- Password helper لحفظ بيانات الدخول وملئها.
- Intranet-only mode لتقييد التصفح داخل الشبكة.
- Export/Import لإعدادات المتصفح.

### تحديثات الديسكتوب

الديسكتوب يحتوي Update Agent:

- يتواصل مع الـBackend بالـheartbeat.
- يستقبل مهام تحديث موجهة لجهاز معين أو فرع أو كل الأجهزة.
- ينزل installer بصمت.
- يتحقق من checksum عند توفره.
- يشغل PowerShell helper منفصل.
- يغلق التطبيق، يثبت التحديث silent، ثم يفتح التطبيق مرة أخرى.
- يعرض Overlay للمستخدم أثناء التحديث.

## 7. تطبيق الموبايل Mobile App

تطبيق الموبايل موجه للعمل الميداني والسريع. نقطة الدخول:

- `mobile_app/lib/main.dart`
- `mobile_app/lib/app/mobile_app.dart`
- `mobile_app/lib/features/home/presentation/home_screen.dart`

### الشاشة الرئيسية

الشاشة الرئيسية تعرض حسب صلاحيات المستخدم:

- مسح مستند جديد.
- ملفاتي السحابية.
- ملفاتي المحلية والمرفوعات المعلقة.
- إدارة الشات للمستخدمين المصرح لهم.
- مراقبة الطابعات.
- ماسح أصول IT.
- تذاكر الدعم.
- إعلانات النظام.
- حالة offline/sync.
- تبديل الثيم.

### مميزات الموبايل

- تسجيل دخول واسترجاع جلسة.
- تغيير رابط السيرفر عند تعذر الاتصال.
- Scanner للمستندات باستخدام ML Kit Document Scanner.
- مراجعة الصفحات قبل الرفع.
- تحسين صور المستندات وبناء PDF.
- حفظ مسودات محلية لو عملية المسح لم تكتمل.
- Pending uploads عند عدم توفر الإنترنت.
- مزامنة تلقائية عند رجوع الاتصال.
- عرض الملفات السحابية وتنزيلها وفتحها ومشاركتها.
- شات كامل مع المحادثات والمرفقات والرسائل الصوتية.
- Push Notifications عبر Firebase Messaging.
- Local notifications أثناء تشغيل التطبيق.
- فتح المحادثة أو التذكرة مباشرة عند الضغط على الإشعار.
- تذاكر الدعم ومتابعة الحالة والتقييم.
- مسح QR لأصول IT وقطع الغيار.
- المشاركة وحفظ الملفات على الجهاز.
- دعم Light/Dark/System theme وواجهة عربية.

## 8. موديول المستندات والـScanner

الغرض منه تحويل الورق إلى ملفات PDF منظمة ومرفوعة للـBackend.

### على الموبايل

- التقاط مستند بالكاميرا.
- تعديل/مراجعة الصفحات.
- تحسين الإضاءة والتباين وإزالة الظلال قدر الإمكان.
- بناء PDF متعدد الصفحات.
- رفعه للحساب الحالي.
- حفظ pending upload عند انقطاع الإنترنت.

### على الكمبيوتر

- عرض المستندات.
- تنزيل وفتح الملفات.
- إدارة ملفات المستخدمين حسب الصلاحيات.
- دعم حفظ/استقبال ملفات من الموبايل.

### على الـBackend

- تخزين metadata في MongoDB.
- تخزين الملفات فعلياً داخل uploads.
- حماية الملكية والصلاحيات.
- حذف الملفات الفعلية عند حذف المستند.

## 9. موديول الشات

الشات من أكبر أجزاء المشروع، ويعمل REST + Socket.IO.

### أنواع المحادثات

- Direct بين مستخدمين.
- Group rooms.
- Department conversations.
- Broadcast channels.

### وظائف الشات

- إرسال واستقبال لحظي.
- Typing indicator.
- Delivery وSeen state.
- Unread counts.
- Presence online/idle/offline/last seen.
- تعديل الرسائل.
- حذف الرسائل.
- Reply.
- Forward.
- Reactions.
- Favorite messages.
- Search داخل الرسائل.
- Pagination للرسائل القديمة.
- Pin/Mute/Archive/Favorite للمحادثات.
- مرفقات: ملفات، صور، PDF، Audio.
- تنزيل أو فتح المرفقات.
- طلب استعادة مرفق attachment rehydrate.
- إدارة أعضاء الجروبات.
- ترقية/إزالة Admin داخل الجروب.
- Block/Unblock لأعضاء المحادثة.
- Audit logs وSystem errors للإدارة.

### تكامل الشات مع الأجهزة

- الديسكتوب يقدر يرسل Screenshot.
- الموبايل يقدر يرسل صور وملفات وصوت.
- إشعارات محلية وPush.
- عند الضغط على notification يفتح التطبيق المحادثة المقصودة.

## 10. موديول التذاكر Tickets

يدعم تذاكر الدعم والشكاوى والاقتراحات.

### الوظائف

- إنشاء تذكرة بعنوان ووصف وأولوية.
- أرقام تلقائية للتذاكر.
- حالات: open, assigned, in_progress, waiting_branch, resolved, closed.
- تعيين موظف دعم.
- تعليقات عامة وInternal notes.
- Dashboard statistics.
- تصدير تقارير التذاكر.
- تقييم التذكرة من 1 إلى 5 بعد الحل.
- إعداد فريق الدعم.
- تحديد مسؤولي الأقسام حسب النوع: ticket / complaint / suggestion.
- تحديثات لحظية عبر Socket.IO.

## 11. موديول الطابعات Printers

الموديول يتعامل مع مراقبة الطابعات والفروع والاستهلاك والتقارير.

### الوظائف

- Dashboard للطابعات.
- إدارة فروع الطابعات.
- Discovery للشبكات داخل الفرع.
- قائمة الطابعات.
- تفاصيل طابعة واحدة.
- Sync لطابعة واحدة.
- Full sync لكل الطابعات.
- إيقاف Full sync.
- عرض حالة المزامنة.
- Sync logs.
- متابعة الاستهلاك حسب شهر/سنة/فرع/طابعة.
- تصدير تقارير PDF وXLSX بنوع branch/global/printer.

### البيانات المخزنة

- Printer.
- PrinterBranch.
- DailySnapshot.
- SyncLog.
- PrinterReport.
- PrinterNotification.
- CounterResetEvent.
- WasteStatistic.

## 12. موديول أصول IT

هذا الموديول يحول المشروع لنظام IT Asset Management داخلي.

### إدارة الأصول

- إضافة جهاز IT.
- تعديل بيانات الجهاز.
- أرشفة الجهاز.
- بحث بالـasset code أو serial.
- عرض Timeline لكل جهاز.
- حالات مثل available, assigned, maintenance, damaged, scrapped, lost.

### قطع الغيار

- إضافة قطع غيار.
- تعديل الكميات والمخزون.
- متابعة الحد الأدنى والحرج والمفضل.
- أرشفة القطع.
- Lookup بالـpart code.

### العمليات

يدعم أنواع عمليات كثيرة:

- حركة جهاز movement.
- صيانة maintenance.
- نقل transfer.
- استبدال replacement.
- تالف damaged.
- جرد inventory.
- عهدة custody.
- إخلاء طرف employee_clearance.
- تسليم فرع branch_handover.
- عهدة مؤقتة temporary_assignment.
- تكهين scrap.

### الحوكمة والرقابة

- Audit approval.
- Digital signature بكلمة مرور المستخدم.
- Period closure لمنع تعديل فترات مغلقة.
- Control records.
- Discrepancies أثناء الجرد.
- Damaged inspections.
- Scrap requests.
- Correction requests.
- Workflow rules.
- Reconciliation بين تنفيذ IT ومراجعة Audit.
- Data quality checks.
- Analytics للمخاطر حسب الفرع أو الموظف أو السبب الجذري.
- Notifications للمخزون المنخفض، الضمانات القريبة، الصيانة المتأخرة، والعمليات المعلقة.

### التقارير والمرفقات

- مرفقات للأصول والعمليات والسجلات.
- PDF لعملية IT.
- PDF لسجل رقابي.
- PDF labels للأجهزة وقطع الغيار.
- Excel/PDF reports.
- Import Excel للأصول وقطع الغيار.

## 13. موديول طلبات الشراء

الموديول موجود في `backend/src/purchasing` و`desktop_app/lib/features/purchasing`.

### مسار العمل

- إنشاء طلب شراء.
- تعديل الطلب وهو draft.
- Submit.
- موافقة IT Manager.
- مراجعة Audit.
- موافقة Audit.
- موافقة Finance.
- الإرسال إلى Purchasing.
- Mark ordered.
- Receive items.
- Reject.
- Return for edit.
- Cancel.
- Close.

كل خطوة مربوطة بصلاحية منفصلة، وهذا يسمح بتوزيع workflow على إدارات مختلفة.

## 14. الإدارة والصلاحيات

النظام يعتمد على Role/Permissions.

### الإدارة تشمل

- إنشاء وتعديل وتعطيل المستخدمين.
- إدارة الأقسام.
- إدارة الفروع.
- إدارة الغرف والمحادثات.
- إدارة أدوار الشات والصلاحيات.
- تحديد مسؤولي الدعم الفني.
- إدارة الإعلانات.
- إدارة النسخ الاحتياطي.
- إدارة التحديثات.
- مراجعة Audit logs.
- مراجعة System errors.

### أمثلة صلاحيات

- `canCreateUsers`
- `canCreateDepartments`
- `canCreateRooms`
- `canSendBroadcast`
- `canDeleteMessages`
- `canUploadFiles`
- `canManageBackups`
- `canManageUpdates`
- `canViewPrinterModule`
- `canManageItAssets`
- `canAuditItAssets`
- `canViewPurchaseRequests`
- `canApproveFinancePurchaseRequests`

## 15. الإعلانات Announcements

الإعلانات تظهر للمستخدمين داخل الموبايل والديسكتوب.

الخصائص:

- عنوان ورسالة.
- حالة active/inactive.
- pinned.
- tone مثل success/warning/critical/default.
- Overlay عائم قابل للطي.
- عرض أحدث الإعلانات النشطة.

## 16. النسخ الاحتياطي Backup

الـBackend يحتوي موديول Backup للإدارة:

- إنشاء نسخة احتياطية.
- عرض النسخ المتاحة.
- تنزيل النسخة.
- رفع نسخة للاستعادة.
- حذف نسخة.
- صلاحية `canManageBackups`.
- مهلة أطول للعمليات الثقيلة.

## 17. التحديثات Updates

يوجد نظام لإدارة تحديث التطبيقات:

### Backend

- Releases.
- Devices.
- Update jobs.
- Update tasks.
- Upload artifacts.
- Queue update tasks.
- متابعة progress.

### Desktop

- Agent يعمل بعد تسجيل الدخول.
- Heartbeat للجهاز.
- تنزيل وتثبيت تلقائي.
- Overlay يوضح التقدم.

### Mobile

- Update agent يتحقق من المهام.
- Update dialog للمستخدم.
- يستجيب لأحداث `updates_updated`.

## 18. الإشعارات

### Local Notifications

موجودة على الكمبيوتر والموبايل للرسائل والأحداث المهمة أثناء تشغيل التطبيق.

### Push Notifications

الموبايل يدعم Firebase Messaging:

- تسجيل FCM token للـBackend.
- حذف token عند logout.
- Backend يرسل Push عندما لا يكون للمستخدم mobile socket نشط.
- الضغط على الإشعار يفتح المحادثة أو التذكرة.

ملاحظة تشغيلية: يلزم إعداد Firebase حقيقي في الإنتاج.

## 19. Offline وSync

الموبايل يحتوي دعم واضح للعمل أثناء ضعف الاتصال:

- حفظ الملفات الممسوحة محلياً.
- Pending uploads.
- Connectivity listener.
- Banner يوضح أن المستخدم offline.
- مزامنة تلقائية عند عودة الاتصال.
- تحديث بيانات التطبيق بعد رجوع السيرفر.

الديسكتوب يحتوي أيضاً:

- كشف فشل الاتصال بالسيرفر.
- رسالة للمستخدم بعد أكثر من فشل.
- تغيير رابط السيرفر.
- إعادة الاتصال وتحديث البيانات عند عودة السيرفر.

## 20. التخزين

الملفات مخزنة على القرص مع metadata في MongoDB.

أمثلة:

- المستندات: `backend/uploads/{userId}/...`
- مرفقات الشات: `backend/uploads/chat/{conversationId}/...`
- الصور الشخصية: `backend/uploads/avatars/{userId}/...`
- مرفقات IT: داخل upload storage الخاص بالموديول.
- ملفات التحديثات والنسخ الاحتياطية ضمن مسارات backend.

## 21. التشغيل

### Backend

```bash
cd backend
npm install
cp .env.example .env
npm run dev
```

أهم متغيرات البيئة:

- `PORT`
- `MONGODB_URI`
- `JWT_SECRET`
- `BASE_URL`
- `UPLOAD_DIR`
- `MAX_FILE_SIZE_MB`
- `CORS_ORIGIN`
- `REDIS_URL`
- `FIREBASE_SERVICE_ACCOUNT_JSON` أو بدائل Firebase عند استخدام Push

### Desktop

```bash
cd desktop_app
flutter pub get
flutter run -d windows --dart-define=API_BASE_URL=https://usta.qzz.io
```

### Mobile

```bash
cd mobile_app
flutter pub get
flutter run --dart-define=API_BASE_URL=https://usta.qzz.io
```

## 22. الاختبارات الموجودة

المشروع يحتوي اختبارات في:

- `backend/test`
- `desktop_app/test`
- `mobile_app/test`

أمثلة تغطية الديسكتوب:

- Auth flow.
- Session persistence.
- Socket listener.
- Print integration.
- Print deduplication.
- Media URL resolver.
- Layout responsiveness.
- Login concurrency.
- Document download.
- App settings deduplication.

أمثلة تغطية الـBackend:

- API error.
- Async handler.
- File util.
- Print.
- Storage paths.

## 23. نقاط قوة المشروع

- Monorepo واضح يفصل Backend/Desktop/Mobile.
- النظام متعدد الموديولات وليس تطبيق واحد محدود.
- استخدام Socket.IO يعطي وظائف لحظية قوية.
- صلاحيات تفصيلية مناسبة لبيئة شركة.
- دعم عربي RTL واضح في الواجهات.
- وجود Audit logs في أكثر من موديول.
- دعم Offline على الموبايل.
- نظام تحديثات ديسكتوب متقدم.
- موديول IT Assets عميق وفيه جرد وتوقيعات وتقارير.
- موديول طابعات يدعم SNMP وتقارير PDF/Excel.
- وجود اختبارات متعددة في الباك والديسكتوب.

## 24. ملاحظات ومخاطر تشغيلية

- Push Notifications تحتاج إعداد Firebase فعلي للإنتاج.
- `npm audit` مذكور في التوثيق أن به vulnerabilities لم يتم حلها.
- ملفات عربية كثيرة في الكود ظاهرة بترميز غير صحيح في مخرجات الطرفية؛ يجب التأكد من Encoding للملفات والـconsole قبل أي مراجعة لغوية.
- جودة Scanner ليست OCR؛ النظام يحسن الصورة ويبني PDF لكنه لا يستخرج نص.
- يلزم اختبار E2E كامل قبل الإنتاج لكل مسارات: login, refresh token, scanner, upload, chat, tickets, printer sync, update install, backup/restore.
- تشغيل WebView على Windows قد يحتاج NuGet/dependencies سليمة.
- تحديث الديسكتوب قد يفشل لو التطبيق التنفيذي مقفول عليه من نسخة تعمل بالفعل، رغم وجود تحسينات single instance.

## 25. الخلاصة

المشروع يمثل منصة داخلية لإدارة عمليات الـIT والملفات والتواصل، وليس مجرد ماسح مستندات. أكبر قيمة فيه أنه يجمع الموظف والمدير والدعم الفني في نفس النظام:

- الموظف يمسح مستندات، يرفع ملفات، يفتح تذاكر، ويتواصل عبر الشات.
- موظف الـIT يدير التذاكر والطابعات والأصول وقطع الغيار.
- الإدارة تراقب المستخدمين والصلاحيات والإعلانات والنسخ الاحتياطي والتحديثات.
- النظام يدعم العمل من الكمبيوتر والموبايل، ويعتمد على Backend مركزي مع Real-time events.

التوصية الفنية قبل الاعتماد النهائي هي تنفيذ دورة اختبار كاملة، مراجعة صلاحيات الإنتاج، إعداد Firebase، معالجة `npm audit`، وتجربة النسخ الاحتياطي والاستعادة والتحديث التلقائي على أجهزة حقيقية.
