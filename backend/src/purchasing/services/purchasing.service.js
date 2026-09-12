const mongoose = require("mongoose");
const PurchaseRequest = require("../models/purchase-request.model");
const PurchaseReceipt = require("../models/purchase-receipt.model");
const PrCounter = require("../models/pr-counter.model");
const ItAsset = require("../../it-assets/models/it-asset.model");
const ItSparePart = require("../../it-assets/models/spare-part.model");
const ItOperation = require("../../it-assets/models/it-operation.model");
const AuditLog = require("../../chat/models/audit-log.model");
const ApiError = require("../../utils/api-error");

async function generatePrNumber() {
  const currentYear = new Date().getFullYear();
  const counterId = `PR_${currentYear}`;
  const counter = await PrCounter.findByIdAndUpdate(
    counterId,
    { $inc: { sequence_value: 1 } },
    { new: true, upsert: true }
  );
  const seq = String(counter.sequence_value).padStart(6, "0");
  return `PR-${currentYear}-${seq}`;
}

async function addTimelineEvent(pr, action, actor, details = "") {
  pr.timeline.push({
    action,
    details,
    performedBy: actor.id,
    performedByName: actor.displayName || actor.name || actor.username || "System",
  });
}

async function logAudit(actor, action, recordId, newValues = {}, oldValues = {}) {
  try {
    await AuditLog.create({
      userId: actor.id,
      action,
      module: "PurchaseRequests",
      recordId,
      oldValues,
      newValues,
      ipAddress: actor.ipAddress || "",
      userAgent: actor.userAgent || "",
    });
  } catch (err) {
    console.error("Audit log failed:", err);
  }
}

function createSignature(actor, action) {
  return {
    userId: actor.id,
    userName: actor.displayName || actor.name || actor.username || "System",
    role: actor.role || "user",
    action,
    ipAddress: actor.ipAddress || "",
    userAgent: actor.userAgent || "",
  };
}

async function createPurchaseRequest(actor, data) {
  const prNo = await generatePrNumber();
  const pr = new PurchaseRequest({
    ...data,
    purchaseRequestNo: prNo,
    requestedBy: actor.id,
    status: "Draft",
  });

  await addTimelineEvent(pr, "Created", actor, "Purchase request created as draft.");
  await pr.save();
  await logAudit(actor, "create", pr._id, { prNo, status: "Draft" });
  return pr;
}

async function updatePurchaseRequest(actor, id, data) {
  const pr = await PurchaseRequest.findById(id);
  if (!pr) throw new ApiError(404, "Purchase request not found.");
  if (pr.status !== "Draft" && pr.status !== "Returned For Edit") {
    throw new ApiError(400, "Can only update draft or returned requests.");
  }
  
  Object.assign(pr, data);
  await addTimelineEvent(pr, "Updated", actor, "Purchase request updated.");
  await pr.save();
  await logAudit(actor, "update", pr._id, data);
  return pr;
}

async function submitPurchaseRequest(actor, id) {
  const pr = await PurchaseRequest.findById(id);
  if (!pr) throw new ApiError(404, "Purchase request not found.");
  if (pr.status !== "Draft" && pr.status !== "Returned For Edit") {
    throw new ApiError(400, "Can only submit draft or returned requests.");
  }
  if (!pr.items || pr.items.length === 0) {
    throw new ApiError(400, "Cannot submit without items.");
  }

  pr.status = "Pending IT Manager Approval";
  pr.submittedAt = new Date();
  pr.signatures.push(createSignature(actor, "Prepared By"));
  await addTimelineEvent(pr, "Submitted", actor, "Submitted for IT Manager approval.");
  
  await pr.save();
  await logAudit(actor, "submit", pr._id, { status: pr.status });
  return pr;
}

async function itApprove(actor, id) {
  const pr = await PurchaseRequest.findById(id);
  if (!pr) throw new ApiError(404, "Not found");
  if (pr.status !== "Pending IT Manager Approval") throw new ApiError(400, "Invalid status");

  pr.status = "Pending Audit Review";
  pr.itManagerApprovedBy = actor.id;
  pr.itManagerApprovedAt = new Date();
  pr.signatures.push(createSignature(actor, "IT Manager Approval"));
  await addTimelineEvent(pr, "IT Approved", actor, "Approved by IT Manager.");
  
  await pr.save();
  await logAudit(actor, "itApprove", pr._id, { status: pr.status });
  return pr;
}

async function auditAcknowledge(actor, id, refNo, notes) {
  const pr = await PurchaseRequest.findById(id);
  if (!pr) throw new ApiError(404, "Not found");
  
  pr.auditStatus = "Acknowledged";
  if (refNo) pr.auditReferenceNo = refNo;
  if (notes) pr.auditNotes = notes;
  
  await addTimelineEvent(pr, "Audit Acknowledged", actor, `Audit Reference: ${refNo}`);
  await pr.save();
  await logAudit(actor, "auditAcknowledge", pr._id, { auditStatus: pr.auditStatus, refNo });
  return pr;
}

async function auditApprove(actor, id, refNo, notes) {
  const pr = await PurchaseRequest.findById(id);
  if (!pr) throw new ApiError(404, "Not found");
  if (pr.status !== "Pending Audit Review") throw new ApiError(400, "Invalid status");

  pr.status = "Pending Finance/Admin Approval";
  pr.auditStatus = "Approved";
  if (refNo) pr.auditReferenceNo = refNo;
  if (notes) pr.auditNotes = notes;
  pr.auditReviewedBy = actor.id;
  pr.auditReviewedAt = new Date();
  pr.signatures.push(createSignature(actor, "Audit Review"));
  
  await addTimelineEvent(pr, "Audit Approved", actor, `Audit Reference: ${refNo || ''}`);
  await pr.save();
  await logAudit(actor, "auditApprove", pr._id, { status: pr.status });
  return pr;
}

async function financeApprove(actor, id) {
  const pr = await PurchaseRequest.findById(id);
  if (!pr) throw new ApiError(404, "Not found");
  if (pr.status !== "Pending Finance/Admin Approval") throw new ApiError(400, "Invalid status");

  pr.status = "Approved";
  pr.financeApprovedBy = actor.id;
  pr.financeApprovedAt = new Date();
  pr.signatures.push(createSignature(actor, "Finance/Admin Approval"));
  await addTimelineEvent(pr, "Finance Approved", actor, "Approved by Finance/Admin.");
  
  await pr.save();
  await logAudit(actor, "financeApprove", pr._id, { status: pr.status });
  return pr;
}

async function sendToPurchasing(actor, id) {
  const pr = await PurchaseRequest.findById(id);
  if (!pr) throw new ApiError(404, "Not found");
  if (pr.status !== "Approved") throw new ApiError(400, "Must be approved first");

  pr.status = "Sent To Purchasing";
  pr.sentToPurchasingBy = actor.id;
  pr.sentToPurchasingAt = new Date();
  await addTimelineEvent(pr, "Sent To Purchasing", actor);
  
  await pr.save();
  await logAudit(actor, "sendToPurchasing", pr._id, { status: pr.status });
  return pr;
}

async function markOrdered(actor, id) {
  const pr = await PurchaseRequest.findById(id);
  if (!pr) throw new ApiError(404, "Not found");
  
  pr.status = "Ordered";
  pr.orderedBy = actor.id;
  pr.orderedAt = new Date();
  await addTimelineEvent(pr, "Ordered", actor, "Items have been ordered.");
  
  await pr.save();
  await logAudit(actor, "markOrdered", pr._id, { status: pr.status });
  return pr;
}

async function rejectRequest(actor, id, reason) {
  const pr = await PurchaseRequest.findById(id);
  if (!pr) throw new ApiError(404, "Not found");
  
  pr.status = "Rejected";
  pr.rejectedBy = actor.id;
  pr.rejectedAt = new Date();
  pr.rejectionReason = reason;
  await addTimelineEvent(pr, "Rejected", actor, `Reason: ${reason}`);
  
  await pr.save();
  await logAudit(actor, "reject", pr._id, { status: pr.status, reason });
  return pr;
}

async function returnForEdit(actor, id, reason) {
  const pr = await PurchaseRequest.findById(id);
  if (!pr) throw new ApiError(404, "Not found");
  
  pr.status = "Returned For Edit";
  await addTimelineEvent(pr, "Returned For Edit", actor, `Reason: ${reason}`);
  
  await pr.save();
  await logAudit(actor, "returnForEdit", pr._id, { status: pr.status, reason });
  return pr;
}

async function cancelRequest(actor, id, reason) {
  const pr = await PurchaseRequest.findById(id);
  if (!pr) throw new ApiError(404, "Not found");
  
  pr.status = "Cancelled";
  pr.cancelledBy = actor.id;
  pr.cancelledAt = new Date();
  pr.cancellationReason = reason;
  await addTimelineEvent(pr, "Cancelled", actor, `Reason: ${reason}`);
  
  await pr.save();
  await logAudit(actor, "cancel", pr._id, { status: pr.status, reason });
  return pr;
}

async function closeRequest(actor, id) {
  const pr = await PurchaseRequest.findById(id);
  if (!pr) throw new ApiError(404, "Not found");
  
  pr.status = "Closed";
  pr.closedBy = actor.id;
  pr.closedAt = new Date();
  await addTimelineEvent(pr, "Closed", actor);
  
  await pr.save();
  await logAudit(actor, "close", pr._id, { status: pr.status });
  return pr;
}

async function receiveItems(actor, id, receiptData) {
  const pr = await PurchaseRequest.findById(id);
  if (!pr) throw new ApiError(404, "Not found");
  if (!["Sent To Purchasing", "Ordered", "Partially Received"].includes(pr.status)) {
    throw new ApiError(400, "Cannot receive items at this status.");
  }

  const newReceiptNo = `REC-${new Date().getTime()}`;
  const receipt = new PurchaseReceipt({
    purchaseRequestId: pr._id,
    receiptNo: newReceiptNo,
    invoiceNo: receiptData.invoiceNo,
    vendorId: receiptData.vendorId,
    receivedBy: actor.id,
    storeLocationId: receiptData.storeLocationId,
    notes: receiptData.notes,
    attachmentId: receiptData.attachmentId,
    items: receiptData.items || [],
  });

  await receipt.save();

  // Process items and update PR received quantities
  for (const rItem of receipt.items) {
    const prItem = pr.items.id(rItem.purchaseRequestItemId);
    if (!prItem) continue;

    prItem.receivedQuantity += rItem.acceptedQuantity;

    // Create Asset or Update Spare Part
    if (prItem.itemType === "Asset") {
      const serials = rItem.serialNumbers || [];
      for (let i = 0; i < rItem.acceptedQuantity; i++) {
        const serialNumber = serials[i] || "";
        
        // Generate asset code logic (simplified)
        const count = await ItAsset.countDocuments();
        const assetCode = `ASSET-${new Date().getFullYear()}-${String(count + 1 + i).padStart(5, "0")}`;
        
        const newAsset = new ItAsset({
          assetCode,
          category: prItem.assetCategoryId || "Unknown",
          assetType: prItem.itemName,
          brand: prItem.brand,
          model: prItem.model,
          serialNumber: serialNumber || undefined,
          status: "available",
          location: "المخزن الرئيسي",
          vendor: "Vendor", // Should be fetched from vendorId ideally
          invoiceNumber: receiptData.invoiceNo,
          createdBy: actor.id,
          updatedBy: actor.id,
        });
        await newAsset.save();

        await ItOperation.create({
          documentNumber: `OP-${new Date().getTime()}-${i}`,
          operationType: "purchase_received_as_asset",
          title: "Purchase Received (Asset)",
          assetId: newAsset._id,
          quantity: 1,
          toLocation: "المخزن الرئيسي",
          status: "completed",
          createdBy: actor.id,
          createdByName: actor.displayName || actor.name || "System",
        });
      }
    } else if (prItem.itemType === "Spare Part" || prItem.itemType === "Consumable") {
      if (prItem.sparePartId) {
        await ItSparePart.findByIdAndUpdate(prItem.sparePartId, {
          $inc: { quantityAvailable: rItem.acceptedQuantity }
        });

        await ItOperation.create({
          documentNumber: `OP-${new Date().getTime()}-${rItem.purchaseRequestItemId}`,
          operationType: "purchase_received_to_stock",
          title: "Purchase Received (Stock)",
          sparePartId: prItem.sparePartId,
          quantity: rItem.acceptedQuantity,
          toLocation: "المخزن الرئيسي",
          status: "completed",
          createdBy: actor.id,
          createdByName: actor.displayName || actor.name || "System",
        });
      }
    }
  }

  // Check if fully received
  let isFullyReceived = true;
  for (const item of pr.items) {
    if (item.receivedQuantity < (item.approvedQuantity || item.requestedQuantity)) {
      isFullyReceived = false;
      break;
    }
  }

  pr.status = isFullyReceived ? "Fully Received" : "Partially Received";
  await addTimelineEvent(pr, pr.status, actor, `Receipt No: ${newReceiptNo}`);
  
  await pr.save();
  await logAudit(actor, "receiveItems", pr._id, { status: pr.status, receiptNo: newReceiptNo });
  return { pr, receipt };
}

async function getPurchaseRequests(query) {
  // Add pagination and filtering
  return await PurchaseRequest.find(query).sort({ createdAt: -1 }).lean();
}

async function getPurchaseRequestById(id) {
  return await PurchaseRequest.findById(id).lean();
}

module.exports = {
  createPurchaseRequest,
  updatePurchaseRequest,
  submitPurchaseRequest,
  itApprove,
  auditAcknowledge,
  auditApprove,
  financeApprove,
  sendToPurchasing,
  markOrdered,
  rejectRequest,
  returnForEdit,
  cancelRequest,
  closeRequest,
  receiveItems,
  getPurchaseRequests,
  getPurchaseRequestById,
};
