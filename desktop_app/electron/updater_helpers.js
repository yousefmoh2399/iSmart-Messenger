const fs = require("fs");
const path = require("path");

function normalizeSha256(value) {
  return String(value || "").trim().toLowerCase();
}

function escapePsSingleQuoted(value) {
  return String(value == null ? "" : value).replace(/'/g, "''");
}

function toWinPath(filePath) {
  return path.win32.normalize(String(filePath || "")).replace(/\//g, "\\");
}

function resolvePowerShellExecutable(env = process.env, existsSyncFn = fs.existsSync) {
  const sysRoot = (env && (env.SystemRoot || env.SYSTEMROOT || env.WINDIR)) || "C:\\Windows";
  const explicit = path.win32.join(sysRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  try {
    if (existsSyncFn(explicit)) {
      return explicit;
    }
  } catch (_) {}
  return "powershell.exe";
}

function readJsonSafe(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    const raw = fs.readFileSync(filePath, "utf8");
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch (_) {
    return null;
  }
}

function readUpdateMeta(tempDir) {
  return readJsonSafe(path.join(tempDir, "update-meta.json"));
}

function readUpdateResult(tempDir) {
  return readJsonSafe(path.join(tempDir, "update-result.json"));
}

function clearUpdateResult(tempDir) {
  try {
    const resultPath = path.join(tempDir, "update-result.json");
    if (fs.existsSync(resultPath)) {
      fs.unlinkSync(resultPath);
    }
  } catch (_) {}
}

function locatePreparedPackageFile(tempDir, meta) {
  const candidates = [];
  if (meta && meta.packagePath) {
    candidates.push(String(meta.packagePath));
  }
  candidates.push(
    path.join(tempDir, "update-installer.exe"),
    path.join(tempDir, "update-installer.msi"),
    path.join(tempDir, "update-package.zip"),
    path.join(tempDir, "app-update.zip")
  );
  for (const candidate of candidates) {
    try {
      if (candidate && fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
        return candidate;
      }
    } catch (_) {}
  }
  return null;
}

async function validatePreparedPackage({
  tempDir,
  checksumSha256 = "",
  fileName = "",
  version = "",
  downloadUrl = "",
  detectFileType,
  calculateFileSha256,
  requireMatchForReuse = false,
}) {
  const meta = readUpdateMeta(tempDir);
  const lastInstallResult = readUpdateResult(tempDir);
  const packagePath = locatePreparedPackageFile(tempDir, meta);

  if (!packagePath) {
    return {
      prepared: false,
      reason: "missing",
      meta,
      lastInstallResult,
    };
  }

  let pkgStat;
  try {
    pkgStat = fs.statSync(packagePath);
  } catch (_) {
    return {
      prepared: false,
      reason: "stat_failed",
      packagePath,
      meta,
      lastInstallResult,
    };
  }

  if (
    pkgStat.size < 1024 ||
    (meta && Number(meta.expectedSize) > 0 && pkgStat.size !== Number(meta.expectedSize))
  ) {
    return {
      prepared: false,
      reason: "size_mismatch",
      packagePath,
      fileSize: pkgStat.size,
      expectedSize: meta ? Number(meta.expectedSize || 0) : 0,
      meta,
      lastInstallResult,
    };
  }

  const detectedType = detectFileType(packagePath);
  const lowerTarget = String(
    fileName || (meta && meta.fileName) || packagePath || ""
  ).toLowerCase();
  const expectsExe =
    lowerTarget.endsWith(".exe") ||
    (meta && String(meta.installerKind || "").toLowerCase() === "exe");

  if (expectsExe && detectedType !== "exe") {
    return {
      prepared: false,
      reason: "invalid_pe_header",
      packagePath,
      detectedType,
      meta,
      lastInstallResult,
    };
  }

  const requestedVersion = String(version || "").trim();
  const metaVersion = String(
    (meta && (meta.version || meta.targetVersion)) || ""
  ).trim();
  if (requestedVersion && metaVersion && requestedVersion !== metaVersion) {
    return {
      prepared: false,
      reason: "version_mismatch",
      packagePath,
      meta,
      lastInstallResult,
    };
  }

  const expectedHash = normalizeSha256(checksumSha256);
  const metaHash = normalizeSha256(meta && meta.checksumSha256);
  if (expectedHash && metaHash && expectedHash !== metaHash) {
    return {
      prepared: false,
      reason: "checksum_mismatch",
      packagePath,
      meta,
      lastInstallResult,
    };
  }

  const effectiveHash = expectedHash || metaHash;
  if (requireMatchForReuse && !effectiveHash) {
    const metaFileName = String((meta && meta.fileName) || "").trim().toLowerCase();
    const reqFileName = String(fileName || "").trim().toLowerCase();
    const fileNameMatches = !reqFileName || !metaFileName || reqFileName === metaFileName;
    const versionMatches =
      Boolean(requestedVersion) && Boolean(metaVersion) && requestedVersion === metaVersion;
    const urlMatches =
      !downloadUrl ||
      !meta ||
      !meta.downloadUrl ||
      String(meta.downloadUrl).trim() === String(downloadUrl).trim();
    const sizeMatches = Boolean(meta && Number(meta.expectedSize) > 0 && Number(meta.expectedSize) === pkgStat.size);
    if (!fileNameMatches || !versionMatches || !urlMatches || !sizeMatches) {
      return {
        prepared: false,
        reason: "unverified_reuse_mismatch",
        packagePath,
        meta,
        lastInstallResult,
      };
    }
  }

  if (effectiveHash) {
    const actualHash = normalizeSha256(await calculateFileSha256(packagePath));
    if (!actualHash || actualHash !== effectiveHash) {
      return {
        prepared: false,
        reason: "hash_verification_failed",
        packagePath,
        expectedHash: effectiveHash,
        actualHash,
        meta,
        lastInstallResult,
      };
    }
  }

  return {
    prepared: true,
    packagePath,
    packageType: detectedType,
    fileSize: pkgStat.size,
    checksumSha256: effectiveHash || null,
    version: metaVersion || null,
    fileName: (meta && meta.fileName) || path.basename(packagePath),
    silentInstallArgs: (meta && meta.silentInstallArgs) || "",
    meta,
    lastInstallResult,
  };
}

function buildCommonPowerShellHelpers() {
  return `
function Log-Msg($msg) {
    try {
        $logParent = [System.IO.Path]::GetDirectoryName($logPath)
        if ($logParent -and (-not (Test-Path -LiteralPath $logParent))) {
            New-Item -ItemType Directory -Path $logParent -Force | Out-Null
        }
        $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        "[$ts] $msg" | Out-File -FilePath $logPath -Append -Encoding UTF8
    } catch {}
}

function Escape-JsonStr($val) {
    if ($null -eq $val) { return "" }
    $s = [string]$val
    $s = $s.Replace("\\", "\\\\").Replace('"', '\\"').Replace("\`r", "\\r").Replace("\`n", "\\n").Replace("\`t", "\\t")
    return $s
}

function Write-UpdateResult($status, $exitCode, $reason, $installedVersionAfter, $installerPreserved) {
    try {
        $parentDir = [System.IO.Path]::GetDirectoryName($resultPath)
        if ($parentDir -and (-not (Test-Path -LiteralPath $parentDir))) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        $tsIso = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $preservedLiteral = if ($installerPreserved) { "true" } else { "false" }
        $exitCodeNum = if ($null -eq $exitCode) { -1 } else { [int]$exitCode }
        $json = "{\`"status\`":\`"$(Escape-JsonStr $status)\`",\`"exitCode\`":$exitCodeNum,\`"targetVersion\`":\`"$(Escape-JsonStr $targetVersion)\`",\`"previousVersion\`":\`"$(Escape-JsonStr $previousVersion)\`",\`"installedVersionAfter\`":\`"$(Escape-JsonStr $installedVersionAfter)\`",\`"reason\`":\`"$(Escape-JsonStr $reason)\`",\`"installerPreserved\`":$preservedLiteral,\`"timestamp\`":\`"$tsIso\`"}"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($resultPath, $json, $utf8NoBom)
    } catch {
        Log-Msg "Warning: failed to write result json: $($_.Exception.Message)"
    }
}

function Get-Win32Processes {
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
        }
        return @(Get-WmiObject Win32_Process -ErrorAction SilentlyContinue)
    } catch {
        return @()
    }
}

function Get-InstalledAppInfo {
    $regRoots = @(
        "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*",
        "HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*",
        "HKLM:\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*"
    )
    foreach ($root in $regRoots) {
        try {
            $entries = Get-ItemProperty -Path $root -ErrorAction SilentlyContinue
            foreach ($entry in $entries) {
                $dispName = [string]$entry.DisplayName
                $uninst = [string]$entry.UninstallString
                if (($dispName -like "iSmart Messenger*") -or ($uninst -like "*Uninstall iSmart Messenger.exe*") -or ($uninst -like "*ismart-messenger*")) {
                    $installDir = ""
                    $loc = [string]$entry.InstallLocation
                    if ($loc -and $loc.Trim()) {
                        $installDir = $loc.Trim().Trim('"').TrimEnd("\\")
                    } elseif ($uninst -and $uninst.Trim()) {
                        $cleaned = $uninst.Trim()
                        if ($cleaned.StartsWith('"')) {
                            $endQuote = $cleaned.IndexOf('"', 1)
                            if ($endQuote -gt 1) {
                                $cleaned = $cleaned.Substring(1, $endQuote - 1)
                            }
                        } else {
                            $exeIdx = $cleaned.ToLower().IndexOf(".exe")
                            if ($exeIdx -gt 0) {
                                $cleaned = $cleaned.Substring(0, $exeIdx + 4)
                            }
                        }
                        try {
                            $installDir = [System.IO.Path]::GetDirectoryName($cleaned)
                        } catch {}
                    }
                    return New-Object PSObject -Property @{
                        InstallDir = $installDir
                        Version = ([string]$entry.DisplayVersion).Trim()
                    }
                }
            }
        } catch {}
    }
    return New-Object PSObject -Property @{ InstallDir = ""; Version = "" }
}

function Stop-AppProcesses($extraDirs) {
    $localApp = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
    $dirList = New-Object System.Collections.Generic.List[string]
    foreach ($d in (@($appDir, (Join-Path $localApp "Programs\\ismart-messenger-electron"), (Join-Path $localApp "Programs\\iSmart Messenger")) + @($extraDirs))) {
        if ($d -and ([string]$d).Trim()) {
            $norm = ([string]$d).Trim().TrimEnd("\\").ToLower()
            if ($norm -and (-not $dirList.Contains($norm))) {
                $dirList.Add($norm)
            }
        }
    }

    $names = @($procName, "iSmart Messenger", "ismart-messenger", "ismart-messenger-electron", "clip_helper", "electron")
    foreach ($n in $names) {
        if ($n -and $n.Trim()) {
            try {
                Get-Process -Name $n -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID } | Stop-Process -Force -ErrorAction SilentlyContinue
            } catch {}
        }
    }

    $procs = Get-Win32Processes
    foreach ($p in $procs) {
        try {
            if ($null -eq $p -or ([int]$p.ProcessId -eq $PID)) { continue }
            $exe = [string]$p.ExecutablePath
            if (-not $exe) { continue }
            $exeLower = $exe.ToLower()
            foreach ($dirPrefix in $dirList) {
                if ($exeLower.StartsWith($dirPrefix + "\\")) {
                    Log-Msg "Stopping process inside install dir: PID=$($p.ProcessId) Path=$exe"
                    Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue
                    break
                }
            }
        } catch {}
    }
}

function Wait-ParentExit {
    if ($parentPid -le 0) { return }
    Log-Msg "Waiting for parent process $parentPid to exit..."
    $timeout = 40
    while ((Get-Process -Id $parentPid -ErrorAction SilentlyContinue) -and ($timeout -gt 0)) {
        Start-Sleep -Milliseconds 200
        $timeout--
    }
    if (Get-Process -Id $parentPid -ErrorAction SilentlyContinue) {
        Log-Msg "Terminating parent PID $parentPid forcefully..."
        Stop-Process -Id $parentPid -Force -ErrorAction SilentlyContinue
    }
}

function Wait-FilesUnlocked($dirs, $maxSeconds) {
    $filesToCheck = New-Object System.Collections.Generic.List[string]
    if ($exePath -and (-not $filesToCheck.Contains($exePath))) {
        $filesToCheck.Add($exePath)
    }
    foreach ($d in $dirs) {
        if (-not $d -or (-not ([string]$d).Trim())) { continue }
        foreach ($rel in @("$procName.exe", "iSmart Messenger.exe", "resources\\app.asar", "resources\\clip_helper.exe")) {
            $candidate = Join-Path ([string]$d) $rel
            if (-not $filesToCheck.Contains($candidate)) {
                $filesToCheck.Add($candidate)
            }
        }
    }

    $maxLoops = [Math]::Max(1, [int]($maxSeconds * 2))
    for ($attempt = 1; $attempt -le $maxLoops; $attempt++) {
        $lockedFile = $null
        foreach ($f in $filesToCheck) {
            if (-not (Test-Path -LiteralPath $f)) { continue }
            $fsHandle = $null
            try {
                $fsHandle = [System.IO.File]::Open($f, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            } catch [System.UnauthorizedAccessException] {
                # Non-writable location (e.g. Program Files without elevation) is not a runtime process lock
                $fsHandle = $null
            } catch [System.IO.IOException] {
                $lockedFile = $f
            } catch {
                $lockedFile = $f
            } finally {
                if ($null -ne $fsHandle) {
                    try { $fsHandle.Close() } catch {}
                }
            }
            if ($lockedFile) { break }
        }
        if (-not $lockedFile) {
            if ($attempt -gt 1) {
                Log-Msg "All application files verified unlocked after $attempt checks."
            }
            Start-Sleep -Milliseconds 800
            return $true
        }
        if (($attempt % 10) -eq 0) {
            Log-Msg "File still locked ($lockedFile); re-clearing app processes..."
            Stop-AppProcesses $dirs
        }
        Start-Sleep -Milliseconds 500
    }
    Log-Msg "Warning: timed out waiting for file lock release after $($maxSeconds)s."
    return $false
}

function Get-BinarySnapshot($dir) {
    $asarTicks = [long]0
    $exeTicks = [long]0
    if ($dir -and (Test-Path -LiteralPath $dir)) {
        try {
            $asar = Join-Path $dir "resources\\app.asar"
            if (Test-Path -LiteralPath $asar) {
                $asarTicks = [long](Get-Item -LiteralPath $asar).LastWriteTimeUtc.Ticks
            }
        } catch {}
        foreach ($exeName in @("$procName.exe", "iSmart Messenger.exe")) {
            try {
                $bin = Join-Path $dir $exeName
                if (Test-Path -LiteralPath $bin) {
                    $exeTicks = [long](Get-Item -LiteralPath $bin).LastWriteTimeUtc.Ticks
                    break
                }
            } catch {}
        }
    }
    return New-Object PSObject -Property @{ AsarTicks = $asarTicks; ExeTicks = $exeTicks }
}

function Resolve-LaunchExecutable($preferredRegDir) {
    $localApp = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
    $pf32 = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ProgramFilesX86)
    $pf64 = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ProgramFiles)

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($preferredRegDir -and ([string]$preferredRegDir).Trim()) {
        $candidates.Add((Join-Path ([string]$preferredRegDir) "$procName.exe"))
        $candidates.Add((Join-Path ([string]$preferredRegDir) "iSmart Messenger.exe"))
    }
    $candidates.Add((Join-Path $localApp "Programs\\ismart-messenger-electron\\$procName.exe"))
    $candidates.Add((Join-Path $localApp "Programs\\ismart-messenger-electron\\iSmart Messenger.exe"))
    if ($exePath) { $candidates.Add($exePath) }
    $candidates.Add((Join-Path $localApp "Programs\\iSmart Messenger\\$procName.exe"))
    $candidates.Add((Join-Path $localApp "iSmart Messenger\\$procName.exe"))
    $candidates.Add((Join-Path $pf32 "iSmart Messenger\\$procName.exe"))
    $candidates.Add((Join-Path $pf64 "iSmart Messenger\\$procName.exe"))
    $candidates.Add((Join-Path $pf32 "$procName\\$procName.exe"))
    $candidates.Add((Join-Path $pf64 "$procName\\$procName.exe"))

    foreach ($cand in $candidates) {
        if ($cand -and (Test-Path -LiteralPath $cand)) {
            return $cand
        }
    }
    return $null
}

function Launch-AppIfStopped($preferredRegDir) {
    Start-Sleep -Seconds 1
    $running = @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
    if ($running.Count -eq 0) {
        $running = @(Get-Process -Name "iSmart Messenger" -ErrorAction SilentlyContinue)
    }
    if ($running.Count -eq 0) {
        $launchTarget = Resolve-LaunchExecutable $preferredRegDir
        if ($launchTarget) {
            Log-Msg "Starting installed application cleanly: $launchTarget"
            $workDir = [System.IO.Path]::GetDirectoryName($launchTarget)
            Start-Process -FilePath $launchTarget -WorkingDirectory $workDir
        } else {
            Log-Msg "ERROR: Could not locate installed executable to launch."
        }
    } else {
        Log-Msg "Application process is already running (PID: $($running[0].Id))."
    }
}

function Cleanup-LegacyInstallArtifacts($activeInstallDir) {
    try {
        $publicDesktop = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonDesktopDirectory)
        if ($publicDesktop) {
            Remove-Item (Join-Path $publicDesktop "iSmart Messenger.lnk") -Force -ErrorAction SilentlyContinue
            Remove-Item (Join-Path $publicDesktop "$procName.lnk") -Force -ErrorAction SilentlyContinue
        }
        $pf32 = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ProgramFilesX86)
        $legacyPf32Dir = if ($pf32) { Join-Path $pf32 "iSmart Messenger" } else { "" }
        $activeNorm = if ($activeInstallDir) { $activeInstallDir.TrimEnd("\\").ToLower() } else { "" }
        if ($legacyPf32Dir -and (Test-Path -LiteralPath $legacyPf32Dir)) {
            if ($legacyPf32Dir.TrimEnd("\\").ToLower() -ne $activeNorm) {
                Remove-Item -LiteralPath $legacyPf32Dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}
}
`.trim();
}

function buildApplyUpdatePsScript({
  packageType,
  packagePath,
  appDir,
  exePath,
  procName,
  parentPid,
  logPath,
  metaPath,
  resultPath,
  silentArgs,
  targetVersion,
  previousVersion,
  tempDir,
}) {
  const header = `
$logPath = '${escapePsSingleQuoted(toWinPath(logPath))}'
$installerPath = '${escapePsSingleQuoted(toWinPath(packagePath))}'
$metaPath = '${escapePsSingleQuoted(toWinPath(metaPath))}'
$resultPath = '${escapePsSingleQuoted(toWinPath(resultPath))}'
$appDir = '${escapePsSingleQuoted(toWinPath(appDir))}'
$exePath = '${escapePsSingleQuoted(toWinPath(exePath))}'
$procName = '${escapePsSingleQuoted(procName)}'
$parentPid = ${Number(parentPid) || 0}
$silentArgs = '${escapePsSingleQuoted(String(silentArgs || "/S").trim() || "/S")}'
$targetVersion = '${escapePsSingleQuoted(String(targetVersion || "").trim())}'
$previousVersion = '${escapePsSingleQuoted(String(previousVersion || "").trim())}'
`.trim();

  const helpers = buildCommonPowerShellHelpers();

  if (packageType === "exe") {
    return `\uFEFF${header}

${helpers}

Log-Msg "=== Starting Electron / NSIS Self-Update (Target: '$targetVersion', Previous: '$previousVersion') ==="
Log-Msg "Installer: $installerPath | AppDir: $appDir | Exe: $exePath"

Wait-ParentExit
$preInfo = Get-InstalledAppInfo
$preDir = if ($preInfo.InstallDir) { $preInfo.InstallDir } else { $appDir }
$preSnap = Get-BinarySnapshot $preDir
Log-Msg "Pre-install snapshot: RegistryVersion='$($preInfo.Version)' Dir='$preDir' AsarTicks=$($preSnap.AsarTicks) ExeTicks=$($preSnap.ExeTicks)"

$installSucceeded = $false
$lastExitCode = -1
$failureReason = "Unknown installer failure"
$postInfo = $preInfo

for ($attempt = 1; $attempt -le 2; $attempt++) {
    Log-Msg "Attempt $attempt/2: stopping processes and waiting for file lock release..."
    Stop-AppProcesses @($preDir, $postInfo.InstallDir)
    Wait-FilesUnlocked @($appDir, $preDir, $postInfo.InstallDir) 15 | Out-Null

    try {
        Log-Msg "Launching installer in silent per-user mode (args: '$silentArgs')..."
        $inst = Start-Process -FilePath $installerPath -ArgumentList $silentArgs -PassThru -Wait
        $lastExitCode = if ($null -eq $inst) { -1 } else { [int]$inst.ExitCode }
        Log-Msg "Silent installer process finished with exit code: $lastExitCode"
    } catch {
        $lastExitCode = -2
        $failureReason = "Failed to execute installer process: $($_.Exception.Message)"
        Log-Msg "CRITICAL ERROR: $failureReason"
        Start-Sleep -Seconds 2
        continue
    }

    Start-Sleep -Milliseconds 500
    $postInfo = Get-InstalledAppInfo
    $postDir = if ($postInfo.InstallDir) { $postInfo.InstallDir } else { $appDir }
    $postSnap = Get-BinarySnapshot $postDir
    Log-Msg "Post-install snapshot: RegistryVersion='$($postInfo.Version)' Dir='$postDir' AsarTicks=$($postSnap.AsarTicks) ExeTicks=$($postSnap.ExeTicks)"

    if ($lastExitCode -ne 0) {
        $failureReason = "Installer exited with non-zero code $lastExitCode (file locked or interrupted)"
        Log-Msg "WARNING: $failureReason"
        Start-Sleep -Seconds 2
        continue
    }

    $expectedUpdateVersion = if ($targetVersion) { $targetVersion } else { "" }
    $knownOldVersion = if ($preInfo.Version) { $preInfo.Version } else { $previousVersion }
    $expectingVersionBump = $expectedUpdateVersion -and $knownOldVersion -and ($expectedUpdateVersion -ne $knownOldVersion)
    $versionStuckAtOld = $expectingVersionBump -and $postInfo.Version -and ($postInfo.Version -eq $knownOldVersion)
    $filesCompletelyUnchanged = $expectingVersionBump -and (-not $postInfo.Version) -and ($preSnap.AsarTicks -gt 0) -and ($postSnap.AsarTicks -eq $preSnap.AsarTicks) -and ($postSnap.ExeTicks -eq $preSnap.ExeTicks)

    if ($versionStuckAtOld -or $filesCompletelyUnchanged) {
        $failureReason = "Silent installer returned exit code 0 but installed binary/version remained '$($postInfo.Version)' instead of '$expectedUpdateVersion'"
        Log-Msg "WARNING: $failureReason"
        Start-Sleep -Seconds 2
        continue
    }

    $installSucceeded = $true
    break
}

if ($installSucceeded) {
    Log-Msg "Update installation verified successfully (Installed version: '$($postInfo.Version)'). Cleaning up temporary installer..."
    Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $metaPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    Cleanup-LegacyInstallArtifacts $postInfo.InstallDir
} else {
    Log-Msg "ERROR: Update failed after retry ($failureReason). Preserving verified installer at '$installerPath' to avoid re-download."
    Write-UpdateResult "failed" $lastExitCode $failureReason $postInfo.Version $true
}

Launch-AppIfStopped $postInfo.InstallDir
Log-Msg "=== Installer update completed ==="
Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
`;
  }

  if (packageType === "msi") {
    return `\uFEFF${header}

${helpers}

Log-Msg "=== Starting MSI Package Update ==="
Wait-ParentExit
$preInfo = Get-InstalledAppInfo
Stop-AppProcesses @($preInfo.InstallDir)
Wait-FilesUnlocked @($appDir, $preInfo.InstallDir) 15 | Out-Null

$installSucceeded = $false
$lastExitCode = -1
$failureReason = "Unknown MSI error"
$postInfo = $preInfo

try {
    $msiArgs = "/i \`"$installerPath\`" /qn /norestart"
    $inst = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -PassThru -Wait
    $lastExitCode = if ($null -eq $inst) { -1 } else { [int]$inst.ExitCode }
    Log-Msg "msiexec finished with exit code: $lastExitCode"
    $installSucceeded = ($lastExitCode -eq 0 -or $lastExitCode -eq 3010)
    if (-not $installSucceeded) {
        $failureReason = "msiexec exited with code $lastExitCode"
    }
} catch {
    $lastExitCode = -2
    $failureReason = $_.Exception.Message
    Log-Msg "MSI install error: $failureReason"
}

Start-Sleep -Milliseconds 500
$postInfo = Get-InstalledAppInfo
if ($installSucceeded) {
    Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $metaPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
} else {
    Write-UpdateResult "failed" $lastExitCode $failureReason $postInfo.Version $true
}

Launch-AppIfStopped $postInfo.InstallDir
Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
`;
  }

  const extractedPath = toWinPath(path.join(tempDir || path.dirname(packagePath), "extracted"));
  return `\uFEFF${header}
$extractedPath = '${escapePsSingleQuoted(extractedPath)}'

${helpers}

Log-Msg "=== Starting Zip Update Process ==="
Wait-ParentExit
$preInfo = Get-InstalledAppInfo
$preDir = if ($preInfo.InstallDir) { $preInfo.InstallDir } else { $appDir }
Stop-AppProcesses @($preDir, $preInfo.InstallDir)
Wait-FilesUnlocked @($appDir, $preDir, $preInfo.InstallDir) 15 | Out-Null

if (Test-Path -LiteralPath $extractedPath) {
    Remove-Item -LiteralPath $extractedPath -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $extractedPath -Force | Out-Null

$installSucceeded = $false
$failureReason = ""

try {
    Log-Msg "Extracting zip package cleanly..."
    $extractedOk = $false
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($installerPath, $extractedPath)
        $extractedOk = $true
    } catch {
        Log-Msg "ZipFile extraction failed ($($_.Exception.Message)); trying Expand-Archive..."
    }
    if (-not $extractedOk) {
        Expand-Archive -LiteralPath $installerPath -DestinationPath $extractedPath -Force
    }
    Log-Msg "Zip extraction complete."

    $sourceRoot = $extractedPath
    $subItems = Get-ChildItem -LiteralPath $extractedPath -Force
    if ($subItems.Count -eq 1 -and $subItems[0].PSIsContainer) {
        $sourceRoot = $subItems[0].FullName
    }

    Log-Msg "Mirroring extracted files from $sourceRoot into $appDir..."
    Get-ChildItem -LiteralPath $sourceRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $appDir -Recurse -Force
    }
    $installSucceeded = $true
} catch {
    $failureReason = "Error during Zip extraction/copy: $($_.Exception.Message)"
    Log-Msg $failureReason
}

if ($installSucceeded) {
    Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $metaPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
} else {
    Write-UpdateResult "failed" -1 $failureReason $preInfo.Version $true
}

Remove-Item -LiteralPath $extractedPath -Recurse -Force -ErrorAction SilentlyContinue
Launch-AppIfStopped $appDir
Log-Msg "=== Update process completed ==="
Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
`;
}

module.exports = {
  normalizeSha256,
  escapePsSingleQuoted,
  toWinPath,
  resolvePowerShellExecutable,
  readUpdateMeta,
  readUpdateResult,
  clearUpdateResult,
  locatePreparedPackageFile,
  validatePreparedPackage,
  buildApplyUpdatePsScript,
};
