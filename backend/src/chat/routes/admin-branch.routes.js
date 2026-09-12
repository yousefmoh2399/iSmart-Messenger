const express = require("express");
const { body, param } = require("express-validator");
const {
  createManagedBranch,
  updateManagedBranch,
  deleteManagedBranch,
} = require("../controllers/branch.controller");
const { requireAuth } = require("../../middleware/auth.middleware");
const { requirePermission } = require("../../middleware/permission.middleware");
const validateRequest = require("../../middleware/validate.middleware");

const router = express.Router();

router.use(requireAuth, requirePermission("canManageBranches"));

router.post(
  "/",
  [
    body("name").trim().notEmpty().withMessage("اسم الفرع مطلوب."),
    body("code").trim().notEmpty().withMessage("كود الفرع مطلوب."),
    body("description").optional().isString(),
  ],
  validateRequest,
  createManagedBranch
);

router.put(
  "/:id",
  [
    param("id").isMongoId().withMessage("معرّف الفرع غير صالح."),
    body("name").optional().trim().notEmpty(),
    body("code").optional().trim().notEmpty(),
    body("description").optional().isString(),
  ],
  validateRequest,
  updateManagedBranch
);

router.delete(
  "/:id",
  [param("id").isMongoId().withMessage("معرّف الفرع غير صالح.")],
  validateRequest,
  deleteManagedBranch
);

module.exports = router;
