const express = require("express");
const {
  getSystemStats,
  getConnections,
  getErrors,
  markErrorResolved,
  deleteAllErrors,
  getBranchesDeployment,
  getRequestTelemetry,
  exportDeploymentReport,
} = require("./system-monitor.controller");
const { requireAuth } = require("../../middleware/auth.middleware");
const { requirePermission } = require("../../middleware/permission.middleware");

const router = express.Router();

router.use(requireAuth, requirePermission("canViewSystemMonitor"));

router.get("/stats", getSystemStats);
router.get("/connections", getConnections);
router.get("/branches-deployment", getBranchesDeployment);
router.get("/request-telemetry", getRequestTelemetry);
router.get("/reports/export", exportDeploymentReport);
router.get("/errors", getErrors);
router.delete("/errors", deleteAllErrors);
router.patch("/errors/:id/resolve", markErrorResolved);

module.exports = router;
