const cron = require("node-cron");
const logger = require("../../utils/logger");
const { fullSync } = require("./printer.service");

let scheduledTask = null;

function startPrinterScheduler() {
  if (scheduledTask) return;

  // Poll at midnight (00:00) for daily snapshot, and during business hours (09:00, 13:00, 16:30)
  // so branch printers that are powered off at night are reliably synced while active during workday.
  const cronExpression = process.env.PRINTER_SYNC_CRON || "0 0,9,13,16 * * *";

  scheduledTask = cron.schedule(
    cronExpression,
    async () => {
      try {
        logger.info("printers.sync.scheduled.start", { cron: cronExpression });
        await fullSync(null);
        logger.info("printers.sync.scheduled.done");
      } catch (error) {
        logger.error("printers.sync.scheduled.failed", {
          message: error?.message,
          stack: error?.stack,
        });
      }
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
