#!/usr/bin/env pwsh
# =============================================================================
# iSmart Backend Build Script
# Builds standalone EXE for Windows and Linux using pkg
# =============================================================================
param(
    [string]$Target = "both",   # "windows" | "linux" | "both"
    [switch]$SkipNodeCheck,
    [switch]$NoCurl              # Skip curl binary check warning
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "=== iSmart Backend Build Script ===" -ForegroundColor Cyan

# ── 1. Check Node.js ───────────────────────────────────────────────────────
if (-not $SkipNodeCheck) {
    $nodeVersion = node --version 2>$null
    if (-not $nodeVersion) {
        Write-Error "Node.js not found. Install Node.js 18+ first."
        exit 1
    }
    Write-Host "  Node.js: $nodeVersion" -ForegroundColor Green
}

# ── 2. Check npm dependencies ──────────────────────────────────────────────
if (-not (Test-Path "node_modules")) {
    Write-Host "  Installing npm dependencies..." -ForegroundColor Yellow
    npm install
}

# ── 3. Check pkg ───────────────────────────────────────────────────────────
$pkgPath = ".\node_modules\.bin\pkg.cmd"
if (-not (Test-Path $pkgPath)) {
    Write-Error "pkg not found. Run 'npm install' first (it's in devDependencies)."
    exit 1
}
Write-Host "  pkg: found" -ForegroundColor Green

# ── 4. Warn about curl binaries ────────────────────────────────────────────
if (-not $NoCurl) {
    $winCurl  = ".\bin\curl.exe"
    $linCurl  = ".\bin\curl"
    $missing  = @()
    if (-not (Test-Path $winCurl))  { $missing += $winCurl }
    if (-not (Test-Path $linCurl))  { $missing += $linCurl }
    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "  WARNING: Missing curl binary files:" -ForegroundColor Yellow
        $missing | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
        Write-Host "  The server will fall back to system curl if not bundled." -ForegroundColor Yellow
        Write-Host "  See bin\README.md for download instructions." -ForegroundColor Yellow
        Write-Host ""
    }
}

# ── 5. Create output directory ─────────────────────────────────────────────
if (-not (Test-Path "dist")) { New-Item -ItemType Directory -Path "dist" | Out-Null }

# ── 6. Build targets ───────────────────────────────────────────────────────
$targets = @()
if ($Target -eq "both" -or $Target -eq "windows") { $targets += "node18-win-x64" }
if ($Target -eq "both" -or $Target -eq "linux")   { $targets += "node18-linux-x64" }

if ($targets.Count -eq 0) {
    Write-Error "Invalid -Target value: '$Target'. Use 'windows', 'linux', or 'both'."
    exit 1
}

$targetArg = $targets -join ","
Write-Host "  Building targets: $targetArg" -ForegroundColor Cyan

& $pkgPath . --targets $targetArg --output dist/ismart-backend --compress GZip

if ($LASTEXITCODE -ne 0) {
    Write-Error "pkg build failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

# ── 7. Rename outputs to match deployment scripts ──────────────────────────
# pkg names them ismart-backend-win.exe / ismart-backend-linux automatically
# when multiple targets are used. Verify and show results.

Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Green
Get-ChildItem dist | ForEach-Object {
    $size = "{0:N1} MB" -f ($_.Length / 1MB)
    Write-Host "  $($_.Name)  ($size)" -ForegroundColor White
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  Windows deployment:" -ForegroundColor White
Write-Host "    1. Copy dist\ismart-backend-win.exe to the server" -ForegroundColor Gray
Write-Host "    2. Copy bin\curl.exe next to the EXE (optional)" -ForegroundColor Gray
Write-Host "    3. Run: deployment\windows\install-service.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "  Linux deployment:" -ForegroundColor White
Write-Host "    1. Copy dist\ismart-backend-linux to the server" -ForegroundColor Gray
Write-Host "    2. Copy bin\curl next to the EXE (optional)" -ForegroundColor Gray
Write-Host "    3. Run: bash deployment/ubuntu/install-service.sh" -ForegroundColor Gray
