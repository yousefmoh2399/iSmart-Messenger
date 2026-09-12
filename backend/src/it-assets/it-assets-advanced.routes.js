const express = require("express");
const mongoose = require("mongoose");
const bcrypt = require("bcryptjs");
const ExcelJS = require("exceljs");
const { requireAuth } = require("../middleware/auth.middleware");
const { requirePermission } = require("../middleware/permission.middleware");
const ApiError = require("../utils/api-error");
const asyncHandler = require("../utils/async-handler");
const { sendUploadFile } = require("../utils/send-upload-file");
const { toRelativeUploadPath } = require("../utils/storage-paths");
const User = require("../models/user.model");
const ItAsset = require("./models/it-asset.model");
const SparePart = require("./models/spare-part.model");
const ItOperation = require("./models/it-operation.model");
const ItAuditLog = require("./models/it-audit-log.model");
const ItControlRecord = require("./models/it-control-record.model");
const ItAttachment = require("./models/it-attachment.model");
const { itAssetsUpload } = require("./it-assets-upload");
const {
  streamOperationPdf,
  streamControlRecordPdf,
  streamAssetLabelPdf,
  streamSparePartLabelPdf,
  buildReport,
  streamFilteredExcelReport,
  streamReportPdf,
  getDataQuality,
} = require("./it-assets-report.service");

const router = express.Router();
router.use(requireAuth);

const prefixes = {
  inventory_session: "INV",
  discrepancy: "DC",
  correction: "COR",
  period_closure: "CLOSE",
  vendor: "VEN",
  purchase_request: "PR",
  damaged_inspection: "DI",
  scrap_request: "SR",
  workflow_rule: "WF",
  notification: "NTF",
};

function cleanText(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text || fallback;
}

function currentActor(req) {
  return { id: req.user.id, name: req.user.fullName || req.user.username };
}

function requireAnyPermission(...permissionNames) {
  return (req, res, next) => {
    if (
      req.user?.role === "admin" ||
      permissionNames.some((name) => req.user?.permissions?.[name] === true)
    ) {
      next();
      return;
    }
    next(new ApiError(403, "Permission denied."));
  };
}

async function nextRecordNumber(recordType) {
  const year = new Date().getFullYear();
  const count = await ItControlRecord.countDocuments({
    recordType,
    createdAt: {
      $gte: new Date(`${year}-01-01T00:00:00.000Z`),
      $lt: new Date(`${year + 1}-01-01T00:00:00.000Z`),
    },
  });
  return `${prefixes[recordType] || "REC"}-${year}-${String(count + 1).padStart(6, "0")}`;
}

async function audit(req, action, entityType, entityId, summary, documentNumber, metadata = {}) {
  const actor = currentActor(req);
  await ItAuditLog.create({
    action,
    entityType,
    entityId,
    documentNumber,
    summary,
    metadata,
    actorId: actor.id,
    actorName: actor.name,
    ipAddress: req.ip || "",
    userAgent: req.get("user-agent") || "",
  });
}

router.get(
  "/control-records",
  requireAnyPermission("canViewItAssets", "canScanItInventory", "canManageItInventory"),
  asyncHandler(async (req, res) => {
    const query = {};
    if (req.query.type) query.recordType = req.query.type;
    if (req.query.status) query.status = req.query.status;
    const records = await ItControlRecord.find(query)
      .populate("assetId", "assetCode assetType serialNumber status location assignedTo")
      .populate("sparePartId", "partCode name quantityAvailable quantityReserved")
      .populate("operationId", "documentNumber title status operationType")
      .sort({ createdAt: -1 })
      .lean();
    res.json({ records });
  }),
);

router.post(
  "/control-records",
  requireAnyPermission(
    "canExecuteItAssets",
    "canInspectDamagedItAssets",
    "canManageItProcurement",
    "canManageItSettings",
  ),
  asyncHandler(async (req, res) => {
    const recordType = cleanText(req.body.recordType);
    if (!Object.prototype.hasOwnProperty.call(prefixes, recordType)) {
      throw new ApiError(400, "نوع السجل غير صالح.");
    }
    const permissions = req.user.permissions || {};
    const permitted =
      permissions.canExecuteItAssets === true ||
      (["damaged_inspection", "scrap_request"].includes(recordType) &&
        permissions.canInspectDamagedItAssets === true) ||
      (["vendor", "purchase_request"].includes(recordType) &&
        permissions.canManageItProcurement === true) ||
      (recordType === "workflow_rule" &&
        permissions.canManageItSettings === true) ||
      (recordType === "correction" &&
        permissions.canAuditItAssets === true);
    if (!permitted) throw new ApiError(403, "Permission denied.");
    const actor = currentActor(req);
    const record = await ItControlRecord.create({
      recordType,
      recordNumber: await nextRecordNumber(recordType),
      title: cleanText(req.body.title, "مستند IT"),
      status: cleanText(req.body.status, "open"),
      assetId: mongoose.isValidObjectId(req.body.assetId) ? req.body.assetId : null,
      sparePartId: mongoose.isValidObjectId(req.body.sparePartId) ? req.body.sparePartId : null,
      operationId: mongoose.isValidObjectId(req.body.operationId) ? req.body.operationId : null,
      branchName: cleanText(req.body.branchName),
      location: cleanText(req.body.location),
      assignedTo: cleanText(req.body.assignedTo),
      reason: cleanText(req.body.reason),
      notes: cleanText(req.body.notes),
      data: req.body.data && typeof req.body.data === "object" ? req.body.data : {},
      createdBy: actor.id,
      createdByName: actor.name,
    });
    await audit(req, "create_control_record", recordType, record._id, `إنشاء ${record.title}`, record.recordNumber);
    res.status(201).json({ record });
  }),
);

router.post(
  "/inventory-sessions",
  requireAnyPermission("canExecuteItAssets", "canManageItInventory"),
  asyncHandler(async (req, res) => {
    const actor = currentActor(req);
    const query = { isArchived: false };
    if (cleanText(req.body.branchName)) query.branchName = cleanText(req.body.branchName);
    if (cleanText(req.body.location)) query.location = cleanText(req.body.location);
    const expectedAssets = await ItAsset.find(query).select("_id").lean();
    const record = await ItControlRecord.create({
      recordType: "inventory_session",
      recordNumber: await nextRecordNumber("inventory_session"),
      title: cleanText(req.body.title, "جلسة جرد"),
      status: "in_progress",
      branchName: cleanText(req.body.branchName),
      location: cleanText(req.body.location),
      notes: cleanText(req.body.notes),
      data: {
        expectedAssetIds: expectedAssets.map((entry) => entry._id.toString()),
        scannedAssetIds: [],
        scans: [],
      },
      createdBy: actor.id,
      createdByName: actor.name,
    });
    await audit(req, "inventory_started", "inventory_session", record._id, `بدء ${record.title}`, record.recordNumber);
    res.status(201).json({ record });
  }),
);

router.post(
  "/inventory-sessions/:id/scan",
  requireAnyPermission("canScanItInventory", "canExecuteItAssets", "canManageItInventory"),
  asyncHandler(async (req, res) => {
    const session = await ItControlRecord.findOne({ _id: req.params.id, recordType: "inventory_session" });
    if (!session) throw new ApiError(404, "Inventory session not found.");
    if (session.status !== "in_progress") throw new ApiError(409, "جلسة الجرد مغلقة.");
    const code = cleanText(req.body.code).replace(/^itasset:\/\/asset\//i, "");
    const asset = mongoose.isValidObjectId(code)
      ? await ItAsset.findById(code)
      : await ItAsset.findOne({
          $or: [{ assetCode: code.toUpperCase() }, { serialNumber: code.toUpperCase() }],
          isArchived: false,
        });
    if (!asset) throw new ApiError(404, "لم يتم العثور على الجهاز.");
    const scanned = new Set((session.data?.scannedAssetIds || []).map(String));
    const duplicate = scanned.has(asset._id.toString());
    scanned.add(asset._id.toString());
    const scans = [...(session.data?.scans || []), {
      assetId: asset._id.toString(),
      assetCode: asset.assetCode,
      foundLocation: cleanText(req.body.foundLocation, asset.location),
      foundEmployee: cleanText(req.body.foundEmployee, asset.assignedTo),
      duplicate,
      scannedAt: new Date(),
      scannedBy: currentActor(req).name,
    }];
    session.data = { ...(session.data || {}), scannedAssetIds: [...scanned], scans };
    session.markModified("data");
    await session.save();
    res.json({ asset, duplicate, record: session });
  }),
);

router.post(
  "/inventory-sessions/:id/close",
  requireAnyPermission("canExecuteItAssets", "canManageItInventory"),
  asyncHandler(async (req, res) => {
    const session = await ItControlRecord.findOne({ _id: req.params.id, recordType: "inventory_session" });
    if (!session) throw new ApiError(404, "Inventory session not found.");
    const expected = new Set((session.data?.expectedAssetIds || []).map(String));
    const scanned = new Set((session.data?.scannedAssetIds || []).map(String));
    const scans = session.data?.scans || [];
    const discrepancies = [];
    for (const assetId of expected) {
      if (!scanned.has(assetId)) discrepancies.push({ assetId, type: "expected_not_found" });
    }
    for (const assetId of scanned) {
      if (!expected.has(assetId)) discrepancies.push({ assetId, type: "found_not_expected" });
    }
    for (const scan of scans) {
      const asset = await ItAsset.findById(scan.assetId).lean();
      if (!asset) continue;
      if (scan.duplicate) discrepancies.push({ assetId: scan.assetId, type: "duplicate_scan" });
      if (scan.foundLocation && scan.foundLocation !== asset.location) {
        discrepancies.push({ assetId: scan.assetId, type: "wrong_location", expected: asset.location, found: scan.foundLocation });
      }
      if (scan.foundEmployee && scan.foundEmployee !== asset.assignedTo) {
        discrepancies.push({ assetId: scan.assetId, type: "wrong_employee", expected: asset.assignedTo, found: scan.foundEmployee });
      }
    }
    const actor = currentActor(req);
    for (const item of discrepancies) {
      await ItControlRecord.create({
        recordType: "discrepancy",
        recordNumber: await nextRecordNumber("discrepancy"),
        title: `فرق جرد - ${item.type}`,
        status: "open",
        assetId: item.assetId,
        parentRecordId: session._id,
        branchName: session.branchName,
        location: session.location,
        reason: item.type,
        data: item,
        createdBy: actor.id,
        createdByName: actor.name,
      });
    }
    session.status = discrepancies.length ? "closed_with_discrepancies" : "closed";
    session.closedAt = new Date();
    session.data = { ...(session.data || {}), discrepancyCount: discrepancies.length };
    session.markModified("data");
    await session.save();
    await audit(req, "inventory_closed", "inventory_session", session._id, `إغلاق ${session.recordNumber}`, session.recordNumber, {
      discrepancyCount: discrepancies.length,
    });
    res.json({ record: session, discrepancies });
  }),
);

router.post(
  "/control-records/:id/approve",
  requirePermission("canAuditItAssets"),
  asyncHandler(async (req, res) => {
    const record = await ItControlRecord.findById(req.params.id);
    if (!record) throw new ApiError(404, "Control record not found.");
    record.status = req.body.approved === false ? "rejected" : "approved";
    record.approvedBy = req.user.id;
    record.approvedAt = new Date();
    record.notes = [record.notes, cleanText(req.body.note)].filter(Boolean).join("\n");
    await record.save();
    await audit(req, "control_record_reviewed", record.recordType, record._id, `مراجعة ${record.recordNumber}`, record.recordNumber);
    res.json({ record });
  }),
);

router.post(
  "/control-records/:id/sign",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => {
    const record = await ItControlRecord.findById(req.params.id);
    if (!record) throw new ApiError(404, "Control record not found.");
    const user = await User.findById(req.user.id).select("+passwordHash");
    if (!user || !(await bcrypt.compare(cleanText(req.body.password), user.passwordHash))) {
      throw new ApiError(401, "كلمة المرور غير صحيحة.");
    }
    const actor = currentActor(req);
    record.signatures.push({
      role: cleanText(req.body.role, "signed_by"),
      userId: actor.id,
      userName: actor.name,
      ipAddress: req.ip || "",
    });
    record.locked = true;
    await record.save();
    await audit(req, "digital_signature", record.recordType, record._id, `توقيع ${record.recordNumber}`, record.recordNumber);
    res.json({ record });
  }),
);

router.post(
  "/operations/:id/sign",
  requireAnyPermission("canExecuteItAssets", "canAuditItAssets", "canManageItAssets"),
  asyncHandler(async (req, res) => {
    const operation = await ItOperation.findById(req.params.id);
    if (!operation) throw new ApiError(404, "Operation not found.");
    if (operation.signedAt) {
      throw new ApiError(409, "تم توقيع الحركة بالفعل ولا يمكن استبدال التوقيع.");
    }
    if (["completed", "rejected", "cancelled"].includes(operation.status)) {
      throw new ApiError(409, "لا يمكن توقيع حركة مغلقة.");
    }
    const user = await User.findById(req.user.id).select("+passwordHash");
    if (!user || !(await bcrypt.compare(cleanText(req.body.password), user.passwordHash))) {
      throw new ApiError(401, "كلمة المرور غير صحيحة.");
    }
    const actor = currentActor(req);
    operation.signedAt = new Date();
    operation.signedByName = `${cleanText(req.body.role, "signed_by")}: ${actor.name}`;
    await operation.save();
    await audit(req, "digital_signature", "operation", operation._id, `توقيع ${operation.documentNumber}`, operation.documentNumber);
    res.json({ operation });
  }),
);

router.post(
  "/corrections/:id/execute",
  requirePermission("canAuditItAssets"),
  asyncHandler(async (req, res) => {
    const record = await ItControlRecord.findOne({ _id: req.params.id, recordType: "correction" });
    if (!record) throw new ApiError(404, "Correction request not found.");
    if (record.status !== "approved") throw new ApiError(409, "طلب التصحيح غير معتمد.");
    record.status = "executed";
    record.closedAt = new Date();
    record.data = { ...(record.data || {}), executedValues: req.body.newValues || record.data?.newValues || {} };
    record.markModified("data");
    await record.save();
    await audit(req, "correction_executed", "correction", record._id, `تنفيذ ${record.recordNumber}`, record.recordNumber);
    res.json({ record });
  }),
);

router.post(
  "/control-records/:id/execute",
  requireAnyPermission(
    "canExecuteItAssets",
    "canManageItInventory",
    "canInspectDamagedItAssets",
    "canManageItProcurement",
    "canAuditItAssets",
  ),
  asyncHandler(async (req, res) => {
    const record = await ItControlRecord.findById(req.params.id);
    if (!record) throw new ApiError(404, "Control record not found.");
    if (!["approved", "open", "under_investigation", "active"].includes(record.status)) {
      throw new ApiError(409, "حالة المستند لا تسمح بالتنفيذ.");
    }
    const actor = currentActor(req);
    if (record.recordType === "scrap_request") {
      if (!record.assetId) throw new ApiError(400, "طلب التكهين غير مرتبط بجهاز.");
      const hasInspection = await ItControlRecord.exists({
        recordType: "damaged_inspection",
        assetId: record.assetId,
        status: { $in: ["approved", "executed", "closed"] },
      });
      if (!hasInspection) throw new ApiError(409, "لا يمكن التكهين بدون فحص معتمد.");
      const attachment = await ItAttachment.exists({
        entityType: "control_record",
        entityId: record._id,
      });
      if (!attachment) throw new ApiError(409, "يجب رفع التقرير الفني قبل التكهين.");
      await ItAsset.updateOne(
        { _id: record.assetId },
        {
          $set: { status: "scrapped", condition: "not_repairable", updatedBy: actor.id },
          $push: {
            timeline: {
              action: "scrapped",
              details: record.reason || "تم تنفيذ التكهين.",
              documentNumber: record.recordNumber,
              performedBy: actor.id,
              performedByName: actor.name,
            },
          },
        },
      );
    } else if (record.recordType === "damaged_inspection" && record.assetId) {
      const decision = cleanText(record.data?.recommendedDecision).toLowerCase();
      const status = {
        repair: "repairable",
        scrap: "pending_scrap",
        send_external_maintenance: "external_maintenance",
        replace_under_warranty: "replaced_under_warranty",
        use_for_spare_parts: "used_for_spare_parts",
      }[decision] || "damaged_store";
      await ItAsset.updateOne(
        { _id: record.assetId },
        {
          $set: { status, updatedBy: actor.id },
          $push: {
            timeline: {
              action: "damaged_inspection",
              details: record.notes || record.reason,
              documentNumber: record.recordNumber,
              performedBy: actor.id,
              performedByName: actor.name,
            },
          },
        },
      );
    } else if (record.recordType === "purchase_request" && record.sparePartId) {
      const receivedQuantity = Math.max(
        0,
        Number(req.body.receivedQuantity || record.data?.requestedQuantity) || 0,
      );
      if (receivedQuantity <= 0) throw new ApiError(400, "الكمية المستلمة غير صالحة.");
      await SparePart.updateOne(
        { _id: record.sparePartId },
        {
          $inc: { quantityAvailable: receivedQuantity },
          $set: { updatedBy: actor.id },
        },
      );
      record.data = { ...(record.data || {}), receivedQuantity };
      record.markModified("data");
    } else if (record.recordType === "discrepancy" && record.assetId) {
      const resolution = cleanText(req.body.resolution, record.data?.resolution);
      record.data = { ...(record.data || {}), resolution };
      record.markModified("data");
      if (resolution === "mark_lost") {
        await ItAsset.updateOne(
          { _id: record.assetId },
          { $set: { status: "lost", updatedBy: actor.id } },
        );
      }
    } else if (record.recordType === "correction") {
      record.data = {
        ...(record.data || {}),
        executedValues: req.body.newValues || record.data?.newValues || {},
      };
      record.markModified("data");
    }
    record.status = "executed";
    record.closedAt = new Date();
    await record.save();
    await audit(req, "control_record_executed", record.recordType, record._id, `تنفيذ ${record.recordNumber}`, record.recordNumber);
    res.json({ record });
  }),
);

router.post(
  "/periods/close",
  requireAnyPermission("canCloseItPeriods", "canManageItAssets"),
  asyncHandler(async (req, res) => {
    const month = cleanText(req.body.month);
    if (!/^\d{4}-\d{2}$/.test(month)) throw new ApiError(400, "الشهر يجب أن يكون بصيغة YYYY-MM.");
    const existing = await ItControlRecord.findOne({ recordType: "period_closure", "data.month": month });
    if (existing) throw new ApiError(409, "هذه الفترة مغلقة بالفعل.");
    const actor = currentActor(req);
    const record = await ItControlRecord.create({
      recordType: "period_closure",
      recordNumber: await nextRecordNumber("period_closure"),
      title: `قفل فترة ${month}`,
      status: "closed",
      locked: true,
      notes: cleanText(req.body.notes),
      data: { month },
      closedAt: new Date(),
      createdBy: actor.id,
      createdByName: actor.name,
    });
    await audit(req, "period_closed", "period_closure", record._id, record.title, record.recordNumber);
    res.status(201).json({ record });
  }),
);

router.get(
  "/reconciliation",
  requirePermission("canAuditItAssets"),
  asyncHandler(async (req, res) => {
    const operations = await ItOperation.find().sort({ createdAt: -1 }).lean();
    const items = operations.map((operation) => ({
      id: operation._id,
      documentNumber: operation.documentNumber,
      itStatus: operation.status,
      auditStatus: operation.acknowledgedAt ? "acknowledged" : "not_recorded",
      result:
        operation.status === "completed" && operation.acknowledgedAt
          ? "matched"
          : operation.status === "completed"
            ? "missing_audit_acknowledgement"
            : operation.acknowledgedAt
              ? "missing_it_execution"
              : "pending",
    }));
    res.json({ items });
  }),
);

router.get(
  "/data-quality",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => res.json({ quality: await getDataQuality() })),
);

router.get(
  "/analytics",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => {
    const operations = await ItOperation.find().lean();
    const assets = await ItAsset.find({ isArchived: false }).lean();
    const rootCauses = {};
    const branchRisk = {};
    const employeeRisk = {};
    for (const operation of operations) {
      if (operation.rootCause) rootCauses[operation.rootCause] = (rootCauses[operation.rootCause] || 0) + 1;
      const asset = assets.find((entry) => String(entry._id) === String(operation.assetId));
      if (!asset) continue;
      const weight = operation.operationType === "damaged" ? 3 : operation.operationType === "maintenance" ? 1 : 0;
      if (asset.branchName) branchRisk[asset.branchName] = (branchRisk[asset.branchName] || 0) + weight;
      if (asset.assignedTo) employeeRisk[asset.assignedTo] = (employeeRisk[asset.assignedTo] || 0) + weight;
    }
    const riskLevel = (score) => score >= 10 ? "high" : score >= 4 ? "medium" : "low";
    res.json({
      analytics: {
        rootCauses,
        branchRisk: Object.entries(branchRisk).map(([name, score]) => ({ name, score, level: riskLevel(score) })),
        employeeRisk: Object.entries(employeeRisk).map(([name, score]) => ({ name, score, level: riskLevel(score) })),
      },
    });
  }),
);

router.get(
  "/notifications",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => {
    const now = new Date();
    const inThirtyDays = new Date(now.getTime() + 30 * 86400000);
    const [lowStock, expiringWarranty, overdueMaintenance, pendingAudit, temporaryReturns] = await Promise.all([
      SparePart.find({
        isArchived: false,
        $expr: { $lte: [{ $subtract: ["$quantityAvailable", "$quantityReserved"] }, "$minimumQuantity"] },
      }).lean(),
      ItAsset.find({ isArchived: false, warrantyEndDate: { $gte: now, $lte: inThirtyDays } }).lean(),
      ItOperation.find({ operationType: "maintenance", dueAt: { $lt: now }, status: { $nin: ["completed", "cancelled"] } }).lean(),
      ItOperation.find({ status: "pending_audit" }).lean(),
      ItOperation.find({
        operationType: "temporary_assignment",
        expectedReturnDate: { $lte: inThirtyDays },
        status: { $nin: ["completed", "cancelled"] },
      }).lean(),
    ]);
    res.json({ notifications: { lowStock, expiringWarranty, overdueMaintenance, pendingAudit, temporaryReturns } });
  }),
);

router.post(
  "/attachments/:entityType/:entityId",
  requirePermission("canExecuteItAssets"),
  itAssetsUpload.single("file"),
  asyncHandler(async (req, res) => {
    if (!req.file || !mongoose.isValidObjectId(req.params.entityId)) throw new ApiError(400, "المرفق أو المعرف غير صالح.");
    const actor = currentActor(req);
    const attachment = await ItAttachment.create({
      entityType: cleanText(req.params.entityType),
      entityId: req.params.entityId,
      originalName: req.file.originalname,
      storedPath: toRelativeUploadPath(req.file.path),
      mimeType: req.file.mimetype || "application/octet-stream",
      size: req.file.size,
      uploadedBy: actor.id,
      uploadedByName: actor.name,
    });
    await audit(req, "attachment_uploaded", req.params.entityType, req.params.entityId, `رفع ${attachment.originalName}`);
    res.status(201).json({ attachment });
  }),
);

router.get(
  "/attachments/:entityType/:entityId",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => {
    const attachments = await ItAttachment.find({
      entityType: req.params.entityType,
      entityId: req.params.entityId,
    }).sort({ createdAt: -1 }).lean();
    res.json({ attachments });
  }),
);

router.get(
  "/attachments/file/:id",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => {
    const attachment = await ItAttachment.findById(req.params.id).lean();
    if (!attachment) throw new ApiError(404, "Attachment not found.");
    await sendUploadFile(res, attachment.storedPath, {
      contentType: attachment.mimeType,
      disposition: "attachment",
      fileName: attachment.originalName,
    });
  }),
);

router.get(
  "/assets/:id/label.pdf",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => {
    const asset = await ItAsset.findById(req.params.id).lean();
    if (!asset) throw new ApiError(404, "Asset not found.");
    await audit(req, "print_asset_label", "asset", asset._id, `طباعة ملصق ${asset.assetCode}`);
    await streamAssetLabelPdf(res, asset);
  }),
);

router.get(
  "/spare-parts/:id/label.pdf",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => {
    const part = await SparePart.findById(req.params.id).lean();
    if (!part) throw new ApiError(404, "Spare part not found.");
    await audit(
      req,
      "print_spare_part_label",
      "spare_part",
      part._id,
      `طباعة ملصق ${part.partCode}`,
    );
    await streamSparePartLabelPdf(res, part);
  }),
);

router.get(
  "/operations/:id/document.pdf",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => {
    const operation = await ItOperation.findById(req.params.id)
      .populate("assetId", "assetCode assetType serialNumber")
      .populate("sparePartId", "partCode name")
      .lean();
    if (!operation) throw new ApiError(404, "Operation not found.");
    await audit(req, "print_pdf", "operation", operation._id, `طباعة ${operation.documentNumber}`, operation.documentNumber);
    await streamOperationPdf(res, operation);
  }),
);

router.get(
  "/control-records/:id/document.pdf",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => {
    const record = await ItControlRecord.findById(req.params.id).lean();
    if (!record) throw new ApiError(404, "Control record not found.");
    await audit(req, "print_pdf", record.recordType, record._id, `طباعة ${record.recordNumber}`, record.recordNumber);
    await streamControlRecordPdf(res, record);
  }),
);

router.get(
  "/reports/:type.xlsx",
  requireAnyPermission("canExportItReports", "canAuditItAssets", "canManageItAssets"),
  asyncHandler(async (req, res) => {
    const reportType = req.params.type;
    await audit(req, "export_excel", "report", new mongoose.Types.ObjectId(), `تصدير تقرير ${reportType}`);
    await streamFilteredExcelReport(res, reportType, req.query);
  }),
);

router.get(
  "/reports/:type.pdf",
  requireAnyPermission("canExportItReports", "canAuditItAssets", "canManageItAssets"),
  asyncHandler(async (req, res) => {
    const reportType = req.params.type;
    await audit(req, "export_pdf", "report", new mongoose.Types.ObjectId(), `تصدير تقرير ${reportType}`);
    await streamReportPdf(res, reportType, req.query);
  }),
);

router.get(
  "/reports/:type/preview",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => {
    const report = await buildReport(req.params.type, req.query);
    res.json({
      ...report,
      rows: report.rows.slice(0, 250),
      truncated: report.rows.length > 250,
    });
  }),
);

router.post(
  "/import/:type",
  requirePermission("canManageItAssets"),
  itAssetsUpload.single("file"),
  asyncHandler(async (req, res) => {
    if (!req.file) throw new ApiError(400, "ملف Excel مطلوب.");
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.readFile(req.file.path);
    const sheet = workbook.worksheets[0];
    const headers = {};
    sheet.getRow(1).eachCell((cell, column) => {
      headers[cleanText(cell.value).toLowerCase()] = column;
    });
    const rows = [];
    const errors = [];
    for (let rowNumber = 2; rowNumber <= sheet.rowCount; rowNumber += 1) {
      const row = sheet.getRow(rowNumber);
      const read = (name) => cleanText(row.getCell(headers[name] || 0).value);
      if (req.params.type === "assets") {
        const item = {
          assetCode: read("assetcode") || read("asset_code"),
          assetType: read("assettype") || read("asset_type"),
          serialNumber: read("serialnumber") || read("serial_number"),
          brand: read("brand"),
          model: read("model"),
          location: read("location"),
          branchName: read("branch"),
          assignedTo: read("employee"),
        };
        if (!item.assetCode || !item.assetType) errors.push({ row: rowNumber, error: "assetCode و assetType مطلوبان" });
        else rows.push(item);
      } else {
        const item = {
          partCode: read("partcode") || read("part_code"),
          name: read("name"),
          category: read("category"),
          quantityAvailable: Number(read("quantity")) || 0,
          minimumQuantity: Number(read("minimumquantity") || read("minimum_quantity")) || 0,
          location: read("location"),
        };
        if (!item.partCode || !item.name) errors.push({ row: rowNumber, error: "partCode و name مطلوبان" });
        else rows.push(item);
      }
    }
    if (req.query.apply === "true" && errors.length === 0) {
      const actor = currentActor(req);
      if (req.params.type === "assets") {
        for (const item of rows) {
          await ItAsset.updateOne(
            { assetCode: item.assetCode.toUpperCase() },
            {
              $setOnInsert: {
                ...item,
                assetCode: item.assetCode.toUpperCase(),
                category: item.assetType,
                status: "available",
                condition: "good",
                createdBy: actor.id,
                updatedBy: actor.id,
              },
            },
            { upsert: true },
          );
        }
      } else {
        for (const item of rows) {
          await SparePart.updateOne(
            { partCode: item.partCode.toUpperCase() },
            {
              $setOnInsert: {
                ...item,
                partCode: item.partCode.toUpperCase(),
                createdBy: actor.id,
                updatedBy: actor.id,
              },
            },
            { upsert: true },
          );
        }
      }
      await audit(req, "excel_import", req.params.type, new mongoose.Types.ObjectId(), `استيراد ${rows.length} صف`);
    }
    res.json({ preview: { validRows: rows.length, invalidRows: errors.length, rows, errors }, applied: req.query.apply === "true" && errors.length === 0 });
  }),
);

module.exports = router;
