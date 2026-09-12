const express = require("express");
const { body, param } = require("express-validator");
const ApiError = require("../utils/api-error");
const {
  getUsers,
  createManagedUser,
  updateManagedUser,
  updateManagedUserStatus,
  resetManagedUserPassword,
  getMyProfile,
  updateMyProfile,
  uploadMyAvatar,
  registerMyPushDevice,
  unregisterMyPushDevice,
  downloadAvatar,
  logoutUserAllHandler,
  deleteUserHandler,
} = require("../controllers/user.controller");
const { requireAuth } = require("../middleware/auth.middleware");
const { requirePermission } = require("../middleware/permission.middleware");
const validateRequest = require("../middleware/validate.middleware");
const { avatarUpload } = require("../utils/avatar-upload");

const router = express.Router();

function normalizeActorRole(role) {
  return String(role || "user").trim().toLowerCase();
}

function requireUserManagementRead(req, res, next) {
  const role = normalizeActorRole(req.user?.role);
  if (
    role === "admin" ||
    role === "manager" ||
    req.user.permissions?.canCreateUsers === true
  ) {
    next();
    return;
  }

  next(new ApiError(403, "غير مسموح."));
}

function requireUserManagementWrite(req, res, next) {
  const role = normalizeActorRole(req.user?.role);
  if (role === "admin" || req.user.permissions?.canCreateUsers === true) {
    next();
    return;
  }

  next(new ApiError(403, "غير مسموح."));
}

router.get("/:id/avatar", downloadAvatar);

router.use(requireAuth);

router.get("/me", getMyProfile);

router.put(
  "/me",
  [
    body("fullName")
      .optional()
      .trim()
      .isLength({ min: 2, max: 120 })
      .withMessage("الاسم يجب أن يكون بين 2 و120 حرفًا."),
    body("password")
      .optional()
      .isLength({ min: 6 })
      .withMessage("كلمة المرور يجب ألا تقل عن 6 أحرف."),
    body("chatPreferences").optional().isObject(),
    body("chatPreferences.themeId").optional().isString(),
    body("chatPreferences.wallpaperId").optional().isString(),
    body("chatPreferences.customTheme").optional().isObject(),
    body("chatPreferences.customTheme.accentColorHex").optional().isString(),
    body("chatPreferences.customTheme.incomingBubbleColorHex")
      .optional()
      .isString(),
    body("chatPreferences.customTheme.outgoingBubbleColorHexes")
      .optional()
      .isArray({ min: 1, max: 2 }),
    body("chatPreferences.customTheme.wallpaperColorHexes")
      .optional()
      .isArray({ min: 2, max: 4 }),
  ],
  validateRequest,
  updateMyProfile,
);

router.post("/me/avatar", avatarUpload.single("avatar"), uploadMyAvatar);

router.post(
  "/me/push-devices",
  [
    body("token")
      .isString()
      .trim()
      .notEmpty()
      .withMessage("رمز الإشعارات مطلوب."),
    body("platform")
      .optional()
      .isIn(["android", "ios", "unknown"])
      .withMessage("نوع المنصة يجب أن يكون Android أو iOS."),
    body("deviceId").optional().isString(),
    body("deviceName").optional().isString(),
    body("appVersion").optional().isString(),
    body("notificationToneId")
      .optional()
      .isIn(["default", "chime", "alert", "silent"])
      .withMessage("نغمة الإشعارات غير صالحة."),
  ],
  validateRequest,
  registerMyPushDevice,
);

router.delete(
  "/me/push-devices",
  [
    body("token")
      .isString()
      .trim()
      .notEmpty()
      .withMessage("رمز الإشعارات مطلوب."),
  ],
  validateRequest,
  unregisterMyPushDevice,
);

router.get("/", requireUserManagementRead, getUsers);

router.post(
  "/",
  requirePermission("canCreateUsers"),
  [
    body("username")
      .trim()
      .notEmpty()
      .withMessage("اسم المستخدم مطلوب.")
      .isLength({ min: 3, max: 50 })
      .withMessage("اسم المستخدم يجب أن يكون بين 3 و50 حرفًا."),
    body("password")
      .notEmpty()
      .withMessage("كلمة المرور مطلوبة.")
      .isLength({ min: 6 })
      .withMessage("كلمة المرور يجب ألا تقل عن 6 أحرف."),
    body("fullName")
      .trim()
      .notEmpty()
      .withMessage("الاسم مطلوب.")
      .isLength({ min: 2, max: 120 })
      .withMessage("الاسم يجب أن يكون بين 2 و120 حرفًا."),
    body("role")
      .optional()
      .isIn(["user", "manager", "admin"])
      .withMessage("الوظيفة يجب أن تكون user أو manager أو admin."),
    body("departmentId")
      .optional({ nullable: true })
      .isMongoId()
      .withMessage("معرّف القسم غير صالح."),
    body("departmentIds")
      .optional()
      .isArray()
      .withMessage("الأقسام يجب أن تكون قائمة."),
    body("departmentIds.*")
      .optional()
      .isMongoId()
      .withMessage("معرّف قسم غير صالح."),
    body("branchId")
      .optional({ nullable: true })
      .isMongoId()
      .withMessage("معرّف الفرع غير صالح."),
    body("permissions").optional().isObject(),
  ],
  validateRequest,
  createManagedUser,
);

router.put(
  "/:id",
  requireUserManagementRead,
  [
    param("id").isMongoId().withMessage("معرّف المستخدم غير صالح."),
    body("username")
      .optional()
      .trim()
      .isLength({ min: 3, max: 50 })
      .withMessage("اسم المستخدم يجب أن يكون بين 3 و50 حرفًا."),
    body("password")
      .optional()
      .isLength({ min: 6 })
      .withMessage("كلمة المرور يجب ألا تقل عن 6 أحرف."),
    body("fullName")
      .optional()
      .trim()
      .isLength({ min: 2, max: 120 })
      .withMessage("الاسم يجب أن يكون بين 2 و120 حرفًا."),
    body("role")
      .optional()
      .isIn(["user", "manager", "admin"])
      .withMessage("الوظيفة يجب أن تكون user أو manager أو admin."),
    body("departmentId")
      .optional({ nullable: true })
      .isMongoId()
      .withMessage("معرّف القسم غير صالح."),
    body("departmentIds")
      .optional()
      .isArray()
      .withMessage("الأقسام يجب أن تكون قائمة."),
    body("departmentIds.*")
      .optional()
      .isMongoId()
      .withMessage("معرّف قسم غير صالح."),
    body("branchId")
      .optional({ nullable: true })
      .isMongoId()
      .withMessage("معرّف الفرع غير صالح."),
    body("permissions").optional().isObject(),
  ],
  validateRequest,
  updateManagedUser,
);

router.patch(
  "/:id/status",
  requireUserManagementWrite,
  [
    param("id").isMongoId().withMessage("معرّف المستخدم غير صالح."),
    body("isActive")
      .isBoolean()
      .withMessage("حالة التفعيل يجب أن تكون true/false."),
  ],
  validateRequest,
  updateManagedUserStatus,
);

router.patch(
  "/:id/reset-password",
  requireUserManagementWrite,
  [
    param("id").isMongoId().withMessage("معرّف المستخدم غير صالح."),
    body("password")
      .isLength({ min: 6 })
      .withMessage("كلمة المرور يجب ألا تقل عن 6 أحرف."),
  ],
  validateRequest,
  resetManagedUserPassword,
);

router.post(
  "/:id/logout-all",
  requireUserManagementWrite,
  [param("id").isMongoId().withMessage("معرّف المستخدم غير صالح.")],
  validateRequest,
  logoutUserAllHandler,
);

router.delete(
  "/:id",
  requireUserManagementWrite,
  [param("id").isMongoId().withMessage("معرّف المستخدم غير صالح.")],
  validateRequest,
  deleteUserHandler,
);

module.exports = router;
