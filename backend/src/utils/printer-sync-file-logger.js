const fs = require("fs");
const path = require("path");

const { getBackendRoot } = require("./storage-paths");

const LOG_DIR = process.env.PRINTER_SYNC_LOG_DIR
  ? path.resolve(process.env.PRINTER_SYNC_LOG_DIR)
  : path.join(getBackendRoot(), "logs");

const LOG_FILE = path.join(LOG_DIR, "printer-sync.log");

function safeJson(value) {
  try {
    return JSON.stringify(value);
  } catch (_) {
    return JSON.stringify({ message: "unserializable" });
  }
}

function logPrinterSync(event, meta = {}) {
  const payload = {
    ts: new Date().toISOString(),
    event,
    ...meta,
  };
  const line = `${safeJson(payload)}\n`;

  try {
    fs.mkdirSync(LOG_DIR, { recursive: true });
    fs.appendFileSync(LOG_FILE, line, "utf8");
  } catch (_) {
    // Logging must never block or fail printer sync.
  }
}

module.exports = {
  LOG_FILE,
  logPrinterSync,
};
