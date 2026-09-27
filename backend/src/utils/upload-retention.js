const fs = require("fs");
const path = require("path");
const { withDistributedLock } = require("./distributed-lock");

const DEFAULT_RETENTION_DAYS = 7;

function retentionMs(envKey) {
  const days = Number(process.env[envKey] || process.env.UPLOAD_RETENTION_DAYS);
  const resolvedDays =
    Number.isFinite(days) && days > 0 ? days : DEFAULT_RETENTION_DAYS;
  return resolvedDays * 24 * 60 * 60 * 1000;
}

function cleanupOldFiles(directoryPath, maxAgeMs) {
  const now = Date.now();
  try {
    if (!fs.existsSync(directoryPath)) return;
    for (const entry of fs.readdirSync(directoryPath, { withFileTypes: true })) {
      const entryPath = path.join(directoryPath, entry.name);
      if (entry.isDirectory()) {
        cleanupOldFiles(entryPath, maxAgeMs);
        try {
          if (fs.readdirSync(entryPath).length === 0) {
            fs.rmdirSync(entryPath);
          }
        } catch (_) {}
        continue;
      }
      if (!entry.isFile()) continue;
      const stat = fs.statSync(entryPath);
      if (now - stat.mtimeMs > maxAgeMs) {
        try {
          fs.unlinkSync(entryPath);
        } catch (err) {
          if (err.code !== "ENOENT") throw err;
        }
      }
    }
  } catch (error) {
    console.warn(`Upload retention cleanup failed: ${error.message}`);
  }
}

function scheduleUploadRetentionCleanup({
  directoryPath,
  envKey,
  intervalMs = 60 * 60 * 1000,
}) {
  const lockKey = `retention:${envKey || path.basename(directoryPath || "uploads")}`;
  const run = () => {
    withDistributedLock(lockKey, 10 * 60 * 1000, async () => {
      cleanupOldFiles(directoryPath, retentionMs(envKey));
    }).catch(() => {});
  };
  setTimeout(run, 30 * 1000).unref?.();
  const timer = setInterval(run, intervalMs);
  if (typeof timer.unref === "function") timer.unref();
}

module.exports = {
  cleanupOldFiles,
  retentionMs,
  scheduleUploadRetentionCleanup,
};
