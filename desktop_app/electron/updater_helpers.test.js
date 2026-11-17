const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const {
  validatePreparedPackage,
  buildApplyUpdatePsScript,
  resolvePowerShellExecutable,
} = require("./updater_helpers");

function detectFakeFileType(filePath) {
  const buf = fs.readFileSync(filePath);
  if (buf.length >= 2 && buf[0] === 0x4d && buf[1] === 0x5a) return "exe";
  if (buf.length >= 2 && buf[0] === 0x50 && buf[1] === 0x4b) return "zip";
  return "unknown";
}

async function sha256File(filePath) {
  const hash = crypto.createHash("sha256");
  hash.update(fs.readFileSync(filePath));
  return hash.digest("hex");
}

function makeTempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "ismart-updater-test-"));
}

test("validatePreparedPackage detects missing, tiny, non-PE, hash mismatch, and version mismatch", async () => {
  const dir = makeTempDir();
  try {
    const emptyRes = await validatePreparedPackage({
      tempDir: dir,
      detectFileType: detectFakeFileType,
      calculateFileSha256: sha256File,
    });
    assert.equal(emptyRes.prepared, false);
    assert.equal(emptyRes.reason, "missing");

    const exePath = path.join(dir, "update-installer.exe");
    fs.writeFileSync(exePath, Buffer.from("MZsmall"));
    const tinyRes = await validatePreparedPackage({
      tempDir: dir,
      detectFileType: detectFakeFileType,
      calculateFileSha256: sha256File,
    });
    assert.equal(tinyRes.prepared, false);
    assert.equal(tinyRes.reason, "size_mismatch");

    // 2048 bytes of HTML instead of PE header
    fs.writeFileSync(exePath, Buffer.alloc(2048, 0x3c));
    const htmlRes = await validatePreparedPackage({
      tempDir: dir,
      detectFileType: detectFakeFileType,
      calculateFileSha256: sha256File,
    });
    assert.equal(htmlRes.prepared, false);
    assert.equal(htmlRes.reason, "invalid_pe_header");

    // Valid MZ payload with SHA-256 metadata
    const validBuf = Buffer.concat([Buffer.from("MZ"), Buffer.alloc(2046, 0x41)]);
    fs.writeFileSync(exePath, validBuf);
    const validHash = crypto.createHash("sha256").update(validBuf).digest("hex");

    fs.writeFileSync(
      path.join(dir, "update-meta.json"),
      JSON.stringify({
        packagePath: exePath,
        packageType: "exe",
        fileName: "iSmart Messenger Setup 1.1.24.exe",
        expectedSize: validBuf.length,
        checksumSha256: validHash,
        version: "1.1.24",
      }),
      "utf8"
    );
    fs.writeFileSync(
      path.join(dir, "update-result.json"),
      JSON.stringify({
        status: "failed",
        exitCode: 2,
        reason: "Locked file",
        installerPreserved: true,
      }),
      "utf8"
    );

    const wrongHashRes = await validatePreparedPackage({
      tempDir: dir,
      checksumSha256: "f".repeat(64),
      detectFileType: detectFakeFileType,
      calculateFileSha256: sha256File,
    });
    assert.equal(wrongHashRes.prepared, false);
    assert.equal(wrongHashRes.reason, "checksum_mismatch");

    const wrongVersionRes = await validatePreparedPackage({
      tempDir: dir,
      version: "1.1.25",
      detectFileType: detectFakeFileType,
      calculateFileSha256: sha256File,
    });
    assert.equal(wrongVersionRes.prepared, false);
    assert.equal(wrongVersionRes.reason, "version_mismatch");

    const validRes = await validatePreparedPackage({
      tempDir: dir,
      checksumSha256: validHash.toUpperCase(),
      version: "1.1.24",
      detectFileType: detectFakeFileType,
      calculateFileSha256: sha256File,
      requireMatchForReuse: true,
    });
    assert.equal(validRes.prepared, true);
    assert.equal(validRes.packageType, "exe");
    assert.equal(validRes.checksumSha256, validHash);
    assert.equal(validRes.lastInstallResult.status, "failed");
    assert.equal(validRes.lastInstallResult.exitCode, 2);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("buildApplyUpdatePsScript orders launch candidates safely, preserves installer on failure, and passes PowerShell parser", () => {
  const dir = makeTempDir();
  try {
    const quotedUserDir = path.join(dir, "Ahmed 'O'Malley", "iSmart Messenger");
    fs.mkdirSync(quotedUserDir, { recursive: true });

    const commonArgs = {
      packagePath: path.join(quotedUserDir, "update-installer.exe"),
      appDir: "C:\\Users\\Ahmed 'O'Malley\\AppData\\Local\\Programs\\ismart-messenger-electron",
      exePath: "C:\\Users\\Ahmed 'O'Malley\\AppData\\Local\\Programs\\ismart-messenger-electron\\iSmart Messenger.exe",
      procName: "iSmart Messenger",
      parentPid: 999999,
      logPath: path.join(quotedUserDir, "update_log.txt"),
      metaPath: path.join(quotedUserDir, "update-meta.json"),
      resultPath: path.join(quotedUserDir, "update-result.json"),
      silentArgs: "/S",
      targetVersion: "1.1.24",
      previousVersion: "1.1.23",
      tempDir: quotedUserDir,
    };

    const exeScript = buildApplyUpdatePsScript({ ...commonArgs, packageType: "exe" });
    assert.ok(exeScript.startsWith("\uFEFF"), "Must include UTF-8 BOM for PowerShell");
    assert.ok(exeScript.includes("Ahmed ''O''Malley"), "Must escape single quotes cleanly");
    assert.ok(exeScript.includes("Get-WmiObject Win32_Process"), "Must include Win7 PS 2.0 fallback");
    assert.ok(exeScript.includes("Wait-FilesUnlocked"), "Must wait until files unlock");
    assert.ok(exeScript.includes('"clip_helper"'), "Must terminate clip_helper");
    const resolveFnSlice = exeScript.slice(
      exeScript.indexOf("function Resolve-LaunchExecutable"),
      exeScript.indexOf("function Launch-AppIfStopped")
    );
    const electronIdx = resolveFnSlice.indexOf("Programs\\ismart-messenger-electron");
    const currentExeIdx = resolveFnSlice.indexOf("$candidates.Add($exePath)");
    const legacyIdx = resolveFnSlice.indexOf("Programs\\iSmart Messenger");
    assert.ok(electronIdx >= 0 && currentExeIdx >= 0 && legacyIdx >= 0);
    assert.ok(
      electronIdx < legacyIdx && currentExeIdx < legacyIdx,
      "Current install dir and running exePath must take priority over legacy Programs\\iSmart Messenger"
    );

    // Ensure installer removal is gated behind $installSucceeded
    const ifSucceededIdx = exeScript.indexOf("if ($installSucceeded)");
    const removeInstallerIdx = exeScript.indexOf("Remove-Item -LiteralPath $installerPath");
    const elseIdx = exeScript.indexOf("} else {", ifSucceededIdx);
    assert.ok(ifSucceededIdx > 0);
    assert.ok(removeInstallerIdx > ifSucceededIdx && removeInstallerIdx < elseIdx);

    const msiScript = buildApplyUpdatePsScript({
      ...commonArgs,
      packageType: "msi",
      packagePath: path.join(quotedUserDir, "update-installer.msi"),
    });
    const zipScript = buildApplyUpdatePsScript({
      ...commonArgs,
      packageType: "zip",
      packagePath: path.join(quotedUserDir, "update-package.zip"),
    });

    const psExe = resolvePowerShellExecutable();
    for (const [label, scriptBody] of [
      ["exe", exeScript],
      ["msi", msiScript],
      ["zip", zipScript],
    ]) {
      const psFile = path.join(dir, `check_${label}.ps1`);
      fs.writeFileSync(psFile, scriptBody, "utf8");
      const out = execFileSync(
        psExe,
        [
          "-NoProfile",
          "-Command",
          `$errors = $null; $content = [System.IO.File]::ReadAllText('${psFile.replace(/'/g, "''")}'); [void][System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors); if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Error $_.Message }; exit 1 }; Write-Output 'OK'`,
        ],
        { encoding: "utf8" }
      );
      assert.equal(out.trim(), "OK");
    }

    // Extract helper definitions and invoke Write-UpdateResult to verify valid JSON generation
    const resultJsonOut = path.join(dir, "result_probe.json");
    const helpersOnly = exeScript.slice(0, exeScript.indexOf('Log-Msg "=== Starting'));
    const probeScript = `${helpersOnly}
$resultPath = '${resultJsonOut.replace(/'/g, "''")}'
$targetVersion = '1.1.24'
$previousVersion = '1.1.23'
Write-UpdateResult "failed" 2 "Locked file at C:\\app\\test" "1.1.23" $true
`;
    const probeFile = path.join(dir, "probe_json.ps1");
    fs.writeFileSync(probeFile, probeScript, "utf8");
    execFileSync(
      psExe,
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", probeFile],
      { encoding: "utf8" }
    );
    const parsedResult = JSON.parse(fs.readFileSync(resultJsonOut, "utf8"));
    assert.equal(parsedResult.status, "failed");
    assert.equal(parsedResult.exitCode, 2);
    assert.equal(parsedResult.targetVersion, "1.1.24");
    assert.equal(parsedResult.previousVersion, "1.1.23");
    assert.equal(parsedResult.installedVersionAfter, "1.1.23");
    assert.equal(parsedResult.reason, "Locked file at C:\\app\\test");
    assert.equal(parsedResult.installerPreserved, true);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("resolvePowerShellExecutable prefers System32 WindowsPowerShell when present", () => {
  const fakeEnv = { SystemRoot: "D:\\Windows" };
  const resolved = resolvePowerShellExecutable(
    fakeEnv,
    (p) => p === "D:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
  );
  assert.equal(resolved, "D:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe");

  const fallback = resolvePowerShellExecutable(fakeEnv, () => false);
  assert.equal(fallback, "powershell.exe");
});
