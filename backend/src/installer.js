/**
 * iSmart Backend — Self-contained Installer / Backup / Restore / Doctor
 *
 * Modes (triggered from server.js):
 *   --install    Interactive setup wizard (fresh install OR restore from backup)
 *   --uninstall  Remove the installed service
 *   --backup     Manual backup (can be run from terminal anytime)
 *   --doctor     Health check on all services
 */

"use strict";

const readline  = require("readline");
const fs        = require("fs");
const fsp       = require("fs/promises");
const path      = require("path");
const os        = require("os");
const net       = require("net");
const { execSync, spawnSync, spawn } = require("child_process");

// ─── Platform & paths ─────────────────────────────────────────────────────────
const IS_WIN   = process.platform === "win32";
const IS_LINUX = process.platform === "linux";
const EXE_PATH = process.execPath;
const EXE_DIR  = path.dirname(EXE_PATH);

// ─── Colors (disabled on Windows cmd) ────────────────────────────────────────
const C = {
  red:    IS_WIN ? "" : "\x1b[31m",
  green:  IS_WIN ? "" : "\x1b[32m",
  yellow: IS_WIN ? "" : "\x1b[33m",
  cyan:   IS_WIN ? "" : "\x1b[36m",
  bold:   IS_WIN ? "" : "\x1b[1m",
  dim:    IS_WIN ? "" : "\x1b[2m",
  reset:  IS_WIN ? "" : "\x1b[0m",
};

// ─── Logging ──────────────────────────────────────────────────────────────────
const log   = (msg = "")   => process.stdout.write(msg + "\n");
const ok    = (msg)        => log(`  ${C.green}✓${C.reset}  ${msg}`);
const warn  = (msg)        => log(`  ${C.yellow}⚠${C.reset}  ${msg}`);
const fail  = (msg)        => log(`  ${C.red}✗${C.reset}  ${msg}`);
const info  = (msg)        => log(`  ${C.cyan}ℹ${C.reset}  ${msg}`);
const step  = (n, t, msg)  => log(`\n${C.bold}[ ${n}/${t} ] ${msg}${C.reset}`);
const hr    = ()           => log("─".repeat(60));
const title = (msg)        => {
  log("");
  log(`${C.cyan}${"═".repeat(60)}${C.reset}`);
  log(`${C.cyan}  ${msg}${C.reset}`);
  log(`${C.cyan}${"═".repeat(60)}${C.reset}`);
  log("");
};

// ─── Prompts ──────────────────────────────────────────────────────────────────
let _rl = null;
function getRl() {
  if (!_rl) {
    _rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
      terminal: false,
    });
  }
  return _rl;
}
function closeRl() {
  if (_rl) { try { _rl.close(); } catch (_) {} _rl = null; }
}

function prompt(question, defaultValue = "") {
  return new Promise((resolve) => {
    const display = defaultValue
      ? `  ${question} [${C.dim}${defaultValue}${C.reset}]: `
      : `  ${question}: `;
    process.stdout.write(display);
    const rl = readline.createInterface({ input: process.stdin, output: null, terminal: false });
    let answered = false;
    rl.once("line", (ans) => {
      answered = true;
      rl.close();
      const trimmed = ans.trim();
      resolve(trimmed || defaultValue);
    });
    rl.once("close", () => { if (!answered) resolve(defaultValue); });
  });
}

function promptSecret(question) {
  return new Promise((resolve) => {
    process.stdout.write(`  ${question}: `);
    if (process.stdin.isTTY) {
      let password = "";
      process.stdin.setRawMode(true);
      process.stdin.resume();
      process.stdin.setEncoding("utf8");
      const onData = (char) => {
        if (char === "\r" || char === "\n") {
          process.stdin.setRawMode(false);
          process.stdin.pause();
          process.stdin.removeListener("data", onData);
          process.stdout.write("\n");
          resolve(password);
        } else if (char === "\u0003") {
          process.exit(1);
        } else if (char === "\u007f") {
          if (password.length > 0) {
            password = password.slice(0, -1);
            process.stdout.clearLine(0);
            process.stdout.cursorTo(0);
            process.stdout.write(`  ${question}: ${"*".repeat(password.length)}`);
          }
        } else {
          password += char;
          process.stdout.write("*");
        }
      };
      process.stdin.on("data", onData);
    } else {
      const rl = readline.createInterface({ input: process.stdin, output: null, terminal: false });
      rl.once("line", (ans) => { rl.close(); resolve(ans.trim()); });
    }
  });
}

function promptChoice(question, choices) {
  // choices: ["Fresh install", "Restore from backup"]
  return new Promise(async (resolve) => {
    log(`\n  ${C.bold}${question}${C.reset}`);
    choices.forEach((c, i) => log(`    ${C.cyan}${i + 1})${C.reset} ${c}`));
    log("");
    while (true) {
      const ans = await prompt(`Choose (1-${choices.length})`);
      const idx = parseInt(ans, 10) - 1;
      if (idx >= 0 && idx < choices.length) {
        resolve({ index: idx, value: choices[idx] });
        break;
      }
      warn(`Invalid choice. Enter a number between 1 and ${choices.length}.`);
    }
  });
}

// ─── Path validation ──────────────────────────────────────────────────────────
async function validateAndPrepareDir(dirPath, label) {
  const resolved = path.resolve(dirPath);
  log("");
  info(`Checking ${label}: ${resolved}`);

  // Try to create if not exists
  try {
    fs.mkdirSync(resolved, { recursive: true });
  } catch (e) {
    fail(`Cannot create directory: ${e.message}`);
    return { ok: false, resolved };
  }

  // Check write permission
  const testFile = path.join(resolved, ".ismart_write_test");
  try {
    fs.writeFileSync(testFile, "test");
    fs.unlinkSync(testFile);
    ok(`${label} is valid and writable: ${resolved}`);
    return { ok: true, resolved };
  } catch (e) {
    fail(`Directory is not writable: ${e.message}`);
    return { ok: false, resolved };
  }
}

async function promptValidatedDir(question, defaultValue, label) {
  while (true) {
    const input = await prompt(question, defaultValue);
    const result = await validateAndPrepareDir(input, label);
    if (result.ok) return result.resolved;
    warn("Please enter a valid, writable directory path.");
  }
}

// ─── Process utilities ────────────────────────────────────────────────────────
function run(cmd, opts = {}) {
  try {
    const r = spawnSync(cmd, { shell: true, encoding: "utf8", stdio: "pipe", ...opts });
    return { ok: r.status === 0, stdout: r.stdout || "", stderr: r.stderr || "", status: r.status };
  } catch (_) {
    return { ok: false, stdout: "", stderr: "", status: -1 };
  }
}

function runVisible(cmd) {
  try { execSync(cmd, { stdio: "inherit", shell: true }); return true; }
  catch (_) { return false; }
}

function runAsync(cmd, opts = {}) {
  return new Promise((resolve) => {
    const child = spawn(cmd, { shell: true, stdio: "inherit", ...opts });
    child.on("close", (code) => resolve(code === 0));
  });
}

function isPortOpen(host, port) {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    socket.setTimeout(2000);
    socket.once("connect", () => { socket.destroy(); resolve(true); });
    socket.once("timeout", () => { socket.destroy(); resolve(false); });
    socket.once("error", () => { socket.destroy(); resolve(false); });
    socket.connect(port, host);
  });
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function generateSecret(len = 64) {
  const crypto = require("crypto");
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = crypto.randomBytes(len);
  return Array.from(bytes, b => chars[b % chars.length]).join("");
}

function downloadFile(url, dest) {
  return new Promise((resolve) => {
    const proto = url.startsWith("https") ? require("https") : require("http");
    const file = fs.createWriteStream(dest);
    const req = proto.get(url, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302) {
        file.close();
        try { fs.unlinkSync(dest); } catch (_) {}
        resolve(downloadFile(res.headers.location, dest));
        return;
      }
      res.pipe(file);
      file.on("finish", () => { file.close(); resolve(true); });
    });
    req.on("error", () => { file.close(); resolve(false); });
    req.setTimeout(180_000, () => { req.destroy(); resolve(false); });
  });
}

// ─── MongoDB utilities ────────────────────────────────────────────────────────
async function isMongoRunning(uri = "mongodb://127.0.0.1:27017") {
  try {
    const match = uri.match(/:\/\/([^:/]+):?(\d+)?/);
    return await isPortOpen((match && match[1]) || "127.0.0.1",
                            parseInt((match && match[2]) || "27017", 10));
  } catch (_) { return false; }
}

function findMongodump() {
  // Try PATH first
  const fromPath = run("mongodump --version");
  if (fromPath.ok) return "mongodump";

  if (IS_WIN) {
    // Common Windows MongoDB paths
    const commonPaths = [
      "C:\\Program Files\\MongoDB\\Tools\\100\\bin\\mongodump.exe",
      "C:\\Program Files\\MongoDB\\Server\\7.0\\bin\\mongodump.exe",
      "C:\\Program Files\\MongoDB\\Server\\6.0\\bin\\mongodump.exe",
    ];
    for (const p of commonPaths) {
      if (fs.existsSync(p)) return `"${p}"`;
    }
  }
  return null;
}

function findMongorestore() {
  const fromPath = run("mongorestore --version");
  if (fromPath.ok) return "mongorestore";

  if (IS_WIN) {
    const commonPaths = [
      "C:\\Program Files\\MongoDB\\Tools\\100\\bin\\mongorestore.exe",
      "C:\\Program Files\\MongoDB\\Server\\7.0\\bin\\mongorestore.exe",
    ];
    for (const p of commonPaths) {
      if (fs.existsSync(p)) return `"${p}"`;
    }
  }
  return null;
}

async function installMongoWindows() {
  log(`\n  ${C.cyan}Installing MongoDB via winget...${C.reset}`);
  if (run("winget --version").ok) {
    const success = runVisible(
      "winget install --id MongoDB.Server -e --silent --accept-package-agreements --accept-source-agreements"
    );
    if (success) {
      runVisible("net start MongoDB");
      await sleep(4000);
      ok("MongoDB installed and started via winget.");
      return true;
    }
  }
  warn("winget not available. Downloading MongoDB installer...");
  const mongoUrl = "https://fastdl.mongodb.org/windows/mongodb-windows-x86_64-7.0.14-signed.msi";
  const msiPath  = path.join(os.tmpdir(), "mongodb-installer.msi");
  info(`Downloading MongoDB installer (~500 MB)...`);
  const downloaded = await downloadFile(mongoUrl, msiPath);
  if (!downloaded) { fail("Download failed."); return false; }
  runVisible(`msiexec /i "${msiPath}" /quiet /norestart ADDLOCAL="ServerNoService" SHOULD_INSTALL_COMPASS="0"`);
  // Also install MongoDB Database Tools for mongodump/mongorestore
  if (run("winget --version").ok) {
    runVisible("winget install --id MongoDB.DatabaseTools -e --silent --accept-package-agreements --accept-source-agreements");
  }
  const mongoDataDir = "C:\\ProgramData\\MongoDB\\data";
  const mongoLogDir  = "C:\\ProgramData\\MongoDB\\log";
  fs.mkdirSync(mongoDataDir, { recursive: true });
  fs.mkdirSync(mongoLogDir,  { recursive: true });
  runVisible("net start MongoDB");
  await sleep(4000);
  ok("MongoDB installed and started.");
  return true;
}

async function installMongoLinux() {
  log(`\n  ${C.cyan}Installing MongoDB via apt...${C.reset}`);
  const lsb = run("lsb_release -sc");
  const codename = lsb.ok ? lsb.stdout.trim() : "focal";
  info(`Ubuntu codename: ${codename}`);
  const steps = [
    "apt-get install -y gnupg curl",
    `curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg`,
    `echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${codename}/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list`,
    "apt-get update -qq",
    "apt-get install -y mongodb-org mongodb-database-tools",
    "systemctl enable mongod",
    "systemctl start mongod",
  ];
  for (const cmd of steps) {
    info(`→ ${cmd}`);
    runVisible(cmd);
  }
  await sleep(4000);
  return true;
}

// ─── Backup engine ────────────────────────────────────────────────────────────
async function createBackup(config, backupDir) {
  const archiver = require("archiver");

  const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const archiveName = `ismart-backup-${timestamp}.zip`;
  const archivePath = path.join(backupDir, archiveName);

  log("");
  title("Creating Full Backup");
  info(`Archive: ${archivePath}`);

  // Step 1: MongoDB dump to temp dir
  const tmpDir     = path.join(os.tmpdir(), `ismart-backup-${Date.now()}`);
  const dbDumpDir  = path.join(tmpDir, "db");
  fs.mkdirSync(dbDumpDir, { recursive: true });

  const mongodump = findMongodump();
  let dbDumpOk = false;

  if (mongodump) {
    info("Dumping MongoDB database...");
    const mongoUri = config.MONGODB_URI || "mongodb://127.0.0.1:27017/workplace_documents";
    const dumpOk = runVisible(`${mongodump} --uri="${mongoUri}" --out="${dbDumpDir}" --quiet`);
    if (dumpOk) {
      ok("Database dump complete.");
      dbDumpOk = true;
    } else {
      warn("Database dump failed — archive will not include DB.");
    }
  } else {
    warn("mongodump not found — archive will not include DB.");
    warn("Install MongoDB Database Tools to enable DB backup.");
  }

  // Step 2: Create ZIP archive
  info("Archiving files...");
  const output = fs.createWriteStream(archivePath);
  const archive = archiver("zip", { zlib: { level: 6 } });

  await new Promise((resolve, reject) => {
    output.on("close", resolve);
    archive.on("error", reject);
    archive.pipe(output);

    // Add DB dump
    if (dbDumpOk) {
      archive.directory(dbDumpDir, "db");
    }

    // Add uploads (chat files, documents, avatars)
    const uploadsDir = config.UPLOADS_DIR || path.join(config.DATA_DIR, "uploads");
    if (fs.existsSync(uploadsDir)) {
      info("Adding uploads directory...");
      archive.directory(uploadsDir, "uploads");
    }

    // Write manifest
    const manifest = {
      version:   "1.0",
      timestamp: new Date().toISOString(),
      platform:  process.platform,
      config:    { ...config, JWT_SECRET: "[redacted]" },
      includes:  { database: dbDumpOk, uploads: fs.existsSync(uploadsDir) },
    };
    archive.append(JSON.stringify(manifest, null, 2), { name: "backup-manifest.json" });

    archive.finalize();
  });

  // Cleanup temp
  try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (_) {}

  const sizeMb = (fs.statSync(archivePath).size / 1024 / 1024).toFixed(1);
  log("");
  ok(`Backup created: ${archivePath}  (${sizeMb} MB)`);

  // Make readable on network shares (Windows: ensure no permission issues)
  if (IS_WIN) {
    run(`icacls "${archivePath}" /grant Everyone:R /Q`);
  }

  return archivePath;
}

// ─── Restore engine ───────────────────────────────────────────────────────────
async function restoreFromBackup(archivePath, targetConfig) {
  const unzipper = require("unzipper");

  title("Restoring from Backup");
  info(`Archive: ${archivePath}`);

  // Validate archive
  if (!fs.existsSync(archivePath)) {
    fail(`Backup file not found: ${archivePath}`);
    return false;
  }

  // Extract to temp
  const tmpDir = path.join(os.tmpdir(), `ismart-restore-${Date.now()}`);
  fs.mkdirSync(tmpDir, { recursive: true });

  info("Extracting backup archive...");
  await fs.createReadStream(archivePath)
    .pipe(unzipper.Extract({ path: tmpDir }))
    .promise();

  // Read manifest
  const manifestPath = path.join(tmpDir, "backup-manifest.json");
  if (!fs.existsSync(manifestPath)) {
    fail("Invalid backup archive — manifest not found.");
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (_) {}
    return false;
  }

  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  info(`Backup date: ${manifest.timestamp}`);
  info(`Original platform: ${manifest.platform}`);
  info(`Includes DB: ${manifest.includes.database ? "Yes" : "No"}`);
  info(`Includes uploads: ${manifest.includes.uploads ? "Yes" : "No"}`);

  // Restore MongoDB
  if (manifest.includes.database) {
    const mongorestore = findMongorestore();
    if (mongorestore) {
      info("Restoring MongoDB database...");
      const dbDumpDir = path.join(tmpDir, "db");
      const mongoUri  = targetConfig.MONGODB_URI || "mongodb://127.0.0.1:27017/workplace_documents";
      const restored  = runVisible(
        `${mongorestore} --uri="${mongoUri}" --dir="${dbDumpDir}" --drop --quiet`
      );
      if (restored) { ok("Database restored."); }
      else { warn("Database restore failed. Check MongoDB logs."); }
    } else {
      warn("mongorestore not found — DB restore skipped.");
    }
  }

  // Restore uploads
  if (manifest.includes.uploads) {
    const srcUploads = path.join(tmpDir, "uploads");
    const dstUploads = targetConfig.UPLOADS_DIR || path.join(targetConfig.DATA_DIR, "uploads");
    if (fs.existsSync(srcUploads)) {
      info(`Restoring uploads to: ${dstUploads}`);
      fs.mkdirSync(dstUploads, { recursive: true });
      copyDirSync(srcUploads, dstUploads);
      ok("Uploads restored.");
    }
  }

  try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (_) {}
  ok("Restore complete.");
  return true;
}

function copyDirSync(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath  = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDirSync(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

// ─── Backup scheduler ─────────────────────────────────────────────────────────
function scheduleBackupWindows(backupHour, backupDir) {
  const timeStr = `${String(backupHour).padStart(2, "0")}:00`;
  const taskName = "iSmartBackup";
  const cmd = `"${EXE_PATH}" --backup`;

  // Remove old task
  run(`schtasks /delete /tn "${taskName}" /f`);

  const result = run(
    `schtasks /create /tn "${taskName}" /tr "${cmd}" /sc daily /st ${timeStr} /ru SYSTEM /rl HIGHEST /f`
  );

  if (result.ok) {
    ok(`Backup scheduled daily at ${timeStr} (Windows Task Scheduler: ${taskName})`);
  } else {
    warn(`Could not schedule backup: ${result.stderr}`);
  }

  // Write the backup dir into a config override so --backup knows where to save
  return result.ok;
}

function scheduleBackupLinux(backupHour, backupDir) {
  const cronFile = "/etc/cron.d/ismart-backup";
  const logFile  = "/var/lib/ismart/logs/backup.log";
  const content  = [
    `# iSmart Backend — daily backup at ${backupHour}:00`,
    `0 ${backupHour} * * * root ${EXE_PATH} --backup >> ${logFile} 2>&1`,
    "",
  ].join("\n");

  try {
    fs.writeFileSync(cronFile, content, { mode: 0o644 });
    runVisible(`chmod 644 ${cronFile}`);
    ok(`Backup scheduled daily at ${backupHour}:00 (cron: ${cronFile})`);
    return true;
  } catch (e) {
    warn(`Could not write cron file: ${e.message}`);
    return false;
  }
}

// ─── Service installation ─────────────────────────────────────────────────────
function installWindowsService(configPath) {
  const serviceName = "iSmartBackend";
  const displayName = "iSmart Messenger Backend";
  const description = "iSmart Messenger Backend API Server";
  const logDir      = path.join(path.dirname(configPath), "logs");
  fs.mkdirSync(logDir, { recursive: true });

  const escapedExe    = EXE_PATH.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  const escapedConfig = configPath.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  const binPathValue  = `${EXE_PATH} --config "${configPath}"`;

  run(`sc.exe stop ${serviceName}`);
  run(`sc.exe delete ${serviceName}`);
  const deadline = Date.now() + 3000;
  while (Date.now() < deadline) { /* wait */ }

  const create = run(`sc.exe create "${serviceName}" binPath= "${binPathValue}" start= auto DisplayName= "${displayName}"`);
  if (!create.ok) throw new Error(`sc.exe create failed: ${create.stderr}`);

  run(`sc.exe description "${serviceName}" "${description}"`);
  run(`sc.exe failure "${serviceName}" reset= 86400 actions= restart/5000/restart/5000/restart/5000`);

  const started = run(`sc.exe start "${serviceName}"`);
  if (!started.ok) throw new Error(`sc.exe start failed: ${started.stderr}`);

  return serviceName;
}

function installLinuxService(configPath, dataDir) {
  const logDir = path.join(dataDir, "logs");
  fs.mkdirSync(logDir, { recursive: true });

  const unit = [
    "[Unit]",
    "Description=iSmart Messenger Backend API",
    "After=network.target mongod.service",
    "Wants=mongod.service",
    "",
    "[Service]",
    "Type=simple",
    "User=ismart",
    "Group=ismart",
    `ExecStart=${EXE_PATH} --config ${configPath}`,
    `WorkingDirectory=${dataDir}`,
    "Restart=on-failure",
    "RestartSec=5",
    "LimitNOFILE=65536",
    `StandardOutput=append:${path.join(logDir, "stdout.log")}`,
    `StandardError=append:${path.join(logDir, "stderr.log")}`,
    "",
    "[Install]",
    "WantedBy=multi-user.target",
  ].join("\n");

  fs.writeFileSync("/etc/systemd/system/ismart-backend.service", unit);
  run("id ismart || useradd -r -s /bin/false -d /var/lib/ismart ismart");
  run(`chown -R ismart:ismart "${dataDir}"`);
  run("chown -R ismart:ismart /etc/ismart");
  run("chmod 600 /etc/ismart/config.json");
  runVisible("systemctl daemon-reload");
  runVisible("systemctl enable ismart-backend");
  runVisible("systemctl start ismart-backend");
  return "ismart-backend";
}

// ─── Health doctor ────────────────────────────────────────────────────────────
async function runDoctor(config) {
  title("System Health Check (Doctor)");

  const results = [];

  // 1. MongoDB
  {
    const uri  = config && config.MONGODB_URI || "mongodb://127.0.0.1:27017";
    const alive = await isMongoRunning(uri);
    if (alive) {
      ok("MongoDB: reachable");
      results.push({ name: "MongoDB", ok: true });
    } else {
      fail("MongoDB: NOT reachable");
      results.push({ name: "MongoDB", ok: false, fix: "Start MongoDB service" });
    }
  }

  // 2. Backend service
  if (IS_WIN) {
    const svc = run("sc.exe query iSmartBackend");
    const running = svc.ok && svc.stdout.includes("RUNNING");
    if (running) {
      ok("Windows Service (iSmartBackend): Running");
      results.push({ name: "Windows Service", ok: true });
    } else {
      fail("Windows Service (iSmartBackend): NOT running");
      results.push({
        name: "Windows Service", ok: false,
        fix: 'sc.exe start iSmartBackend',
      });
    }
  } else if (IS_LINUX) {
    const svc = run("systemctl is-active ismart-backend");
    const running = svc.ok && svc.stdout.trim() === "active";
    if (running) {
      ok("systemd service (ismart-backend): active");
      results.push({ name: "systemd Service", ok: true });
    } else {
      fail("systemd service (ismart-backend): NOT active");
      results.push({
        name: "systemd Service", ok: false,
        fix: "sudo systemctl start ismart-backend",
      });
    }
  }

  // 3. API health check
  {
    const port   = (config && config.PORT) || 5000;
    const apiOk  = await isPortOpen("127.0.0.1", port);
    if (apiOk) {
      ok(`API (port ${port}): responding`);
      results.push({ name: "API", ok: true });
    } else {
      fail(`API (port ${port}): NOT responding`);
      results.push({ name: "API", ok: false, fix: "Check service logs" });
    }
  }

  // 4. Uploads directory
  if (config && config.UPLOADS_DIR) {
    const writable = checkDirWritable(config.UPLOADS_DIR);
    if (writable) {
      ok(`Uploads dir: writable (${config.UPLOADS_DIR})`);
      results.push({ name: "Uploads Dir", ok: true });
    } else {
      fail(`Uploads dir: NOT writable (${config.UPLOADS_DIR})`);
      results.push({ name: "Uploads Dir", ok: false, fix: `Fix permissions: ${config.UPLOADS_DIR}` });
    }
  }

  // 5. Backups directory
  if (config && config.BACKUPS_DIR) {
    const writable = checkDirWritable(config.BACKUPS_DIR);
    if (writable) {
      ok(`Backups dir: writable (${config.BACKUPS_DIR})`);
      results.push({ name: "Backups Dir", ok: true });
    } else {
      fail(`Backups dir: NOT writable (${config.BACKUPS_DIR})`);
      results.push({ name: "Backups Dir", ok: false, fix: `Fix permissions: ${config.BACKUPS_DIR}` });
    }
  }

  // 6. mongodump availability
  {
    const md = findMongodump();
    if (md) {
      ok("mongodump: found → DB backup supported");
      results.push({ name: "mongodump", ok: true });
    } else {
      warn("mongodump: NOT found → DB backup will be skipped");
      results.push({
        name: "mongodump", ok: false,
        fix: IS_WIN
          ? "Install MongoDB Database Tools: winget install MongoDB.DatabaseTools"
          : "sudo apt-get install -y mongodb-database-tools",
      });
    }
  }

  // ── Summary ──────────────────────────────────────────────────────────────
  log("");
  hr();
  const failed = results.filter(r => !r.ok);
  if (failed.length === 0) {
    log(`  ${C.green}${C.bold}✓ All checks passed!${C.reset}`);
  } else {
    log(`  ${C.red}${C.bold}${failed.length} check(s) failed:${C.reset}`);
    log("");

    const fixable = failed.filter(r => r.fix);
    if (fixable.length > 0) {
      log(`  ${C.bold}Suggested fixes:${C.reset}`);
      fixable.forEach((r, i) => {
        log(`    ${C.cyan}${i + 1})${C.reset} ${r.name}: ${C.yellow}${r.fix}${C.reset}`);
      });

      log("");
      const { index } = await promptChoice(
        "Would you like to attempt an automatic fix?",
        [...fixable.map(r => `Fix: ${r.name}`), "Skip all fixes"]
      );

      if (index < fixable.length) {
        const toFix = fixable[index];
        info(`Attempting fix for: ${toFix.name} ...`);
        if (toFix.name === "MongoDB") {
          if (IS_WIN) { await installMongoWindows(); }
          else        { await installMongoLinux(); }
        } else if (toFix.name === "Windows Service") {
          run("sc.exe start iSmartBackend");
        } else if (toFix.name === "systemd Service") {
          runVisible("systemctl start ismart-backend");
        } else if (toFix.name === "mongodump") {
          if (IS_WIN) {
            runVisible("winget install --id MongoDB.DatabaseTools -e --silent --accept-package-agreements --accept-source-agreements");
          } else {
            runVisible("apt-get install -y mongodb-database-tools");
          }
        } else {
          info(`Please run manually: ${toFix.fix}`);
        }
      }
    }
  }
  hr();
  return results;
}

function checkDirWritable(dirPath) {
  try {
    const test = path.join(dirPath, ".ismart_test");
    fs.writeFileSync(test, "1");
    fs.unlinkSync(test);
    return true;
  } catch (_) { return false; }
}

/**
 * Verifies the admin account was created by trying to log in via the API.
 * Returns true if login succeeds, false otherwise.
 */
async function verifyAdminAccount(port, username, password) {
  return new Promise((resolve) => {
    const http = require("http");
    const body = JSON.stringify({ username, password });
    const options = {
      hostname: "127.0.0.1",
      port:     port,
      path:     "/api/auth/login",
      method:   "POST",
      headers:  {
        "Content-Type":   "application/json",
        "Content-Length": Buffer.byteLength(body),
      },
    };
    const req = http.request(options, (res) => {
      let data = "";
      res.on("data", chunk => data += chunk);
      res.on("end",  ()    => resolve(res.statusCode === 200));
    });
    req.on("error", () => resolve(false));
    req.setTimeout(5000, () => { req.destroy(); resolve(false); });
    req.write(body);
    req.end();
  });
}


// ─── Write config helper ──────────────────────────────────────────────────────
function writeConfig(configPath, config) {
  const dir = path.dirname(configPath);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2), "utf8");
  if (IS_LINUX) { run(`chmod 600 "${configPath}"`); }
}

// ─── Fresh install flow ───────────────────────────────────────────────────────
async function runFreshInstall() {
  const TOTAL = 7;

  // ── Step 1: Privileges ──────────────────────────────────────────────────
  step(1, TOTAL, "Checking privileges...");
  if (IS_WIN) {
    const adminCheck = run("net session >nul 2>&1 && echo YES");
    if (!adminCheck.stdout.includes("YES")) {
      fail("Must be run as Administrator. Right-click → Run as administrator.");
      process.exit(1);
    }
    ok("Running as Administrator.");
  } else if (IS_LINUX) {
    if (process.getuid && process.getuid() !== 0) {
      fail("Must be run as root. Use: sudo " + EXE_PATH + " --install");
      process.exit(1);
    }
    ok("Running as root.");
  }

  // ── Step 2: MongoDB ─────────────────────────────────────────────────────
  step(2, TOTAL, "Checking MongoDB...");
  let mongoOk = await isMongoRunning();
  if (mongoOk) {
    ok("MongoDB is running on port 27017.");
  } else {
    warn("MongoDB is NOT running.");
    const { index } = await promptChoice(
      "MongoDB is required. What would you like to do?",
      [
        "Install MongoDB automatically (recommended)",
        "MongoDB is on a remote host — skip local install",
        "Cancel",
      ]
    );
    if (index === 0) {
      if (IS_WIN)      mongoOk = await installMongoWindows();
      else if (IS_LINUX) mongoOk = await installMongoLinux();
      if (mongoOk) {
        mongoOk = await isMongoRunning();
        if (mongoOk) ok("MongoDB is running.");
        else warn("MongoDB port not responding yet — continuing.");
      }
    } else if (index === 2) {
      log("  Cancelled."); process.exit(0);
    }
  }

  // ── Step 3: Data paths ──────────────────────────────────────────────────
  step(3, TOTAL, "Configure data directories...");
  log("  These directories will store chat files, documents, and backups.");
  log("  They should be on a disk with enough free space.\n");

  const defaultDataDir = IS_WIN ? "C:\\ProgramData\\iSmart" : "/var/lib/ismart";

  const dataDir    = await promptValidatedDir("Main data directory", defaultDataDir, "Data directory");
  const uploadsDir = await promptValidatedDir("Chat & uploads directory", path.join(dataDir, "uploads"), "Uploads directory");
  const backupsDir = await promptValidatedDir("Backups directory", path.join(dataDir, "backups"), "Backups directory");
  const releasesDir= await promptValidatedDir("App updates directory", path.join(dataDir, "releases"), "Releases directory");

  // ── Step 4: Connection & credentials ───────────────────────────────────
  step(4, TOTAL, "Configure connection settings...");

  const port = await prompt("API Port", "5000");

  const defaultMongoUri = "mongodb://127.0.0.1:27017/workplace_documents";
  const mongoUri = await prompt("MongoDB URI", defaultMongoUri);

  log("");
  log(`  ${C.bold}Admin Account${C.reset}`);
  log(`  ${C.dim}This account will be used to log in to iSmart for the first time.${C.reset}`);
  log(`  ${C.dim}Username: min 4 characters | Password: min 8 characters${C.reset}`);
  log("");

  let adminUser = "";
  while (adminUser.length < 4) {
    adminUser = await prompt("Admin username");
    if (adminUser.length < 4) warn("Username must be at least 4 characters.");
  }

  let adminPass = "";
  while (adminPass.length < 8) {
    adminPass = await promptSecret("Admin password");
    if (adminPass.length < 8) warn("Password must be at least 8 characters.");
  }

  let adminPassConfirm = "";
  while (adminPassConfirm !== adminPass) {
    adminPassConfirm = await promptSecret("Confirm admin password");
    if (adminPassConfirm !== adminPass) warn("Passwords do not match. Try again.");
  }
  ok("Admin credentials accepted.");

  // ── Step 5: Backup schedule ─────────────────────────────────────────────
  step(5, TOTAL, "Configure automatic backup...");
  log("  A backup will run automatically every night.");
  log("  It includes the database AND all chat files.\n");

  const timeChoice = await promptChoice("Daily backup time", [
    "1:00 AM (recommended for light usage)",
    "2:00 AM",
    "3:00 AM (recommended for high usage — gives more time to finish)",
  ]);
  const backupHour = [1, 2, 3][timeChoice.index];
  info(`Backup will run daily at ${backupHour}:00 AM.`);

  log("");
  info("Where should backups be saved?");
  info("Tip: Use a network share path (e.g. \\\\NAS\\Backups\\iSmart) for off-server backups.");
  const backupSaveDir = await promptValidatedDir(
    "Backup save directory",
    backupsDir,
    "Backup save directory"
  );

  // ── Step 6: Write config & install service ──────────────────────────────
  step(6, TOTAL, "Writing config and installing service...");

  const configDir  = IS_WIN ? dataDir : "/etc/ismart";
  const configPath = path.join(configDir, "config.json");

  const config = {
    DATA_DIR:                 dataDir,
    PORT:                     parseInt(port, 10),
    MONGODB_URI:              mongoUri,
    JWT_SECRET:               generateSecret(64),
    NODE_ENV:                 "production",
    UPLOADS_DIR:              uploadsDir,
    BACKUPS_DIR:              backupsDir,
    BACKUP_SAVE_DIR:          backupSaveDir,
    UPDATE_RELEASES_DIR:      releasesDir,
    BOOTSTRAP_ADMIN_ENABLED:  (adminUser && adminPass) ? "true" : "false",
    BOOTSTRAP_ADMIN_USERNAME: adminUser || "",
    BOOTSTRAP_ADMIN_PASSWORD: adminPass || "",
    CORS_ORIGIN:              "*",
  };

  writeConfig(configPath, config);
  ok(`Config saved: ${configPath}`);

  // Create all dirs
  for (const d of [uploadsDir, backupsDir, backupSaveDir, releasesDir, path.join(dataDir, "logs")]) {
    fs.mkdirSync(d, { recursive: true });
  }

  // Install service
  try {
    if (IS_WIN)      { installWindowsService(configPath); ok("Windows Service installed: iSmartBackend"); }
    else if (IS_LINUX) { installLinuxService(configPath, dataDir); ok("systemd service installed: ismart-backend"); }
  } catch (e) {
    fail(`Service install failed: ${e.message}`);
  }

  // Schedule backup
  if (IS_WIN)        scheduleBackupWindows(backupHour, backupSaveDir);
  else if (IS_LINUX) scheduleBackupLinux(backupHour, backupSaveDir);

  // ── Step 7: Doctor check + Admin verification ───────────────────────────
  step(7, TOTAL, "Running health check and verifying admin account...");
  info("Waiting for service to start...");

  // Wait up to 15 seconds for the API to respond
  const apiPort = parseInt(port, 10);
  let apiReady  = false;
  for (let i = 0; i < 15; i++) {
    await sleep(1000);
    apiReady = await isPortOpen("127.0.0.1", apiPort);
    if (apiReady) break;
    process.stdout.write(".");
  }
  if (!apiReady) process.stdout.write("\n");

  await runDoctor(config);

  // Verify admin account was created by logging in
  log("");
  info("Verifying admin account...");
  let adminVerified = false;
  for (let attempt = 0; attempt < 5; attempt++) {
    await sleep(1000);
    adminVerified = await verifyAdminAccount(apiPort, adminUser, adminPass);
    if (adminVerified) break;
  }

  if (adminVerified) {
    ok(`Admin account verified: "${adminUser}" can log in successfully.`);
  } else {
    warn(`Could not verify admin login — service may still be starting.`);
    warn(`Try logging in with username "${adminUser}" in a few seconds.`);
    warn(`If login fails, run: ${IS_WIN ? `"${EXE_PATH}" --doctor` : `sudo ${EXE_PATH} --doctor`}`);
  }

  // ── Done ─────────────────────────────────────────────────────────────────
  log("");
  log(`${C.green}${"═".repeat(60)}${C.reset}`);
  log(`${C.green}  Installation complete!${C.reset}`);
  log(`${C.green}${"═".repeat(60)}${C.reset}`);
  log("");
  log(`  ${C.bold}API URL       :${C.reset} http://localhost:${port}`);
  log(`  ${C.bold}Admin login   :${C.reset} ${C.cyan}${adminUser}${C.reset} ${adminVerified ? C.green + "✓ verified" + C.reset : C.yellow + "(verify manually)" + C.reset}`);
  log(`  ${C.bold}Data dir      :${C.reset} ${dataDir}`);
  log(`  ${C.bold}Uploads dir   :${C.reset} ${uploadsDir}`);
  log(`  ${C.bold}Backup dir    :${C.reset} ${backupSaveDir}`);
  log(`  ${C.bold}Config file   :${C.reset} ${configPath}`);
  log(`  ${C.bold}Backup time   :${C.reset} Daily at ${backupHour}:00 AM`);
  log("");
  log(`  ${C.bold}Manual backup command:${C.reset}`);
  if (IS_WIN)        log(`    ${C.cyan}"${EXE_PATH}" --backup${C.reset}`);
  else if (IS_LINUX) log(`    ${C.cyan}sudo ${EXE_PATH} --backup${C.reset}`);
  log("");
  log(`  ${C.bold}Doctor / health check command:${C.reset}`);
  if (IS_WIN)        log(`    ${C.cyan}"${EXE_PATH}" --doctor${C.reset}`);
  else if (IS_LINUX) log(`    ${C.cyan}sudo ${EXE_PATH} --doctor${C.reset}`);
  log("");

  if (IS_WIN) {
    log(`  ${C.bold}Service management:${C.reset}`);
    log(`    sc.exe query  iSmartBackend`);
    log(`    sc.exe start  iSmartBackend`);
    log(`    sc.exe stop   iSmartBackend`);
  } else if (IS_LINUX) {
    log(`  ${C.bold}Service management:${C.reset}`);
    log(`    sudo systemctl status  ismart-backend`);
    log(`    sudo systemctl start   ismart-backend`);
    log(`    sudo systemctl stop    ismart-backend`);
    log(`    sudo tail -f ${path.join(dataDir, "logs/stdout.log")}`);
  }
  log("");
}

// ─── Restore flow ─────────────────────────────────────────────────────────────
async function runRestoreFlow() {
  title("Restore from Backup");

  // Privileges check
  if (IS_WIN) {
    const adminCheck = run("net session >nul 2>&1 && echo YES");
    if (!adminCheck.stdout.includes("YES")) {
      fail("Must be run as Administrator."); process.exit(1);
    }
  } else if (IS_LINUX) {
    if (process.getuid && process.getuid() !== 0) {
      fail("Must be run as root (sudo)."); process.exit(1);
    }
  }

  // Get backup file
  info("Please provide the path to your backup .zip file.");
  let backupPath = "";
  while (true) {
    backupPath = await prompt("Backup file path (.zip)");
    if (fs.existsSync(backupPath)) {
      ok(`Backup file found: ${backupPath}`);
      break;
    }
    fail(`File not found: ${backupPath}`);
  }

  // Read manifest preview
  const unzipper = require("unzipper");
  let manifest = null;
  try {
    const zip = await unzipper.Open.file(backupPath);
    const manifestEntry = zip.files.find(f => f.path === "backup-manifest.json");
    if (manifestEntry) {
      const content = await manifestEntry.buffer();
      manifest = JSON.parse(content.toString("utf8"));
      log("");
      info(`Backup date    : ${manifest.timestamp}`);
      info(`Original OS    : ${manifest.platform}`);
      info(`Includes DB    : ${manifest.includes.database ? "Yes" : "No"}`);
      info(`Includes files : ${manifest.includes.uploads ? "Yes" : "No"}`);
    }
  } catch (e) {
    warn("Could not read backup manifest. Will attempt restore anyway.");
  }

  // Data directory
  const defaultDataDir = IS_WIN ? "C:\\ProgramData\\iSmart" : "/var/lib/ismart";
  const dataDir    = await promptValidatedDir("Restore data to directory", defaultDataDir, "Data directory");
  const uploadsDir = await promptValidatedDir("Uploads restore directory", path.join(dataDir, "uploads"), "Uploads directory");
  const backupsDir = await promptValidatedDir("Backups directory", path.join(dataDir, "backups"), "Backups directory");
  const backupSaveDir = await promptValidatedDir("Future backup save directory", backupsDir, "Backup save directory");
  const releasesDir= await promptValidatedDir("App updates directory", path.join(dataDir, "releases"), "Releases directory");

  const port     = await prompt("API Port", "5000");
  const mongoUri = await prompt("MongoDB URI", (manifest && manifest.config && manifest.config.MONGODB_URI) || "mongodb://127.0.0.1:27017/workplace_documents");

  // Backup schedule
  const timeChoice = await promptChoice("Daily backup time", ["1:00 AM", "2:00 AM", "3:00 AM"]);
  const backupHour = [1, 2, 3][timeChoice.index];

  // Check / install MongoDB
  const mongoOk = await isMongoRunning(mongoUri);
  if (!mongoOk) {
    warn("MongoDB is not running.");
    const { index } = await promptChoice("Install MongoDB?", ["Yes, install automatically", "No, I'll start it manually"]);
    if (index === 0) {
      if (IS_WIN)      await installMongoWindows();
      else if (IS_LINUX) await installMongoLinux();
    }
  } else {
    ok("MongoDB is reachable.");
  }

  // Write config
  const configDir  = IS_WIN ? dataDir : "/etc/ismart";
  const configPath = path.join(configDir, "config.json");
  const config = {
    DATA_DIR:            dataDir,
    PORT:                parseInt(port, 10),
    MONGODB_URI:         mongoUri,
    JWT_SECRET:          (manifest && manifest.config && manifest.config.JWT_SECRET) || generateSecret(64),
    NODE_ENV:            "production",
    UPLOADS_DIR:         uploadsDir,
    BACKUPS_DIR:         backupsDir,
    BACKUP_SAVE_DIR:     backupSaveDir,
    UPDATE_RELEASES_DIR: releasesDir,
    CORS_ORIGIN:         "*",
  };
  writeConfig(configPath, config);
  ok(`Config saved: ${configPath}`);

  // Restore data
  const restored = await restoreFromBackup(backupPath, config);

  // Install service
  try {
    if (IS_WIN)        installWindowsService(configPath);
    else if (IS_LINUX) installLinuxService(configPath, dataDir);
    ok("Service installed and started.");
  } catch (e) {
    fail(`Service install failed: ${e.message}`);
  }

  // Schedule backup
  if (IS_WIN)        scheduleBackupWindows(backupHour, backupSaveDir);
  else if (IS_LINUX) scheduleBackupLinux(backupHour, backupSaveDir);

  // Doctor
  await sleep(3000);
  await runDoctor(config);

  log("");
  log(`${C.green}${"═".repeat(60)}${C.reset}`);
  log(`${C.green}  Restore complete! System is back online.${C.reset}`);
  log(`${C.green}${"═".repeat(60)}${C.reset}`);
  log("");
  log(`  ${C.bold}Manual backup command:${C.reset}`);
  if (IS_WIN)      log(`    ${C.cyan}"${EXE_PATH}" --backup${C.reset}`);
  else if (IS_LINUX) log(`    ${C.cyan}sudo ${EXE_PATH} --backup${C.reset}`);
  log("");
}

// ─── Standalone backup (--backup) ────────────────────────────────────────────
async function runStandaloneBackup() {
  // Load current config
  const configPath = IS_WIN
    ? "C:\\ProgramData\\iSmart\\config.json"
    : "/etc/ismart/config.json";

  // Also check ISMART_CONFIG_PATH
  const envConfigPath = process.env.ISMART_CONFIG_PATH || "";
  const actualPath    = (envConfigPath && fs.existsSync(envConfigPath)) ? envConfigPath : configPath;

  if (!fs.existsSync(actualPath)) {
    fail("Config not found. Run --install first.");
    process.exit(1);
  }

  const config    = JSON.parse(fs.readFileSync(actualPath, "utf8"));
  const backupDir = config.BACKUP_SAVE_DIR || config.BACKUPS_DIR || path.join(config.DATA_DIR, "backups");

  fs.mkdirSync(backupDir, { recursive: true });
  await createBackup(config, backupDir);
}

// ─── Uninstaller ─────────────────────────────────────────────────────────────
async function runUninstaller() {
  title("Uninstalling iSmart Backend");

  if (IS_WIN) {
    run("schtasks /delete /tn \"iSmartBackup\" /f");
    run("sc.exe stop iSmartBackend");
    run("sc.exe delete iSmartBackend");
    ok("Windows Service removed: iSmartBackend");
    ok("Backup scheduled task removed: iSmartBackup");
  } else if (IS_LINUX) {
    run("systemctl stop ismart-backend");
    run("systemctl disable ismart-backend");
    try { fs.unlinkSync("/etc/systemd/system/ismart-backend.service"); } catch (_) {}
    try { fs.unlinkSync("/etc/cron.d/ismart-backup"); } catch (_) {}
    run("systemctl daemon-reload");
    ok("systemd service removed: ismart-backend");
    ok("Cron backup job removed.");
  }

  log("");
  warn("Data and config files were NOT deleted.");
  log(`  To delete: remove ${IS_WIN ? "C:\\ProgramData\\iSmart" : "/var/lib/ismart"} and ${IS_WIN ? "" : "/etc/ismart"}`);
  log("");
  return 0;
}

// ─── Main entry point ─────────────────────────────────────────────────────────
async function runInstaller(uninstall = false) {
  if (uninstall) {
    await runUninstaller();
    return 0;
  }

  title("iSmart Messenger Backend — Setup Wizard");

  const { index } = await promptChoice(
    "What would you like to do?",
    [
      "Fresh installation — set up iSmart Backend from scratch",
      "Restore from backup — recover an existing installation",
    ]
  );

  if (index === 0) {
    await runFreshInstall();
  } else {
    await runRestoreFlow();
  }

  return 0;
}

module.exports = { runInstaller, runStandaloneBackup, runDoctor };
