$ErrorActionPreference = "Stop"

Set-Location -LiteralPath (Resolve-Path "$PSScriptRoot\..")

flutter build web --no-tree-shake-icons

$buildWebPath = Resolve-Path ".\build\web"
$bootstrapPath = Join-Path $buildWebPath "flutter_bootstrap.js"
$indexPath = Join-Path $buildWebPath "index.html"

if (Test-Path $bootstrapPath) {
    $bootstrapText = Get-Content $bootstrapPath -Raw
    $bootstrapText = $bootstrapText -replace '(?s)(_flutter\.loader\.load\(\{\s*serviceWorkerSettings:\s*\{\s*serviceWorkerVersion:\s*"[^"]*"(?:\s*/\*.*?\*/)?\s*\}\s*)(\}\s*\);)', '$1,config:{useLocalCanvasKit:true,canvasKitBaseUrl:"canvaskit"}$2'
    Set-Content $bootstrapPath $bootstrapText
}

if (Test-Path $indexPath) {
    (Get-Content $indexPath) -replace '<base href="/">', '<base href="./">' | Set-Content $indexPath
}

Write-Host "Built web release at:"
Write-Host $buildWebPath
