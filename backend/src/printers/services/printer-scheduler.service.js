const cron = require("node-cron");
const logger = require("../../utils/logger");
const { fullSync } = require("./printer.service");

let scheduledTask = null;

function startPrinterScheduler() {
  if (scheduledTask) return;
  scheduledTask = cron.schedule(
    "0 0 * * *",
    async () => {
      try {
        logger.info("printers.sync.daily.start");
        await fullSync(null);
        logger.info("printers.sync.daily.done");
      } catch (error) {
        logger.error("printers.sync.daily.failed", {
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
