const express = require("express");
const rateLimit = require("express-rate-limit");
const { RedisStore } = require("rate-limit-redis");
const { body } = require("express-validator");
const {
  login,
  me,
  refresh,
  logout,
} = require("../controllers/auth.controller");
const validateRequest = require("../middleware/validate.middleware");
const { requireAuth } = require("../middleware/auth.middleware");
const { getRedisClient } = require("../config/redis");

const router = express.Router();

const redis = getRedisClient();
function buildStore(prefix) {
  if (!redis) return undefined;
  return new RedisStore({
    // rate-limit-redis expects a node-redis-like command interface.
    sendCommand: (...args) => redis.call(...args),
    prefix,
  });
}

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 25,
  standardHeaders: true,
  legacyHeaders: false,
  store: buildStore("rl:auth_login:"),
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
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
  store: buildStore("rl:auth_refresh:"),
  passOnStoreError: true,
  keyGenerator: (req) => {
    // We can't reliably bucket by user without verifying the refresh token here,
    // so use the requester IP.
    return `refresh_ip:${req.ip}`;
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
  ],
  validateRequest,
  refresh,
);

router.get("/me", requireAuth, me);

router.post(
  "/logout",
  requireAuth,
  [body("deviceUid").optional().isString().trim()],
  validateRequest,
  logout,
);

module.exports = router;
