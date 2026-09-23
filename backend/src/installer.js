/**
 * iSmart Backend — Self-contained installer
 *
 * Triggered when the binary is run with --install flag.
 * Handles:
 *   - MongoDB detection + auto-install (Windows: winget/MSI, Linux: apt)
 *   - Interactive configuration wizard
 *   - Windows Service registration via sc.exe (no NSSM needed)
 *   - Linux systemd service registration
 *   - First-run admin user configuration
 */

"use strict";

const readline  = require("readline");
const fs        = require("fs");
const path      = require("path");
const os        = require("os");
const { execSync, spawnSync } = require("child_process");

// ─── Helpers ──────────────────────────────────────────────────────────────────

const IS_WIN   = process.platform === "win32";
const IS_LINUX = process.platform === "linux";
const EXE_PATH = process.execPath;
const EXE_DIR  = path.dirname(EXE_PATH);

const RED    = IS_WIN ? "" : "\x1b[31m";
const GREEN  = IS_WIN ? "" : "\x1b[32m";
const YELLOW = IS_WIN ? "" : "\x1b[33m";
const CYAN   = IS_WIN ? "" : "\x1b[36m";
const BOLD   = IS_WIN ? "" : "\x1b[1m";
const RESET  = IS_WIN ? "" : "\x1b[0m";

function log(msg)        { process.stdout.write(msg + "\n"); }
function ok(msg)         { log(`  ${GREEN}✓${RESET}  ${msg}`); }
function warn(msg)       { log(`  ${YELLOW}⚠${RESET}  ${msg}`); }
function err(msg)        { log(`  ${RED}✗${RESET}  ${msg}`); }
function step(n, t, msg) { log(`\n${BOLD}[ ${n}/${t} ] ${msg}${RESET}`); }
function hr()            { log("─".repeat(56)); }

function prompt(rl, question) {
  return new Promise((resolve) => rl.question(question, (ans) => resolve(ans.trim())));
}

function promptSecret(question) {
  return new Promise((resolve) => {
    if (process.stdin.isTTY) {
      // Hide input on TTY
      process.stdout.write(question);
      let password = "";
      process.stdin.setRawMode(true);
      process.stdin.resume();
      process.stdin.setEncoding("utf8");
      process.stdin.on("data", function onData(char) {
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
            process.stdout.write(question + "*".repeat(password.length));
          }
        } else {
          password += char;
          process.stdout.write("*");
        }
      });
    } else {
      // Not a TTY (piped input), just read normally
      const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
      rl.question(question, (ans) => { rl.close(); resolve(ans.trim()); });
    }
  });
}

function run(cmd, opts = {}) {
  try {
    const result = spawnSync(cmd, { shell: true, encoding: "utf8", stdio: "pipe", ...opts });
    return { ok: result.status === 0, stdout: result.stdout || "", stderr: result.stderr || "" };
  } catch (_) {
    return { ok: false, stdout: "", stderr: "" };
  }
}

function runVisible(cmd) {
  try {
    execSync(cmd, { stdio: "inherit", shell: true });
    return true;
  } catch (_) {
    return false;
  }
}

function isPortOpen(host, port) {
  const net = require("net");
  return new Promise((resolve) => {
    const socket = new net.Socket();
    socket.setTimeout(1500);
    socket.once("connect", () => { socket.destroy(); resolve(true); });
    socket.once("timeout", () => { socket.destroy(); resolve(false); });
    socket.once("error", () => { socket.destroy(); resolve(false); });
    socket.connect(port, host);
  });
}

function generateSecret(len = 64) {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const crypto = require("crypto");
  let result = "";
  const bytes = crypto.randomBytes(len);
  for (let i = 0; i < len; i++) {
    result += chars[bytes[i] % chars.length];
  }
  return result;
}

// ─── MongoDB helpers ──────────────────────────────────────────────────────────

async function isMongoRunning(uri) {
  // Quick check: is port 27017 (or the port in uri) open?
  try {
    const match = uri.match(/:\/\/([^:/]+):?(\d+)?/);
    const host  = (match && match[1]) || "127.0.0.1";
    const port  = parseInt((match && match[2]) || "27017", 10);
    return await isPortOpen(host, port);
  } catch (_) {
    return false;
  }
}

async function installMongoWindows() {
  log(`\n  ${CYAN}Attempting to install MongoDB via winget...${RESET}`);

  const winget = run("winget --version");
  if (winget.ok) {
    log("  winget found — installing MongoDB Community Server...");
    const success = runVisible(
      "winget install --id MongoDB.Server -e --silent --accept-package-agreements --accept-source-agreements"
    );
    if (success) {
      // Start the MongoDB service
      runVisible("net start MongoDB");
      // Wait a moment for it to start
      await new Promise(r => setTimeout(r, 3000));
      ok("MongoDB installed and started via winget.");
      return true;
    }
  }

  // Fallback: download MSI manually
  warn("winget not available. Downloading MongoDB installer...");
  const mongoUrl =
    "https://fastdl.mongodb.org/windows/mongodb-windows-x86_64-7.0.14-signed.msi";
  const msiPath  = path.join(os.tmpdir(), "mongodb-installer.msi");

  log(`  Downloading: ${mongoUrl}`);
  log(`  Saving to  : ${msiPath}`);

  const downloaded = await downloadFile(mongoUrl, msiPath);
  if (!downloaded) {
    err("Download failed.");
    return false;
  }

  log("  Running MongoDB installer (silent)...");
  const installed = runVisible(
    `msiexec /i "${msiPath}" /quiet /norestart ADDLOCAL="ServerNoService" ` +
    `SHOULD_INSTALL_COMPASS="0"`
  );

  if (!installed) {
    err("MongoDB installation failed.");
    return false;
  }

  // Register and start MongoDB as a Windows Service manually
  const mongoDbDir  = "C:\\Program Files\\MongoDB\\Server\\7.0";
  const mongoDataDir = "C:\\ProgramData\\MongoDB\\data";
  const mongoLogDir  = "C:\\ProgramData\\MongoDB\\log";

  fs.mkdirSync(mongoDataDir, { recursive: true });
  fs.mkdirSync(mongoLogDir,  { recursive: true });

  // Write mongod.cfg
  const mongoCfg = path.join(mongoDbDir, "bin", "mongod.cfg");
  fs.writeFileSync(mongoCfg, [
    "systemLog:",
    `  destination: file`,
    `  path: ${path.join(mongoLogDir, "mongod.log").replace(/\\/g, "/")}`,
    "storage:",
    `  dbPath: ${mongoDataDir.replace(/\\/g, "/")}`,
    "net:",
    "  bindIp: 127.0.0.1",
  ].join("\n"));

  run(`"${path.join(mongoDbDir, "bin", "mongod.exe")}" --config "${mongoCfg}" --install`);
  runVisible("net start MongoDB");

  await new Promise(r => setTimeout(r, 3000));
  ok("MongoDB installed and started.");
  return true;
}

async function installMongoLinux() {
  log(`\n  ${CYAN}Installing MongoDB via apt...${RESET}`);

  // Detect Ubuntu/Debian codename
  const lsbResult = run("lsb_release -sc");
  const codename  = lsbResult.ok ? lsbResult.stdout.trim() : "focal";

  log(`  Detected Ubuntu codename: ${codename}`);

  const steps = [
    "apt-get install -y gnupg curl",
    `curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg`,
    `echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${codename}/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list`,
    "apt-get update -qq",
    "apt-get install -y mongodb-org",
    "systemctl enable mongod",
    "systemctl start mongod",
  ];

  for (const cmd of steps) {
    log(`  → ${cmd}`);
    const ok = runVisible(cmd);
    if (!ok) {
      // Some steps are non-critical, continue
      warn(`Command may have failed: ${cmd}`);
    }
  }

  await new Promise(r => setTimeout(r, 3000));
  return true;
}

function downloadFile(url, dest) {
  return new Promise((resolve) => {
    const https = require("https");
    const http  = require("http");
    const proto = url.startsWith("https") ? https : http;
    const file  = fs.createWriteStream(dest);

    const req = proto.get(url, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302) {
        file.close();
        fs.unlinkSync(dest);
        resolve(downloadFile(res.headers.location, dest));
        return;
      }
      res.pipe(file);
      file.on("finish", () => { file.close(); resolve(true); });
    });
    req.on("error", () => { file.close(); resolve(false); });
    req.setTimeout(120_000, () => { req.destroy(); resolve(false); });
  });
}

// ─── Service installation ─────────────────────────────────────────────────────

function installWindowsService(configPath) {
  const serviceName  = "iSmartBackend";
  const displayName  = "iSmart Messenger Backend";
  const description  = "iSmart Messenger Backend API Server";

  // Build the binary path including --config argument for sc.exe.
  // sc.exe binPath= requires the entire value to be one double-quoted string,
  // with inner quotes escaped as \".  The trailing space after binPath= is
  // intentional — it is part of sc.exe's unusual argument syntax.
  const escapedExe    = EXE_PATH.replace(/"/g, '\\"');
  const escapedConfig = configPath.replace(/"/g, '\\"');
  const binPathValue  = `"${escapedExe}" --config "${escapedConfig}"`;

  // Remove existing service if present
  run(`sc.exe stop ${serviceName}`);
  run(`sc.exe delete ${serviceName}`);

  // Let Windows finish removing the service (up to 3 s)
  const deadline = Date.now() + 3000;
  while (Date.now() < deadline) { /* spin */ }

  // Create service — note the intentional space after every "key= "
  const create = run(
    `sc.exe create ${serviceName} binPath= "${binPathValue.replace(/"/g, '\\"')}" ` +
    `start= auto DisplayName= "${displayName}"`
  );
  if (!create.ok) throw new Error(`sc.exe create failed: ${create.stderr}`);

  // Set description
  run(`sc.exe description ${serviceName} "${description}"`);

  // Restart on failure: 3 attempts, 5-second delay each, reset counter after 24 h
  run(
    `sc.exe failure ${serviceName} reset= 86400 actions= restart/5000/restart/5000/restart/5000`
  );

  // Start the service
  const started = run(`sc.exe start ${serviceName}`);
  if (!started.ok) throw new Error(`sc.exe start failed: ${started.stderr}`);

  return serviceName;
}

function installLinuxService(configPath, dataDir) {
  const logDir = path.join(dataDir, "logs");
  fs.mkdirSync(logDir, { recursive: true });

  const unitContent = [
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

  fs.writeFileSync("/etc/systemd/system/ismart-backend.service", unitContent);

  // Create ismart user if not exists
  run("id ismart || useradd -r -s /bin/false -d /var/lib/ismart ismart");

  // Set permissions
  run(`chown -R ismart:ismart "${dataDir}"`);
  run("chown -R ismart:ismart /etc/ismart");
  run("chmod 600 /etc/ismart/config.json");

  execSync("systemctl daemon-reload", { stdio: "inherit" });
  execSync("systemctl enable ismart-backend", { stdio: "inherit" });
  execSync("systemctl start ismart-backend", { stdio: "inherit" });

  return "ismart-backend";
}

// ─── Uninstaller ─────────────────────────────────────────────────────────────

async function runUninstaller() {
  log("");
  log(`${YELLOW}Uninstalling iSmart Backend service...${RESET}`);

  if (IS_WIN) {
    run("sc.exe stop iSmartBackend");
    run("sc.exe delete iSmartBackend");
    ok("Windows Service removed: iSmartBackend");
  } else if (IS_LINUX) {
    run("systemctl stop ismart-backend");
    run("systemctl disable ismart-backend");
    try { fs.unlinkSync("/etc/systemd/system/ismart-backend.service"); } catch (_) {}
    run("systemctl daemon-reload");
    ok("systemd service removed: ismart-backend");
  }

  log("");
  log("  Config and data files were NOT deleted.");
  log(`  To delete data: remove ${IS_WIN ? "C:\\ProgramData\\iSmart" : "/var/lib/ismart"} and ${IS_WIN ? "%DataDir%\\config.json" : "/etc/ismart"}`);
  log("");
  return 0;
}

// ─── Main installer ───────────────────────────────────────────────────────────

async function runInstaller(uninstall = false) {
  if (uninstall) {
    return runUninstaller();
  }

  log("");
  log(`${CYAN}${"═".repeat(56)}${RESET}`);
  log(`${CYAN}  iSmart Messenger Backend — Setup Wizard${RESET}`);
  log(`${CYAN}${"═".repeat(56)}${RESET}`);
  log("");

  const TOTAL_STEPS = 5;

  // ── Check privileges ─────────────────────────────────────────────────────
  step(1, TOTAL_STEPS, "Checking privileges...");
  if (IS_WIN) {
    const adminCheck = run(
      'net session >nul 2>&1 && echo YES || echo NO'
    );
    if (!adminCheck.stdout.includes("YES")) {
      err("This installer must be run as Administrator.");
      log("  Right-click the EXE and choose 'Run as administrator'.");
      process.exit(1);
    }
    ok("Running as Administrator.");
  } else if (IS_LINUX) {
    if (process.getuid && process.getuid() !== 0) {
      err("This installer must be run as root (sudo).");
      log("  Run: sudo " + EXE_PATH + " --install");
      process.exit(1);
    }
    ok("Running as root.");
  }

  // ── Check / install MongoDB ───────────────────────────────────────────────
  step(2, TOTAL_STEPS, "Checking MongoDB...");

  const defaultMongoUri = "mongodb://127.0.0.1:27017/workplace_documents";
  let mongoOk = await isMongoRunning(defaultMongoUri);

  if (mongoOk) {
    ok("MongoDB is running on port 27017.");
  } else {
    warn("MongoDB is NOT running on port 27017.");
    log("");
    log("  iSmart Backend requires MongoDB to work.");
    log("  Options:");
    log("    1) Install MongoDB automatically (recommended)");
    log("    2) I have MongoDB on another host — skip");
    log("    3) Cancel installation");
    log("");

    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const choice = await prompt(rl, "  Your choice [1/2/3]: ");
    rl.close();

    if (choice === "1") {
      if (IS_WIN) {
        mongoOk = await installMongoWindows();
      } else if (IS_LINUX) {
        mongoOk = await installMongoLinux();
      }
      if (!mongoOk) {
        warn("MongoDB installation may not have completed. Continuing anyway...");
      } else {
        // verify
        mongoOk = await isMongoRunning(defaultMongoUri);
        if (mongoOk) {
          ok("MongoDB is running.");
        } else {
          warn("MongoDB port not responding yet. It may need a few more seconds.");
        }
      }
    } else if (choice === "3") {
      log("  Installation cancelled.");
      process.exit(0);
    } else {
      warn("Skipping MongoDB installation. Make sure MongoDB is reachable.");
    }
  }

  // ── Configuration ─────────────────────────────────────────────────────────
  step(3, TOTAL_STEPS, "Configuration...");
  log("");

  const rl2 = readline.createInterface({ input: process.stdin, output: process.stdout });

  const defaultDataDir = IS_WIN
    ? "C:\\ProgramData\\iSmart"
    : "/var/lib/ismart";

  const dataDir = await prompt(rl2,
    `  Data directory [${defaultDataDir}]: `
  ) || defaultDataDir;

  const port = await prompt(rl2, "  API Port [5000]: ") || "5000";

  const mongoUri = await prompt(rl2,
    `  MongoDB URI [${defaultMongoUri}]: `
  ) || defaultMongoUri;

  const adminUser = await prompt(rl2,
    "  First admin username (leave empty to skip): "
  );

  rl2.close();

  let adminPass = "";
  if (adminUser) {
    adminPass = await promptSecret("  First admin password: ");
    if (!adminPass) {
      warn("Empty password — admin creation skipped.");
    }
  }

  // ── Write config file ─────────────────────────────────────────────────────
  step(4, TOTAL_STEPS, "Writing configuration...");

  const uploadsDir  = path.join(dataDir, "uploads");
  const backupsDir  = path.join(dataDir, "backups");
  const releasesDir = path.join(dataDir, "releases");
  const logsDir     = path.join(dataDir, "logs");

  for (const dir of [dataDir, uploadsDir, backupsDir, releasesDir, logsDir]) {
    fs.mkdirSync(dir, { recursive: true });
  }

  const configDir  = IS_WIN ? dataDir : "/etc/ismart";
  fs.mkdirSync(configDir, { recursive: true });
  const configPath = path.join(configDir, "config.json");

  const config = {
    DATA_DIR:                   dataDir,
    PORT:                       parseInt(port, 10),
    MONGODB_URI:                mongoUri,
    JWT_SECRET:                 generateSecret(64),
    NODE_ENV:                   "production",
    UPLOADS_DIR:                uploadsDir,
    BACKUPS_DIR:                backupsDir,
    UPDATE_RELEASES_DIR:        releasesDir,
    BOOTSTRAP_ADMIN_ENABLED:    (adminUser && adminPass) ? "true" : "false",
    BOOTSTRAP_ADMIN_USERNAME:   adminUser || "",
    BOOTSTRAP_ADMIN_PASSWORD:   adminPass || "",
    CORS_ORIGIN:                "*",
  };

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2), "utf8");
  ok(`Config saved: ${configPath}`);

  // ── Install service ───────────────────────────────────────────────────────
  step(5, TOTAL_STEPS, "Installing service...");

  let serviceName;
  if (IS_WIN) {
    serviceName = installWindowsService(configPath);
    ok(`Windows Service installed: ${serviceName}`);
  } else if (IS_LINUX) {
    serviceName = installLinuxService(configPath, dataDir);
    ok(`systemd service installed: ${serviceName}`);
  } else {
    warn(`Platform '${process.platform}' — service registration not supported.`);
    log(`  Run manually: ${EXE_PATH} --config "${configPath}"`);
  }

  // ── Done ──────────────────────────────────────────────────────────────────
  log("");
  log(`${GREEN}${"═".repeat(56)}${RESET}`);
  log(`${GREEN}  Installation complete!${RESET}`);
  log(`${GREEN}${"═".repeat(56)}${RESET}`);
  log("");
  log(`  ${BOLD}API URL    :${RESET} http://localhost:${port}`);
  log(`  ${BOLD}Data Dir   :${RESET} ${dataDir}`);
  log(`  ${BOLD}Config     :${RESET} ${configPath}`);
  log(`  ${BOLD}Logs       :${RESET} ${logsDir}`);
  log("");

  if (IS_WIN) {
    log(`  ${BOLD}Service management (run as Admin):${RESET}`);
    log("    Start  : sc.exe start iSmartBackend");
    log("    Stop   : sc.exe stop iSmartBackend");
    log("    Status : sc.exe query iSmartBackend");
    log("    Remove : sc.exe delete iSmartBackend");
    log("    Logs   : Get-Content <DataDir>\\logs\\stdout.log -Wait");
  } else if (IS_LINUX) {
    log(`  ${BOLD}Service management:${RESET}`);
    log("    sudo systemctl status  ismart-backend");
    log("    sudo systemctl start   ismart-backend");
    log("    sudo systemctl stop    ismart-backend");
    log("    sudo systemctl restart ismart-backend");
    log(`    sudo tail -f ${logsDir}/stdout.log`);
  }

  log("");
  return 0;
}

module.exports = { runInstaller };
