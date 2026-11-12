const cron = require("node-cron");
const logger = require("../../utils/logger");
const { createBackup, listBackups, deleteBackup } = require("./backup.service");

let scheduledTask = null;

const DEFAULT_SCHEDULE = process.env.BACKUP_NIGHTLY_SCHEDULE || "0 2 * * *"; // Daily at 02:00 AM (after 1:00 AM)
const IS_ENABLED = String(process.env.BACKUP_NIGHTLY_ENABLED || "true").toLowerCase() !== "false";
const RETENTION_DAYS = Number(process.env.BACKUP_RETENTION_DAYS || 7);

async function pruneOldBackups(retentionDays) {
  try {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - retentionDays);

    const backups = await listBackups();
    if (!Array.isArray(backups)) {
      return;
    }

    for (const b of backups) {
      if (b && b.createdAt) {
        const backupDate = new Date(b.createdAt);
        if (backupDate < cutoffDate) {
          logger.info("[BackupScheduler] Pruning old backup past retention", {
            name: b.name,
            createdAt: b.createdAt,
            retentionDays,
          });
          await deleteBackup(b.name).catch((delErr) => {
            logger.warn("[BackupScheduler] Failed to prune old backup", {
              name: b.name,
              error: delErr.message,
            });
          });
        }
      }
    }
  } catch (err) {
    logger.warn("[BackupScheduler] Backup retention pruning error", {
      error: err.message,
    });
  }
}

async function runNightlyBackup() {
  logger.info("[BackupScheduler] Starting scheduled nightly full backup (Database + Uploads)...");
  try {
    const systemActor = {
      id: "system-nightly-scheduler",
      username: "System Nightly Backup",
      role: "admin",
    };

    const backup = await createBackup(systemActor);

    logger.info("[BackupScheduler] Nightly backup created successfully", {
      name: backup.name,
      size: backup.size,
      createdAt: backup.createdAt,
    });

    // Prune old backups older than configured retention period
    await pruneOldBackups(RETENTION_DAYS);
  } catch (error) {
    logger.error("[BackupScheduler] Scheduled nightly backup failed", {
      error: error.message,
      stack: error.stack,
    });
  }
}

function startBackupScheduler() {
  if (!IS_ENABLED) {
    logger.info("[BackupScheduler] Nightly backup scheduler is disabled via config");
    return;
  }
  if (scheduledTask) {
    return;
  }

  logger.info("[BackupScheduler] Initializing nightly backup scheduler", {
    schedule: DEFAULT_SCHEDULE,
    retentionDays: RETENTION_DAYS,
  });

  scheduledTask = cron.schedule(DEFAULT_SCHEDULE, () => {
    runNightlyBackup();
  });
}

function stopBackupScheduler() {
  if (scheduledTask) {
    scheduledTask.stop();
    scheduledTask = null;
    logger.info("[BackupScheduler] Stopped nightly backup scheduler");
  }
}

module.exports = {
  startBackupScheduler,
  stopBackupScheduler,
  runNightlyBackup,
};
