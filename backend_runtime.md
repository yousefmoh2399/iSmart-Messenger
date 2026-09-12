
بنيت لك الآن المسار الصح والبسيط:

حزمة تشغيل للباك إند فقط: backend_runtime (line 1)
تطبيق ويندوز بسيط لإدارة هذا المسار: windows_host (line 1)
أهم ما تم:

backend_runtime فيه:
تثبيت الخدمة
تشغيل/إيقاف/إعادة تشغيل
فحص الحالة
Backup
Restore
جدولة Backup
windows_host فيه:
شاشة إعدادات
اختيار المجلدات والملفات
زر Install Service
Start / Stop / Restart / Status
Create Backup / Restore Backup
Save Schedule / Remove Schedule
Console داخل التطبيق
الملفات الأساسية:

Install-CSScannerBackendService.ps1 (line 1)
Backup-CSScannerBackend.ps1 (line 1)
Restore-CSScannerBackend.ps1 (line 1)
main.dart (line 1)
build_windows_host.ps1 (line 1)
Package-CSScannerBackendSuite.ps1 (line 1)
الذي تفعله الآن عندك على جهاز Windows

ابنِ حزمة الباك إند فقط:
Set-ExecutionPolicy -Scope Process Bypass
.\backend_runtime\Package-CSScannerBackendRuntime.ps1 -Version 1.0.0
أو ابنِ التسليم الكامل مع تطبيق الويندوز:
Set-ExecutionPolicy -Scope Process Bypass
.\backend_runtime\Package-CSScannerBackendSuite.ps1 -Version 1.0.0 -BuildNumber 1
على سيرفر الشركة ثبّت:
Node.js 20+
MongoDB Database Tools
NSSM
فك CSScannerBackendRuntime_1.0.0.zip
فك CSScannerBackendHost_1.0.0.zip
شغّل تطبيق:
CSScannerBackendHost.exe
داخل التطبيق:
Runtime Root = مجلد backend_runtime المفكوك
Server Host = IP السيرفر
Port = 2311
MongoDB URI = لينك قاعدة البيانات
NSSM Path = مسار nssm.exe
MongoDB Tools Directory = مسار أدوات Mongo
ثم اضغط Install Service
بعد التثبيت:
اضغط Status
ثم Start لو احتاج
ثم اضبط Backup وSchedule
برامج الموظفين تتصل على:
http://SERVER_IP:2311
تحقق شغلته

dart analyze على backend_runtime/windows_host: ناجح
flutter test على backend_runtime/windows_host: ناجح
مهم جدًا
هذا المسار ممتاز تشغيليًا، لكنه لا يخفي الكود 100% لأن حزمة التشغيل ما زالت Node runtime عادية.
لو تريد المرحلة التالية للحماية الفعلية، فهي:

تحويل الباك إند إلى EXE / protected runtime
ثم نفس الـ Host App الحالي يشغله
إذا أردت، الخطوة التالية أعملها لك هي: أرتب لك تسليم شركة نهائي جدًا:

ما الملفات التي سترسلها فقط
كيف يثبتها موظف IT
وكيف يضبط IP وMongoDB خطوة بخطوة بالعر