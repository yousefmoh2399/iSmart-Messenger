# iSmart Backend — Build & Deployment Guide

> دليل شامل من الصفر حتى نظام شغّال على Windows Server و Ubuntu Linux

---

## 📋 جدول المحتويات

1. [نظرة عامة](#1-نظرة-عامة)
2. [المتطلبات المسبقة للبناء](#2-المتطلبات-المسبقة-للبناء)
3. [بناء الـ EXE على Windows](#3-بناء-الـ-exe-على-windows)
4. [بناء الـ Binary على Linux](#4-بناء-الـ-binary-على-linux)
5. [نشر على Windows Server](#5-نشر-على-windows-server)
6. [نشر على Ubuntu Linux](#6-نشر-على-ubuntu-linux)
7. [تحديث نسخة موجودة](#7-تحديث-نسخة-موجودة)
8. [النسخ الاحتياطي والاستعادة](#8-النسخ-الاحتياطي-والاستعادة)
9. [فحص صحة النظام](#9-فحص-صحة-النظام)
10. [الأوامر المرجعية الكاملة](#10-الأوامر-المرجعية-الكاملة)
11. [هيكل الملفات على السيرفر](#11-هيكل-الملفات-على-السيرفر)
12. [استكشاف الأخطاء](#12-استكشاف-الأخطاء)

---

## 1. نظرة عامة

iSmart Backend هو API server مبني بـ Node.js/Express يُوزَّع كملف تنفيذي واحد مشفّر (pkg).

| الملف | النظام | الحجم |
|-------|--------|-------|
| `ismart-backend-win.exe` | Windows x64 | ~74 MB |
| `ismart-backend-linux`   | Linux x64   | ~82 MB |

**المميزات:**
- كود مصدري مشفّر بالكامل (bytecode)
- تثبيت كـ Windows Service أو Linux systemd
- يثبّت MongoDB تلقائياً لو مش موجود
- Backup تلقائي يومي (قاعدة بيانات + ملفات)
- Wizard للتثبيت / التحديث / الاستعادة
- فحص صحة كامل (Doctor)

---

## 2. المتطلبات المسبقة للبناء

> هذه المتطلبات فقط على جهاز التطوير — السيرفر لا يحتاجها

### على Windows (جهاز التطوير):

```powershell
# 1. تأكد من Node.js 18+
node --version   # يجب v18.x أو أعلى

# 2. ثبّت dependencies
cd "f:\iSmart New Github\iSmart-Messenger\backend"
npm install
```

### على Linux (جهاز التطوير):

```bash
# 1. ثبّت Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# 2. ثبّت dependencies
cd /path/to/backend
npm install
```

---

## 3. بناء الـ EXE على Windows

```powershell
cd "f:\iSmart New Github\iSmart-Messenger\backend"

# ابنِ الـ EXE لـ Windows و Linux معاً
npx pkg . --compress GZip

# النتيجة:
# dist/
# ├── ismart-backend-win.exe   (74 MB)
# └── ismart-backend-linux     (82 MB)
```

> ملاحظة: رسائل "Warning Failed to make bytecode" طبيعية جداً — تخص مكتبات ES Modules فقط.
> كودك الخاص مشفّر بالكامل.

---

## 4. بناء الـ Binary على Linux

```bash
cd /path/to/backend
npx pkg . --compress GZip
# النتيجة في dist/
```

> يمكنك بناء ملف Linux من على Windows والعكس — pkg يدعم cross-compilation.

---

## 5. نشر على Windows Server

### الخطوات:

```powershell
# 1. انسخ ملفاً واحداً فقط على السيرفر:
ismart-backend-win.exe

# 2. افتح PowerShell كـ Administrator
# (Right-click على PowerShell → Run as Administrator)

# 3. شغّل الـ Wizard
.\ismart-backend-win.exe --install
```

### ما يحدث خلال التثبيت:

```
Setup Wizard — ما تراه على الشاشة:

  What would you like to do?
    1) Fresh installation — set up from scratch
    2) Update existing installation
    3) Restore from backup

  اختر: 1

[1/7] Checking privileges...
  ✓ Running as Administrator.

[2/7] Checking MongoDB...
  ✓ MongoDB is running.
  (أو يعرض خيار تثبيته تلقائياً)

[3/7] Configure data directories...
  Main data directory
  Suggested paths:
    1)  C:\ProgramData\iSmart    [will be created]
    2)  D:\iSmart                [will be created]
    3)  C:\iSmart                [will be created]
  Path or number [1]: 2
  ✓ Main data directory: D:\iSmart  (created)

  Chat & uploads directory
    1)  D:\iSmart\uploads        [will be created]
    2)  D:\iSmart\files          [will be created]
  Path or number [1]:
  ✓ D:\iSmart\uploads  (created)

[4/7] Configure connection settings...
  API Port [5000]:
  MongoDB URI [...]:
  Admin username: admin
  Admin password: ********  (8 حروف على الأقل)
  Confirm:        ********
  ✓ Admin credentials accepted.

[5/7] Configure backup schedule...
  Daily backup time:
    1) 1:00 AM
    2) 2:00 AM
    3) 3:00 AM

  Backup save directory:
    1)  D:\iSmart\backups        [will be created]
    2)  E:\iSmart\backups        [will be created]
    3)  \\NAS\Backups\iSmart     (network share example)
  Path or number [1]: 3

[6/7] Writing config and installing service...
  ✓ Config saved: D:\iSmart\config.json
  ✓ Windows Service installed: iSmartBackend

[7/7] Health check + admin verification...
  ✓ MongoDB: reachable
  ✓ Windows Service: Running
  ✓ API (port 5000): responding
  ✓ Admin "admin": verified

  Installation complete!
  API URL    : http://localhost:5000
  Admin      : admin  ✓ verified
  Backup     : Daily 3AM → \\NAS\Backups\iSmart
```

---

## 6. نشر على Ubuntu Linux

```bash
# 1. انسخ الملف للسيرفر
scp ismart-backend-linux user@server:/tmp/

# 2. سجّل دخول
ssh user@server

# 3. صلاحيات التشغيل
chmod +x /tmp/ismart-backend-linux

# 4. شغّل الـ Wizard
sudo /tmp/ismart-backend-linux --install
```

### اختيار المسارات على Linux:

```
[3/7] Configure data directories...

  Main data directory
  Suggested paths:
    1)  /var/lib/ismart      [will be created]  (standard للـ services)
    2)  /opt/ismart          [will be created]
    3)  /home/ismart/data    [will be created]

  Backup save directory
    1)  /var/lib/ismart/backups
    2)  /mnt/nas/ismart-backups   (network mount example)
    3)  /media/backup/ismart
```

> للـ network share على Linux: mount المجلد في /etc/fstab أولاً

---

## 7. تحديث نسخة موجودة

> البيانات والـ config لن تتأثر — فقط الـ EXE يتحدّث

```powershell
# Windows — ضع الـ EXE الجديد في أي مكان وشغّله
.\ismart-backend-win-NEW.exe --install
# اختر: 2) Update existing installation

# ما يحدث:
# - يقرأ الـ config الموجودة تلقائياً
# - يوقف الـ service القديم
# - يسجّل النسخة الجديدة كـ service
# - يعيد التشغيل ويفحص الصحة
```

```bash
# Linux
sudo ./ismart-backend-linux-NEW --install
# اختر: 2) Update existing installation
```

---

## 8. النسخ الاحتياطي والاستعادة

### Backup يدوي:

```powershell
# Windows
"C:\path\to\ismart-backend-win.exe" --backup

# Linux
sudo /usr/local/bin/ismart-backend --backup
```

### محتوى ملف الـ Backup:

```
ismart-backup-2026-09-23T01-00-00.zip
├── db/                        (MongoDB dump كامل)
│   └── workplace_documents/
├── uploads/                   (ملفات الشات والمستندات)
│   ├── chat/
│   ├── avatars/
│   └── chat_transfers/
└── backup-manifest.json       (معلومات الـ backup)
```

### Backup تلقائي:
- **Windows:** Windows Task Scheduler — يومي في الوقت المختار
- **Linux:** `/etc/cron.d/ismart-backup` — cron job يومي

### استعادة من Backup:

```powershell
.\ismart-backend-win.exe --install
# اختر: 3) Restore from backup
# Backup file path: \\NAS\Backups\iSmart\ismart-backup-2026-09-23.zip
```

---

## 9. فحص صحة النظام

```powershell
# Windows
"C:\path\to\ismart-backend-win.exe" --doctor

# Linux
sudo ./ismart-backend --doctor
```

### مثال على النتيجة:

```
System Health Check (Doctor)
  ✓  MongoDB: reachable
  ✓  Windows Service: Running
  ✓  API (port 5000): responding
  ✓  Uploads dir: writable
  ✓  Backups dir: writable
  ✗  mongodump: NOT found

  Suggested fixes:
    1) mongodump: winget install MongoDB.DatabaseTools
    2) Skip

  > اختر 1 → يثبّته تلقائياً
```

---

## 10. الأوامر المرجعية الكاملة

### Windows (PowerShell كـ Administrator):

| الأمر | الوظيفة |
|-------|---------|
| `.\ismart-backend-win.exe --install` | تثبيت / تحديث / استعادة |
| `.\ismart-backend-win.exe --uninstall` | إزالة كاملة |
| `.\ismart-backend-win.exe --backup` | backup يدوي فوري |
| `.\ismart-backend-win.exe --doctor` | فحص صحة النظام |
| `sc.exe query iSmartBackend` | حالة الـ service |
| `sc.exe start iSmartBackend` | تشغيل الـ service |
| `sc.exe stop iSmartBackend` | إيقاف الـ service |
| `type D:\iSmart\logs\stdout.log` | عرض الـ logs |

### Linux (sudo):

| الأمر | الوظيفة |
|-------|---------|
| `sudo ./ismart-backend-linux --install` | تثبيت / تحديث / استعادة |
| `sudo ./ismart-backend-linux --uninstall` | إزالة كاملة |
| `sudo ./ismart-backend-linux --backup` | backup يدوي فوري |
| `sudo ./ismart-backend-linux --doctor` | فحص صحة النظام |
| `sudo systemctl status ismart-backend` | حالة الـ service |
| `sudo systemctl start ismart-backend` | تشغيل |
| `sudo systemctl stop ismart-backend` | إيقاف |
| `sudo tail -f /var/lib/ismart/logs/stdout.log` | عرض الـ logs |

---

## 11. هيكل الملفات على السيرفر

### Windows:

```
D:\iSmart\                         (DATA_DIR — تختاره عند التثبيت)
├── config.json                    (الإعدادات — JWT, MongoDB, ports)
├── uploads\
│   ├── chat\<conversation_id>\    (ملفات الشات)
│   ├── avatars\<user_id>\         (صور البروفايل)
│   └── chat_transfers\<user_id>\  (نقل الملفات)
├── backups\                       (backups محلية)
├── releases\                      (تحديثات تطبيق الموبايل)
└── logs\
    ├── stdout.log
    └── stderr.log

\\NAS\Backups\iSmart\              (backup save dir — network share)
└── ismart-backup-2026-09-23.zip
```

### Linux:

```
/var/lib/ismart/                   (DATA_DIR)
├── uploads/
├── backups/
├── releases/
└── logs/
    ├── stdout.log
    └── stderr.log

/etc/ismart/
└── config.json                    (chmod 600)

/etc/systemd/system/
└── ismart-backend.service

/etc/cron.d/
└── ismart-backup

/usr/local/bin/
└── ismart-backend
```

---

## 12. استكشاف الأخطاء

### "Access Denied" على Windows

```powershell
# تأكد من تشغيل PowerShell كـ Administrator
# Right-click → "Run as Administrator"
```

### MongoDB لا يستجيب

```powershell
# Windows
net start MongoDB

# Linux
sudo systemctl start mongod

# أو شغّل doctor — يقترح الإصلاح تلقائياً
.\ismart-backend-win.exe --doctor
```

### الـ service لا يبدأ — قراءة الـ logs

```powershell
# Windows
type "D:\iSmart\logs\stderr.log"
Get-EventLog -LogName Application -Newest 10
```

```bash
# Linux
sudo journalctl -u ismart-backend -n 50
sudo cat /var/lib/ismart/logs/stderr.log
```

### Backup لم ينجز — mongodump مش موجود

```powershell
# Windows
winget install --id MongoDB.DatabaseTools -e

# Linux
sudo apt-get install -y mongodb-database-tools
```

### Network share backup لا يعمل (Windows)

```powershell
# الـ service يعمل كـ SYSTEM — أعط الصلاحيات
icacls "\\NAS\Backups\iSmart" /grant "SYSTEM:(OI)(CI)F"
```

---

## ملاحظات أمنية

- `config.json` يحتوي `JWT_SECRET` — لا تشاركه أبداً
- كلمة مرور الـ admin تُمسح تلقائياً من `config.json` بعد أول تشغيل للسيرفر
- على Linux: `config.json` محمي بـ `chmod 600`
- على Windows: `config.json` في `ProgramData` — محمي من المستخدمين العاديين

---

*iSmart Messenger Backend — آخر تحديث: 2026-09-23*
