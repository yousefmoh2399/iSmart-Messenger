const { TextEncoder, TextDecoder } = require("text-encoding");
const util = require("util");
global.TextEncoder = TextEncoder;
global.TextDecoder = TextDecoder;
util.TextEncoder = TextEncoder;
util.TextDecoder = TextDecoder;


const http = require("http");
const app = require("./app");

const { connectDatabase } = require("./config/database");
const { host, port } = require("./config/env");
const { ensureDefaultRoles } = require("./chat/services/role.service");
const { ensureDirectoryIndexes } = require("./chat/services/directory-index.service");
const { initializeChatSocketServer } = require("./chat/sockets/chat.socket");
const { closeRedisClient } = require("./config/redis");
const logger = require("./utils/logger");
const mongoose = require("mongoose");
const { ensureBootstrapAdmins } = require("./services/bootstrap-admin.service");
const { startPrinterScheduler, stopPrinterScheduler } = require("./printers/services/printer-scheduler.service");

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
  server.headersTimeout  = 125_000; // must be > keepAliveTimeout

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
  try {
    stopPrinterScheduler();
  } catch (_) {}
  try {
    if (serverRef) {
      await new Promise((resolve) => serverRef.close(() => resolve()));
    }
  } catch (_) {}
  try {
    await closeRedisClient();
  } catch (_) {}
  try {
    await mongoose.connection.close(false);
  } catch (_) {}
  logger.info("server.shutdown.done", { signal });
  process.exit(0);
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

process.on("unhandledRejection", (reason, promise) => {
  logger.error("server.unhandledRejection", {
    reason: reason?.message || String(reason),
    stack: reason?.stack,
  });
});

startServer().catch((error) => {
  logger.error("server.start.failed", { message: error?.message, stack: error?.stack });
  process.exit(1);
});
