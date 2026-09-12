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
  [string]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-Shortcut {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ShortcutPath,

    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory
  )

  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($ShortcutPath)
  $shortcut.TargetPath = $TargetPath
  $shortcut.WorkingDirectory = $WorkingDirectory
  $shortcut.IconLocation = $TargetPath
  $shortcut.Save()
}

function New-InstallScript {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter(Mandatory = $true)]
    [string]$DisplayName,

    [Parameter(Mandatory = $true)]
    [string]$ExecutableName
  )

  $processName = [System.IO.Path]::GetFileNameWithoutExtension($ExecutableName)
  $script = @"
param([switch]`$Quiet)

Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'

function New-Shortcut {
  param(
    [Parameter(Mandatory = `$true)]
    [string]`$ShortcutPath,
    [Parameter(Mandatory = `$true)]
    [string]`$TargetPath,
    [Parameter(Mandatory = `$true)]
    [string]`$WorkingDirectory
  )

  `$shell = New-Object -ComObject WScript.Shell
  `$shortcut = `$shell.CreateShortcut(`$ShortcutPath)
  `$shortcut.TargetPath = `$TargetPath
  `$shortcut.WorkingDirectory = `$WorkingDirectory
  `$shortcut.IconLocation = `$TargetPath
  `$shortcut.Save()
}

`$appName = '$DisplayName'
`$exeName = '$ExecutableName'
`$processName = '$processName'
`$sourceDir = Join-Path `$PSScriptRoot 'app'
`$installDir = Join-Path `$env:LOCALAPPDATA `$appName
`$startMenuDir = Join-Path `$env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
`$desktopPath = [Environment]::GetFolderPath('Desktop')
`$startMenuShortcut = Join-Path `$startMenuDir ("{0}.lnk" -f `$appName)
`$desktopShortcut = Join-Path `$desktopPath ("{0}.lnk" -f `$appName)
`$targetExe = Join-Path `$installDir `$exeName

if (-not (Test-Path -LiteralPath `$sourceDir)) {
  throw 'Missing packaged app payload.'
}

Get-Process -Name `$processName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 1200

New-Item -ItemType Directory -Force -Path `$installDir | Out-Null
New-Item -ItemType Directory -Force -Path `$startMenuDir | Out-Null

robocopy `$sourceDir `$installDir /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if (`$LASTEXITCODE -gt 7) {
  throw ("Copy failed with exit code {0}" -f `$LASTEXITCODE)
}

New-Shortcut -ShortcutPath `$startMenuShortcut -TargetPath `$targetExe -WorkingDirectory `$installDir
New-Shortcut -ShortcutPath `$desktopShortcut -TargetPath `$targetExe -WorkingDirectory `$installDir

Start-Process -FilePath `$targetExe | Out-Null
"@

  Set-Content -LiteralPath $FilePath -Value $script -Encoding Ascii
}

function Add-SedLines {
  param(
    [Parameter(Mandatory = $true)]
    [System.Text.StringBuilder]$Builder,

    [Parameter(Mandatory = $true)]
    [string[]]$Lines
  )

  foreach ($line in $Lines) {
    [void]$Builder.AppendLine($line)
  }
}

$resolvedBundleDir = (Resolve-Path -LiteralPath $BundleDir).Path
$resolvedOutputDir = $OutputDir
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$stageDir = Join-Path $resolvedOutputDir '_iexpress_stage'
$payloadDir = Join-Path $stageDir 'app'
$versionTag = ($Version -replace '[^0-9A-Za-z._-]', '_')
$installerPath = Join-Path $resolvedOutputDir ("iSmartMessenger_Installer_v{0}.exe" -f $versionTag)
$zipPath = Join-Path $resolvedOutputDir ("iSmartMessenger_UpdateBundle_v{0}.zip" -f $versionTag)
$installScriptPath = Join-Path $stageDir 'install.ps1'
$sedPath = Join-Path $stageDir 'package.sed'

if (Test-Path -LiteralPath $stageDir) {
  Remove-Item -LiteralPath $stageDir -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $payloadDir | Out-Null

Get-ChildItem -LiteralPath $resolvedBundleDir -Force | Where-Object {
  $_.Name -notlike 'iSmartMessenger_Installer_v*.exe' -and
  $_.Name -notlike 'iSmartMessenger_UpdateBundle_v*.zip' -and
  $_.Name -ne '_iexpress_stage'
} | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $payloadDir -Recurse -Force
}

New-InstallScript -FilePath $installScriptPath -DisplayName $AppName -ExecutableName $ExeName

if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $payloadDir '*') -DestinationPath $zipPath -CompressionLevel Optimal

$allFiles = Get-ChildItem -LiteralPath $stageDir -Recurse -File | Sort-Object FullName
$sourceGroups = @{}
$groupOrder = New-Object System.Collections.Generic.List[string]
$fileIndex = 0
$fileEntries = New-Object System.Collections.Generic.List[hashtable]

foreach ($file in $allFiles) {
  $relative = $file.FullName.Substring($stageDir.Length).TrimStart('\')
  $relativeDir = Split-Path -Path $relative -Parent
  if ([string]::IsNullOrWhiteSpace($relativeDir)) {
    $relativeDir = '.'
  }
  if (-not $sourceGroups.ContainsKey($relativeDir)) {
    $sourceGroups[$relativeDir] = $groupOrder.Count
    [void]$groupOrder.Add($relativeDir)
  }
  $groupIndex = $sourceGroups[$relativeDir]
  [void]$fileEntries.Add(@{
      Index = $fileIndex
      GroupIndex = $groupIndex
      Name = [System.IO.Path]::GetFileName($file.FullName)
    })
  $fileIndex += 1
}

$builder = New-Object System.Text.StringBuilder
Add-SedLines -Builder $builder -Lines @(
  '[Version]',
  'Class=IEXPRESS',
  'SEDVersion=3',
  '',
  '[Options]',
  'PackagePurpose=InstallApp',
  'ShowInstallProgramWindow=0',
  'HideExtractAnimation=0',
  'UseLongFileName=1',
  'InsideCompressed=1',
  'CAB_FixedSize=0',
  'CAB_ResvCodeSigning=0',
  'RebootMode=N',
  'InstallPrompt=%InstallPrompt%',
  'DisplayLicense=%DisplayLicense%',
  'FinishMessage=%FinishMessage%',
  'TargetName=%TargetName%',
  'FriendlyName=%FriendlyName%',
  'AppLaunched=%AppLaunched%',
  'PostInstallCmd=<None>',
  'AdminQuietInstCmd=',
  'UserQuietInstCmd=%UserQuietInstCmd%',
  'SourceFiles=SourceFiles',
  '',
  '[Strings]',
  'InstallPrompt=',
  'DisplayLicense=',
  ('FinishMessage={0} installed successfully.' -f $AppName),
  ('TargetName={0}' -f $installerPath),
  ('FriendlyName={0} Installer' -f $AppName),
  'AppLaunched=powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1',
  'UserQuietInstCmd=powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Quiet'
)

foreach ($entry in $fileEntries) {
  Add-SedLines -Builder $builder -Lines @(
    ('FILE{0}={1}' -f $entry.Index, ('"{0}"' -f $entry.Name))
  )
}

Add-SedLines -Builder $builder -Lines @(
  '',
  '[SourceFiles]'
)

for ($i = 0; $i -lt $groupOrder.Count; $i += 1) {
  $relativeDir = $groupOrder[$i]
  $fullDir = if ($relativeDir -eq '.') { $stageDir } else { Join-Path $stageDir $relativeDir }
  Add-SedLines -Builder $builder -Lines @(
    ('SourceFiles{0}={1}' -f $i, $fullDir)
  )
}

for ($i = 0; $i -lt $groupOrder.Count; $i += 1) {
  Add-SedLines -Builder $builder -Lines @(
    '',
    ('[SourceFiles{0}]' -f $i)
  )
  foreach ($entry in $fileEntries | Where-Object { $_.GroupIndex -eq $i }) {
    Add-SedLines -Builder $builder -Lines @(
      ('%FILE{0}%=' -f $entry.Index)
    )
  }
}

Set-Content -LiteralPath $sedPath -Value $builder.ToString() -Encoding Ascii

$iexpress = Get-Command iexpress.exe -ErrorAction Stop
& $iexpress.Source /N /Q $sedPath | Out-Null

if (-not (Test-Path -LiteralPath $installerPath)) {
  throw 'IExpress did not produce the installer artifact.'
}

