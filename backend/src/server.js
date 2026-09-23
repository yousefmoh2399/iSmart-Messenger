const { TextEncoder, TextDecoder } = require("text-encoding");
const util = require("util");
global.TextEncoder = TextEncoder;
global.TextDecoder = TextDecoder;
util.TextEncoder = TextEncoder;
util.TextDecoder = TextDecoder;

// ─── CLI argument handling ────────────────────────────────────────────────────
// Supported flags:
//   --install           Run the interactive setup wizard (installs as a service)
//   --uninstall         Remove the installed service
//   --config <path>     Load settings from a JSON file (used when running as service)
//
// The service registered by --install passes --config automatically.
// No external tools (NSSM etc.) are needed.

const args = process.argv.slice(2);

// --config: load a JSON config file into process.env BEFORE env.js runs
const configArgIdx = args.indexOf("--config");
if (configArgIdx !== -1 && args[configArgIdx + 1]) {
  const configPath = args[configArgIdx + 1];
  try {
    const fs = require("fs");
    if (fs.existsSync(configPath)) {
      const fileConfig = JSON.parse(fs.readFileSync(configPath, "utf8"));
      for (const [key, value] of Object.entries(fileConfig)) {
        if (process.env[key] === undefined) {
          process.env[key] = String(value);
        }
      }
    }
  } catch (e) {
    // eslint-disable-next-line no-console
    console.error(`[server] Failed to load --config file: ${e.message}`);
  }
}

// ─── Server dependencies (loaded after env vars are set) ──────────────────────
const http     = require("http");
const app      = require("./app");
const { connectDatabase }            = require("./config/database");
const { host, port }                 = require("./config/env");
const { ensureDefaultRoles }         = require("./chat/services/role.service");
const { ensureDirectoryIndexes }     = require("./chat/services/directory-index.service");
const { initializeChatSocketServer } = require("./chat/sockets/chat.socket");
const { closeRedisClient }           = require("./config/redis");
const logger                         = require("./utils/logger");
const mongoose                       = require("mongoose");
const { ensureBootstrapAdmins }      = require("./services/bootstrap-admin.service");
const {
  startPrinterScheduler,
  stopPrinterScheduler,
} = require("./printers/services/printer-scheduler.service");

// ─── Server ───────────────────────────────────────────────────────────────────

let serverRef = null;

async function startServer() {
  await connectDatabase();
  await ensureDefaultRoles();
  await ensureDirectoryIndexes();
  await ensureBootstrapAdmins();

  const server = http.createServer(app);
  serverRef = server;

  // Allow large file downloads to complete without connection being closed.
  // Node's default keepAliveTimeout is 5s which causes "Connection closed while
  // receiving data" errors on slow or large downloads behind reverse proxies.
  server.keepAliveTimeout = 120_000; // 2 minutes
  server.headersTimeout   = 125_000; // must be > keepAliveTimeout

  const io = initializeChatSocketServer(server);
  app.set("io", io);
  startPrinterScheduler();

  const { startMessageScheduler } = require("./services/scheduler.service");
  startMessageScheduler(io);

  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, () => {
      server.off("error", reject);
      logger.info("server.listening", { host, port });
      resolve();
    });
  });
}

async function shutdown(signal) {
  logger.info("server.shutdown.start", { signal });
  try { stopPrinterScheduler(); } catch (_) {}
  try {
    if (serverRef) {
      await new Promise((resolve) => serverRef.close(() => resolve()));
    }
  } catch (_) {}
  try { await closeRedisClient(); } catch (_) {}
  try { await mongoose.connection.close(false); } catch (_) {}
  logger.info("server.shutdown.done", { signal });
  process.exit(0);
}

process.on("SIGINT",  () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

process.on("unhandledRejection", (reason) => {
  logger.error("server.unhandledRejection", {
    reason: reason?.message || String(reason),
    stack:  reason?.stack,
  });
});

// ─── Entry point ──────────────────────────────────────────────────────────────

if (args.includes("--install") || args.includes("--uninstall")) {
  // Delegate to the installer module
  const { runInstaller } = require("./installer");
  runInstaller(args.includes("--uninstall"))
    .then((code) => process.exit(code ?? 0))
    .catch((e) => {
      // eslint-disable-next-line no-console
      console.error("Installation failed:", e.message);
      process.exit(1);
    });
} else {
  // Normal server mode
  startServer().catch((error) => {
    logger.error("server.start.failed", { message: error?.message, stack: error?.stack });
    process.exit(1);
  });
}
