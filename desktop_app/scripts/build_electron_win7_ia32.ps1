param(
  [switch]$SkipNpmInstall
)

$ErrorActionPreference = "Stop"

$desktopRoot = Resolve-Path "$PSScriptRoot\.."
$electronRoot = Join-Path $desktopRoot "electron"
$electronBuildRoot = Join-Path $electronRoot "build"

Write-Host "Stopping existing iSmart Messenger instances..."
Get-Process -ErrorAction SilentlyContinue |
  Where-Object {
    $_.ProcessName -eq "iSmart Messenger" -or
    ($_.ProcessName -eq "electron" -and $_.Path -like "$electronRoot*")
  } |
  ForEach-Object {
    try {
      Stop-Process -Id $_.Id -Force -ErrorAction Stop
      Write-Host "Stopped $($_.ProcessName) [$($_.Id)]"
    } catch {
      Write-Warning "Could not stop $($_.ProcessName) [$($_.Id)]: $($_.Exception.Message)"
    }
  }
Start-Sleep -Milliseconds 800

Set-Location -LiteralPath $desktopRoot

Write-Host "Preparing Electron build resources..."
New-Item -ItemType Directory -Force -Path $electronBuildRoot | Out-Null
$iconSource = Join-Path $desktopRoot "windows\runner\resources\app_icon.ico"
if (-not (Test-Path -LiteralPath $iconSource)) {
  $iconSource = Join-Path $desktopRoot "windows\runner\resources\1.ico"
}
if (-not (Test-Path -LiteralPath $iconSource)) {
  throw "Electron icon source was not found."
}
Copy-Item -LiteralPath $iconSource -Destination (Join-Path $electronBuildRoot "icon.ico") -Force

function New-InstallerBrandingBitmap {
  param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [Parameter(Mandatory = $true)]
    [int]$Width,
    [Parameter(Mandatory = $true)]
    [int]$Height,
    [Parameter(Mandatory = $true)]
    [string]$Title,
    [string]$Subtitle = ""
  )

  Add-Type -AssemblyName System.Drawing
  $bitmap = New-Object System.Drawing.Bitmap $Width, $Height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

  $background = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Rectangle]::new(0, 0, $Width, $Height),
    [System.Drawing.Color]::FromArgb(12, 27, 47),
    [System.Drawing.Color]::FromArgb(24, 92, 160),
    90
  )
  $graphics.FillRectangle($background, 0, 0, $Width, $Height)

  $accent = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(55, 185, 255))
  $graphics.FillRectangle($accent, 0, 0, 6, $Height)

  $titleFont = [System.Drawing.Font]::new("Segoe UI", [Math]::Max(9, [Math]::Floor($Height / 18)), [System.Drawing.FontStyle]::Bold)
  $subtitleFont = [System.Drawing.Font]::new("Segoe UI", [Math]::Max(7, [Math]::Floor($Height / 32)), [System.Drawing.FontStyle]::Regular)
  $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
  $muted = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(210, 230, 245))

  $logoPath = Join-Path $desktopRoot "assets\images\logo.png"
  if (Test-Path -LiteralPath $logoPath) {
    $logo = [System.Drawing.Image]::FromFile($logoPath)
    $logoSize = [Math]::Min([Math]::Floor($Width * 0.42), [Math]::Floor($Height * 0.28))
    $logoX = [Math]::Floor(($Width - $logoSize) / 2)
    $logoY = if ($Height -gt 100) { 32 } else { 8 }
    $graphics.DrawImage($logo, $logoX, $logoY, $logoSize, $logoSize)
    $logo.Dispose()
  }

  $textTop = if ($Height -gt 100) { [Math]::Floor($Height * 0.45) } else { 13 }
  $format = [System.Drawing.StringFormat]::new()
  $format.Alignment = [System.Drawing.StringAlignment]::Center
  $graphics.DrawString($Title, $titleFont, $white, [System.Drawing.RectangleF]::new(12, $textTop, $Width - 24, 42), $format)
  if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
    $graphics.DrawString($Subtitle, $subtitleFont, $muted, [System.Drawing.RectangleF]::new(12, $textTop + 36, $Width - 24, 80), $format)
  }

  $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
  $graphics.Dispose()
  $bitmap.Dispose()
  $background.Dispose()
  $accent.Dispose()
  $titleFont.Dispose()
  $subtitleFont.Dispose()
  $white.Dispose()
  $muted.Dispose()
}

New-InstallerBrandingBitmap `
  -OutputPath (Join-Path $electronBuildRoot "sidebar.bmp") `
  -Width 164 `
  -Height 314 `
  -Title "iSmart Messenger" `
  -Subtitle "Secure workplace communication"

New-InstallerBrandingBitmap `
  -OutputPath (Join-Path $electronBuildRoot "header.bmp") `
  -Width 150 `
  -Height 57 `
  -Title "iSmart Messenger"

# 1. Parse Version and Build Number from pubspec.yaml
Write-Host "Reading version from pubspec.yaml..."
$pubspecContent = Get-Content -LiteralPath (Join-Path $desktopRoot "pubspec.yaml") -Raw
if ($pubspecContent -match 'version:\s*([^\s#]+)') {
    $fullVersion = $Matches[1].Trim()
    $versionParts = $fullVersion -split '\+'
    $appVersion = $versionParts[0]
    $buildNumber = if ($versionParts.Length -gt 1) { $versionParts[1] } else { "1" }
    Write-Host "Detected version: $appVersion, Build Number: $buildNumber (from pubspec.yaml)"
} else {
    throw "Could not parse version from pubspec.yaml"
}

# 2. Update Electron package.json version
Write-Host "Updating Electron package.json to match version $appVersion..."
$packageJsonPath = Join-Path $electronRoot "package.json"
if (Test-Path $packageJsonPath) {
    $packageJson = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
    $packageJson.version = $appVersion
    $packageJsonJson = $packageJson | ConvertTo-Json -Depth 10
    
    # Save without BOM (Byte Order Mark) to prevent electron-builder readObjectStart parser error
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($packageJsonPath, $packageJsonJson, $utf8NoBom)
} else {
    throw "package.json not found in electron folder"
}

Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
Write-Host "Building Flutter web for Electron..."
flutter build web --no-web-resources-cdn --no-tree-shake-icons --no-wasm-dry-run --pwa-strategy=none
(Get-Content -LiteralPath (Join-Path $desktopRoot "build\web\index.html") -Raw -Encoding UTF8) `
  -replace '<base href="/">', '<base href="./">' |
  Set-Content -LiteralPath (Join-Path $desktopRoot "build\web\index.html") -Encoding UTF8

$bootstrapPath = Join-Path $desktopRoot "build\web\flutter_bootstrap.js"
(Get-Content -LiteralPath $bootstrapPath -Raw -Encoding UTF8) `
  -replace '(?s)_flutter\.loader\.load\(\{\s*serviceWorkerSettings:\s*\{\s*serviceWorkerVersion:\s*"[^"]*".*?\}\s*\}\);', '_flutter.loader.load();' |
  Set-Content -LiteralPath $bootstrapPath -Encoding UTF8

Set-Location -LiteralPath $electronRoot
if (-not $SkipNpmInstall -or -not (Test-Path "node_modules")) {
  Write-Host "Installing Electron dependencies..."
  npm install
}

Write-Host "Building Windows 7 32-bit installer..."
Get-ChildItem -LiteralPath (Join-Path $electronRoot "dist") -File -Filter "*.exe" -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notlike "*uninstaller*" } |
  Remove-Item -Force
Get-ChildItem -LiteralPath (Join-Path $electronRoot "dist") -File -Filter "*.blockmap" -ErrorAction SilentlyContinue |
  Remove-Item -Force
npm run dist:win7:ia32
if ($LASTEXITCODE -ne 0) {
  throw "electron-builder failed with exit code $LASTEXITCODE"
}

Write-Host "Done. Installer output:"
Get-ChildItem -LiteralPath (Join-Path $electronRoot "dist") -File

$nsisInstaller = Get-ChildItem -LiteralPath (Join-Path $electronRoot "dist") -File -Filter "*.exe" -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notlike "*uninstaller*" } |
  Select-Object -First 1
$bundleDir = Join-Path $electronRoot "dist\win-ia32-unpacked"
if (-not $nsisInstaller) {
  Write-Warning "electron-builder did not produce an installer exe. Creating a portable installer with IExpress..."
  $installerScript = Join-Path $desktopRoot "windows\packaging\create_installer.ps1"
  if (-not (Test-Path -LiteralPath $installerScript)) {
    throw "Installer script not found at $installerScript"
  }
  & $installerScript `
    -BundleDir $bundleDir `
    -OutputDir (Join-Path $electronRoot "dist") `
    -AppName "iSmart Messenger" `
    -ExeName "iSmart Messenger.exe" `
    -Version $appVersion
  $nsisInstaller = Get-ChildItem -LiteralPath (Join-Path $electronRoot "dist") -File -Filter "*Installer*.exe" -ErrorAction SilentlyContinue |
    Select-Object -First 1
}
if (-not $nsisInstaller) {
  throw "No installer exe was produced."
}
Write-Host "Installer ready: $($nsisInstaller.FullName)"

# 3. Automatically run packaging script to generate release artifacts
Write-Host "Packaging release artifacts using version $appVersion and build number $buildNumber..."
$packagingScript = Join-Path $desktopRoot "windows\packaging\create_release_package.ps1"
if (Test-Path $packagingScript) {
    & $packagingScript `
      -BundleDir $bundleDir `
      -OutputDir (Join-Path $desktopRoot "build\windows\release_artifacts") `
      -AppName "iSmart Messenger" `
      -ExeName "iSmart Messenger.exe" `
      -Version $appVersion `
      -BuildNumber $buildNumber `
      -Channel "stable" `
      -PackageType "full" `
      -PackageLayout "bundle_zip" `
      -TargetArchitecture "ia32"
} else {
    Write-Warning "Packaging script not found at $packagingScript"
}
