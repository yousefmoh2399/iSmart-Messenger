const express = require("express");
const { getAppSettingsHandler } = require("../admin/app-settings/app-settings.controller");

const router = express.Router();

router.get("/", getAppSettingsHandler);

module.exports = router;
