const express = require("express");
const { body } = require("express-validator");
const { requireAuth } = require("../../middleware/auth.middleware");
const { requireAdmin } = require("../../middleware/admin.middleware");
const validateRequest = require("../../middleware/validate.middleware");
const {
  getAppSettingsHandler,
  updateAppSettingsHandler,
} = require("./app-settings.controller");

const router = express.Router();

router.use(requireAuth, requireAdmin);

router.get("/", getAppSettingsHandler);

router.put(
  "/",
  [
    body("desktopBaseUrl").optional().isString(),
    body("mobileBaseUrl").optional().isString(),
    body("serverTargets").optional().isArray(),
    body("serverTargets.*.title").optional().isString(),
    body("serverTargets.*.baseUrl").optional().isString(),
    body("serverTargets.*.ports").optional().isArray(),
    body("showServersShortcut").optional().isBoolean(),
  ],
  validateRequest,
  updateAppSettingsHandler,
);

module.exports = router;
