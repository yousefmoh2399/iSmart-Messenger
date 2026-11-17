@echo off
chcp 65001 >nul
title تثبيت خط الإيموجي - iSmart Messenger

echo ========================================================
echo         تثبيت خط Segoe UI Emoji لأجهزة ويندوز
echo ========================================================
echo.

:: التأكد من صلاحيات المسؤول
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [X] خطأ: يجب تشغيل هذا الملف كمسؤول!
    echo [!] اضغط كليك يمين على الملف واختر "Run as administrator" (تشغيل كمسؤول)
    echo.
    pause
    exit /b 1
)

if not exist "%~dp0seguiemj.ttf" (
    echo [X] خطأ: لم يتم العثور على ملف seguiemj.ttf بجوار هذا الملف!
    pause
    exit /b 1
)

echo [+] جار نسخ الخط إلى مجلد خطوط الويندوز (C:\Windows\Fonts)...
copy /y "%~dp0seguiemj.ttf" "%windir%\Fonts\seguiemj.ttf" >nul
if %errorlevel% neq 0 (
    echo [X] فشل نسخ الملف! تأكد من صلاحيات النظام.
    pause
    exit /b 1
)

echo [+] جار تسجيل الخط في ريجيستري الويندوز (Windows Registry)...
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" /v "Segoe UI Emoji (TrueType)" /t REG_SZ /d "seguiemj.ttf" /f >nul
if %errorlevel% neq 0 (
    echo [X] فشل تسجيل الخط في الريجستري!
    pause
    exit /b 1
)

echo.
echo ========================================================
echo [OK] تم تثبيت وتسجيل خط الإيموجي بنجاح تام!
echo      يرجى إعادة تشغيل برنامج iSmart Messenger الآن.
echo ========================================================
echo.
pause
