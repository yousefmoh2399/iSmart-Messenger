const express = require("express");
const rateLimit = require("express-rate-limit");
const { body } = require("express-validator");
const {
  login,
  me,
  refresh,
  logout,
  getSessions,
  revokeSession,
  revokeOtherSessions,
} = require("../controllers/auth.controller");
const validateRequest = require("../middleware/validate.middleware");
const { requireAuth, optionalAuth } = require("../middleware/auth.middleware");
const { createRateLimitStore } = require("../config/rate-limit-store");

const router = express.Router();

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 25,
  standardHeaders: true,
  legacyHeaders: false,
  store: createRateLimitStore("rl:auth_login:"),
  passOnStoreError: true,
  keyGenerator: (req) => {
    const username = String(req.body?.username || "")
      .trim()
      .toLowerCase()
      .slice(0, 80);
    // Prefer per-username buckets to avoid a shared office IP blocking everyone.
    return username ? `login:${username}` : `login_ip:${req.ip}`;
  },
  message: {
    message: "تم تجاوز عدد محاولات تسجيل الدخول. حاول مرة أخرى بعد قليل.",
  },
});

const refreshLimiter = rateLimit({
  windowMs: 5 * 60 * 1000,
  max: (req) => (req.body?.deviceUid ? 60 : 600),
  standardHeaders: true,
  legacyHeaders: false,
  store: createRateLimitStore("rl:auth_refresh:"),
  passOnStoreError: true,
  keyGenerator: (req) => {
    // Key per (IP, deviceUid) when deviceUid is available so one shared branch NAT/VPN
    // gateway IP does not throttle 30-50 workstations signing in at peak morning hours.
    const deviceUid = String(req.body?.deviceUid || "")
      .trim()
      .slice(0, 80);
    return deviceUid
      ? `refresh_dev:${req.ip}:${deviceUid}`
      : `refresh_ip:${req.ip}`;
  },
  message: {
    message: "تم تجاوز عدد محاولات تحديث الجلسة. حاول مرة أخرى بعد قليل.",
  },
});

router.post(
  "/login",
  authLimiter,
  [
    body("username").trim().notEmpty().withMessage("اسم المستخدم مطلوب."),
    body("password").notEmpty().withMessage("كلمة المرور مطلوبة."),
    body("deviceUid").optional().isString().trim(),
    body("deviceName").optional().isString().trim(),
    body("platform").optional().isString().trim(),
    body("appVersion").optional().isString().trim(),
  ],
  validateRequest,
  login,
);

router.post(
  "/refresh",
  refreshLimiter,
  [
    body("refreshToken").notEmpty().withMessage("رمز تحديث الجلسة مطلوب."),
    body("deviceUid").optional().isString().trim(),
    body("deviceName").optional().isString().trim(),
    body("platform").optional().isString().trim(),
    body("appVersion").optional().isString().trim(),
  ],
  validateRequest,
  refresh,
);

router.get("/me", requireAuth, me);

router.get("/sessions", requireAuth, getSessions);

router.post(
  "/sessions/revoke-others",
  requireAuth,
  [
    body("currentDeviceUid").optional().isString().trim(),
    body("deviceUid").optional().isString().trim(),
  ],
  validateRequest,
  revokeOtherSessions,
);

router.delete("/sessions/:deviceUid", requireAuth, revokeSession);

router.post(
  "/logout",
  optionalAuth,
  [body("deviceUid").optional().isString().trim()],
  validateRequest,
  logout,
);

module.exports = router;
