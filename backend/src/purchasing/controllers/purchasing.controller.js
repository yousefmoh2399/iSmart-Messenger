const purchasingService = require("../services/purchasing.service");
const catchAsync = require("../../utils/async-handler");
const ApiError = require("../../utils/api-error");

exports.getPurchaseRequests = catchAsync(async (req, res) => {
  const requests = await purchasingService.getPurchaseRequests(req.query);
  res.status(200).json({ success: true, data: requests });
});

exports.getPurchaseRequestById = catchAsync(async (req, res) => {
  const request = await purchasingService.getPurchaseRequestById(req.params.id);
  if (!request) throw new ApiError(404, "Purchase request not found.");
  res.status(200).json({ success: true, data: request });
});

exports.createPurchaseRequest = catchAsync(async (req, res) => {
  const request = await purchasingService.createPurchaseRequest(req.user, req.body);
  res.status(201).json({ success: true, data: request });
});

exports.updatePurchaseRequest = catchAsync(async (req, res) => {
  const request = await purchasingService.updatePurchaseRequest(req.user, req.params.id, req.body);
  res.status(200).json({ success: true, data: request });
});

exports.submitPurchaseRequest = catchAsync(async (req, res) => {
  const request = await purchasingService.submitPurchaseRequest(req.user, req.params.id);
  res.status(200).json({ success: true, data: request });
});

exports.itApprove = catchAsync(async (req, res) => {
  const request = await purchasingService.itApprove(req.user, req.params.id);
  res.status(200).json({ success: true, data: request });
});

exports.auditAcknowledge = catchAsync(async (req, res) => {
  const request = await purchasingService.auditAcknowledge(req.user, req.params.id, req.body.refNo, req.body.notes);
  res.status(200).json({ success: true, data: request });
});

exports.auditApprove = catchAsync(async (req, res) => {
  const request = await purchasingService.auditApprove(req.user, req.params.id, req.body.refNo, req.body.notes);
  res.status(200).json({ success: true, data: request });
});

exports.financeApprove = catchAsync(async (req, res) => {
  const request = await purchasingService.financeApprove(req.user, req.params.id);
  res.status(200).json({ success: true, data: request });
});

exports.sendToPurchasing = catchAsync(async (req, res) => {
  const request = await purchasingService.sendToPurchasing(req.user, req.params.id);
  res.status(200).json({ success: true, data: request });
});

exports.markOrdered = catchAsync(async (req, res) => {
  const request = await purchasingService.markOrdered(req.user, req.params.id);
  res.status(200).json({ success: true, data: request });
});

exports.receiveItems = catchAsync(async (req, res) => {
  const result = await purchasingService.receiveItems(req.user, req.params.id, req.body);
  res.status(200).json({ success: true, data: result });
});

exports.rejectRequest = catchAsync(async (req, res) => {
  const request = await purchasingService.rejectRequest(req.user, req.params.id, req.body.reason);
  res.status(200).json({ success: true, data: request });
});

exports.returnForEdit = catchAsync(async (req, res) => {
  const request = await purchasingService.returnForEdit(req.user, req.params.id, req.body.reason);
  res.status(200).json({ success: true, data: request });
});

exports.cancelRequest = catchAsync(async (req, res) => {
  const request = await purchasingService.cancelRequest(req.user, req.params.id, req.body.reason);
  res.status(200).json({ success: true, data: request });
});

exports.closeRequest = catchAsync(async (req, res) => {
  const request = await purchasingService.closeRequest(req.user, req.params.id);
  res.status(200).json({ success: true, data: request });
});
