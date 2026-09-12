param(
  [int]$Port = 15570,
  [string]$HostName = "0.0.0.0",
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

Set-Location -LiteralPath (Resolve-Path "$PSScriptRoot\..")

if (-not $SkipBuild) {
  Write-Host "Building Flutter web release..."
  flutter build web --no-web-resources-cdn --no-tree-shake-icons --no-wasm-dry-run
}

$env:WEB_PORT = "$Port"
$env:WEB_HOST = "$HostName"

Write-Host "Starting static web server. Keep this PowerShell window open."
node "$PSScriptRoot\serve_web_build.js" $Port
