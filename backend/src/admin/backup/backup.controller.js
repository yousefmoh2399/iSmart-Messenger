const fs = require("fs/promises");
const asyncHandler = require("../../utils/async-handler");
const logger = require("../../utils/logger");
const {
  createBackup,
  listBackups,
  restoreBackup,
  deleteBackup,
  getBackupForDownload,
  inspectBackupArchive,
  verifyBackupArchive,
} = require("./backup.service");

const createBackupArchive = asyncHandler(async (req, res) => {
  const backup = await createBackup(req.user);
  res.status(201).json({
    success: true,
    data: { backup },
    message: "Backup created successfully.",
  });
});

const listBackupArchives = asyncHandler(async (req, res) => {
  const backups = await listBackups();
  res.status(200).json({
    success: true,
    data: { backups },
    message: "Backups retrieved successfully.",
  });
});

const restoreBackupArchive = asyncHandler(async (req, res) => {
  const result = await restoreBackup(req.user, {
    backupFileName: req.body.backupFileName,
    confirmRestore: req.body.confirmRestore,
    createSafetyBackup: req.body.createSafetyBackup !== false,
  });
  res.status(200).json({
    success: true,
    data: result,
    message: "Backup restored successfully.",
  });
});

async function handleRestoreUploadedBackup(req, res) {
  if (!req.file || !req.file.filename) {
    logger.warn("Backup upload: No file provided");
    return res.status(400).json({
      success: false,
      message: "Backup file is required.",
    });
  }

  const filePath = req.file.path;
  const expectedBytes = Number(req.body.backupSizeBytes || 0);

  // Verify the file was actually written to disk
  try {
    const stats = await fs.stat(filePath);
    logger.info("Backup upload: File verified", {
      filename: req.file.filename,
      diskSize: stats.size,
      expectedSize: req.file.size,
    });

    if (stats.size === 0) {
      await fs.unlink(filePath).catch(() => {});
      logger.error("Backup upload: Uploaded file is empty", {
        filename: req.file.filename,
      });
      return res.status(400).json({
        success: false,
        message: "Uploaded file is empty. Upload may have failed.",
      });
    }

    if (Math.abs(stats.size - req.file.size) > 1024) {
      // Allow 1KB difference
      logger.warn("Backup upload: Size mismatch detected", {
        filename: req.file.filename,
        expectedSize: req.file.size,
        actualSize: stats.size,
        difference: stats.size - req.file.size,
      });
    }

    if (expectedBytes > 0 && stats.size !== expectedBytes) {
      logger.warn("Backup upload: Client size mismatch", {
        filename: req.file.filename,
        expectedBytes,
        actualSize: stats.size,
      });
      await fs.unlink(filePath).catch(() => {});
      return res.status(400).json({
        success: false,
        message: "Backup upload is incomplete. Please re-upload the file.",
      });
    }

    await verifyBackupArchive(filePath);
  } catch (error) {
    logger.error("Backup upload: File verification failed", {
      filename: req.file.filename,
      error: error.message,
    });
    await fs.unlink(filePath).catch(() => {});
    return res.status(400).json({
      success: false,
      message: error.message || "Failed to verify uploaded file.",
    });
  }

  const result = await restoreBackup(req.user, {
    backupFileName: req.file.filename,
    confirmRestore: true,
    createSafetyBackup: req.body.createSafetyBackup !== false,
  });
  res.status(200).json({
    success: true,
    data: result,
    message: "Backup restored successfully.",
  });
}

const restoreUploadedBackupArchive = asyncHandler(handleRestoreUploadedBackup);

const emergencyRestoreUploadedBackupArchive = asyncHandler(async (req, res) => {
  req.user = req.user || {
    id: null,
    username: "emergency-restore",
    role: "admin",
    permissions: { canManageBackups: true },
  };
  return handleRestoreUploadedBackup(req, res);
});

const deleteBackupArchive = asyncHandler(async (req, res) => {
  const result = await deleteBackup(req.user, req.params.id);
  res.status(200).json({
    success: true,
    data: result,
    message: "Backup deleted successfully.",
  });
});

const downloadBackupArchive = asyncHandler(async (req, res) => {
  const backup = await getBackupForDownload(req.params.id);
  res.download(backup.absolutePath, backup.fileName);
});

const inspectBackupArchiveHandler = asyncHandler(async (req, res) => {
  const inspection = await inspectBackupArchive(req.params.id);
  res.status(200).json({
    success: true,
    data: { backup: inspection },
    message: "Backup verified successfully.",
  });
});

module.exports = {
  createBackupArchive,
  listBackupArchives,
  restoreBackupArchive,
  restoreUploadedBackupArchive,
  emergencyRestoreUploadedBackupArchive,
  deleteBackupArchive,
  downloadBackupArchive,
  inspectBackupArchiveHandler,
};
