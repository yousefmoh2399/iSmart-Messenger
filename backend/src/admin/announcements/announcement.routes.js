const express = require("express");
const { body, param } = require("express-validator");
const {
  getAnnouncements,
  createManagedAnnouncement,
  updateManagedAnnouncement,
  updateManagedAnnouncementStatus,
  deleteManagedAnnouncement,
} = require("./announcement.controller");
const { requireAuth } = require("../../middleware/auth.middleware");
const { requirePermission } = require("../../middleware/permission.middleware");
const validateRequest = require("../../middleware/validate.middleware");

const router = express.Router();

router.use(requireAuth);

router.get("/", getAnnouncements);

router.post(
  "/",
  requirePermission("canManageAnnouncements"),
  [
    body("title")
      .trim()
      .isLength({ min: 2, max: 140 })
      .withMessage("عنوان الإعلان يجب أن يكون بين 2 و140 حرفًا."),
    body("message")
      .trim()
      .isLength({ min: 4, max: 4000 })
      .withMessage("نص الإعلان يجب أن يكون بين 4 و4000 حرف."),
    body("tone")
      .optional()
      .isIn(["info", "success", "warning", "critical"])
      .withMessage("نوع الإعلان غير صالح."),
    body("isPinned").optional().isBoolean(),
    body("isActive").optional().isBoolean(),
    body("startsAt").optional({ nullable: true }).isISO8601(),
    body("endsAt").optional({ nullable: true }).isISO8601(),
  ],
  validateRequest,
  createManagedAnnouncement
);

router.put(
  "/:id",
  requirePermission("canManageAnnouncements"),
  [
    param("id").isMongoId().withMessage("معرّف الإعلان غير صالح."),
    body("title").optional().trim().isLength({ min: 2, max: 140 }),
    body("message").optional().trim().isLength({ min: 4, max: 4000 }),
    body("tone").optional().isIn(["info", "success", "warning", "critical"]),
    body("isPinned").optional().isBoolean(),
    body("isActive").optional().isBoolean(),
    body("startsAt").optional({ nullable: true }).isISO8601(),
    body("endsAt").optional({ nullable: true }).isISO8601(),
  ],
  validateRequest,
  updateManagedAnnouncement
);

router.patch(
  "/:id/status",
  requirePermission("canManageAnnouncements"),
  [
    param("id").isMongoId().withMessage("معرّف الإعلان غير صالح."),
    body("isActive").isBoolean().withMessage("حالة التفعيل يجب أن تكون true/false."),
  ],
  validateRequest,
  updateManagedAnnouncementStatus
);

router.delete(
  "/:id",
  requirePermission("canManageAnnouncements"),
  [param("id").isMongoId().withMessage("معرّف الإعلان غير صالح.")],
  validateRequest,
  deleteManagedAnnouncement
);

module.exports = router;
