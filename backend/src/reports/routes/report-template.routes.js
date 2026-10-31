const express = require("express");
const { body, param, query } = require("express-validator");
const { requireAuth } = require("../../middleware/auth.middleware");
const validateRequest = require("../../middleware/validate.middleware");
const ApiError = require("../../utils/api-error");
const {
  listTemplatesHandler,
  getAvailableColumnsHandler,
  getTemplateByIdHandler,
  createTemplateHandler,
  updateTemplateHandler,
  deleteTemplateHandler,
  setDefaultTemplateHandler,
} = require("../controllers/report-template.controller");

const router = express.Router();

router.use(requireAuth);

function requireAdmin(req, res, next) {
  if (req.user?.role !== "admin") {
    return next(new ApiError(403, "Admins only."));
  }
  next();
}

router.get(
  "/available-columns",
  [
    query("reportType")
      .optional()
      .isIn(["printer_consumption", "tickets"]),
  ],
  validateRequest,
  getAvailableColumnsHandler,
);

router.get(
  "/",
  [
    query("reportType")
      .optional()
      .isIn(["printer_consumption", "tickets"]),
  ],
  validateRequest,
  listTemplatesHandler,
);

router.get(
  "/:id",
  [param("id").isMongoId()],
  validateRequest,
  getTemplateByIdHandler,
);

router.post(
  "/",
  requireAdmin,
  [
    body("name").trim().notEmpty().withMessage("Template name is required"),
    body("reportType")
      .isIn(["printer_consumption", "tickets"])
      .withMessage("Invalid reportType"),
    body("columns").optional().isArray(),
    body("headerConfig").optional().isObject(),
    body("options").optional().isObject(),
  ],
  validateRequest,
  createTemplateHandler,
);

router.put(
  "/:id",
  requireAdmin,
  [
    param("id").isMongoId(),
    body("name").optional().trim().notEmpty(),
    body("columns").optional().isArray(),
    body("headerConfig").optional().isObject(),
    body("options").optional().isObject(),
  ],
  validateRequest,
  updateTemplateHandler,
);

router.delete(
  "/:id",
  requireAdmin,
  [param("id").isMongoId()],
  validateRequest,
  deleteTemplateHandler,
);

router.post(
  "/:id/default",
  requireAdmin,
  [param("id").isMongoId()],
  validateRequest,
  setDefaultTemplateHandler,
);

module.exports = router;
