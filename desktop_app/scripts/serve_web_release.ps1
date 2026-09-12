param(
  [int]$Port = 15570,
  [string]$HostName = "0.0.0.0"
)

$ErrorActionPreference = "Stop"

Set-Location -LiteralPath (Resolve-Path "$PSScriptRoot\..")

flutter build web --no-tree-shake-icons --no-wasm-dry-run

$pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
if ($pythonLauncher) {
  $python = $pythonLauncher.Source
  $pythonArgs = @("-3", "-m", "http.server", $Port.ToString(), "--bind", $HostName)
} else {
  $pythonLauncher = Get-Command python -ErrorAction SilentlyContinue
  if (-not $pythonLauncher) {
    throw "Python is required to serve build\web. Install Python or serve build\web from IIS/Nginx/Node."
  }
  $python = $pythonLauncher.Source
  $pythonArgs = @("-m", "http.server", $Port.ToString(), "--bind", $HostName)
}

Write-Host "Serving release web app from build\web"
Write-Host "Local URL: http://localhost:$Port"
Write-Host "Branch URL: http://<this-device-ip>:$Port"
Write-Host "Keep this PowerShell window open."

Set-Location -LiteralPath (Resolve-Path ".\build\web")
& $python @pythonArgs
