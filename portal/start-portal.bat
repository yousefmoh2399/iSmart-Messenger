@echo off
chcp 65001 > nul
echo ========================================================
echo   iSmart Messenger - تشغيل البوابة الرسمية للفروع
echo ========================================================
echo.

where node >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo تم العثور على Node.js، جاري تشغيل الخادم مع دعم بث الفيديو الكامل...
    node "%~dp0server.js"
    goto :end
)

where python >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo جاري تشغيل الخادم عبر Python...
    start http://localhost:8080/index.html
    python -m http.server 8080
    goto :end
)

echo جاري فتح الموقع في المتصفح مباشرة...
start "" "%~dp0index.html"

:end
