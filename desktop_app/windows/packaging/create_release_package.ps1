param(
  [Parameter(Mandatory = $true)]
  [string]$BundleDir,

  [Parameter(Mandatory = $true)]
  [string]$OutputDir,

  [Parameter(Mandatory = $true)]
  [string]$AppName,

  [Parameter(Mandatory = $true)]
  [string]$ExeName,

  [Parameter(Mandatory = $true)]
  [string]$Version,

  [string]$BuildNumber = "",
  [string]$Channel = "stable",
  [string]$PackageType = "full",
  [string]$PackageLayout = "bundle_zip",
  [string]$TargetArchitecture = "x64",
  [string]$MinSupportedVersion = "",
  [string]$MinWindowsBuild = "",
  [int]$RolloutPercentage = 100
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedBundleDir = (Resolve-Path -LiteralPath $BundleDir).Path
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$safeVersion = ($Version -replace '[^0-9A-Za-z._-]', '_')
$stageDir = Join-Path $OutputDir ("release_package_{0}" -f $safeVersion)
$appStageDir = Join-Path $stageDir 'app'
$manifestPath = Join-Path $stageDir 'manifest.json'
$packagePath = Join-Path $OutputDir ("{0}_{1}_{2}.zip" -f ($AppName -replace '\s+', ''), $PackageType, $safeVersion)
$metadataPath = Join-Path $OutputDir ("{0}_{1}_{2}_upload.json" -f ($AppName -replace '\s+', ''), $PackageType, $safeVersion)

if (Test-Path -LiteralPath $stageDir) {
  Remove-Item -LiteralPath $stageDir -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $appStageDir | Out-Null

Get-ChildItem -LiteralPath $resolvedBundleDir -Force | Where-Object {
  $_.Name -ne 'update-data' -and
  $_.Name -notlike '*.zip' -and
  $_.Name -notlike '*Installer*.exe'
} | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $appStageDir -Recurse -Force
}

if (-not (Test-Path -LiteralPath (Join-Path $appStageDir $ExeName))) {
  throw "Executable $ExeName was not found in the packaged app bundle."
}

$manifest = [ordered]@{
  schemaVersion = 1
  appName = $AppName
  version = $Version
  buildNumber = if ([string]::IsNullOrWhiteSpace($BuildNumber)) { $null } else { $BuildNumber }
  releaseNotes = ""
  required = $false
  minSupportedVersion = if ([string]::IsNullOrWhiteSpace($MinSupportedVersion)) { $null } else { $MinSupportedVersion }
  packageType = $PackageType
  packageLayout = $PackageLayout
  entryExecutable = $ExeName
  targetChannel = $Channel
  targetPlatform = "desktop_windows"
  targetArchitecture = $TargetArchitecture
  minWindowsBuild = if ([string]::IsNullOrWhiteSpace($MinWindowsBuild)) { $null } else { $MinWindowsBuild }
  rollout = @{
    percentage = $RolloutPercentage
  }
  createdAt = (Get-Date).ToString("o")
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

if (Test-Path -LiteralPath $packagePath) {
  Remove-Item -LiteralPath $packagePath -Force
}

Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $packagePath -CompressionLevel Optimal

$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$size = (Get-Item -LiteralPath $packagePath).Length

$uploadPayload = [ordered]@{
  version = $Version
  buildNumber = if ([string]::IsNullOrWhiteSpace($BuildNumber)) { $null } else { $BuildNumber }
  channel = $Channel
  platform = "desktop_windows"
  installerKind = "zip"
  packageType = $PackageType
  packageLayout = $PackageLayout
  entryExecutable = $ExeName
  minSupportedVersion = if ([string]::IsNullOrWhiteSpace($MinSupportedVersion)) { $null } else { $MinSupportedVersion }
  targetArchitecture = $TargetArchitecture
  minWindowsBuild = if ([string]::IsNullOrWhiteSpace($MinWindowsBuild)) { $null } else { $MinWindowsBuild }
  rolloutPercentage = $RolloutPercentage
  checksumSha256 = $hash
  packageSize = $size
  artifactFile = $packagePath
  manifestFile = $manifestPath
}

$uploadPayload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

Write-Host "Release package created:"
Write-Host "  Package : $packagePath"
Write-Host "  Manifest: $manifestPath"
Write-Host "  Metadata: $metadataPath"
Write-Host "  SHA256  : $hash"
Write-Host "  Size    : $size"
