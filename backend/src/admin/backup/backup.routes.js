const express = require("express");
const multer = require("multer");
const { body, param } = require("express-validator");
const { requireAuth } = require("../../middleware/auth.middleware");
const { requirePermission } = require("../../middleware/permission.middleware");
const validateRequest = require("../../middleware/validate.middleware");
const ApiError = require("../../utils/api-error");
const {
  restoreEmergencyAllowNonEmpty,
  restoreEmergencyToken,
} = require("../../config/env");
const User = require("../../models/user.model");
const { backupUpload } = require("./backup-upload");
const {
  createBackupArchive,
  listBackupArchives,
  restoreBackupArchive,
  restoreUploadedBackupArchive,
  emergencyRestoreUploadedBackupArchive,
  deleteBackupArchive,
  downloadBackupArchive,
  inspectBackupArchiveHandler,
} = require("./backup.controller");

const router = express.Router();

function timingSafeEquals(a, b) {
  const crypto = require("crypto");
  const left = Buffer.from(String(a || ""));
  const right = Buffer.from(String(b || ""));
  if (left.length !== right.length) {
    return false;
  }
  return crypto.timingSafeEqual(left, right);
}

async function requireEmergencyRestoreAccess(req, res, next) {
  try {
    if (!restoreEmergencyToken) {
      throw new ApiError(404, "Emergency restore is not configured.");
    }
    const providedToken =
      req.headers["x-restore-token"] ||
      req.body?.restoreToken ||
      req.query?.restoreToken;
    if (!timingSafeEquals(providedToken, restoreEmergencyToken)) {
      throw new ApiError(403, "Invalid emergency restore token.");
    }
    if (!restoreEmergencyAllowNonEmpty) {
      const usersCount = await User.estimatedDocumentCount();
      if (usersCount > 0) {
        throw new ApiError(
          403,
          "Emergency restore is only allowed when the users collection is empty.",
        );
      }
    }
    next();
  } catch (error) {
    next(error);
  }
}

router.post(
  "/emergency/restore-upload",
  backupUpload.single("backup"),
  handleMulterErrors,
  requireEmergencyRestoreAccess,
  [
    body("backupSizeBytes")
      .optional()
      .toInt()
      .isInt({ min: 1 })
      .withMessage("backupSizeBytes must be a positive number."),
    body("createSafetyBackup")
      .optional()
      .toBoolean()
      .isBoolean()
      .withMessage("createSafetyBackup must be true/false."),
  ],
  validateRequest,
  emergencyRestoreUploadedBackupArchive,
);

router.use(requireAuth, requirePermission("canManageBackups"));

router.post("/create", createBackupArchive);
router.get("/list", listBackupArchives);

router.post(
  "/restore",
  [
    body("backupFileName")
      .isString()
      .trim()
      .notEmpty()
      .withMessage("اسم ملف النسخة الاحتياطية مطلوب."),
    body("confirmRestore")
      .isBoolean()
      .withMessage("تأكيد الاستعادة يجب أن يكون true/false."),
    body("createSafetyBackup")
      .optional()
      .toBoolean()
      .isBoolean()
      .withMessage("createSafetyBackup must be true/false."),
  ],
  validateRequest,
  restoreBackupArchive,
);

function handleMulterErrors(err, req, res, next) {
  if (err instanceof multer.MulterError) {
    if (err.code === "LIMIT_FILE_SIZE") {
      return res.status(413).json({
        success: false,
        message: "Backup file exceeds maximum size of 5GB.",
      });
    }
    return res.status(400).json({
      success: false,
      message: `Upload error: ${err.message}`,
    });
  }
  if (err instanceof ApiError) {
    return res.status(err.statusCode || 400).json({
      success: false,
      message: err.message,
    });
  }
  if (err) {
    return res.status(500).json({
      success: false,
      message: `Upload failed: ${err.message}`,
    });
  }
  next();
}

router.post(
  "/restore-upload",
  backupUpload.single("backup"),
  handleMulterErrors,
  [
    body("confirmRestore")
      .optional()
      .toBoolean()
      .isBoolean()
      .withMessage("confirmRestore must be true/false."),
    body("backupSizeBytes")
      .optional()
      .toInt()
      .isInt({ min: 1 })
      .withMessage("backupSizeBytes must be a positive number."),
    body("createSafetyBackup")
      .optional()
      .toBoolean()
      .isBoolean()
      .withMessage("createSafetyBackup must be true/false."),
  ],
  validateRequest,
  restoreUploadedBackupArchive,
);

router.get(
  "/:id/verify",
  [
    param("id")
      .matches(/^[a-zA-Z0-9._-]+\.zip$/)
      .withMessage("Invalid backup file name."),
  ],
  validateRequest,
  inspectBackupArchiveHandler,
);

router.get(
  "/:id/download",
  [
    param("id")
      .matches(/^[a-zA-Z0-9._-]+\.zip$/)
      .withMessage("اسم ملف النسخة الاحتياطية غير صالح."),
  ],
  validateRequest,
  downloadBackupArchive,
);

router.delete(
  "/:id",
  [
    param("id")
      .matches(/^[a-zA-Z0-9._-]+\.zip$/)
      .withMessage("اسم ملف النسخة الاحتياطية غير صالح."),
  ],
  validateRequest,
  deleteBackupArchive,
);

module.exports = router;

