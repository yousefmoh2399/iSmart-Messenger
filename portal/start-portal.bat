@echo off
setlocal
cd /d "%~dp0"
title iSmart Messenger Portal - Next.js

echo ========================================================
echo   iSmart Messenger - Official Branch Portal (Next.js)
echo ========================================================
echo.

where node >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Node.js is not found. Please install Node.js 18+ first.
    pause
    exit /b 1
)

if not exist ".next" (
    echo [.next folder not found, running build first...]
    call npm run build
)

echo.
echo Starting Next.js Portal on port 8080...
echo Portal URL: http://localhost:8080
echo.

:: Open browser automatically
start http://localhost:8080

call npm start

pause
