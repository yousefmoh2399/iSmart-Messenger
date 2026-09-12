const express = require("express");
const { body, param, query } = require("express-validator");
const { requireAuth } = require("../../middleware/auth.middleware");
const validateRequest = require("../../middleware/validate.middleware");
const {
  requirePrinterAccess,
  requirePrinterManagement,
  requirePrinterReports,
  requirePrinterSync,
} = require("../services/printer-access.service");
const {
  createBranchHandler,
  deleteBranchHandler,
  deletePrinterHandler,
  discoverBranchHandler,
  exportReportHandler,
  fullSyncHandler,
  stopFullSyncHandler,
  getFullSyncStatusHandler,
  getDashboardHandler,
  getPrinterHandler,
  listBranchesHandler,
  listPrintersHandler,
  listSyncLogsHandler,
  syncPrinterHandler,
  updateBranchHandler,
  getConsumptionHandler,
} = require("../controllers/printer.controller");

const router = express.Router();

router.use(requireAuth);

function requirePrinterAccessMiddleware(req, res, next) {
  try {
    requirePrinterAccess(req.user);
    next();
  } catch (error) {
    next(error);
  }
}

function requirePrinterManagementMiddleware(req, res, next) {
  try {
    requirePrinterManagement(req.user);
    next();
  } catch (error) {
    next(error);
  }
}

function requirePrinterSyncMiddleware(req, res, next) {
  try {
    requirePrinterSync(req.user);
    next();
  } catch (error) {
    next(error);
  }
}

function requirePrinterReportsMiddleware(req, res, next) {
  try {
    requirePrinterReports(req.user);
    next();
  } catch (error) {
    next(error);
  }
}

router.get("/dashboard", requirePrinterAccessMiddleware, getDashboardHandler);
router.get("/branches", requirePrinterAccessMiddleware, listBranchesHandler);
router.post(
  "/branches",
  requirePrinterManagementMiddleware,
  [
    body("name").trim().notEmpty(),
    body("code").trim().notEmpty(),
    body("networkRange").trim().notEmpty(),
    body("location").optional().isString(),
    body("status").optional().isIn(["active", "inactive"]),
  ],
  validateRequest,
  createBranchHandler,
);
router.put(
  "/branches/:id",
  requirePrinterManagementMiddleware,
  [
    param("id").isMongoId(),
    body("name").optional().trim().notEmpty(),
    body("code").optional().trim().notEmpty(),
    body("networkRange").optional().trim().notEmpty(),
    body("location").optional().isString(),
    body("status").optional().isIn(["active", "inactive"]),
  ],
  validateRequest,
  updateBranchHandler,
);
router.delete(
  "/branches/:id",
  requirePrinterManagementMiddleware,
  [param("id").isMongoId()],
  validateRequest,
  deleteBranchHandler,
);
router.post(
  "/branches/:id/discover",
  requirePrinterSyncMiddleware,
  [param("id").isMongoId()],
  validateRequest,
  discoverBranchHandler,
);

router.get("/printers", requirePrinterAccessMiddleware, listPrintersHandler);
router.get(
  "/printers/:id",
  requirePrinterAccessMiddleware,
  [param("id").isMongoId()],
  validateRequest,
  getPrinterHandler,
);
router.post(
  "/printers/:id/sync",
  requirePrinterSyncMiddleware,
  [param("id").isMongoId()],
  validateRequest,
  syncPrinterHandler,
);
router.delete(
  "/printers/:id",
  requirePrinterManagementMiddleware,
  [param("id").isMongoId()],
  validateRequest,
  deletePrinterHandler,
);
router.post("/sync/full", requirePrinterSyncMiddleware, fullSyncHandler);
router.post("/sync/full/stop", requirePrinterSyncMiddleware, stopFullSyncHandler);
router.get("/sync/full/status", requirePrinterAccessMiddleware, getFullSyncStatusHandler);
router.get("/sync/logs", requirePrinterAccessMiddleware, listSyncLogsHandler);

router.get(
  "/consumption",
  requirePrinterAccessMiddleware,
  [
    query("branchId").optional().isMongoId(),
    query("printerId").optional().isMongoId(),
    query("month").optional().isInt({ min: 1, max: 12 }),
    query("year").optional().isInt({ min: 2000, max: 2100 }),
  ],
  validateRequest,
  getConsumptionHandler,
);

router.get(
  "/reports/export",
  requirePrinterReportsMiddleware,
  [
    query("type").optional().isIn(["branch", "global", "printer"]),
    query("format").optional().isIn(["pdf", "xlsx"]),
    query("branchId").optional().isMongoId(),
    query("printerId").optional().isMongoId(),
    query("month").optional().isInt({ min: 1, max: 12 }),
    query("year").optional().isInt({ min: 2000, max: 2100 }),
  ],
  validateRequest,
  exportReportHandler,
);

module.exports = router;
