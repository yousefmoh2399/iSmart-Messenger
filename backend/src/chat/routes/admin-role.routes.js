const express = require("express");
const { body, param } = require("express-validator");
const { requireAuth } = require("../../middleware/auth.middleware");
const { requirePermission } = require("../../middleware/permission.middleware");
const validateRequest = require("../../middleware/validate.middleware");
const {
  getAdminRoles,
  createAdminRole,
  updateAdminRole,
} = require("../controllers/role.controller");

const router = express.Router();

router.use(requireAuth);
router.use(requirePermission("canManageRoles"));

router.get("/", getAdminRoles);
router.post(
  "/",
  [
    body("roleName")
      .trim()
      .notEmpty()
      .withMessage("اسم الدور مطلوب."),
    body("permissions")
      .optional()
      .isObject()
      .withMessage("الصلاحيات يجب أن تكون كائنًا (object)."),
  ],
  validateRequest,
  createAdminRole
);
router.put(
  "/:id",
  [
    param("id").isMongoId().withMessage("معرّف الدور غير صالح."),
    body("permissions").isObject().withMessage("الصلاحيات مطلوبة."),
    body("permissions.canCreateUsers").optional().isBoolean(),
    body("permissions.canCreateDepartments").optional().isBoolean(),
    body("permissions.canCreateRooms").optional().isBoolean(),
    body("permissions.canSendBroadcast").optional().isBoolean(),
    body("permissions.canDeleteMessages").optional().isBoolean(),
    body("permissions.canUploadFiles").optional().isBoolean(),
    body("permissions.canModerateDepartment").optional().isBoolean(),
    body("permissions.canViewDepartmentLogs").optional().isBoolean(),
    body("permissions.canManageAnnouncements").optional().isBoolean(),
    body("permissions.canManageFiles").optional().isBoolean(),
    body("permissions.canManageBranches").optional().isBoolean(),
    body("permissions.canManageRoles").optional().isBoolean(),
    body("permissions.canManageSystem").optional().isBoolean(),
    body("permissions.canManageUpdates").optional().isBoolean(),
    body("permissions.canManageBackups").optional().isBoolean(),
    body("permissions.canManageTickets").optional().isBoolean(),
    body("permissions.canViewSnipeit").optional().isBoolean(),
  ],
  validateRequest,
  updateAdminRole
);

module.exports = router;
