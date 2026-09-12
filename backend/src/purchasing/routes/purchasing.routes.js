const express = require("express");
const purchasingController = require("../controllers/purchasing.controller");
const { requireAuth } = require("../../middleware/auth.middleware");
const { requirePermission } = require("../../middleware/permission.middleware");

const router = express.Router();

router.use((req, res, next) => require("../../middleware/auth.middleware").requireAuth(req, res, next));

router.get(
  "/",
  requirePermission("canViewPurchaseRequests"),
  purchasingController.getPurchaseRequests
);

router.post(
  "/",
  requirePermission("canCreatePurchaseRequests"),
  purchasingController.createPurchaseRequest
);

router.get(
  "/:id",
  requirePermission("canViewPurchaseRequests"),
  purchasingController.getPurchaseRequestById
);

router.patch(
  "/:id",
  requirePermission("canUpdateDraftPurchaseRequests"),
  purchasingController.updatePurchaseRequest
);

router.post(
  "/:id/submit",
  requirePermission("canSubmitPurchaseRequests"),
  purchasingController.submitPurchaseRequest
);

router.post(
  "/:id/it-approve",
  requirePermission("canApproveItManagerPurchaseRequests"),
  purchasingController.itApprove
);

router.post(
  "/:id/audit-acknowledge",
  requirePermission("canReviewAuditPurchaseRequests"),
  purchasingController.auditAcknowledge
);

router.post(
  "/:id/audit-approve",
  requirePermission("canApproveAuditPurchaseRequests"),
  purchasingController.auditApprove
);

router.post(
  "/:id/finance-approve",
  requirePermission("canApproveFinancePurchaseRequests"),
  purchasingController.financeApprove
);

router.post(
  "/:id/send-to-purchasing",
  requirePermission("canSendToPurchasing"),
  purchasingController.sendToPurchasing
);

router.post(
  "/:id/mark-ordered",
  requirePermission("canMarkOrderedPurchaseRequests"),
  purchasingController.markOrdered
);

router.post(
  "/:id/receive",
  requirePermission("canReceivePurchaseRequests"),
  purchasingController.receiveItems
);

router.post(
  "/:id/reject",
  requirePermission("canRejectPurchaseRequests"),
  purchasingController.rejectRequest
);

router.post(
  "/:id/return-for-edit",
  requirePermission("canUpdateDraftPurchaseRequests"),
  purchasingController.returnForEdit
);

router.post(
  "/:id/cancel",
  requirePermission("canCancelPurchaseRequests"),
  purchasingController.cancelRequest
);

router.post(
  "/:id/close",
  requirePermission("canClosePurchaseRequests"),
  purchasingController.closeRequest
);

module.exports = router;
