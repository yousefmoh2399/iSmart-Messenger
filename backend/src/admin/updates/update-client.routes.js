const express = require("express");
const rateLimit = require("express-rate-limit");
const { RedisStore } = require("rate-limit-redis");
const { body, param, query } = require("express-validator");
const { requireAuth } = require("../../middleware/auth.middleware");
const validateRequest = require("../../middleware/validate.middleware");
const { getRedisClient } = require("../../config/redis");
const {
  heartbeatDevice,
  reportTaskState,
  downloadReleaseArtifact,
  checkMobileUpdates,
  listAuthenticatedBranchPeers,
} = require("./update.controller");

const router = express.Router();

const redis = getRedisClient();
function buildStore(prefix) {
  if (!redis) return undefined;
  return new RedisStore({
    sendCommand: (...args) => redis.call(...args),
    prefix,
  });
}

const updateClientLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
  store: buildStore("rl:update_client:"),
  keyGenerator: (req) => {
    const deviceUid = String(req.body?.deviceUid || "")
      .trim()
      .slice(0, 160);
    return deviceUid ? `device:${deviceUid}` : `device_ip:${req.ip}`;
  },
  message: {
    message: "طلبات التحديث كثيرة جدًا. برجاء الإبطاء قليلًا.",
  },
});

const updateProgressLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 3000,
  standardHeaders: true,
  legacyHeaders: false,
  store: buildStore("rl:update_progress:"),
  keyGenerator: (req) => {
    const deviceUid = String(req.body?.deviceUid || "")
      .trim()
      .slice(0, 160);
    return `${req.params.taskId || "task"}:${deviceUid || req.ip}`;
  },
  message: {
    success: false,
    message: "Progress updates are arriving too quickly.",
  },
});

router.get(
  "/releases/:id/download",
  [param("id").isMongoId().withMessage("معرّف الإصدار غير صالح.")],
  validateRequest,
  downloadReleaseArtifact,
);

router.use(requireAuth);

router.post(
  "/devices/heartbeat",
  updateClientLimiter,
  [
    body("deviceUid")
      .isString()
      .trim()
      .notEmpty()
      .withMessage("معرّف الجهاز مطلوب."),
    body("deviceName").optional().isString(),
    body("hostName").optional().isString(),
    body("branchCode").optional().isString(),
    body("channel").optional().isString(),
    body("platform").optional().isIn(["desktop_windows", "mobile_android"]),
    body("appVersion").optional().isString(),
    body("osName").optional().isString(),
    body("osVersion").optional().isString(),
    body("architecture").optional().isString(),
    body("localIp").optional().isString(),
    body("connectionStatus")
      .optional()
      .isIn(["online", "idle", "meeting", "lunch", "offline"]),
    body("capabilities").optional().isObject(),
  ],
  validateRequest,
  heartbeatDevice,
);

router.post(
  "/tasks/:taskId/progress",
  updateProgressLimiter,
  [
    param("taskId").isMongoId().withMessage("معرّف المهمة غير صالح."),
    body("deviceUid")
      .isString()
      .trim()
      .notEmpty()
      .withMessage("معرّف الجهاز مطلوب."),
    body("status")
      .isIn([
        "pending",
        "acknowledged",
        "downloading",
        "installing",
        "completed",
        "failed",
        "cancelled",
      ])
      .withMessage("حالة المهمة غير صالحة."),
    body("progress").optional().isInt({ min: 0, max: 100 }),
    body("message").optional().isString(),
    body("connectionStatus")
      .optional()
      .isIn(["online", "idle", "meeting", "lunch", "offline"]),
  ],
  validateRequest,
  reportTaskState,
);

router.post(
  "/mobile/check",
  updateClientLimiter,
  [
    body("deviceUid")
      .isString()
      .trim()
      .notEmpty()
      .withMessage("معرّف الجهاز مطلوب."),
    body("currentVersion").optional().isString(),
    body("branchCode").optional().isString(),
    body("channel").optional().isString(),
  ],
  validateRequest,
  checkMobileUpdates,
);

router.get(
  "/branch-peers",
  [
    query("branchCode").optional().isString(),
    query("userId").optional().isMongoId(),
    query("includeSelf").optional().isIn(["true", "false"]),
  ],
  validateRequest,
  listAuthenticatedBranchPeers,
);

module.exports = router;
