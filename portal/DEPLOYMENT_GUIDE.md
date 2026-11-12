# 🚀 دليل نشر واستضافة بوابة iSmart Messenger على السيرفر (لربط 50 فرعاً)

هذا الدليل الفني يوضح لمسؤول النظام (System Administrator) كيفية استضافة ونشر موقع البوابة (`portal`) ليكون متاحاً لجميع موظفي الفروع لتحميل البرنامج ومشاهدة الفيديوهات.

الموقع عبارة عن **Static Web Portal (HTML5 / CSS3 / Vanilla JS)** فائق السرعة، ولا يتطلب أي قاعدة بيانات أو إعدادات برمجية معقدة.

---

## 📁 هيكل مجلد الموقع قبل النشر
تأكد من وجود الملفات التالية داخل مجلد `portal`:
```text
portal/
├── index.html                           # الصفحة الرئيسية (الزرين + الفيديوهات)
├── windows.html                         # دليل برنامج الكمبيوتر المفصل
├── mobile.html                          # دليل تطبيق الموبايل المفصل
├── deploy.html                          # دليل النشر
├── faq.html                             # مركز الدعم الفني للفروع
├── css/style.css                        # التنسيقات (Apple Minimalist Design)
├── js/main.js                           # التفاعلية ومحاور الفيديو
├── assets/images/                       # الشعار والأيقونات
└── downloads/                           # مجلد الملفات (يحتوي على الملفات الـ 4 التالية):
    ├── iSmart Messenger Setup 1.1.15.exe
    ├── iSmart-Messenger.apk
    ├── iSmart Messenger Windows.mp4
    └── iSmart Messenger Mobile.mp4
```

---

## 🛠️ الخيار الأول: النشر على سيرفر لينكس (Ubuntu / Debian مع Nginx) — الأفضل والموصى به

### 1. نسخ الملفات للسيرفر
قم بنسخ كامل مجلد `portal` إلى مسار الويب في سيرفر اللينكس عبر SCP أو FileZilla:
```bash
sudo mkdir -p /var/www/ismart-portal
sudo cp -r /path/to/portal/* /var/www/ismart-portal/
sudo chown -R www-data:www-data /var/www/ismart-portal
sudo chmod -R 755 /var/www/ismart-portal
```

### 2. إنشاء إعدادات Nginx
قم بإنشاء ملف إعداد جديد للموقع:
```bash
sudo nano /etc/nginx/sites-available/ismart-portal
```

ضع الإعدادات التالية:
```nginx
server {
    listen 80;
    server_name portal.yourcompany.local 192.168.1.100; # استبدل بـ IP أو دومين السيرفر الخاص بك

    root /var/www/ismart-portal;
    index index.html;

    # دعم تحميل الفيديوهات والملفات الكبيرة بسلاسة
    client_max_body_size 500M;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # تسريع تقديم ملفات التنزيل والفيديوهات
    location /downloads/ {
        sendfile on;
        sendfile_max_chunk 1m;
        tcp_nopush on;
        tcp_nodelay on;
        keepalive_timeout 65;
    }

    # التخزين المؤقت للأيقونات والتنسيقات
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
        expires 7d;
        add_header Cache-Control "public, no-transform";
    }
}
```

### 3. تفعيل الموقع وإعادة تشغيل Nginx
```bash
sudo ln -s /etc/nginx/sites-available/ismart-portal /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```
الموقع سيعمل فوراً على العنوان: `http://192.168.1.100`

---

## 🖥️ الخيار الثاني: النشر على سيرفر ويندوز (Windows Server مع IIS)

إذا كان سيرفر الشركة يعمل بنظام Windows Server:

1. **نسخ المجلد:**
   - انقل مجلد `portal` إلى المسار:
     `C:\inetpub\wwwroot\portal`

2. **إضافة الموقع في IIS:**
   - افتح **Internet Information Services (IIS) Manager**.
   - كليك يمين على **Sites** ثم اختر **Add Website...**.
   - **Site name:** `iSmart Portal`
   - **Physical path:** `C:\inetpub\wwwroot\portal`
   - **Port:** اختر المنفذ المطلوب (مثلاً `80` أو `8080`).

3. **إضافة أنواع MIME Type لملفات الـ APK والـ MP4:**
   - من داخل الـ IIS، اضغط على **MIME Types** وتأكد من وجود الأنواع التالية (أو أضفها):
     * `.apk` ➔ `application/vnd.android.package-archive`
     * `.mp4` ➔ `video/mp4`
     * `.exe` ➔ `application/octet-stream`

4. اضغط **Restart** للموقع من لوحة الـ IIS وسيعمل الموقع لجميع الأجهزة بالشبكة.

---

## 🐳 الخيار الثالث: تشغيل فوري عبر Docker (سطر أوامر واحد)

إذا كان لديك Docker على السيرفر:
```bash
docker run -d \
  --name ismart-portal \
  --restart always \
  -p 8080:80 \
  -v /var/www/portal:/usr/share/nginx/html:ro \
  nginx:alpine
```
الموقع سيعمل فوراً على المنفذ `8080`.

---

## ⚡ الخيار الرابع: تشغيل محلي فوري للمعاينة على جهازك
افتح مجلد `portal` واضغط دبل كليك على:
```cmd
start-portal.bat
```
سيقوم السكريبت بتشغيل خادم ويب فوري وفتح الموقع في متصفحك مباشرة.

---

## ✅ قائمة التحقق لضمان عمل الموقع لـ 50 فرعاً:
1. **جدار الحماية (Firewall):** تأكد من فتح المنفذ (Port 80 أو 8080) في جدار حماية السيرفر للسماح للأجهزة في الفروع بالدخول.
2. **الربط بالـ VPN أو الـ Static IP:** تأكد أن أجهزة الفروع قادرة على عمل Ping لعنوان السيرفر.
3. **الملفات الـ 4:** تأكد أن الملفات الـ 4 (الـ EXE والـ APK والـ 2 فيديوهات) موجودة داخل مجلد `downloads/`.
4. **مشاركة الرابط:** انسخ الرابط وأرسله في بريد إداري رسمي أو رسالة تعميم لمديري الفروع لسرعة التثبيت.
