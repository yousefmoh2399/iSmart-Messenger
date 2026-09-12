const express = require("express");
const { body, param } = require("express-validator");
const {
  createManagedDepartment,
  updateManagedDepartment,
  deleteManagedDepartment,
} = require("../controllers/department.controller");
const { requireAuth } = require("../../middleware/auth.middleware");
const { requirePermission } = require("../../middleware/permission.middleware");
const validateRequest = require("../../middleware/validate.middleware");

const router = express.Router();

router.use(requireAuth, requirePermission("canCreateDepartments"));

router.post(
  "/",
  [
    body("name").trim().notEmpty().withMessage("اسم القسم مطلوب."),
    body("code").trim().notEmpty().withMessage("كود القسم مطلوب."),
    body("description").optional().isString(),
    body("managers").optional().isArray(),
  ],
  validateRequest,
  createManagedDepartment
);

router.put(
  "/:id",
  [
    param("id").isMongoId().withMessage("معرّف القسم غير صالح."),
    body("name").optional().trim().notEmpty(),
    body("code").optional().trim().notEmpty(),
    body("description").optional().isString(),
    body("managers").optional().isArray(),
  ],
  validateRequest,
  updateManagedDepartment
);

router.delete(
  "/:id",
  [param("id").isMongoId().withMessage("معرّف القسم غير صالح.")],
  validateRequest,
  deleteManagedDepartment
);

module.exports = router;
