const path = require("path");
const PDFDocument = require("pdfkit");
const ExcelJS = require("exceljs");
const QRCode = require("qrcode");

const ItAsset = require("./models/it-asset.model");
const SparePart = require("./models/spare-part.model");
const ItOperation = require("./models/it-operation.model");
const ItControlRecord = require("./models/it-control-record.model");
const ItAuditLog = require("./models/it-audit-log.model");
const { escapeRegExp } = require("../utils/regex.util");

const arabicFont = path.resolve(__dirname, "../assets/fonts/NotoSansArabic-Regular.ttf");
const arabicBoldFont = path.resolve(__dirname, "../assets/fonts/NotoSansArabic-Bold.ttf");

function configurePdfResponse(res, fileName) {
  res.setHeader("Content-Type", "application/pdf");
  res.setHeader("Content-Disposition", `attachment; filename="${encodeURIComponent(fileName)}"`);
}

function text(doc, value, options = {}) {
  doc.text(String(value ?? "-"), { align: "right", ...options });
}

function field(doc, label, value) {
  doc.font(arabicBoldFont).fontSize(10);
  text(doc, `${label}:`);
  doc.font(arabicFont).fontSize(11);
  text(doc, value || "-");
  doc.moveDown(0.35);
}

async function writeQr(doc, payload) {
  const buffer = await QRCode.toBuffer(payload, { width: 180, margin: 1 });
  doc.image(buffer, doc.page.width - 145, 45, { width: 90 });
}

async function streamOperationPdf(res, operation) {
  configurePdfResponse(res, `${operation.documentNumber}.pdf`);
  const doc = new PDFDocument({ size: "A4", margin: 45, info: { Title: operation.documentNumber } });
  doc.pipe(res);
  doc.font(arabicBoldFont).fontSize(20);
  text(doc, "نظام إدارة أصول وتقنية المعلومات");
  doc.fontSize(15);
  text(doc, operation.title);
  await writeQr(doc, `itasset://operation/${operation._id}`);
  doc.moveDown(1.2);
  field(doc, "رقم المستند", operation.documentNumber);
  field(doc, "النوع", operation.operationType);
  field(doc, "الحالة", operation.status);
  field(doc, "الجهاز", operation.assetId?.assetCode);
  field(doc, "السيريال", operation.assetId?.serialNumber);
  field(doc, "قطعة الغيار", operation.sparePartId?.partCode);
  field(doc, "الكمية", operation.quantity);
  field(doc, "من", operation.fromLocation);
  field(doc, "إلى", operation.toLocation);
  field(doc, "المستلم", operation.assignedTo);
  field(doc, "التفاصيل", operation.details);
  field(doc, "الحل / التنفيذ", operation.solution);
  field(doc, "مرجع المراجعة", operation.auditReference);
  field(doc, "ملاحظات المراجعة", operation.auditNote);
  field(doc, "أعد بواسطة", operation.createdByName);
  field(doc, "التوقيع الإلكتروني", operation.signedByName);
  field(doc, "تاريخ الإنشاء", operation.createdAt?.toISOString());
  doc.moveDown(1.5);
  doc.font(arabicBoldFont).fontSize(11);
  text(doc, "التوقيعات");
  doc.moveDown();
  text(doc, "إعداد: ____________________     مراجعة: ____________________");
  text(doc, "تسليم: ____________________     استلام: ____________________");
  doc.end();
}

async function streamControlRecordPdf(res, record) {
  configurePdfResponse(res, `${record.recordNumber}.pdf`);
  const doc = new PDFDocument({ size: "A4", margin: 45 });
  doc.pipe(res);
  doc.font(arabicBoldFont).fontSize(20);
  text(doc, "نظام إدارة أصول وتقنية المعلومات");
  doc.fontSize(15);
  text(doc, record.title);
  await writeQr(doc, `itasset://record/${record._id}`);
  doc.moveDown(1.2);
  field(doc, "رقم المستند", record.recordNumber);
  field(doc, "نوع المستند", record.recordType);
  field(doc, "الحالة", record.status);
  field(doc, "الفرع", record.branchName);
  field(doc, "المكان", record.location);
  field(doc, "المسؤول", record.assignedTo);
  field(doc, "السبب", record.reason);
  field(doc, "الملاحظات", record.notes);
  field(doc, "أعد بواسطة", record.createdByName);
  field(doc, "البيانات", JSON.stringify(record.data || {}, null, 2));
  doc.moveDown();
  doc.font(arabicBoldFont).fontSize(11);
  text(doc, "التوقيعات الإلكترونية");
  for (const signature of record.signatures || []) {
    text(doc, `${signature.role}: ${signature.userName} - ${signature.signedAt?.toISOString()}`);
  }
  doc.end();
}

async function streamAssetLabelPdf(res, asset) {
  configurePdfResponse(res, `${asset.assetCode}-label.pdf`);
  const doc = new PDFDocument({ size: [300, 190], margin: 16 });
  doc.pipe(res);
  const qr = await QRCode.toBuffer(`itasset://asset/${asset._id}`, { width: 220, margin: 1 });
  doc.image(qr, 15, 15, { width: 120 });
  doc.font(arabicBoldFont).fontSize(17).text(asset.assetCode, 145, 25, { width: 135, align: "center" });
  doc.font(arabicFont).fontSize(11).text(asset.assetType, 145, 58, { width: 135, align: "center" });
  doc.text(asset.serialNumber || "بدون سيريال", 145, 82, { width: 135, align: "center" });
  doc.text(asset.location || "-", 145, 108, { width: 135, align: "center" });
  doc.end();
}

async function streamSparePartLabelPdf(res, part) {
  configurePdfResponse(res, `${part.partCode}-label.pdf`);
  const doc = new PDFDocument({ size: [300, 190], margin: 16 });
  doc.pipe(res);
  const qr = await QRCode.toBuffer(`itasset://spare-part/${part._id}`, {
    width: 220,
    margin: 1,
  });
  doc.image(qr, 15, 15, { width: 120 });
  doc
    .font(arabicBoldFont)
    .fontSize(17)
    .text(part.partCode, 145, 25, { width: 135, align: "center" });
  doc
    .font(arabicFont)
    .fontSize(11)
    .text(part.name, 145, 58, { width: 135, align: "center" });
  doc.text(`المتاح: ${part.quantityAvailable}`, 145, 88, {
    width: 135,
    align: "center",
  });
  doc.text(part.location || "-", 145, 112, { width: 135, align: "center" });
  doc.end();
}

async function streamExcelReport(res, reportType) {
  const workbook = new ExcelJS.Workbook();
  workbook.creator = "IT Asset Management";
  const sheet = workbook.addWorksheet("Report", { views: [{ rightToLeft: true }] });

  if (reportType === "spare-parts") {
    const parts = await SparePart.find({ isArchived: false }).lean();
    sheet.columns = [
      { header: "كود القطعة", key: "partCode", width: 18 },
      { header: "الاسم", key: "name", width: 28 },
      { header: "التصنيف", key: "category", width: 20 },
      { header: "المتاح", key: "available", width: 12 },
      { header: "المحجوز", key: "reserved", width: 12 },
      { header: "التالف", key: "damaged", width: 12 },
      { header: "حد الطلب", key: "minimum", width: 12 },
      { header: "المكان", key: "location", width: 26 },
    ];
    parts.forEach((part) => sheet.addRow({
      partCode: part.partCode,
      name: part.name,
      category: part.category,
      available: part.quantityAvailable,
      reserved: part.quantityReserved,
      damaged: part.damagedQuantity,
      minimum: part.minimumQuantity,
      location: part.location,
    }));
  } else if (reportType === "operations") {
    const operations = await ItOperation.find().populate("assetId", "assetCode").lean();
    sheet.columns = [
      { header: "رقم المستند", key: "number", width: 22 },
      { header: "النوع", key: "type", width: 18 },
      { header: "العنوان", key: "title", width: 32 },
      { header: "الجهاز", key: "asset", width: 18 },
      { header: "الحالة", key: "status", width: 18 },
      { header: "المراجعة", key: "audit", width: 22 },
      { header: "التاريخ", key: "createdAt", width: 22 },
    ];
    operations.forEach((operation) => sheet.addRow({
      number: operation.documentNumber,
      type: operation.operationType,
      title: operation.title,
      asset: operation.assetId?.assetCode || "",
      status: operation.status,
      audit: operation.auditReference,
      createdAt: operation.createdAt,
    }));
  } else {
    const assets = await ItAsset.find({ isArchived: false }).lean();
    sheet.columns = [
      { header: "كود الجهاز", key: "assetCode", width: 18 },
      { header: "النوع", key: "assetType", width: 20 },
      { header: "الماركة", key: "brand", width: 18 },
      { header: "الموديل", key: "model", width: 18 },
      { header: "السيريال", key: "serialNumber", width: 24 },
      { header: "الحالة", key: "status", width: 20 },
      { header: "الفرع", key: "branchName", width: 22 },
      { header: "المكان", key: "location", width: 28 },
      { header: "العهدة", key: "assignedTo", width: 24 },
      { header: "المورد", key: "vendor", width: 20 },
    ];
    assets.forEach((asset) => sheet.addRow(asset));
  }

  sheet.getRow(1).font = { bold: true };
  sheet.autoFilter = { from: "A1", to: `${String.fromCharCode(64 + sheet.columnCount)}1` };
  res.setHeader("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
  res.setHeader("Content-Disposition", `attachment; filename="it-${reportType}-report.xlsx"`);
  await workbook.xlsx.write(res);
  res.end();
}

const reportDefinitions = {
  assets: {
    title: "تقرير الأجهزة والأصول",
    columns: [
      ["assetCode", "كود الجهاز"],
      ["assetType", "النوع"],
      ["brand", "الماركة"],
      ["model", "الموديل"],
      ["serialNumber", "السيريال"],
      ["status", "الحالة"],
      ["branchName", "الفرع"],
      ["location", "المكان"],
      ["assignedTo", "العهدة"],
      ["vendor", "المورد"],
    ],
  },
  "spare-parts": {
    title: "تقرير قطع الغيار والمخزون",
    columns: [
      ["partCode", "كود القطعة"],
      ["name", "الاسم"],
      ["category", "التصنيف"],
      ["quantityAvailable", "المتاح"],
      ["quantityReserved", "المحجوز"],
      ["damagedQuantity", "التالف"],
      ["minimumQuantity", "حد الطلب"],
      ["location", "المكان"],
    ],
  },
  operations: {
    title: "تقرير الحركات",
    columns: [
      ["documentNumber", "رقم المستند"],
      ["operationType", "نوع الحركة"],
      ["title", "العنوان"],
      ["assetCode", "الجهاز"],
      ["partCode", "قطعة الغيار"],
      ["quantity", "الكمية"],
      ["status", "الحالة"],
      ["assignedTo", "المستلم"],
      ["signedByName", "التوقيع"],
      ["createdByName", "أنشأ بواسطة"],
      ["createdAt", "تاريخ الإنشاء"],
      ["completedAt", "تاريخ التنفيذ"],
    ],
  },
  maintenance: {
    title: "تقرير الصيانة",
    columns: [
      ["documentNumber", "رقم المستند"],
      ["assetCode", "الجهاز"],
      ["title", "العطل"],
      ["priority", "الأولوية"],
      ["rootCause", "السبب الجذري"],
      ["solution", "الحل"],
      ["cost", "التكلفة"],
      ["status", "الحالة"],
      ["signedByName", "التوقيع"],
      ["createdAt", "التاريخ"],
    ],
  },
  inventory: {
    title: "تقرير جلسات الجرد",
    columns: [
      ["recordNumber", "رقم الجلسة"],
      ["title", "العنوان"],
      ["branchName", "الفرع"],
      ["location", "المكان"],
      ["status", "الحالة"],
      ["expectedCount", "المتوقع"],
      ["scannedCount", "الممسوح"],
      ["discrepancyCount", "الفروقات"],
      ["createdByName", "أنشأ بواسطة"],
      ["createdAt", "تاريخ البدء"],
      ["closedAt", "تاريخ الإغلاق"],
    ],
  },
  damaged: {
    title: "تقرير التالف والتكهين",
    columns: [
      ["recordNumber", "رقم المستند"],
      ["recordType", "النوع"],
      ["assetCode", "الجهاز"],
      ["title", "العنوان"],
      ["reason", "السبب"],
      ["status", "الحالة"],
      ["branchName", "الفرع"],
      ["createdByName", "أنشأ بواسطة"],
      ["createdAt", "التاريخ"],
    ],
  },
  procurement: {
    title: "تقرير الموردين والمشتريات",
    columns: [
      ["recordNumber", "رقم المستند"],
      ["recordType", "النوع"],
      ["title", "العنوان"],
      ["status", "الحالة"],
      ["branchName", "الفرع"],
      ["assignedTo", "المسؤول"],
      ["reason", "السبب"],
      ["createdByName", "أنشأ بواسطة"],
      ["createdAt", "التاريخ"],
    ],
  },
  audit: {
    title: "سجل عمليات النظام",
    columns: [
      ["action", "الإجراء"],
      ["entityType", "نوع السجل"],
      ["documentNumber", "رقم المستند"],
      ["summary", "الوصف"],
      ["actorName", "المستخدم"],
      ["ipAddress", "عنوان الشبكة"],
      ["createdAt", "التاريخ"],
    ],
  },
};

function reportDateFilter(filters, field = "createdAt") {
  const range = {};
  if (filters.dateFrom) {
    const date = new Date(`${filters.dateFrom}T00:00:00.000Z`);
    if (!Number.isNaN(date.getTime())) range.$gte = date;
  }
  if (filters.dateTo) {
    const date = new Date(`${filters.dateTo}T23:59:59.999Z`);
    if (!Number.isNaN(date.getTime())) range.$lte = date;
  }
  return Object.keys(range).length ? { [field]: range } : {};
}

function applyCommonFilters(query, filters) {
  if (filters.status) query.status = filters.status;
  if (filters.branch) query.branchName = new RegExp(escapeRegExp(String(filters.branch).trim()), "i");
  if (filters.category) query.category = new RegExp(escapeRegExp(String(filters.category).trim()), "i");
  if (filters.employee) query.assignedTo = new RegExp(escapeRegExp(String(filters.employee).trim()), "i");
  return query;
}

async function buildReport(reportType, filters = {}) {
  const type = reportDefinitions[reportType] ? reportType : "assets";
  let rows = [];
  if (type === "assets") {
    const query = applyCommonFilters(
      { isArchived: false, ...reportDateFilter(filters) },
      filters,
    );
    rows = await ItAsset.find(query).sort({ updatedAt: -1 }).lean();
  } else if (type === "spare-parts") {
    const query = applyCommonFilters(
      { isArchived: false, ...reportDateFilter(filters) },
      filters,
    );
    rows = await SparePart.find(query).sort({ updatedAt: -1 }).lean();
  } else if (["operations", "maintenance"].includes(type)) {
    const query = applyCommonFilters(
      {
        ...reportDateFilter(filters),
        ...(type === "maintenance" ? { operationType: "maintenance" } : {}),
      },
      filters,
    );
    const operations = await ItOperation.find(query)
      .populate("assetId", "assetCode")
      .populate("sparePartId", "partCode")
      .sort({ createdAt: -1 })
      .lean();
    rows = operations.map((item) => ({
      ...item,
      assetCode: item.assetId?.assetCode || "",
      partCode: item.sparePartId?.partCode || "",
    }));
  } else if (type === "audit") {
    const query = { ...reportDateFilter(filters) };
    if (filters.employee) query.actorName = new RegExp(escapeRegExp(String(filters.employee).trim()), "i");
    rows = await ItAuditLog.find(query).sort({ createdAt: -1 }).lean();
  } else {
    const recordTypes = {
      inventory: ["inventory_session", "discrepancy", "correction"],
      damaged: ["damaged_inspection", "scrap_request"],
      procurement: ["vendor", "purchase_request"],
    }[type];
    const query = applyCommonFilters(
      { recordType: { $in: recordTypes }, ...reportDateFilter(filters) },
      filters,
    );
    const records = await ItControlRecord.find(query)
      .populate("assetId", "assetCode")
      .sort({ createdAt: -1 })
      .lean();
    rows = records.map((item) => ({
      ...item,
      assetCode: item.assetId?.assetCode || "",
      expectedCount: item.data?.expectedAssetIds?.length || 0,
      scannedCount: item.data?.scannedAssetIds?.length || 0,
      discrepancyCount: item.data?.discrepancyCount || 0,
    }));
  }
  return {
    type,
    title: reportDefinitions[type].title,
    columns: reportDefinitions[type].columns,
    rows,
    summary: { total: rows.length, generatedAt: new Date() },
  };
}

function formatReportValue(value) {
  if (value instanceof Date) return value.toISOString();
  if (value && typeof value === "object") return JSON.stringify(value);
  return value ?? "";
}

async function streamFilteredExcelReport(res, reportType, filters = {}) {
  const report = await buildReport(reportType, filters);
  const workbook = new ExcelJS.Workbook();
  workbook.creator = "IT Asset Management";
  const sheet = workbook.addWorksheet("Report", { views: [{ rightToLeft: true }] });
  sheet.columns = report.columns.map(([key, header]) => ({ key, header, width: 24 }));
  report.rows.forEach((row) => {
    sheet.addRow(
      Object.fromEntries(
        report.columns.map(([key]) => [key, formatReportValue(row[key])]),
      ),
    );
  });
  sheet.getRow(1).font = { bold: true, color: { argb: "FFFFFFFF" } };
  sheet.getRow(1).fill = {
    type: "pattern",
    pattern: "solid",
    fgColor: { argb: "FF184E77" },
  };
  sheet.autoFilter = {
    from: "A1",
    to: { row: 1, column: Math.max(1, report.columns.length) },
  };
  res.setHeader(
    "Content-Type",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  );
  res.setHeader(
    "Content-Disposition",
    `attachment; filename="it-${report.type}-report.xlsx"`,
  );
  await workbook.xlsx.write(res);
  res.end();
}

async function streamReportPdf(res, reportType, filters = {}) {
  const report = await buildReport(reportType, filters);
  configurePdfResponse(res, `it-${report.type}-report.pdf`);
  const doc = new PDFDocument({ size: "A4", margin: 36, layout: "landscape" });
  doc.pipe(res);
  doc.font(arabicBoldFont).fontSize(18);
  text(doc, report.title);
  doc.font(arabicFont).fontSize(9);
  text(doc, `الإجمالي: ${report.rows.length} - تاريخ الإصدار: ${new Date().toISOString()}`);
  doc.moveDown();
  for (const row of report.rows) {
    if (doc.y > doc.page.height - 70) doc.addPage();
    doc.font(arabicBoldFont).fontSize(9);
    text(
      doc,
      report.columns
        .map(([key, label]) => `${label}: ${formatReportValue(row[key]) || "-"}`)
        .join("  |  "),
    );
    doc.moveDown(0.35);
  }
  doc.end();
}

async function getDataQuality() {
  const [assets, spareParts, operations, inventorySessions] = await Promise.all([
    ItAsset.find({ isArchived: false }).lean(),
    SparePart.find({ isArchived: false }).lean(),
    ItOperation.find().lean(),
    ItControlRecord.find({ recordType: "inventory_session" }).sort({ createdAt: -1 }).lean(),
  ]);
  const duplicateSerials = {};
  for (const asset of assets) {
    if (!asset.serialNumber) continue;
    duplicateSerials[asset.serialNumber] = (duplicateSerials[asset.serialNumber] || 0) + 1;
  }
  const scannedIds = new Set(
    inventorySessions.flatMap((session) => session.data?.scannedAssetIds || []).map(String),
  );
  return {
    assetsWithoutSerial: assets.filter((asset) => !asset.serialNumber).length,
    assetsWithoutLocation: assets.filter((asset) => !asset.location).length,
    assetsWithoutCustodian: assets.filter((asset) => !asset.assignedTo).length,
    sparePartsBelowMinimum: spareParts.filter(
      (part) => part.quantityAvailable - part.quantityReserved <= part.minimumQuantity,
    ).length,
    movementsWithoutReceiver: operations.filter(
      (operation) => ["movement", "transfer", "custody"].includes(operation.operationType) && !operation.assignedTo,
    ).length,
    assetsNotScanned: assets.filter((asset) => !scannedIds.has(String(asset._id))).length,
    duplicateSerials: Object.values(duplicateSerials).filter((count) => count > 1).length,
    assetsWithoutQr: 0,
  };
}

module.exports = {
  streamOperationPdf,
  streamControlRecordPdf,
  streamAssetLabelPdf,
  streamSparePartLabelPdf,
  streamExcelReport,
  buildReport,
  streamFilteredExcelReport,
  streamReportPdf,
  getDataQuality,
};
