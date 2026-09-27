# الدليل الشامل والاحترافي لتثبيت نظام iSmart Messenger

أهلاً بك في دليل تثبيت نظام **iSmart Messenger Backend**.
اختر القسم الذي يطابق حالة السيرفر الخاص بك واتبع الأوامر خطوة بخطوة بالترتيب.

---

## 🐧 أولاً: تثبيت النظام على سيرفر لينكس (Ubuntu)

### 🔴 السيناريو الأول: لينكس على هارد ديسك واحد (النظام والتخزين في مكان واحد)

في جهازك الشخصي، افتح Terminal وانسخ الملف للسيرفر:

```bash
scp ismart-backend-linux root@IP_ADDRESS:/tmp/
```

*(استبدل IP_ADDRESS برقم الآي بي الخاص بالسيرفر)*

ادخل للسيرفر:

```bash
ssh root@IP_ADDRESS
```

قم بتحديث النظام وفتح بورت 2020 وإعطاء صلاحية التشغيل للملف:

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo ufw allow 2020/tcp
sudo ufw reload
cd /tmp
sudo chmod +x ismart-backend-linux
```

ابدأ معالج التثبيت:

```bash
sudo ./ismart-backend-linux --install
```

**إجابات معالج التثبيت (لهارد واحد):**

- **What would you like to do?** اكتب `1` واضغط `Enter`.
- **MongoDB is NOT running:** اكتب `1` واضغط `Enter`.
- **Main data directory:** اضغط `Enter` للموافقة على `/var/lib/ismart`.
- **Chat & uploads directory:** اضغط `Enter`.
- **Backups directory:** اضغط `Enter`.
- **App updates directory:** اضغط `Enter`.
- **API Port [2020]:** اضغط `Enter`.
- **Admin username:** اكتب `admin` واضغط `Enter`.
- **Admin password:** اكتب باسورد جديد واضغط `Enter`.
- **Confirm admin password:** أعد كتابة الباسورد واضغط `Enter`.
- **Daily backup time:** اكتب `3` واضغط `Enter`.
- **Backup save directory:** اضغط `Enter`.

للتأكد من نجاح التثبيت:

```bash
sudo systemctl status ismart-backend
```

**(انتهى التثبيت بنجاح!)**

---

### 🟢 السيناريو الثاني: لينكس على هاردين (هارد للنظام وهارد للتخزين)

في جهازك الشخصي، افتح Terminal وانسخ الملف للسيرفر:

```bash
scp ismart-backend-linux root@IP_ADDRESS:/tmp/
```

ادخل للسيرفر:

```bash
ssh root@IP_ADDRESS
```

قم بتحديث النظام وفتح البورت:

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo ufw allow 2020/tcp
sudo ufw reload
```

قم بتهيئة الهارد الثاني (بافتراض أن اسمه `sdb`) وربطه بمسار `/mnt/storage`:

```bash
sudo mkfs.ext4 /dev/sdb
sudo mkdir -p /mnt/storage
sudo mount /dev/sdb /mnt/storage
echo '/dev/sdb /mnt/storage ext4 defaults 0 0' | sudo tee -a /etc/fstab
```

إعطاء صلاحية التشغيل للملف وبدء التثبيت:

```bash
cd /tmp
sudo chmod +x ismart-backend-linux
sudo ./ismart-backend-linux --install
```

**إجابات معالج التثبيت (لهاردين):**

- **What would you like to do?** اكتب `1` واضغط `Enter`.
- **MongoDB is NOT running:** اكتب `1` واضغط `Enter`.
- **Main data directory:** اكتب `/mnt/storage/ismart` واضغط `Enter`.
- **Chat & uploads directory:** اضغط `Enter`.
- **Backups directory:** اضغط `Enter`.
- **App updates directory:** اضغط `Enter`.
- **API Port [2020]:** اضغط `Enter`.
- **Admin username:** اكتب `admin` واضغط `Enter`.
- **Admin password:** اكتب باسورد جديد واضغط `Enter`.
- **Confirm admin password:** أعد كتابة الباسورد واضغط `Enter`.
- **Daily backup time:** اكتب `3` واضغط `Enter`.
- **Backup save directory:** اضغط `Enter`.

للتأكد من نجاح التثبيت:

```bash
sudo systemctl status ismart-backend
```

**(انتهى التثبيت بنجاح!)**

---

## 🪟 ثانياً: تثبيت النظام على سيرفر ويندوز (Windows Server)

### 🔴 السيناريو الأول: ويندوز على هارد ديسك واحد (القرص C فقط)

انقل ملف `ismart-backend-win.exe` من جهازك إلى السيرفر وضعه في القرص `C` (مثال: `C:\iSmart`).

افتح **PowerShell كمسؤول (Run as Administrator)**، وقم بفتح البورت 2020:

```powershell
New-NetFirewallRule -DisplayName "iSmart Backend" -Direction Inbound -LocalPort 2020 -Protocol TCP -Action Allow
```

انتقل للمجلد وشغل التثبيت:

```powershell
cd C:\iSmart
.\ismart-backend-win.exe --install
```

**إجابات معالج التثبيت (لهارد واحد):**

- **What would you like to do?** اكتب `1` واضغط `Enter`.
- **MongoDB is NOT running:** اكتب `1` واضغط `Enter`.
- **Main data directory:** اضغط `Enter` للموافقة على `C:\ProgramData\ismart`.
- **Chat, Backups, Updates directories:** اضغط `Enter` 3 مرات للموافقة عليها جميعاً.
- **API Port [2020]:** اضغط `Enter`.
- **Admin username:** اكتب `admin` واضغط `Enter`.
- **Admin password:** اكتب باسورد جديد واضغط `Enter`.
- **Confirm admin password:** أعد كتابة الباسورد واضغط `Enter`.
- **Daily backup time:** اكتب `3` واضغط `Enter`.
- **Backup save directory:** اضغط `Enter`.

للتأكد من نجاح التثبيت:

```powershell
Get-Service ismart-backend
```

**(انتهى التثبيت بنجاح!)**

---

### 🟢 السيناريو الثاني: ويندوز على هاردين (قرص للنظام وقرص للتخزين)

انقل ملف `ismart-backend-win.exe` من جهازك إلى السيرفر وضعه في القرص `C` (مثال: `C:\iSmart`).

افتح **PowerShell كمسؤول (Run as Administrator)**، وقم بتهيئة الهارد الثاني، وإعطائه الحرف `D`، وفتح البورت:

```powershell
# تهيئة الهارد الثاني
Initialize-Disk -Number 1 -PartitionStyle GPT
New-Partition -DiskNumber 1 -UseMaximumSize -DriveLetter D
Format-Volume -DriveLetter D -FileSystem NTFS -NewFileSystemLabel "Storage"

# فتح بورت الجدار الناري
New-NetFirewallRule -DisplayName "iSmart Backend" -Direction Inbound -LocalPort 2020 -Protocol TCP -Action Allow
```

انتقل للمجلد وشغل التثبيت:

```powershell
cd C:\iSmart
.\ismart-backend-win.exe --install
```

**إجابات معالج التثبيت (لهاردين):**

- **What would you like to do?** اكتب `1` واضغط `Enter`.
- **MongoDB is NOT running:** اكتب `1` واضغط `Enter`.
- **Main data directory:** اكتب `D:\ismartData` واضغط `Enter`.
- **Chat, Backups, Updates directories:** اضغط `Enter` 3 مرات للموافقة.
- **API Port [2020]:** اضغط `Enter`.
- **Admin username:** اكتب `admin` واضغط `Enter`.
- **Admin password:** اكتب باسورد جديد واضغط `Enter`.
- **Confirm admin password:** أعد كتابة الباسورد واضغط `Enter`.
- **Daily backup time:** اكتب `3` واضغط `Enter`.
- **Backup save directory:** اضغط `Enter`.

للتأكد من نجاح التثبيت:

```powershell
Get-Service ismart-backend
```

**(انتهى التثبيت بنجاح!)**

---

## 🛠️ أوامر الصيانة وإدارة النظام

استخدم هذه الأوامر للإدارة بعد التثبيت.
*(للينكس استخدم Terminal بـ `sudo` / لويندوز استخدم PowerShell كـ Administrator)*

### 1. الفحص الشامل واكتشاف الأخطاء (Doctor)

- **لينكس:** `sudo /tmp/ismart-backend-linux --doctor`
- **ويندوز:** `cd C:\iSmart ; .\ismart-backend-win.exe --doctor`

### 2. النسخ الاحتياطي اليدوي فوراً (Backup)

- **لينكس:** `sudo /tmp/ismart-backend-linux --backup`
- **ويندوز:** `cd C:\iSmart ; .\ismart-backend-win.exe --backup`

### 3. استعادة النظام (Restore)

- **لينكس:** `sudo /tmp/ismart-backend-linux --restore`
- **ويندوز:** `cd C:\iSmart ; .\ismart-backend-win.exe --restore`

### 4. إعادة تشغيل الخدمة يدوياً

- **لينكس:** `sudo systemctl restart ismart-backend`
- **ويندوز:** `Restart-Service ismart-backend`
