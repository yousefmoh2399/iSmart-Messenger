@echo off
chcp 65001 > nul
echo ========================================================
echo   iSmart Messenger - تشغيل البوابة الرسمية للفروع
echo ========================================================
echo.
echo جاري فتح الموقع في المتصفح...
echo.

:: Try starting a local python server if available, or directly open index.html
where python >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo تم العثور على Python، جاري تشغيل خادم محلي على http://localhost:8080 ...
    start http://localhost:8080/index.html
    python -m http.server 8080
    goto :end
)

where npx >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo جاري تشغيل خادم محلي عبر Node.js...
    start http://localhost:8080/index.html
    npx serve -l 8080 .
    goto :end
)

:: Fallback: Open index.html directly
echo فتح الملف مباشرة في المتصفح...
start index.html

:end
