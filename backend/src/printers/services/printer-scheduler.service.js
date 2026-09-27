const cron = require("node-cron");
const logger = require("../../utils/logger");
const { fullSync } = require("./printer.service");
const { withDistributedLock } = require("../../utils/distributed-lock");

const SYNC_TIMEZONE = process.env.PRINTER_SYNC_TIMEZONE || "Africa/Cairo";
const DAILY_LOCK_TTL_MS = 23 * 60 * 60 * 1000; // 23 hours to prevent re-runs within the same day

function getDateKey(tz = SYNC_TIMEZONE) {
  try {
    return new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(new Date());
  } catch (_) {
    return new Date().toISOString().slice(0, 10);
  }
}

let scheduledTask = null;
let syncRetryTimeout = null;
let syncRetryCount = 0;
const MAX_SYNC_RETRIES = 3;
const RETRY_DELAY_MS = 5 * 60 * 1000; // 5 minutes backoff

async function runDailySync(isRetry = false) {
  const dateKey = getDateKey(SYNC_TIMEZONE);
  const outcome = await withDistributedLock(
    `cron:printer_daily_sync:${dateKey}`,
    DAILY_LOCK_TTL_MS,
    async () => {
      try {
        logger.info("printers.sync.daily.start", {
          dateKey,
          timezone: SYNC_TIMEZONE,
          isRetry,
          retryCount: syncRetryCount,
        });
        await fullSync(null);
        syncRetryCount = 0;
        logger.info("printers.sync.daily.done", { dateKey });
      } catch (error) {
        logger.error("printers.sync.daily.failed", {
          dateKey,
          message: error?.message,
          stack: error?.stack,
        });
        if (syncRetryCount < MAX_SYNC_RETRIES) {
          syncRetryCount++;
          logger.info("printers.sync.daily.scheduling_retry", {
            dateKey,
            nextAttempt: syncRetryCount,
            delayMs: RETRY_DELAY_MS,
          });
          syncRetryTimeout = setTimeout(() => {
            runDailySync(true).catch(() => {});
          }, RETRY_DELAY_MS);
          if (typeof syncRetryTimeout?.unref === "function") {
            syncRetryTimeout.unref();
          }
        }
        throw error; // Rethrow to trigger releaseOnError in withDistributedLock
      }
    },
    { fallbackToLocal: false, autoRelease: false, releaseOnError: true }
  );
  return outcome;
}

function startPrinterScheduler() {
  if (scheduledTask) return;
  scheduledTask = cron.schedule(
    "0 0 * * *",
    () => {
      runDailySync(false).catch(() => {});
    },
    { timezone: SYNC_TIMEZONE },
  );
}

function stopPrinterScheduler() {
  if (syncRetryTimeout) {
    clearTimeout(syncRetryTimeout);
    syncRetryTimeout = null;
  }
  if (!scheduledTask) return;
  scheduledTask.stop();
  scheduledTask = null;
}

module.exports = {
  startPrinterScheduler,
  stopPrinterScheduler,
  getDateKey,
  runDailySync,
};
