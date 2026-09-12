const express = require("express");
const mongoose = require("mongoose");
const { requireAuth } = require("../middleware/auth.middleware");
const { requirePermission } = require("../middleware/permission.middleware");
const ApiError = require("../utils/api-error");
const asyncHandler = require("../utils/async-handler");
const { escapeRegExp } = require("../utils/regex.util");
const ItAsset = require("./models/it-asset.model");
const SparePart = require("./models/spare-part.model");
const ItOperation = require("./models/it-operation.model");
const ItAuditLog = require("./models/it-audit-log.model");
const ItControlRecord = require("./models/it-control-record.model");
const ItAttachment = require("./models/it-attachment.model");

const router = express.Router();
router.use(requireAuth);

function actor(req) {
  return {
    id: req.user.id,
    name: req.user.fullName || req.user.username,
  };
}

function cleanText(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text || fallback;
}

function optionalDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
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

async function logAction(req, { action, entityType, entityId, documentNumber, summary, metadata }) {
  const currentActor = actor(req);
  await ItAuditLog.create({
    action,
    entityType,
    entityId,
    documentNumber,
    summary,
    metadata: metadata || {},
    actorId: currentActor.id,
    actorName: currentActor.name,
    ipAddress: req.ip || "",
    userAgent: req.get("user-agent") || "",
  });
}

async function assertPeriodOpen(date = new Date()) {
  const month = date.toISOString().slice(0, 7);
  const closed = await ItControlRecord.exists({
    recordType: "period_closure",
    status: "closed",
    "data.month": month,
  });
  if (closed) {
    throw new ApiError(409, `الفترة ${month} مغلقة. استخدم طلب تصحيح.`);
  }
}

async function nextDocumentNumber(type) {
  const prefix = {
    movement: "MOV",
    maintenance: "MNT",
    transfer: "TO",
    replacement: "RR",
    damaged: "DMG",
    inventory: "INV",
    custody: "CUS",
    employee_clearance: "EC",
    branch_handover: "BH",
    temporary_assignment: "TA",
    scrap: "SR",
  }[type] || "DOC";
  const year = new Date().getFullYear();
  const count = await ItOperation.countDocuments({
    operationType: type,
    createdAt: {
      $gte: new Date(`${year}-01-01T00:00:00.000Z`),
      $lt: new Date(`${year + 1}-01-01T00:00:00.000Z`),
    },
  });
  return `${prefix}-${year}-${String(count + 1).padStart(5, "0")}`;
}

router.get(
  "/overview",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => {
    const [
      totalAssets,
      availableAssets,
      assignedAssets,
      maintenanceAssets,
      damagedAssets,
      spareParts,
      pendingOperations,
      openMaintenance,
      recentOperations,
    ] = await Promise.all([
      ItAsset.countDocuments({ isArchived: false }),
      ItAsset.countDocuments({ isArchived: false, status: { $in: ["available", "in_stock"] } }),
      ItAsset.countDocuments({ isArchived: false, assignedTo: { $ne: "" } }),
      ItAsset.countDocuments({ isArchived: false, status: { $in: ["in_maintenance", "external_maintenance"] } }),
      ItAsset.countDocuments({ isArchived: false, status: { $in: ["damaged", "damaged_store", "scrapped", "lost"] } }),
      SparePart.find({ isArchived: false }).lean(),
      ItOperation.countDocuments({ status: { $in: ["pending_audit", "approved", "in_progress"] } }),
      ItOperation.countDocuments({ operationType: "maintenance", status: { $nin: ["completed", "cancelled", "rejected"] } }),
      ItOperation.find().sort({ createdAt: -1 }).limit(8).lean(),
    ]);
    const lowStock = spareParts.filter(
      (part) => part.quantityAvailable - part.quantityReserved <= part.minimumQuantity,
    ).length;
    res.json({
      overview: {
        totalAssets,
        availableAssets,
        assignedAssets,
        maintenanceAssets,
        damagedAssets,
        totalSpareParts: spareParts.length,
        lowStock,
        pendingOperations,
        openMaintenance,
        recentOperations,
      },
    });
  }),
);

router.get(
  "/assets",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => {
    const query = { isArchived: false };
    if (req.query.status) query.status = req.query.status;
    if (req.query.search) {
      const pattern = new RegExp(escapeRegExp(String(req.query.search).trim()), "i");
      query.$or = [
        { assetCode: pattern },
        { serialNumber: pattern },
        { assetType: pattern },
        { brand: pattern },
        { assignedTo: pattern },
        { location: pattern },
      ];
    }
    const assets = await ItAsset.find(query).sort({ updatedAt: -1 }).lean();
    res.json({ assets });
  }),
);

router.get(
  "/assets/lookup/:code",
  requireAnyPermission("canScanItAssets", "canViewItAssets", "canManageItAssets"),
  asyncHandler(async (req, res) => {
    const rawCode = cleanText(req.params.code);
    const normalizedCode = rawCode
      .replace(/^itasset:\/\/asset\//i, "")
      .trim();
    const asset = mongoose.isValidObjectId(normalizedCode)
      ? await ItAsset.findOne({ _id: normalizedCode, isArchived: false }).lean()
      : await ItAsset.findOne({
          isArchived: false,
          $or: [
            { assetCode: normalizedCode.toUpperCase() },
            { serialNumber: normalizedCode.toUpperCase() },
          ],
        }).lean();
    if (!asset) throw new ApiError(404, "Asset not found.");
    res.json({ asset });
  }),
);

router.get(
  "/spare-parts/lookup/:code",
  requireAnyPermission("canScanItSpareParts", "canViewItAssets", "canManageItAssets"),
  asyncHandler(async (req, res) => {
    const rawCode = cleanText(req.params.code);
    const normalizedCode = rawCode
      .replace(/^itasset:\/\/spare-part\//i, "")
      .trim();
    const sparePart = mongoose.isValidObjectId(normalizedCode)
      ? await SparePart.findOne({ _id: normalizedCode, isArchived: false }).lean()
      : await SparePart.findOne({
          isArchived: false,
          partCode: normalizedCode.toUpperCase(),
        }).lean();
    if (!sparePart) throw new ApiError(404, "Spare part not found.");
    res.json({ sparePart });
  }),
);

router.post(
  "/assets",
  requirePermission("canManageItAssets"),
  asyncHandler(async (req, res) => {
    await assertPeriodOpen();
    const currentActor = actor(req);
    const assetCode = cleanText(req.body.assetCode).toUpperCase();
    const assetType = cleanText(req.body.assetType);
    if (!assetCode || !assetType) throw new ApiError(400, "كود الجهاز ونوعه مطلوبان.");
    const asset = await ItAsset.create({
      assetCode,
      category: cleanText(req.body.category, assetType),
      assetType,
      brand: cleanText(req.body.brand),
      model: cleanText(req.body.model),
      serialNumber: cleanText(req.body.serialNumber).toUpperCase() || null,
      status: cleanText(req.body.status, "available"),
      condition: cleanText(req.body.condition, "good"),
      branchName: cleanText(req.body.branchName),
      location: cleanText(req.body.location, "المخزن الرئيسي"),
      assignedTo: cleanText(req.body.assignedTo),
      purchaseDate: optionalDate(req.body.purchaseDate),
      warrantyEndDate: optionalDate(req.body.warrantyEndDate),
      vendor: cleanText(req.body.vendor),
      invoiceNumber: cleanText(req.body.invoiceNumber),
      notes: cleanText(req.body.notes),
      createdBy: currentActor.id,
      updatedBy: currentActor.id,
      timeline: [{
        action: "asset_created",
        details: "تم تسجيل الجهاز في النظام.",
        performedBy: currentActor.id,
        performedByName: currentActor.name,
      }],
    });
    await logAction(req, {
      action: "create",
      entityType: "asset",
      entityId: asset._id,
      summary: `إضافة الجهاز ${asset.assetCode}`,
    });
    res.status(201).json({ asset });
  }),
);

router.patch(
  "/assets/:id",
  requirePermission("canManageItAssets"),
  asyncHandler(async (req, res) => {
    await assertPeriodOpen();
    if (!mongoose.isValidObjectId(req.params.id)) throw new ApiError(400, "معرف الجهاز غير صالح.");
    const asset = await ItAsset.findOne({ _id: req.params.id, isArchived: false });
    if (!asset) throw new ApiError(404, "Asset not found.");
    const allowed = [
      "category", "assetType", "brand", "model", "status", "condition", "branchName",
      "location", "assignedTo", "vendor", "invoiceNumber", "notes",
    ];
    for (const key of allowed) {
      if (Object.prototype.hasOwnProperty.call(req.body, key)) asset[key] = cleanText(req.body[key]);
    }
    if (Object.prototype.hasOwnProperty.call(req.body, "serialNumber")) {
      asset.serialNumber = cleanText(req.body.serialNumber).toUpperCase() || null;
    }
    if (Object.prototype.hasOwnProperty.call(req.body, "purchaseDate")) asset.purchaseDate = optionalDate(req.body.purchaseDate);
    if (Object.prototype.hasOwnProperty.call(req.body, "warrantyEndDate")) asset.warrantyEndDate = optionalDate(req.body.warrantyEndDate);
    const currentActor = actor(req);
    asset.updatedBy = currentActor.id;
    asset.timeline.push({
      action: "asset_updated",
      details: cleanText(req.body.changeReason, "تم تحديث بيانات الجهاز."),
      performedBy: currentActor.id,
      performedByName: currentActor.name,
    });
    await asset.save();
    await logAction(req, {
      action: "update",
      entityType: "asset",
      entityId: asset._id,
      summary: `تحديث الجهاز ${asset.assetCode}`,
    });
    res.json({ asset });
  }),
);

router.delete(
  "/assets/:id",
  requirePermission("canDeleteItAssets"),
  asyncHandler(async (req, res) => {
    await assertPeriodOpen();
    const asset = await ItAsset.findOne({ _id: req.params.id, isArchived: false });
    if (!asset) throw new ApiError(404, "Asset not found.");
    const activeOperation = await ItOperation.exists({
      assetId: asset._id,
      status: { $in: ["draft", "pending_audit", "approved", "in_progress"] },
    });
    if (activeOperation) {
      throw new ApiError(409, "لا يمكن حذف الجهاز لوجود حركة مفتوحة مرتبطة به.");
    }
    const currentActor = actor(req);
    asset.isArchived = true;
    asset.updatedBy = currentActor.id;
    asset.timeline.push({
      action: "asset_archived",
      details: cleanText(req.body.reason, "تمت أرشفة الجهاز."),
      performedBy: currentActor.id,
      performedByName: currentActor.name,
    });
    await asset.save();
    await logAction(req, {
      action: "delete",
      entityType: "asset",
      entityId: asset._id,
      summary: `أرشفة الجهاز ${asset.assetCode}`,
      metadata: { reason: cleanText(req.body.reason) },
    });
    res.json({ success: true });
  }),
);

router.get(
  "/spare-parts",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => {
    const query = { isArchived: false };
    if (req.query.search) {
      const pattern = new RegExp(escapeRegExp(String(req.query.search).trim()), "i");
      query.$or = [{ partCode: pattern }, { name: pattern }, { category: pattern }, { brand: pattern }];
    }
    const spareParts = await SparePart.find(query).sort({ updatedAt: -1 }).lean();
    res.json({ spareParts });
  }),
);

router.post(
  "/spare-parts",
  requirePermission("canManageItAssets"),
  asyncHandler(async (req, res) => {
    const currentActor = actor(req);
    const partCode = cleanText(req.body.partCode).toUpperCase();
    const name = cleanText(req.body.name);
    if (!partCode || !name) throw new ApiError(400, "كود القطعة واسمها مطلوبان.");
    const sparePart = await SparePart.create({
      partCode,
      name,
      category: cleanText(req.body.category, "أخرى"),
      brand: cleanText(req.body.brand),
      model: cleanText(req.body.model),
      unit: cleanText(req.body.unit, "قطعة"),
      quantityAvailable: Number(req.body.quantityAvailable) || 0,
      quantityReserved: Number(req.body.quantityReserved) || 0,
      damagedQuantity: Number(req.body.damagedQuantity) || 0,
      minimumQuantity: Number(req.body.minimumQuantity) || 0,
      criticalQuantity: Number(req.body.criticalQuantity) || 0,
      preferredQuantity: Number(req.body.preferredQuantity) || 0,
      location: cleanText(req.body.location, "المخزن الرئيسي"),
      hasSerialNumbers: req.body.hasSerialNumbers === true,
      notes: cleanText(req.body.notes),
      createdBy: currentActor.id,
      updatedBy: currentActor.id,
    });
    await logAction(req, {
      action: "create",
      entityType: "spare_part",
      entityId: sparePart._id,
      summary: `إضافة قطعة الغيار ${sparePart.partCode}`,
    });
    res.status(201).json({ sparePart });
  }),
);

router.patch(
  "/spare-parts/:id",
  requirePermission("canManageItAssets"),
  asyncHandler(async (req, res) => {
    const sparePart = await SparePart.findOne({ _id: req.params.id, isArchived: false });
    if (!sparePart) throw new ApiError(404, "Spare part not found.");
    const textFields = ["name", "category", "brand", "model", "unit", "location", "notes"];
    const numberFields = [
      "quantityAvailable", "quantityReserved", "damagedQuantity", "minimumQuantity",
      "criticalQuantity", "preferredQuantity",
    ];
    for (const key of textFields) if (Object.prototype.hasOwnProperty.call(req.body, key)) sparePart[key] = cleanText(req.body[key]);
    for (const key of numberFields) if (Object.prototype.hasOwnProperty.call(req.body, key)) sparePart[key] = Math.max(0, Number(req.body[key]) || 0);
    if (Object.prototype.hasOwnProperty.call(req.body, "hasSerialNumbers")) sparePart.hasSerialNumbers = req.body.hasSerialNumbers === true;
    sparePart.updatedBy = req.user.id;
    await sparePart.save();
    await logAction(req, {
      action: "update",
      entityType: "spare_part",
      entityId: sparePart._id,
      summary: `تحديث قطعة الغيار ${sparePart.partCode}`,
    });
    res.json({ sparePart });
  }),
);

router.delete(
  "/spare-parts/:id",
  requirePermission("canDeleteItAssets"),
  asyncHandler(async (req, res) => {
    await assertPeriodOpen();
    const sparePart = await SparePart.findOne({
      _id: req.params.id,
      isArchived: false,
    });
    if (!sparePart) throw new ApiError(404, "Spare part not found.");
    if (sparePart.quantityReserved > 0) {
      throw new ApiError(409, "لا يمكن حذف قطعة غيار لها كمية محجوزة.");
    }
    const activeOperation = await ItOperation.exists({
      sparePartId: sparePart._id,
      status: { $in: ["draft", "pending_audit", "approved", "in_progress"] },
    });
    if (activeOperation) {
      throw new ApiError(409, "لا يمكن حذف القطعة لوجود حركة مفتوحة مرتبطة بها.");
    }
    sparePart.isArchived = true;
    sparePart.updatedBy = req.user.id;
    await sparePart.save();
    await logAction(req, {
      action: "delete",
      entityType: "spare_part",
      entityId: sparePart._id,
      summary: `أرشفة قطعة الغيار ${sparePart.partCode}`,
      metadata: { reason: cleanText(req.body.reason) },
    });
    res.json({ success: true });
  }),
);

router.get(
  "/operations",
  requirePermission("canViewItAssets"),
  asyncHandler(async (req, res) => {
    const query = {};
    if (req.query.type) query.operationType = req.query.type;
    if (req.query.status) query.status = req.query.status;
    const operations = await ItOperation.find(query)
      .populate("assetId", "assetCode assetType serialNumber status location assignedTo")
      .populate("sparePartId", "partCode name quantityAvailable quantityReserved damagedQuantity")
      .sort({ createdAt: -1 })
      .lean();
    res.json({ operations });
  }),
);

router.post(
  "/operations",
  requirePermission("canExecuteItAssets"),
  asyncHandler(async (req, res) => {
    await assertPeriodOpen();
    const operationType = cleanText(req.body.operationType);
    if (![
      "movement", "maintenance", "transfer", "replacement", "damaged", "inventory",
      "custody", "employee_clearance", "branch_handover", "temporary_assignment", "scrap",
    ].includes(operationType)) {
      throw new ApiError(400, "نوع العملية غير صالح.");
    }
    const currentActor = actor(req);
    const documentNumber = await nextDocumentNumber(operationType);
    const workflowRule = await ItControlRecord.findOne({
      recordType: "workflow_rule",
      status: { $in: ["active", "approved"] },
      "data.operationType": operationType,
    }).sort({ updatedAt: -1 }).lean();
    const workflow = workflowRule?.data || {};
    const requiresAudit =
      workflow.needsAuditAcknowledgement === true ||
      workflow.needsAuditApproval === true ||
      req.body.requiresAudit !== false;
    const operation = await ItOperation.create({
      documentNumber,
      operationType,
      title: cleanText(req.body.title, "عملية IT"),
      assetId: mongoose.isValidObjectId(req.body.assetId) ? req.body.assetId : null,
      sparePartId: mongoose.isValidObjectId(req.body.sparePartId) ? req.body.sparePartId : null,
      quantity: Math.max(0, Number(req.body.quantity) || 0),
      fromLocation: cleanText(req.body.fromLocation),
      toLocation: cleanText(req.body.toLocation),
      assignedTo: cleanText(req.body.assignedTo),
      status: requiresAudit ? "pending_audit" : "approved",
      details: cleanText(req.body.details),
      rootCause: cleanText(req.body.rootCause),
      priority: cleanText(req.body.priority, "medium"),
      dueAt: operationType === "maintenance"
        ? new Date(Date.now() + ({
            low: 5 * 86400000,
            medium: 3 * 86400000,
            high: 86400000,
            critical: 4 * 3600000,
          }[cleanText(req.body.priority, "medium")] || 3 * 86400000))
        : null,
      expectedReturnDate: optionalDate(req.body.expectedReturnDate),
      cost: Math.max(0, Number(req.body.cost) || 0),
      metadata: {
        ...(req.body.metadata && typeof req.body.metadata === "object" ? req.body.metadata : {}),
        workflowRuleId: workflowRule?._id?.toString() || null,
        needsAttachment: workflow.needsAttachment === true,
        needsDigitalSignature: true,
        needsReceiverSignature: workflow.needsReceiverSignature === true,
      },
      createdBy: currentActor.id,
      createdByName: currentActor.name,
    });
    if (operation.sparePartId && operation.quantity > 0 && operationType === "replacement") {
      const sparePart = await SparePart.findById(operation.sparePartId);
      if (!sparePart) throw new ApiError(404, "Spare part not found.");
      const freeQuantity = sparePart.quantityAvailable - sparePart.quantityReserved;
      if (freeQuantity < operation.quantity) {
        await operation.deleteOne();
        throw new ApiError(409, "الكمية الحرة لا تكفي للحجز.");
      }
      sparePart.quantityReserved += operation.quantity;
      sparePart.updatedBy = currentActor.id;
      await sparePart.save();
      operation.metadata = { ...(operation.metadata || {}), stockReserved: true };
      operation.markModified("metadata");
      await operation.save();
    }
    if (operation.assetId) {
      await ItAsset.updateOne(
        { _id: operation.assetId },
        {
          $push: {
            timeline: {
              action: operationType,
              details: operation.details || operation.title,
              documentNumber,
              performedBy: currentActor.id,
              performedByName: currentActor.name,
            },
          },
        },
      );
    }
    await logAction(req, {
      action: "create_operation",
      entityType: "operation",
      entityId: operation._id,
      documentNumber,
      summary: `إنشاء ${operation.title}`,
    });
    res.status(201).json({ operation });
  }),
);

router.post(
  "/operations/:id/acknowledge",
  requirePermission("canAuditItAssets"),
  asyncHandler(async (req, res) => {
    const operation = await ItOperation.findById(req.params.id);
    if (!operation) throw new ApiError(404, "Operation not found.");
    await assertPeriodOpen(operation.createdAt || new Date());
    if (operation.status !== "pending_audit") throw new ApiError(409, "العملية ليست بانتظار المراجعة.");
    operation.status = req.body.approved === false ? "rejected" : "approved";
    operation.auditNote = cleanText(req.body.auditNote);
    operation.auditReference = cleanText(req.body.auditReference);
    operation.acknowledgedBy = req.user.id;
    operation.acknowledgedAt = new Date();
    await operation.save();
    await logAction(req, {
      action: operation.status === "approved" ? "audit_approved" : "audit_rejected",
      entityType: "operation",
      entityId: operation._id,
      documentNumber: operation.documentNumber,
      summary: `${operation.status === "approved" ? "اعتماد" : "رفض"} ${operation.documentNumber}`,
    });
    res.json({ operation });
  }),
);

router.post(
  "/operations/:id/complete",
  requirePermission("canExecuteItAssets"),
  asyncHandler(async (req, res) => {
    const operation = await ItOperation.findById(req.params.id);
    if (!operation) throw new ApiError(404, "Operation not found.");
    await assertPeriodOpen(operation.createdAt || new Date());
    if (!["approved", "in_progress"].includes(operation.status)) {
      throw new ApiError(409, "يجب اعتماد العملية قبل تنفيذها.");
    }
    if (operation.metadata?.needsAttachment) {
      const hasAttachment = await ItAttachment.exists({
        entityType: "operation",
        entityId: operation._id,
      });
      if (!hasAttachment) {
        throw new ApiError(409, "يجب رفع المرفق المطلوب قبل التنفيذ.");
      }
    }
    if (!operation.signedAt) {
      throw new ApiError(409, "يجب توقيع المستند إلكترونيًا قبل التنفيذ.");
    }
    const currentActor = actor(req);
    if (operation.operationType === "maintenance" && !cleanText(req.body.solution)) {
      throw new ApiError(400, "يجب تسجيل الحل قبل إغلاق الصيانة.");
    }
    if (operation.sparePartId && operation.quantity > 0) {
      const sparePart = await SparePart.findById(operation.sparePartId);
      if (!sparePart) throw new ApiError(404, "Spare part not found.");
      const available = operation.metadata?.stockReserved
        ? sparePart.quantityAvailable
        : sparePart.quantityAvailable - sparePart.quantityReserved;
      if (available < operation.quantity) throw new ApiError(409, "الكمية المتاحة لا تكفي لتنفيذ العملية.");
      sparePart.quantityAvailable -= operation.quantity;
      if (operation.metadata?.stockReserved) {
        sparePart.quantityReserved = Math.max(0, sparePart.quantityReserved - operation.quantity);
      }
      sparePart.updatedBy = currentActor.id;
      await sparePart.save();
    }
    if (operation.assetId) {
      const asset = await ItAsset.findById(operation.assetId);
      if (asset) {
        if (operation.toLocation) asset.location = operation.toLocation;
        if (operation.assignedTo) asset.assignedTo = operation.assignedTo;
        if (operation.operationType === "maintenance") asset.status = "available";
        if (operation.operationType === "damaged") asset.status = "damaged_store";
        if (operation.operationType === "scrap") asset.status = "scrapped";
        if (operation.operationType === "temporary_assignment") asset.status = "assigned_to_employee";
        if (operation.operationType === "employee_clearance") {
          asset.status = "available";
          asset.assignedTo = "";
          asset.location = operation.toLocation || "المخزن الرئيسي";
        }
        asset.updatedBy = currentActor.id;
        asset.timeline.push({
          action: `${operation.operationType}_completed`,
          details: cleanText(req.body.solution, operation.details || "تم تنفيذ العملية."),
          documentNumber: operation.documentNumber,
          performedBy: currentActor.id,
          performedByName: currentActor.name,
        });
        await asset.save();
      }
    }
    if (operation.operationType === "replacement" && operation.metadata?.oldPartCode) {
      await logAction(req, {
        action: "old_part_to_damaged_store",
        entityType: "replacement",
        entityId: operation._id,
        documentNumber: operation.documentNumber,
        summary: `القطعة القديمة ${operation.metadata.oldPartCode} إلى مخزن التالف`,
      });
      await logAction(req, {
        action: "new_part_installed",
        entityType: "replacement",
        entityId: operation._id,
        documentNumber: operation.documentNumber,
        summary: "خصم القطعة الجديدة وتركيبها داخل الجهاز",
      });
    }
    operation.status = "completed";
    operation.solution = cleanText(req.body.solution);
    operation.completedBy = currentActor.id;
    operation.completedAt = new Date();
    await operation.save();
    await logAction(req, {
      action: "complete_operation",
      entityType: "operation",
      entityId: operation._id,
      documentNumber: operation.documentNumber,
      summary: `تنفيذ ${operation.documentNumber}`,
    });
    res.json({ operation });
  }),
);

router.get(
  "/audit-log",
  requirePermission("canAuditItAssets"),
  asyncHandler(async (req, res) => {
    const logs = await ItAuditLog.find().sort({ createdAt: -1 }).limit(500).lean();
    res.json({ logs });
  }),
);

module.exports = router;
