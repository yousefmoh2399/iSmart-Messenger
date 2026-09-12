param(
  [switch]$SkipNpmInstall
)

$ErrorActionPreference = "Stop"

$desktopRoot = Resolve-Path "$PSScriptRoot\.."
$electronRoot = Join-Path $desktopRoot "electron"

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

Write-Host "Starting Electron wrapper..."
npm start
