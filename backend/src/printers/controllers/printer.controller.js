const asyncHandler = require("../../utils/async-handler");
const { sendChatResponse } = require("../../chat/utils/chat-response");
const {
  createBranch,
  deleteBranch,
  deletePrinter,
  discoverBranchPrinters,
  exportReport,
  fullSync,
  startFullSync,
  stopFullSync,
  getFullSyncStatus,
  getDashboard,
  getPrinterDetails,
  listBranches,
  listPrinters,
  listSyncLogs,
  syncPrinter,
  updateBranch,
  calculateMonthlyConsumption,
} = require("../services/printer.service");

const getDashboardHandler = asyncHandler(async (req, res) => {
  const dashboard = await getDashboard(req.query.branchId || null);
  sendChatResponse(res, { data: { dashboard }, legacy: { dashboard } });
});

const listBranchesHandler = asyncHandler(async (req, res) => {
  const branches = await listBranches();
  sendChatResponse(res, { data: { branches }, legacy: { branches } });
});

const createBranchHandler = asyncHandler(async (req, res) => {
  const branch = await createBranch(req.user, req.body);
  sendChatResponse(res, { status: 201, data: { branch }, legacy: { branch } });
});

const updateBranchHandler = asyncHandler(async (req, res) => {
  const branch = await updateBranch(req.params.id, req.body);
  sendChatResponse(res, { data: { branch }, legacy: { branch } });
});

const deleteBranchHandler = asyncHandler(async (req, res) => {
  const result = await deleteBranch(req.params.id);
  sendChatResponse(res, { data: result, legacy: result });
});

const discoverBranchHandler = asyncHandler(async (req, res) => {
  const result = await discoverBranchPrinters(req.user, req.params.id);
  sendChatResponse(res, { data: result, legacy: result });
});

const listPrintersHandler = asyncHandler(async (req, res) => {
  const printers = await listPrinters(req.query);
  sendChatResponse(res, { data: { printers }, legacy: { printers } });
});

const getPrinterHandler = asyncHandler(async (req, res) => {
  const data = await getPrinterDetails(req.params.id);
  sendChatResponse(res, { data, legacy: data });
});

const syncPrinterHandler = asyncHandler(async (req, res) => {
  const data = await syncPrinter(req.user, req.params.id);
  sendChatResponse(res, { data, legacy: data });
});

const deletePrinterHandler = asyncHandler(async (req, res) => {
  const result = await deletePrinter(req.params.id);
  sendChatResponse(res, { data: result, legacy: result });
});

const fullSyncHandler = asyncHandler(async (req, res) => {
  const result = await startFullSync(req.user);
  sendChatResponse(res, {
    status: result.started ? 202 : 200,
    data: result,
    legacy: result,
  });
});

const stopFullSyncHandler = asyncHandler(async (req, res) => {
  const result = await stopFullSync(req.user);
  sendChatResponse(res, { data: result, legacy: result });
});

const getFullSyncStatusHandler = asyncHandler(async (req, res) => {
  const status = await getFullSyncStatus();
  sendChatResponse(res, { data: { status }, legacy: { status } });
});

const listSyncLogsHandler = asyncHandler(async (req, res) => {
  const logs = await listSyncLogs();
  sendChatResponse(res, { data: { logs }, legacy: { logs } });
});

const getConsumptionHandler = asyncHandler(async (req, res) => {
  const result = await calculateMonthlyConsumption({
    branchId: req.query.branchId || null,
    printerId: req.query.printerId || null,
    fromMonth: req.query.fromMonth || null,
    fromYear: req.query.fromYear || null,
    toMonth: req.query.toMonth || null,
    toYear: req.query.toYear || null,
  });
  sendChatResponse(res, { data: result, legacy: result });
});

const exportReportHandler = asyncHandler(async (req, res) => {
  const { buffer, fileName } = await exportReport(req.user, {
    type: req.query.type === "printer" ? "printer" : req.query.type === "branch" ? "branch" : "global",
    format: req.query.format === "xlsx" ? "xlsx" : "pdf",
    branchId: req.query.branchId || null,
    printerId: req.query.printerId || null,
    fromMonth: req.query.fromMonth || null,
    fromYear: req.query.fromYear || null,
    toMonth: req.query.toMonth || null,
    toYear: req.query.toYear || null,
  });
  const isExcel = fileName.endsWith(".xlsx");
  res.setHeader(
    "Content-Type",
    isExcel
      ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      : "application/pdf",
  );
  res.setHeader("Content-Disposition", `attachment; filename="${fileName}"`);
  res.send(buffer);
});

module.exports = {
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
};
