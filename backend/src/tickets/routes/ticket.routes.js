const express = require("express");
const { body, param, query } = require("express-validator");
const { requireAuth } = require("../../middleware/auth.middleware");
const { requireAdmin } = require("../../middleware/admin.middleware");
const validateRequest = require("../../middleware/validate.middleware");
const {
  getTickets,
  getTicketById,
  createNewTicket,
  addCommentToTicket,
  setTicketStatus,
  setTicketAssignee,
  getMyTicketSettings,
  saveTicketSettings,
  getSupportUsers,
  exportTicketsReport,
  getTicketDashboardStats,
  submitTicketRating,
  getDepartmentHandlers,
  updateDepartmentHandlers,
  getDepartmentHandlerAssignments,
} = require("../controllers/ticket.controller");

const router = express.Router();

router.use(requireAuth);

router.get(
  "/",
  [
    query("scope")
      .optional()
      .isIn(["mine", "assigned", "all", "department", "unassigned"])
      .withMessage("نطاق التذكرة غير صالح."),
    query("status")
      .optional()
      .isIn(["open", "assigned", "in_progress", "waiting_branch", "resolved", "closed"])
      .withMessage("حالة التذكرة غير صالحة."),
    query("priority")
      .optional()
      .isIn(["low", "normal", "high", "critical"])
      .withMessage("أولوية التذكرة غير صالحة."),
    query("q").optional().isString().isLength({ max: 200 }),
    query("limit").optional().isInt({ min: 1, max: 200 }),
  ],
  validateRequest,
  getTickets
);

router.post(
  "/",
  [
    body("title")
      .trim()
      .isLength({ min: 4, max: 220 })
      .withMessage("عنوان التذكرة مطلوب."),
    body("description")
      .trim()
      .isLength({ min: 4, max: 6000 })
      .withMessage("وصف التذكرة مطلوب."),
    body("priority")
      .optional()
      .isIn(["low", "normal", "high", "critical"])
      .withMessage("أولوية التذكرة غير صالحة."),
  ],
  validateRequest,
  createNewTicket
);

router.get("/settings", getMyTicketSettings);
router.get("/support-users", getSupportUsers);
router.get("/stats/dashboard", getTicketDashboardStats);

router.get(
  "/reports/export",
  [
    query("status")
      .optional()
      .isIn(["open", "assigned", "in_progress", "waiting_branch", "resolved", "closed"]),
    query("priority").optional().isIn(["low", "normal", "high", "critical"]),
    query("ticketType").optional().isIn(["ticket", "complaint", "suggestion"]),
    query("q").optional().isString().isLength({ max: 200 }),
  ],
  validateRequest,
  exportTicketsReport
);

router.put(
  "/settings",
  requireAdmin,
  [
    body("supportAgentIds").optional().isArray(),
    body("reportExporters").optional().isArray(),
    body("reportExporters.*.userId").optional().isMongoId(),
    body("reportExporters.*.ticketTypes").optional().isArray(),
    body("reportExporters.*.ticketTypes.*")
      .optional()
      .isIn(["ticket", "complaint", "suggestion"]),
  ],
  validateRequest,
  saveTicketSettings
);

router.get(
  "/:id",
  [param("id").isMongoId().withMessage("معرّف التذكرة غير صالح.")],
  validateRequest,
  getTicketById
);

router.post(
  "/:id/comments",
  [
    param("id").isMongoId().withMessage("معرّف التذكرة غير صالح."),
    body("message")
      .trim()
      .isLength({ min: 1, max: 6000 })
      .withMessage("التعليق مطلوب."),
    body("visibility")
      .optional()
      .isIn(["public", "internal"])
      .withMessage("نوع الظهور غير صالح."),
  ],
  validateRequest,
  addCommentToTicket
);

router.patch(
  "/:id/status",
  [
    param("id").isMongoId().withMessage("معرّف التذكرة غير صالح."),
    body("status")
      .isIn(["open", "assigned", "in_progress", "waiting_branch", "resolved", "closed"])
      .withMessage("حالة التذكرة غير صالحة."),
  ],
  validateRequest,
  setTicketStatus
);

router.patch(
  "/:id/assignee",
  [
    param("id").isMongoId().withMessage("معرّف التذكرة غير صالح."),
    body("assignedToId").optional({ nullable: true }).isMongoId(),
  ],
  validateRequest,
  setTicketAssignee
);

router.post(
  "/:id/rate",
  [
    param("id").isMongoId().withMessage("معرّف التذكرة غير صالح."),
    body("rating")
      .isInt({ min: 1, max: 5 })
      .withMessage("التقييم يجب أن يكون من 1 إلى 5."),
    body("feedback")
      .optional()
      .isString()
      .trim()
      .isLength({ max: 1000 })
      .withMessage("ملاحظات التقييم طويلة جداً."),
  ],
  validateRequest,
  submitTicketRating
);

router.get(
  "/settings/department-handler-assignments",
  [
    query("handlerType")
      .optional()
      .isIn(["ticket", "complaint", "suggestion"])
      .withMessage("نوع المسؤولين غير صالح."),
  ],
  validateRequest,
  getDepartmentHandlerAssignments
);

router.get(
  "/settings/departments/:departmentId/handlers",
  [
    param("departmentId").isMongoId().withMessage("معرّف القسم غير صالح."),
    query("handlerType")
      .optional()
      .isIn(["ticket", "complaint", "suggestion"])
      .withMessage("نوع المسؤولين غير صالح."),
  ],
  validateRequest,
  getDepartmentHandlers
);

router.put(
  "/settings/departments/:departmentId/handlers",
  requireAdmin,
  [
    param("departmentId").isMongoId().withMessage("معرّف القسم غير صالح."),
    body("handlerIds").isArray().withMessage("يجب إرسال قائمة من المعرفات."),
    body("handlerIds.*").isMongoId().withMessage("معرّف موظف غير صالح."),
    body("handlerType")
      .optional()
      .isIn(["ticket", "complaint", "suggestion"])
      .withMessage("نوع المسؤولين غير صالح."),
  ],
  validateRequest,
  updateDepartmentHandlers
);

module.exports = router;
