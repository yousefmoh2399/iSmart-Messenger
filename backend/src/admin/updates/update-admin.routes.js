const express = require("express");
const { body, param, query } = require("express-validator");
const { requireAuth } = require("../../middleware/auth.middleware");
const { requirePermission } = require("../../middleware/permission.middleware");
const validateRequest = require("../../middleware/validate.middleware");
const { releaseUpload } = require("./release-upload");
const {
  listManagedDevices,
  toggleManagedDevice,
  createManagedRelease,
  listManagedReleases,
  patchManagedRelease,
  removeManagedRelease,
  createManagedUpdateJob,
  listManagedUpdateJobs,
  getManagedUpdateJob,
  cancelManagedUpdateJob,
} = require("./update.controller");

const router = express.Router();

router.use(requireAuth, requirePermission("canManageUpdates"));

router.get(
  "/devices",
  [
    query("status")
      .optional()
      .isIn(["all", "online", "offline"]),
    query("platform")
      .optional()
      .isIn(["desktop_windows", "mobile_android"]),
    query("branchCode").optional().isString(),
    query("search").optional().isString(),
    query("page").optional().isInt({ min: 1, max: 100000 }),
    query("limit").optional().isInt({ min: 1, max: 200 }),
  ],
  validateRequest,
  listManagedDevices
);

router.patch(
  "/devices/:id/active",
  [
    param("id").isMongoId().withMessage("معرّف الجهاز غير صالح."),
    body("isActive").isBoolean().withMessage("حالة التفعيل يجب أن تكون true/false."),
  ],
  validateRequest,
  toggleManagedDevice
);

router.get("/releases", listManagedReleases);

router.post(
  "/releases",
  releaseUpload.single("artifact"),
  [
    body("version")
      .isString()
      .trim()
      .notEmpty()
      .withMessage("رقم الإصدار مطلوب."),
    body("buildNumber").optional().isString(),
    body("channel").optional().isString(),
    body("notes").optional().isString(),
    body("mandatory").optional().isBoolean(),
    body("isEnabled").optional().isBoolean(),
    body("silentInstallArgs").optional().isString(),
    body("platform").optional().isIn(["desktop_windows", "mobile_android"]),
    body("installerKind").optional().isIn(["msi", "exe", "zip", "apk", "unknown"]),
    body("packageType").optional().isIn(["full", "delta"]),
    body("packageLayout").optional().isIn(["bundle_zip", "installer", "apk"]),
    body("entryExecutable").optional().isString(),
    body("minSupportedVersion").optional().isString(),
    body("targetArchitecture").optional().isString(),
    body("minWindowsBuild").optional().isString(),
    body("rolloutPercentage").optional().isInt({ min: 1, max: 100 }),
    body("checksumSha256").optional().isString(),
    body("externalDownloadUrl").optional().isString(),
  ],
  validateRequest,
  createManagedRelease
);

router.patch(
  "/releases/:id",
  [
    param("id").isMongoId().withMessage("معرّف الإصدار غير صالح."),
    body("channel").optional().isString(),
    body("notes").optional().isString(),
    body("mandatory").optional().isBoolean(),
    body("isEnabled").optional().isBoolean(),
    body("silentInstallArgs").optional().isString(),
    body("buildNumber").optional().isString(),
    body("packageType").optional().isIn(["full", "delta"]),
    body("packageLayout").optional().isIn(["bundle_zip", "installer", "apk"]),
    body("entryExecutable").optional().isString(),
    body("minSupportedVersion").optional().isString(),
    body("targetArchitecture").optional().isString(),
    body("minWindowsBuild").optional().isString(),
    body("rolloutPercentage").optional().isInt({ min: 1, max: 100 }),
  ],
  validateRequest,
  patchManagedRelease
);

router.delete(
  "/releases/:id",
  [param("id").isMongoId().withMessage("معرّف الإصدار غير صالح.")],
  validateRequest,
  removeManagedRelease
);

router.post(
  "/jobs",
  [
    body("releaseId")
      .isMongoId()
      .withMessage("معرّف الإصدار مطلوب."),
    body("targetType")
      .optional()
      .isIn(["all", "branch", "devices"]),
    body("targetBranches").optional().isArray(),
    body("targetDeviceIds").optional().isArray(),
    body("note").optional().isString(),
  ],
  validateRequest,
  createManagedUpdateJob
);

router.get(
  "/jobs",
  [
    query("page").optional().isInt({ min: 1, max: 100000 }),
    query("limit").optional().isInt({ min: 1, max: 200 }),
  ],
  validateRequest,
  listManagedUpdateJobs
);

router.get(
  "/jobs/:id",
  [
    param("id").isMongoId().withMessage("معرّف المهمة غير صالح."),
    query("tasksLimit").optional().isInt({ min: 1, max: 2000 }),
  ],
  validateRequest,
  getManagedUpdateJob
);

router.post(
  "/jobs/:id/cancel",
  [param("id").isMongoId().withMessage("معرّف المهمة غير صالح.")],
  validateRequest,
  cancelManagedUpdateJob
);

module.exports = router;
