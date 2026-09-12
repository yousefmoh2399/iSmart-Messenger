const express = require("express");
const { body, param } = require("express-validator");
const {
  listDocuments,
  uploadDocument,
  listPendingLocalSync,
  getDocument,
  downloadDocument,
  renameUserDocument,
  deleteUserDocument,
  confirmLocalSync,
} = require("../controllers/document.controller");
const { requireAuth } = require("../middleware/auth.middleware");
const validateRequest = require("../middleware/validate.middleware");
const { upload } = require("../config/multer");

const router = express.Router();

router.use(requireAuth);

router.get("/", listDocuments);

router.get("/pending-local-sync", listPendingLocalSync);

router.post(
  "/upload",
  upload.single("file"),
  [
    body("fileName").trim().notEmpty().withMessage("اسم الملف مطلوب."),
    body("pageCount")
      .notEmpty()
      .withMessage("عدد الصفحات مطلوب.")
      .isInt({ min: 1 })
      .withMessage("عدد الصفحات يجب ألا يقل عن 1."),
    body("fileSize")
      .optional()
      .isInt({ min: 1 })
      .withMessage("حجم الملف يجب أن يكون رقمًا صحيحًا موجبًا."),
  ],
  validateRequest,
  uploadDocument
);

router.get(
  "/:id",
  [param("id").isMongoId().withMessage("معرّف المستند غير صالح.")],
  validateRequest,
  getDocument
);

router.get(
  "/:id/download",
  [param("id").isMongoId().withMessage("معرّف المستند غير صالح.")],
  validateRequest,
  downloadDocument
);

router.put(
  "/:id/rename",
  [
    param("id").isMongoId().withMessage("معرّف المستند غير صالح."),
    body("fileName").trim().notEmpty().withMessage("اسم الملف مطلوب."),
  ],
  validateRequest,
  renameUserDocument
);

router.post(
  "/:id/local-sync",
  [param("id").isMongoId().withMessage("معرّف المستند غير صالح.")],
  validateRequest,
  confirmLocalSync
);

router.delete(
  "/:id",
  [param("id").isMongoId().withMessage("معرّف المستند غير صالح.")],
  validateRequest,
  deleteUserDocument
);

module.exports = router;
