const cron = require("node-cron");
const logger = require("../../utils/logger");
const { startFullSync } = require("./printer.service");

let scheduledTask = null;

function startPrinterScheduler() {
  if (scheduledTask) return;

  // Poll at 00:25 for daily snapshot, and during off-peak minutes (09:25, 13:25, 16:25, 17:25)
  // so branch SNMP/HTTP printer scans never collide with the 09:00 AM morning login surge over VPNs.
  const cronExpression = process.env.PRINTER_SYNC_CRON || "25 0,9,13,16,17 * * *";
  // D3: Retry on transient SNMP / network failures (up to 2 retries, 30s apart)
  const MAX_RETRIES = 2;
  const RETRY_DELAY_MS = 30_000;

  scheduledTask = cron.schedule(
    cronExpression,
    async () => {
      let lastError;
      for (let attempt = 1; attempt <= MAX_RETRIES + 1; attempt++) {
        try {
          logger.info("printers.sync.scheduled.start", { cron: cronExpression, attempt });
          // D5: Use startFullSync (guarded) instead of fullSync (raw) to prevent
          // overlapping with a manually-triggered sync and enable progress tracking.
          await startFullSync(null);
          logger.info("printers.sync.scheduled.done", { attempt });
          return;
        } catch (error) {
          lastError = error;
          logger.warn("printers.sync.scheduled.attempt_failed", {
            attempt,
            maxRetries: MAX_RETRIES,
            message: error?.message,
          });
          if (attempt <= MAX_RETRIES) {
            await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS));
          }
        }
      }
      logger.error("printers.sync.scheduled.failed_all_retries", {
        message: lastError?.message,
        stack: lastError?.stack,
      });
    },
    { timezone: process.env.PRINTER_SYNC_TIMEZONE || "Africa/Cairo" },
  );
}

function stopPrinterScheduler() {
  if (!scheduledTask) return;
  scheduledTask.stop();
  scheduledTask = null;
}

module.exports = {
  startPrinterScheduler,
  stopPrinterScheduler,
};
