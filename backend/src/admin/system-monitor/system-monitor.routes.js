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
  getAllPolls,
  exportPollReport,
  seedPolls,
  createPoll,
  togglePollStatusController,
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
router.get("/polls", getAllPolls);
router.post("/polls", createPoll);
router.post("/polls/seed", seedPolls);
router.get("/polls/:id/export", exportPollReport);
router.patch("/polls/:id/toggle", togglePollStatusController);
router.patch("/polls/:id/toggle-status", togglePollStatusController);
router.get("/errors", getErrors);
router.delete("/errors", deleteAllErrors);
router.patch("/errors/:id/resolve", markErrorResolved);

module.exports = router;
