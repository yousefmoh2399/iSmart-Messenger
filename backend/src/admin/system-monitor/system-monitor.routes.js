const express = require("express");
const { getConnections, getErrors, markErrorResolved } = require("./system-monitor.controller");
const { requireAuth } = require("../../middleware/auth.middleware");
const { requirePermission } = require("../../middleware/permission.middleware");

const router = express.Router();

router.use(requireAuth, requirePermission("canViewSystemMonitor"));

router.get("/connections", getConnections);
router.get("/errors", getErrors);
router.patch("/errors/:id/resolve", markErrorResolved);

module.exports = router;
