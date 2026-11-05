const fs = require("fs");
const path = require("path");
const ExcelJS = require("exceljs");
const PDFDocument = require("pdfkit");
const bidiFactory = require("bidi-js");
const { ArabicShaper } = require("arabic-persian-reshaper");

const PrinterReport = require("../models/printer-report.model");

const bidi = bidiFactory();
const ARABIC_REGEX = /[\u0600-\u06FF]/;
const SHEETS_PER_REAM = 500;
const SHEETS_PER_CLIENT = 16;
const MOJIBAKE_REGEX = /[ØÙ][^\s]*/;

function fixText(value) {
  if (value == null) return "";
  const text = String(value);
  if (!MOJIBAKE_REGEX.test(text)) return text;
  try {
    return Buffer.from(text, "latin1").toString("utf8");
  } catch (_) {
    return text;
  }
}

function paperMetrics(totalPages) {
  const pages = Math.max(0, Number(totalPages || 0));
  return {
    exactReams: pages / SHEETS_PER_REAM,
    fullReams: Math.floor(pages / SHEETS_PER_REAM),
    remainingSheets: pages % SHEETS_PER_REAM,
    requiredReams: pages === 0 ? 0 : Math.ceil(pages / SHEETS_PER_REAM),
    estimatedClients: pages === 0 ? 0 : Math.ceil(pages / SHEETS_PER_CLIENT),
  };
}

function dataQualityLabel(item = {}) {
  if (item.hasCounterAnomalies || (item.anomalyFlags || []).length > 0) return "قراءات شاذة - تمت معالجتها";
  if (item.hasSuspiciousConsumption || Number(item.suspiciousPrintersCount || 0) > 0) return "مرتفع جدًا - يحتاج مراجعة";
  if (item.hasPartialData || item.hasStaleBaseline) return "جزئي - يحتاج مراجعة";
  if (item.hasBaselineSnapshot === false) return "جزئي";
  return "مكتمل";
}

function hasArabic(text) {
  return ARABIC_REGEX.test(fixText(text));
}

function formatBidiLine(label, value) {
  const cleanLabel = fixText(label);
  const cleanValue = fixText(value);
  const hasArabicStart = /[\u0600-\u06FF]/.test(cleanValue.trim().charAt(0));
  if (hasArabicStart) {
    return `${cleanLabel}: ${cleanValue}`;
  } else {
    return `${cleanLabel}: \u200E${cleanValue}`;
  }
}

function shapeArabicLine(text) {
  const input = fixText(text);
  if (!hasArabic(input)) return input;
  const shaped = ArabicShaper.convertArabic(input);
  const embedding = bidi.getEmbeddingLevels(shaped, "rtl");
  return bidi.getReorderedString(shaped, embedding);
}

function shapeArabicText(text) {
  return fixText(text);
}

function arabicStatus(status) {
  switch (status) {
    case "online":
      return "متصلة";
    case "offline":
      return "غير متصلة";
    case "warning":
      return "تحتاج عناية";
    case "error":
      return "خطأ";
    default:
      return status || "-";
  }
}

function configureArabicPdf(doc) {
  let regularPath = path.join(
    __dirname,
    "../../assets/fonts/Amiri-Regular.ttf",
  );
  let boldPath = path.join(
    __dirname,
    "../../assets/fonts/Amiri-Bold.ttf",
  );

  if (!fs.existsSync(regularPath)) {
    regularPath = path.join(
      __dirname,
      "../../assets/fonts/NotoSansArabic-Regular.ttf",
    );
    boldPath = path.join(
      __dirname,
      "../../assets/fonts/NotoSansArabic-Bold.ttf",
    );
  }

  if (!fs.existsSync(regularPath)) {
    regularPath = path.join(
      __dirname,
      "../../../../desktop_app/assets/fonts/NotoSansArabic-Regular.ttf",
    );
    boldPath = path.join(
      __dirname,
      "../../../../desktop_app/assets/fonts/NotoSansArabic-Bold.ttf",
    );
  }

  if (fs.existsSync(regularPath)) {
    doc.registerFont("Arabic", regularPath);
  }
  if (fs.existsSync(boldPath)) {
    doc.registerFont("ArabicBold", boldPath);
  }
  doc.font(fs.existsSync(regularPath) ? "Arabic" : "Helvetica");
}

function withArabicFont(doc, bold = false) {
  if (bold && doc._registeredFonts?.ArabicBold) {
    doc.font("ArabicBold");
  } else if (doc._registeredFonts?.Arabic) {
    doc.font("Arabic");
  } else {
    doc.font(bold ? "Helvetica-Bold" : "Helvetica");
  }
  return doc;
}

function formatDate(value) {
  if (!value) return "-";
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toISOString().replace("T", " ").slice(0, 19);
}

function lineValue(value) {
  if (value == null || value === "") return "-";
  if (Array.isArray(value)) {
    return value.map(lineValue).filter(Boolean).join("، ");
  }
  if (value instanceof Date) return formatDate(value);
  if (typeof value === "object") {
    return Object.entries(value)
      .map(([key, entry]) => `${humanizeKey(key)}: ${lineValue(entry)}`)
      .join(" | ");
  }
  return fixText(value);
}

function humanizeKey(key) {
  const labels = {
    productName: "اسم المنتج",
    productNumber: "رقم المنتج",
    serialNumber: "الرقم التسلسلي",
    serviceId: "رقم تعريف الخدمة",
    firmwareVersion: "إصدار البرنامج الثابت",
    engineFirmware: "برنامج المحرك",
    region: "المنطقة",
    memoryTotalKb: "إجمالي الذاكرة",
    memoryAvailableKb: "الذاكرة المتاحة",
    installedPersonalities: "اللغات المثبتة",
    cartridgeProtection: "حماية الخراطيش",
    cartridgePolicy: "سياسة الخراطيش",
    cartridgeGauge: "مؤشر الخرطوشة",
    engineTotalPages: "إجمالي صفحات المحرك",
    totalPrintedPages: "إجمالي الصفحات المطبوعة",
    simplexPages: "صفحات وجه واحد",
    duplexPages: "صفحات على الوجهين",
    pcl5Pages: "صفحات PCL5",
    pcl6Pages: "صفحات PCL6",
    postScriptPages: "صفحات PostScript",
    paperJams: "مرات انحشار الورق",
    mispicks: "مرات الالتقاط الخاطئ",
    a4EquivalentPages: "انطباعات مكافئة A4",
    mediaSize: "المقاس",
    units: "الوحدات",
    totalPages: "إجمالي الصفحات",
    monoPages: "الصفحات الأحادية",
    colorPages: "الصفحات الملونة",
    copyPages: "صفحات النسخ",
    scanPages: "صفحات المسح الضوئي",
    color: "اللون",
    status: "الحالة",
    type: "النوع",
    firstInstallDate: "أول تركيب",
    lastUseDate: "آخر استخدام",
    pagesPrinted: "صفحات مطبوعة",
    remainingPages: "صفحات متبقية",
    application: "التطبيق",
    partNumber: "رقم الجزء",
    code: "الكود",
    dateTime: "التاريخ",
    cycles: "العداد",
    count: "التكرار",
    description: "الوصف",
    firmware: "البرنامج الثابت",
    name: "الاسم",
    user: "المستخدم",
    details: "التفاصيل",
  };
  return fixText(labels[key] || key);
}

function pdfText(doc, text, options = {}) {
  return doc.text(shapeArabicText(text), options);
}

function writeSectionTitle(doc, title) {
  if (doc.y > 730) doc.addPage();
  doc.moveDown(0.6);
  const y = doc.y;
  doc.save();
  doc.roundedRect(40, y, doc.page.width - 80, 28, 8).fill("#E8EEF7");
  doc.restore();
  doc.fillColor("#0F172A");
  withArabicFont(doc, true).fontSize(13);
  pdfText(doc, title, {
    align: "right",
    width: doc.page.width - 100,
  });
  doc.moveDown(0.8);
  withArabicFont(doc, false).fontSize(10).fillColor("#111827");
}

function writeInfoLines(doc, items) {
  for (const item of items) {
    if (doc.y > 760) doc.addPage();
    const value = lineValue(item.value);
    const line = formatBidiLine(item.label, value);
    withArabicFont(doc, false).fontSize(10);
    pdfText(doc, line, { align: "right" });
  }
}

function writeBullets(doc, items, limit = 20) {
  for (const item of items.slice(0, limit)) {
    if (doc.y > 760) doc.addPage();
    pdfText(doc, `- ${lineValue(item)}`, { align: "right" });
  }
}

function writeRows(doc, title, rows, limit = 30) {
  if (!Array.isArray(rows) || rows.length === 0) return;
  writeSectionTitle(doc, title);
  for (const [index, row] of rows.slice(0, limit).entries()) {
    if (doc.y > 700) doc.addPage();
    const entries = Object.entries(row || {}).filter(([, value]) => value != null && value !== "");
    const blockHeight = Math.max(44, 22 + entries.length * 14);
    const top = doc.y;
    doc.save();
    doc.roundedRect(40, top, doc.page.width - 80, blockHeight, 8).fill(index % 2 === 0 ? "#F8FAFC" : "#EEF4FF");
    doc.restore();
    withArabicFont(doc, true).fontSize(10).fillColor("#0F172A");
    pdfText(doc, `${title} ${index + 1}`, {
      align: "right",
      width: doc.page.width - 100,
    });
    withArabicFont(doc, false).fontSize(9).fillColor("#111827");
    for (const [key, value] of entries) {
      pdfText(doc, formatBidiLine(key, lineValue(value)), {
        align: "right",
        width: doc.page.width - 100,
      });
    }
    doc.y = top + blockHeight + 8;
  }
}

function writeTopPrintersTable(doc, printers) {
  writeSectionTitle(doc, "أكثر الطابعات استخدامًا");
  const rows = printers
    .slice()
    .sort((a, b) => Number(b.lifetimeCounters?.totalPages || 0) - Number(a.lifetimeCounters?.totalPages || 0))
    .slice(0, 12)
    .map((printer, index) => ({
      "#": index + 1,
      "الفرع": printerBranchName(printer),
      "الطابعة": printerDisplayName(printer),
      "الموديل": printer.model || "-",
      "الحالة": arabicStatus(printer.status),
      "عداد العمر": printer.lifetimeCounters?.totalPages || 0,
    }));
  writeRows(doc, "الطابعة", rows, 12);
}

// ─── Shared style helpers ────────────────────────────────────────────────────
const PC = {
  darkBlue:  "FF1E3A8A",
  midBlue:   "FF2563EB",
  lightBlue: "FFE0E7FF",
  rowAlt:    "FFF0F4FF",
  rowAlt2:   "FFF8FAFC",
  white:     "FFFFFFFF",
  labelFont: "FF1E3A8A",
  valueFont: "FF111827",
  mutedFont: "FF6B7280",
  greenDark: "FF065F46",
  greenMid:  "FF059669",
  greenRow:  "FFF0FDF4",
  amber:     "FFFBBF24",
  amberFont: "FF78350F",
  redBg:     "FFFEF2F2",
  redFont:   "FF991B1B",
  borderCol: "FFD1D5DB",
};

function pcHeader(cell, bgArgb, fontSize) {
  cell.font = { name: "Arial", size: fontSize || 11, bold: true, color: { argb: PC.white } };
  cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: bgArgb } };
  cell.alignment = { horizontal: "center", vertical: "middle", wrapText: true };
  cell.border = {
    bottom: { style: "medium", color: { argb: bgArgb } },
  };
}

function pcLabel(cell) {
  cell.font = { name: "Arial", bold: true, size: 10, color: { argb: PC.labelFont } };
  cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.lightBlue } };
  cell.alignment = { horizontal: "right", vertical: "middle" };
}

function pcValue(cell) {
  cell.font = { name: "Arial", size: 10, color: { argb: PC.valueFont } };
  cell.alignment = { horizontal: "right", vertical: "middle", wrapText: true };
}

function pcBorder(cell) {
  cell.border = {
    top:    { style: "hair", color: { argb: PC.borderCol } },
    bottom: { style: "hair", color: { argb: PC.borderCol } },
    left:   { style: "hair", color: { argb: PC.borderCol } },
    right:  { style: "hair", color: { argb: PC.borderCol } },
  };
}

function styleWorksheet(worksheet, headerBg) {
  const bg = headerBg || PC.darkBlue;
  worksheet.views = [{ rightToLeft: true, state: "frozen", ySplit: 2 }];
  worksheet.getRow(1).height = 32;
  worksheet.getRow(2).height = 10; // spacer

  worksheet.getRow(1).eachCell((cell) => {
    pcHeader(cell, bg, 10);
    pcBorder(cell);
  });

  worksheet.eachRow((row, rowNum) => {
    if (rowNum <= 2) return;
    const isAlt = rowNum % 2 === 0;
    row.height = 22;
    row.eachCell((cell) => {
      cell.font = cell.font || {};
      cell.font = { name: "Arial", size: 10, color: { argb: PC.valueFont } };
      cell.alignment = { horizontal: "right", vertical: "middle", wrapText: true };
      if (isAlt) {
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.rowAlt } };
      }
      pcBorder(cell);
    });
  });
}

function normalizeWorksheetStrings(worksheet) {
  worksheet.eachRow((row) => {
    row.eachCell((cell) => {
      if (typeof cell.value === "string") {
        cell.value = fixText(cell.value);
      }
    });
  });
}

async function createReportRecord({ type, format, branchId, actor, fileName }) {
  await PrinterReport.create({
    type,
    format,
    branchId: branchId || null,
    generatedBy: actor?.id || null,
    fileName,
  });
}

function printerDisplayName(printer) {
  return printer?.printerName || printer?.hostname || printer?.ipAddress || "-";
}

function printerBranchName(printer) {
  return printer?.branchId?.name || printer?.branchName || "";
}

async function buildExcelReport({
  type,
  branch,
  branches,
  printers,
  snapshots,
  waste,
  actor,
  month,
  year,
  monthlyConsumption,
}) {
  const workbook = new ExcelJS.Workbook();
  workbook.creator = "iSmart Printer Monitoring";
  workbook.created = new Date();

  const monthNames = [
    "يناير","فبراير","مارس","أبريل","مايو","يونيو",
    "يوليو","أغسطس","سبتمبر","أكتوبر","نوفمبر","ديسمبر",
  ];
  const isAllMonths = month !== null && month !== undefined && Number(month) === 0;
  const monthLabel = isAllMonths
    ? `جميع شهور سنة ${year}`
    : (month && monthNames[Number(month) - 1]
        ? `${monthNames[Number(month) - 1]} ${year}`
        : "");
  const hasMonthly = !!monthlyConsumption;
  const exportDate = new Date();

  // ─── Helpers ───────────────────────────────────────────────────────────────
  function addSheetTitle(sheet, title, subtitle, colCount, bgArgb) {
    const bg = bgArgb || PC.darkBlue;
    // Row 1: main title
    sheet.mergeCells(`A1:${colLetter(colCount)}1`);
    const tc = sheet.getCell("A1");
    tc.value = title;
    tc.font = { name: "Arial", size: 14, bold: true, color: { argb: PC.white } };
    tc.fill = { type: "pattern", pattern: "solid", fgColor: { argb: bg } };
    tc.alignment = { horizontal: "center", vertical: "middle" };
    sheet.getRow(1).height = 40;

    // Row 2: subtitle
    sheet.mergeCells(`A2:${colLetter(colCount)}2`);
    const sc = sheet.getCell("A2");
    sc.value = subtitle || "";
    sc.font = { name: "Arial", size: 10, italic: true, color: { argb: PC.white } };
    sc.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.midBlue } };
    sc.alignment = { horizontal: "center", vertical: "middle" };
    sheet.getRow(2).height = 24;

    return 3; // next row index
  }

  function colLetter(n) {
    let s = "";
    while (n > 0) {
      const rem = (n - 1) % 26;
      s = String.fromCharCode(65 + rem) + s;
      n = Math.floor((n - 1) / 26);
    }
    return s;
  }

  function addSectionRow(sheet, label, colCount, nextRow, bgArgb) {
    sheet.mergeCells(`A${nextRow}:${colLetter(colCount)}${nextRow}`);
    const c = sheet.getCell(`A${nextRow}`);
    c.value = label;
    c.font = { name: "Arial", size: 10, bold: true, color: { argb: bgArgb || PC.darkBlue } };
    c.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.lightBlue } };
    c.alignment = { horizontal: "right", vertical: "middle" };
    sheet.getRow(nextRow).height = 26;
    return nextRow + 1;
  }

  function addHeaderRow(sheet, headers, nextRow, bgArgb) {
    const hRow = sheet.getRow(nextRow);
    hRow.values = ["", ...headers]; // col A is blank (or index)
    hRow.height = 28;
    hRow.eachCell((cell, ci) => {
      if (ci === 1) return;
      pcHeader(cell, bgArgb || PC.midBlue, 10);
      pcBorder(cell);
    });
    return nextRow + 1;
  }

  function statusColor(statusStr) {
    if (statusStr === "متصلة") return PC.greenMid;
    if (statusStr === "تحتاج عناية") return PC.amber;
    return "FFEF4444";
  }

  function tonerBar(pct) {
    if (pct === "" || pct === null || pct === undefined) return "-";
    const n = Math.max(0, Math.min(100, Number(pct)));
    const filled = Math.round(n / 10);
    return "█".repeat(filled) + "░".repeat(10 - filled) + `  ${n}%`;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SHEET 1 — الملخص التنفيذي
  // ════════════════════════════════════════════════════════════════════════════
  const summarySheet = workbook.addWorksheet("الملخص التنفيذي");
  summarySheet.views = [{ rightToLeft: true }];
  summarySheet.columns = [{ width: 32 }, { width: 46 }];

  // Title
  summarySheet.mergeCells("A1:B1");
  const sTitleC = summarySheet.getCell("A1");
  sTitleC.value = "🖨️  تقرير إدارة الطابعات — ملخص تنفيذي";
  sTitleC.font = { name: "Arial", size: 15, bold: true, color: { argb: PC.white } };
  sTitleC.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.darkBlue } };
  sTitleC.alignment = { horizontal: "center", vertical: "middle" };
  summarySheet.getRow(1).height = 44;

  summarySheet.mergeCells("A2:B2");
  const sSubC = summarySheet.getCell("A2");
  sSubC.value = "iSmart Messenger — نظام مراقبة الطابعات الذكية";
  sSubC.font = { name: "Arial", size: 10, italic: true, color: { argb: PC.white } };
  sSubC.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.midBlue } };
  sSubC.alignment = { horizontal: "center", vertical: "middle" };
  summarySheet.getRow(2).height = 24;

  summarySheet.addRow([]);

  // Section: نظرة عامة
  let sRow = 4;
  summarySheet.mergeCells(`A${sRow}:B${sRow}`);
  const secOver = summarySheet.getCell(`A${sRow}`);
  secOver.value = "📊  نظرة عامة على البنية التحتية";
  secOver.font = { name: "Arial", bold: true, size: 10, color: { argb: PC.labelFont } };
  secOver.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.lightBlue } };
  secOver.alignment = { horizontal: "right", vertical: "middle" };
  summarySheet.getRow(sRow).height = 26;
  sRow++;

  const onlinePrinters  = printers.filter((p) => p.status === "online").length;
  const offlinePrinters = printers.filter((p) => p.status !== "online").length;

  const infraRows = [
    ["نوع التقرير",         type === "branch" ? "تقرير فرع" : "تقرير عام — كل الفروع"],
    ["الفرع",               branch?.name || "كل الفروع"],
    ["عدد الفروع المُراقبة",  branches.length],
    ["إجمالي الطابعات",     printers.length],
    ["طابعات متصلة الآن 🟢", onlinePrinters],
    ["طابعات غير متصلة 🔴",  offlinePrinters],
    ["نسبة الاتصال",        printers.length > 0 ? ((onlinePrinters / printers.length) * 100).toFixed(1) + "%" : "-"],
  ];

  infraRows.forEach(([lbl, val], i) => {
    summarySheet.mergeCells(`B${sRow}:B${sRow}`);
    const row = summarySheet.getRow(sRow);
    row.height = 24;
    const lc = row.getCell(1);
    const vc = row.getCell(2);
    lc.value = lbl; pcLabel(lc); pcBorder(lc);
    vc.value = val; pcValue(vc); pcBorder(vc);
    if (lbl.includes("متصلة الآن")) {
      vc.font = { name: "Arial", size: 10, bold: true, color: { argb: PC.greenDark } };
    }
    if (lbl.includes("غير متصلة") && offlinePrinters > 0) {
      vc.font = { name: "Arial", size: 10, bold: true, color: { argb: PC.redFont } };
    }
    sRow++;
  });

  summarySheet.addRow([]); sRow++;

  if (hasMonthly) {
    // Section: استهلاك الورق
    summarySheet.mergeCells(`A${sRow}:B${sRow}`);
    const secCons = summarySheet.getCell(`A${sRow}`);
    secCons.value = `📄  استهلاك الورق — ${monthLabel}`;
    secCons.font = { name: "Arial", bold: true, size: 10, color: { argb: PC.greenDark } };
    secCons.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFD1FAE5" } };
    secCons.alignment = { horizontal: "right", vertical: "middle" };
    summarySheet.getRow(sRow).height = 26;
    sRow++;

    const totalPages  = monthlyConsumption.consumption.reduce((s, b) => s + Number(b.totalPages || 0), 0);
    const totalMono   = monthlyConsumption.consumption.reduce((s, b) => s + Number(b.monoPages || 0), 0);
    const totalColor  = monthlyConsumption.consumption.reduce((s, b) => s + Number(b.colorPages || 0), 0);
    const paper       = paperMetrics(totalPages);
    const partials    = monthlyConsumption.consumption.filter((b) => b.hasPartialData || b.hasStaleBaseline).length;

    const consRows = [
      ["الفترة المُقدَّم عنها", monthLabel],
      ["إجمالي الصفحات المطبوعة", totalPages.toLocaleString("ar-EG")],
      ["صفحات أبيض وأسود",        totalMono.toLocaleString("ar-EG")],
      ["صفحات ملونة",             totalColor.toLocaleString("ar-EG")],
      ["رزم ورق فعلية (500 ورقة)", paper.exactReams.toFixed(2)],
      ["رزم مطلوبة (محاسبياً)",   paper.requiredReams],
      ["عدد رزم كاملة + ورق متبقي", `${paper.fullReams} رزمة + ${paper.remainingSheets} ورقة`],
      ["فروع تحتاج مراجعة بيانات", partials > 0 ? `⚠️  ${partials} فرع` : "✅ لا توجد مشكلات"],
    ];

    consRows.forEach(([lbl, val]) => {
      const row = summarySheet.getRow(sRow);
      row.height = 24;
      const lc = row.getCell(1);
      const vc = row.getCell(2);
      lc.value = lbl; pcLabel(lc); pcBorder(lc);
      vc.value = val; pcValue(vc); pcBorder(vc);
      if (String(val).startsWith("⚠️")) {
        vc.font = { name: "Arial", size: 10, bold: true, color: { argb: PC.amberFont } };
      }
      sRow++;
    });
  }

  summarySheet.addRow([]); sRow++;

  // Section: معلومات التقرير
  summarySheet.mergeCells(`A${sRow}:B${sRow}`);
  const secMeta = summarySheet.getCell(`A${sRow}`);
  secMeta.value = "📤  معلومات التقرير";
  secMeta.font = { name: "Arial", bold: true, size: 10, color: { argb: PC.labelFont } };
  secMeta.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.lightBlue } };
  secMeta.alignment = { horizontal: "right", vertical: "middle" };
  summarySheet.getRow(sRow).height = 26;
  sRow++;

  const metaRows = [
    ["صدّره", actor?.fullName || actor?.username || "النظام"],
    ["تاريخ ووقت التصدير", exportDate.toLocaleString("ar-EG", { dateStyle: "full", timeStyle: "short" })],
  ];
  metaRows.forEach(([lbl, val]) => {
    const row = summarySheet.getRow(sRow);
    row.height = 24;
    const lc = row.getCell(1);
    const vc = row.getCell(2);
    lc.value = lbl; pcLabel(lc); pcBorder(lc);
    vc.value = val; pcValue(vc); pcBorder(vc);
    sRow++;
  });

  // ════════════════════════════════════════════════════════════════════════════
  // SHEET 2 — الطابعات (Printers List)
  // ════════════════════════════════════════════════════════════════════════════
  const printersSheet = workbook.addWorksheet("قائمة الطابعات");
  printersSheet.views = [{ rightToLeft: true, state: "frozen", ySplit: 3 }];

  const printerCols = [
    { width: 6 },   // م
    { width: 22 },  // الفرع
    { width: 28 },  // اسم الطابعة
    { width: 18 },  // IP
    { width: 28 },  // الموديل
    { width: 20 },  // الرقم التسلسلي
    { width: 14 },  // الشركة
    { width: 14 },  // الحالة
    { width: 18 },  // العداد الحالي
    { width: 18 },  // عداد العمر
    { width: 16 },  // أسود %
    { width: 16 },  // سماوي %
    { width: 16 },  // أرجواني %
    { width: 16 },  // أصفر %
    ...(hasMonthly ? [
      { width: 20 }, // استهلاك شهري
      { width: 16 }, // أبيض وأسود شهري
      { width: 16 }, // ملون شهري
      { width: 14 }, // رزم فعلية
      { width: 14 }, // جودة البيانات
    ] : []),
  ];
  printersSheet.columns = printerCols;

  // Title banner
  printersSheet.mergeCells(`A1:${colLetter(printerCols.length)}1`);
  const ptTitle = printersSheet.getCell("A1");
  ptTitle.value = "🖨️  قائمة الطابعات — البيانات التفصيلية";
  ptTitle.font = { name: "Arial", size: 13, bold: true, color: { argb: PC.white } };
  ptTitle.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.darkBlue } };
  ptTitle.alignment = { horizontal: "center", vertical: "middle" };
  printersSheet.getRow(1).height = 36;

  printersSheet.mergeCells(`A2:${colLetter(printerCols.length)}2`);
  const ptSub = printersSheet.getCell("A2");
  ptSub.value = `إجمالي: ${printers.length} طابعة | متصلة: ${onlinePrinters} | غير متصلة: ${offlinePrinters}${hasMonthly ? " | الفترة: " + monthLabel : ""}`;
  ptSub.font = { name: "Arial", size: 10, italic: true, color: { argb: PC.white } };
  ptSub.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.midBlue } };
  ptSub.alignment = { horizontal: "center", vertical: "middle" };
  printersSheet.getRow(2).height = 24;

  // Header row
  const ptHeaders = [
    "م", "الفرع", "اسم الطابعة", "عنوان IP", "الموديل",
    "الرقم التسلسلي", "الشركة", "الحالة",
    "العداد الحالي", "عداد العمر",
    "حبر أسود", "سماوي", "أرجواني", "أصفر",
    ...(hasMonthly ? ["استهلاك شهري", "أبيض وأسود", "ملون", "رزم", "جودة البيانات"] : []),
  ];
  const ptHRow = printersSheet.getRow(3);
  ptHRow.values = ptHeaders;
  ptHRow.height = 28;
  ptHRow.eachCell((cell, ci) => {
    pcHeader(cell, PC.darkBlue, 10);
    pcBorder(cell);
  });

  const printerUsageMap = {};
  if (hasMonthly && Array.isArray(monthlyConsumption.consumption)) {
    for (const b of monthlyConsumption.consumption) {
      for (const p of b.printers || []) {
        printerUsageMap[String(p.printerId)] = p;
      }
    }
  }

  printers.forEach((printer, idx) => {
    const u = printerUsageMap[String(printer._id)] || {};
    const paper = paperMetrics(u.totalPages || 0);
    const statusStr = arabicStatus(printer.status);
    const isOnline  = printer.status === "online";

    const row = printersSheet.getRow(4 + idx);
    row.height = 22;
    row.values = [
      idx + 1,
      printerBranchName(printer),
      printerDisplayName(printer),
      printer.ipAddress || "-",
      printer.model || "-",
      printer.serialNumber || "-",
      printer.vendor || "-",
      statusStr,
      printer.counters?.totalPages || 0,
      printer.lifetimeCounters?.totalPages || 0,
      tonerBar(printer.tonerLevels?.black),
      tonerBar(printer.tonerLevels?.cyan),
      tonerBar(printer.tonerLevels?.magenta),
      tonerBar(printer.tonerLevels?.yellow),
      ...(hasMonthly ? [
        u.totalPages || 0,
        u.monoPages || 0,
        u.colorPages || 0,
        Number(paper.exactReams.toFixed(2)),
        dataQualityLabel(u),
      ] : []),
    ];

    row.eachCell((cell, ci) => {
      cell.font = { name: "Arial", size: 10, color: { argb: PC.valueFont } };
      cell.alignment = { horizontal: ci === 1 ? "center" : "right", vertical: "middle", wrapText: true };
      if (idx % 2 === 0) {
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.rowAlt } };
      }
      pcBorder(cell);
    });

    // Status cell coloring
    const statusCell = row.getCell(8);
    const sColor = isOnline ? PC.greenDark : PC.redFont;
    statusCell.font = { name: "Arial", size: 10, bold: true, color: { argb: sColor } };
    statusCell.alignment = { horizontal: "center", vertical: "middle" };

    // Toner bar cells — monospace
    [11, 12, 13, 14].forEach((ci) => {
      const c = row.getCell(ci);
      c.font = { name: "Courier New", size: 9, color: { argb: PC.labelFont } };
      c.alignment = { horizontal: "left", vertical: "middle" };
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // SHEET 3 — استهلاك الفروع (if monthly)
  // ════════════════════════════════════════════════════════════════════════════
  if (hasMonthly) {
    const branchSheet = workbook.addWorksheet("استهلاك الفروع");
    branchSheet.views = [{ rightToLeft: true, state: "frozen", ySplit: 3 }];

    const bCols = [
      { width: 6 },{ width: 16 },{ width: 26 },{ width: 14 },
      { width: 18 },{ width: 24 },{ width: 20 },{ width: 20 },
      { width: 18 },{ width: 24 },{ width: 18 },{ width: 18 },
    ];
    branchSheet.columns = bCols;

    // Title
    branchSheet.mergeCells(`A1:${colLetter(bCols.length)}1`);
    const bTitle = branchSheet.getCell("A1");
    bTitle.value = `📊  استهلاك الورق بالفروع — ${monthLabel}`;
    bTitle.font = { name: "Arial", size: 13, bold: true, color: { argb: PC.white } };
    bTitle.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.greenDark } };
    bTitle.alignment = { horizontal: "center", vertical: "middle" };
    branchSheet.getRow(1).height = 36;

    branchSheet.mergeCells(`A2:${colLetter(bCols.length)}2`);
    const bSub = branchSheet.getCell("A2");
    bSub.value = `الفترة: ${monthLabel} | عدد الفروع: ${monthlyConsumption.consumption.length}`;
    bSub.font = { name: "Arial", size: 10, italic: true, color: { argb: PC.white } };
    bSub.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.greenMid } };
    bSub.alignment = { horizontal: "center", vertical: "middle" };
    branchSheet.getRow(2).height = 24;

    // Header
    const bHeaders = [
      "م","كود الفرع","اسم الفرع","عدد الطابعات",
      "إجمالي الصفحات","الرزم الفعلية","رزم مطلوبة",
      "أبيض وأسود","ملون",
      "متوسط صفحات/طابعة","طابعات جزئية","جودة البيانات",
    ];
    const bHRow = branchSheet.getRow(3);
    bHRow.values = bHeaders;
    bHRow.height = 28;
    bHRow.eachCell((cell) => { pcHeader(cell, PC.greenDark, 10); pcBorder(cell); });

    monthlyConsumption.consumption.forEach((b, idx) => {
      const pages = Number(b.totalPages || 0);
      const paper = paperMetrics(pages);
      const pCount = Number(b.printersCount || 0);
      const hasIssue = b.hasPartialData || b.hasStaleBaseline;

      const row = branchSheet.getRow(4 + idx);
      row.height = 22;
      row.values = [
        idx + 1,
        b.branchCode || "-",
        b.branchName || "-",
        pCount,
        pages,
        Number(paper.exactReams.toFixed(2)),
        paper.requiredReams,
        b.monoPages || 0,
        b.colorPages || 0,
        pCount > 0 ? Math.round(pages / pCount) : 0,
        b.partialPrintersCount || 0,
        dataQualityLabel(b),
      ];

      row.eachCell((cell, ci) => {
        cell.font = { name: "Arial", size: 10, color: { argb: PC.valueFont } };
        cell.alignment = { horizontal: ci === 1 ? "center" : "right", vertical: "middle" };
        if (idx % 2 === 0) {
          cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.greenRow } };
        }
        pcBorder(cell);
      });

      if (hasIssue) {
        const qCell = row.getCell(12);
        qCell.font = { name: "Arial", size: 10, bold: true, color: { argb: PC.amberFont } };
        qCell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFEF3C7" } };
      }
    });

    // Totals row
    const totals = monthlyConsumption.consumption.reduce((acc, b) => {
      acc.pages += Number(b.totalPages || 0);
      acc.mono  += Number(b.monoPages || 0);
      acc.color += Number(b.colorPages || 0);
      acc.printers += Number(b.printersCount || 0);
      return acc;
    }, { pages: 0, mono: 0, color: 0, printers: 0 });
    const tPaper = paperMetrics(totals.pages);
    const tRow = branchSheet.getRow(4 + monthlyConsumption.consumption.length);
    tRow.height = 26;
    tRow.values = [
      "", "الإجمالي", "", totals.printers,
      totals.pages, Number(tPaper.exactReams.toFixed(2)), tPaper.requiredReams,
      totals.mono, totals.color, "", "", "",
    ];
    tRow.eachCell((cell) => {
      cell.font = { name: "Arial", size: 10, bold: true, color: { argb: PC.greenDark } };
      cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFD1FAE5" } };
      cell.border = { top: { style: "medium", color: { argb: PC.greenDark } } };
      cell.alignment = { horizontal: "right", vertical: "middle" };
      pcBorder(cell);
    });

    // ── SHEET 4 — تفاصيل استهلاك الطابعات ─────────────────────────────────
    const pConSheet = workbook.addWorksheet("تفاصيل استهلاك الطابعات");
    pConSheet.views = [{ rightToLeft: true, state: "frozen", ySplit: 3 }];

    const pcCols = [
      { width: 6 },{ width: 16 },{ width: 26 },{ width: 28 },
      { width: 18 },{ width: 26 },{ width: 16 },{ width: 14 },
      { width: 14 },{ width: 14 },{ width: 22 },{ width: 22 },{ width: 24 },
    ];
    pConSheet.columns = pcCols;

    pConSheet.mergeCells(`A1:${colLetter(pcCols.length)}1`);
    const pcTitle = pConSheet.getCell("A1");
    pcTitle.value = `📋  تفاصيل استهلاك كل طابعة — ${monthLabel}`;
    pcTitle.font = { name: "Arial", size: 13, bold: true, color: { argb: PC.white } };
    pcTitle.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.greenDark } };
    pcTitle.alignment = { horizontal: "center", vertical: "middle" };
    pConSheet.getRow(1).height = 36;

    pConSheet.mergeCells(`A2:${colLetter(pcCols.length)}2`);
    const pcSub = pConSheet.getCell("A2");
    pcSub.value = "تقرير تفصيلي بكل طابعة — الاستهلاك والقراءات والملاحظات";
    pcSub.font = { name: "Arial", size: 10, italic: true, color: { argb: PC.white } };
    pcSub.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.greenMid } };
    pcSub.alignment = { horizontal: "center", vertical: "middle" };
    pConSheet.getRow(2).height = 24;

    const pcHeaders = [
      "م","كود الفرع","اسم الفرع","اسم الطابعة",
      "عنوان IP","الموديل","إجمالي الصفحات","أبيض وأسود",
      "ملون","رزم فعلية",
      "أول قراءة في الفترة","آخر قراءة","جودة البيانات",
    ];
    const pcHRow = pConSheet.getRow(3);
    pcHRow.values = pcHeaders;
    pcHRow.height = 28;
    pcHRow.eachCell((cell) => { pcHeader(cell, PC.greenMid, 10); pcBorder(cell); });

    let pcIdx = 1;
    for (const b of monthlyConsumption.consumption) {
      for (const p of b.printers || []) {
        const pages = Number(p.totalPages || 0);
        const paper2 = paperMetrics(pages);
        const hasAnomaly = (p.anomalyFlags || []).length > 0;

        const row = pConSheet.getRow(3 + pcIdx);
        row.height = 22;
        row.values = [
          pcIdx,
          b.branchCode || "-",
          b.branchName || "-",
          p.printerName || "-",
          p.ipAddress || "-",
          p.model || "-",
          pages,
          p.monoPages || 0,
          p.colorPages || 0,
          Number(paper2.exactReams.toFixed(2)),
          p.firstSnapshotAt ? new Date(p.firstSnapshotAt).toLocaleDateString("ar-EG") : "-",
          p.lastSnapshotAt  ? new Date(p.lastSnapshotAt).toLocaleDateString("ar-EG")  : "-",
          dataQualityLabel(p),
        ];

        row.eachCell((cell, ci) => {
          cell.font = { name: "Arial", size: 10, color: { argb: PC.valueFont } };
          cell.alignment = { horizontal: ci === 1 ? "center" : "right", vertical: "middle" };
          if (pcIdx % 2 === 0) {
            cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.rowAlt2 } };
          }
          pcBorder(cell);
        });

        if (hasAnomaly) {
          [7, 13].forEach((ci) => {
            const c = row.getCell(ci);
            c.font = { name: "Arial", size: 10, bold: true, color: { argb: PC.amberFont } };
          });
        }
        pcIdx++;
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SHEET 5 — الورق الهالك
  // ════════════════════════════════════════════════════════════════════════════
  const wasteSheet = workbook.addWorksheet("الورق الهالك والأعطال");
  wasteSheet.views = [{ rightToLeft: true, state: "frozen", ySplit: 3 }];

  const wCols = [
    { width: 6 },{ width: 22 },{ width: 28 },
    { width: 16 },{ width: 16 },{ width: 16 },{ width: 24 },
  ];
  wasteSheet.columns = wCols;

  wasteSheet.mergeCells(`A1:${colLetter(wCols.length)}1`);
  const wTitle = wasteSheet.getCell("A1");
  wTitle.value = "⚠️  سجل الورق الهالك والأعطال";
  wTitle.font = { name: "Arial", size: 13, bold: true, color: { argb: PC.white } };
  wTitle.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFB45309" } };
  wTitle.alignment = { horizontal: "center", vertical: "middle" };
  wasteSheet.getRow(1).height = 36;

  wasteSheet.mergeCells(`A2:${colLetter(wCols.length)}2`);
  const wSub = wasteSheet.getCell("A2");
  wSub.value = `إجمالي سجلات الهالك: ${waste.length} سجل — صفحات مقدّرة ضائعة بسبب الانحشار والأخطاء`;
  wSub.font = { name: "Arial", size: 10, italic: true, color: { argb: PC.white } };
  wSub.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFD97706" } };
  wSub.alignment = { horizontal: "center", vertical: "middle" };
  wasteSheet.getRow(2).height = 24;

  const wHeaders = ["م","الفرع","الطابعة","صفحات هالك مقدّرة","مرات الانحشار","أخطاء الطابعة","تاريخ التسجيل"];
  const wHRow = wasteSheet.getRow(3);
  wHRow.values = wHeaders;
  wHRow.height = 28;
  wHRow.eachCell((cell) => { pcHeader(cell, "FFB45309", 10); pcBorder(cell); });

  waste.forEach((entry, idx) => {
    const row = wasteSheet.getRow(4 + idx);
    row.height = 22;
    row.values = [
      idx + 1,
      entry.branchId?.name || "-",
      entry.printerId?.printerName || "-",
      entry.estimatedWastePages || 0,
      entry.paperJams || 0,
      entry.printerErrors || 0,
      formatDate(entry.calculatedAt),
    ];
    row.eachCell((cell, ci) => {
      cell.font = { name: "Arial", size: 10, color: { argb: PC.valueFont } };
      cell.alignment = { horizontal: ci === 1 ? "center" : "right", vertical: "middle" };
      if (idx % 2 === 0) {
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFEF3C7" } };
      }
      pcBorder(cell);
    });
    // Highlight high waste
    if ((entry.estimatedWastePages || 0) > 100) {
      row.getCell(4).font = { name: "Arial", size: 10, bold: true, color: { argb: PC.redFont } };
    }
  });

  // ════════════════════════════════════════════════════════════════════════════
  // SHEET 6 — اللقطات التاريخية
  // ════════════════════════════════════════════════════════════════════════════
  const historySheet = workbook.addWorksheet("سجل القراءات التاريخية");
  historySheet.views = [{ rightToLeft: true, state: "frozen", ySplit: 3 }];

  const hCols = [
    { width: 6 },{ width: 22 },{ width: 28 },
    { width: 24 },{ width: 18 },{ width: 18 },{ width: 14 },{ width: 14 },
  ];
  historySheet.columns = hCols;

  historySheet.mergeCells(`A1:${colLetter(hCols.length)}1`);
  const hTitle = historySheet.getCell("A1");
  hTitle.value = "📅  سجل القراءات التاريخية — اللقطات اليومية";
  hTitle.font = { name: "Arial", size: 13, bold: true, color: { argb: PC.white } };
  hTitle.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF374151" } };
  hTitle.alignment = { horizontal: "center", vertical: "middle" };
  historySheet.getRow(1).height = 36;

  historySheet.mergeCells(`A2:${colLetter(hCols.length)}2`);
  const hSub = historySheet.getCell("A2");
  hSub.value = `إجمالي اللقطات المسجّلة: ${snapshots.length} قراءة`;
  hSub.font = { name: "Arial", size: 10, italic: true, color: { argb: PC.white } };
  hSub.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF4B5563" } };
  hSub.alignment = { horizontal: "center", vertical: "middle" };
  historySheet.getRow(2).height = 24;

  const hHeaders = ["م","الفرع","الطابعة","تاريخ ووقت القراءة","إجمالي الصفحات","عداد العمر","انحشار الورق","الحالة"];
  const hHRow = historySheet.getRow(3);
  hHRow.values = hHeaders;
  hHRow.height = 28;
  hHRow.eachCell((cell) => { pcHeader(cell, "FF374151", 10); pcBorder(cell); });

  snapshots.forEach((entry, idx) => {
    const row = historySheet.getRow(4 + idx);
    row.height = 22;
    row.values = [
      idx + 1,
      entry.branchId?.name || "-",
      entry.printerId?.printerName || "-",
      formatDate(entry.snapshotAt),
      entry.counters?.totalPages || 0,
      entry.lifetimeCounters?.totalPages || 0,
      entry.maintenance?.paperJams || 0,
      arabicStatus(entry.status),
    ];
    row.eachCell((cell, ci) => {
      cell.font = { name: "Arial", size: 10, color: { argb: PC.valueFont } };
      cell.alignment = { horizontal: ci === 1 ? "center" : "right", vertical: "middle" };
      if (idx % 2 === 0) {
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.rowAlt2 } };
      }
      pcBorder(cell);
    });
    const statusCell = row.getCell(8);
    const isOn = entry.status === "online";
    statusCell.font = { name: "Arial", size: 10, bold: true, color: { argb: isOn ? PC.greenDark : PC.redFont } };
    statusCell.alignment = { horizontal: "center", vertical: "middle" };
  });

  // ─── Finalize ──────────────────────────────────────────────────────────────
  const buffer = await workbook.xlsx.writeBuffer();
  const suffix = (month && year) ? `-${year}-${month}` : "";
  const fileName = `printer-${type}-report${suffix}-${Date.now()}.xlsx`;
  await createReportRecord({
    type,
    format: "xlsx",
    branchId: branch?._id || null,
    actor,
    fileName,
  });
  return { buffer: Buffer.from(buffer), fileName };
}

async function buildPdfReport({
  type,
  branch,
  branches,
  printers,
  waste,
  actor,
  month,
  year,
  monthlyConsumption,
}) {
  const doc = new PDFDocument({ margin: 40, size: "A4" });
  configureArabicPdf(doc);
  const chunks = [];
  doc.on("data", (chunk) => chunks.push(chunk));
  const done = new Promise((resolve) => doc.on("end", resolve));

  const monthNames = [
    "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
    "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"
  ];
  const isAllMonths = month !== null && month !== undefined && Number(month) === 0;
  const monthName = isAllMonths ? "جميع الشهور" : (month && monthNames[Number(month) - 1] ? monthNames[Number(month) - 1] : "");
  const title = month && year
    ? (isAllMonths ? `تقرير استهلاك الطابعات لجميع شهور سنة ${year}` : `تقرير استهلاك الطابعات لشهر ${monthName} ${year}`)
    : "تقرير مراقبة الطابعات";

  withArabicFont(doc, true).fontSize(22).fillColor("#0F172A");
  pdfText(doc, title, { align: "right" });
  withArabicFont(doc, false).fontSize(10).fillColor("#475569");
  pdfText(doc, formatBidiLine("نوع التقرير", type === "branch" ? "فرع" : "عام"), { align: "right" });
  pdfText(doc, formatBidiLine("الفرع", branch?.name || "كل الفروع"), { align: "right" });
  pdfText(doc, formatBidiLine("تاريخ التقرير", formatDate(new Date())), { align: "right" });

  writeSectionTitle(doc, "الملخص التنفيذي");
  const summaryLines = [
    { label: "عدد الفروع", value: branches.length },
    { label: "عدد الطابعات", value: printers.length },
    { label: "الطابعات المتصلة", value: printers.filter((item) => item.status === "online").length },
    { label: "الطابعات غير المتصلة", value: printers.filter((item) => item.status !== "online").length },
  ];

  if (monthlyConsumption) {
    const mTotal = monthlyConsumption.consumption.reduce((sum, item) => sum + Number(item.totalPages || 0), 0);
    const mMono = monthlyConsumption.consumption.reduce((sum, item) => sum + Number(item.monoPages || 0), 0);
    const mColor = monthlyConsumption.consumption.reduce((sum, item) => sum + Number(item.colorPages || 0), 0);
    const mPaper = paperMetrics(mTotal);
    const mPartialBranches = monthlyConsumption.consumption.filter((item) => item.hasPartialData || item.hasStaleBaseline).length;
    summaryLines.push(
      { label: isAllMonths ? `إجمالي الاستهلاك للفترة` : `إجمالي استهلاك شهر ${monthName}`, value: `${mTotal} صفحة` },
      { label: "إجمالي استهلاك الرزم (500 ورقة/رزمة)", value: `${mPaper.exactReams.toFixed(2)} رزمة (${mPaper.fullReams} رزمة و ${mPaper.remainingSheets} ورقة)` },
      { label: "الرزم المطلوبة محاسبيًا", value: mPaper.requiredReams },
      { label: "عدد العملاء التقديري", value: `${mPaper.estimatedClients} عميل` },
      { label: "فروع تحتاج مراجعة القراءات", value: mPartialBranches },
      { label: isAllMonths ? "استهلاك أبيض وأسود للفترة" : "استهلاك أبيض وأسود للشهر", value: `${mMono} صفحة` },
      { label: isAllMonths ? "استهلاك ملون للفترة" : "استهلاك ملون للشهر", value: `${mColor} صفحة` }
    );
  } else {
    summaryLines.push(
      {
        label: "إجمالي صفحات العمر",
        value: printers.reduce((sum, item) => sum + Number(item.lifetimeCounters?.totalPages || 0), 0),
      },
      {
        label: "إجمالي الهالك التقديري",
        value: waste.reduce((sum, item) => sum + Number(item.estimatedWastePages || 0), 0),
      }
    );
  }

  writeInfoLines(doc, summaryLines);

  if (monthlyConsumption && Array.isArray(monthlyConsumption.consumption)) {
    writeSectionTitle(doc, isAllMonths ? "استهلاك الفروع خلال الفترة" : "استهلاك الفروع خلال الشهر");
    const branchRows = monthlyConsumption.consumption.map((b, index) => {
      const pages = Number(b.totalPages || 0);
      const paper = paperMetrics(pages);
      return {
        "#": index + 1,
        "كود الفرع": b.branchCode || "",
        "الفرع": b.branchName || "",
        "عدد الأجهزة": b.printersCount || 0,
        "الصفحات": pages,
        "استهلاك الرزم": `${paper.exactReams.toFixed(2)} رزمة`,
        "رزم مطلوبة": paper.requiredReams,
        "العملاء المقدر": paper.estimatedClients,
        "جودة البيانات": dataQualityLabel(b),
        "أبيض وأسود": b.monoPages || 0,
        "ألوان": b.colorPages || 0,
      };
    });
    writeRows(doc, "الفرع", branchRows, 50);

    writeSectionTitle(doc, "استهلاك الطابعات خلال الشهر");
    const printerRows = [];
    let prIndex = 1;
    for (const b of monthlyConsumption.consumption) {
      if (Array.isArray(b.printers)) {
        for (const p of b.printers) {
          const pages = Number(p.totalPages || 0);
          const paper = paperMetrics(pages);
          printerRows.push({
            "#": prIndex++,
            "الفرع": b.branchName,
            "الطابعة": p.printerName,
            "الموديل": p.model || "-",
            "أبيض وأسود": p.monoPages || 0,
            "ألوان": p.colorPages || 0,
            "الاستهلاك": pages,
            "رزم": paper.exactReams.toFixed(2),
            "رزم مطلوبة": paper.requiredReams,
            "عملاء تقديري": paper.estimatedClients,
            "جودة البيانات": dataQualityLabel(p),
          });
        }
      }
    }
    writeRows(doc, "الطابعة", printerRows, 150);
  } else {
    writeTopPrintersTable(doc, printers);
    writeRows(
      doc,
      "ملخص الهالك",
      waste.slice(0, 25).map((entry) => ({
        الفرع: entry.branchId?.name || "",
        الطابعة: entry.printerId?.printerName || "",
        "الهالك التقديري": entry.estimatedWastePages || 0,
        "مرات الانحشار": entry.paperJams || 0,
        التاريخ: formatDate(entry.calculatedAt),
      })),
      25,
    );
  }

  doc.end();
  await done;
  const suffix = (month && year) ? `-${year}-${month}` : "";
  const fileName = `printer-${type}-report${suffix}-${Date.now()}.pdf`;
  await createReportRecord({
    type,
    format: "pdf",
    branchId: branch?._id || null,
    actor,
    fileName,
  });
  return { buffer: Buffer.concat(chunks), fileName };
}

async function buildPrinterPdfReport({
  printer,
  snapshots,
  actor,
  month,
  year,
  fromMonth,
  fromYear,
  toMonth,
  toYear,
  monthlyConsumption,
}) {
  const doc = new PDFDocument({ margin: 40, size: "A4" });
  configureArabicPdf(doc);
  const chunks = [];
  doc.on("data", (chunk) => chunks.push(chunk));
  const done = new Promise((resolve) => doc.on("end", resolve));

  const name = printerDisplayName(printer);
  const maintenance = printer.maintenance || {};
  const toner = printer.tonerLevels || {};
  const extended = printer.extendedDetails || {};
  const product = extended.product || {};
  const usage = extended.usage || {};
  const supplies = Array.isArray(extended.supplies) ? extended.supplies : [];
  const events = Array.isArray(extended.events) ? extended.events : [];
  const jobs = Array.isArray(extended.jobs) ? extended.jobs : [];
  const media = Array.isArray(usage.media) ? usage.media : [];

  withArabicFont(doc, true).fontSize(22).fillColor("#0F172A");
  let mainTitle = "تقرير تفصيلي للطابعة";
  const effectiveMonth = month ?? fromMonth;
  const effectiveYear = year ?? fromYear;
  if (effectiveMonth && effectiveYear) {
    const monthNames = [
      "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
      "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"
    ];
    const isAllMonths = Number(effectiveMonth) === 0;
    const isRange = fromMonth && toMonth && (fromMonth !== toMonth || fromYear !== toYear);
    if (isRange) {
      const fromName = monthNames[Number(fromMonth) - 1] || fromMonth;
      const toName = monthNames[Number(toMonth) - 1] || toMonth;
      mainTitle = `تقرير الطابعة للفترة من شهر ${fromName} ${fromYear} إلى ${toName} ${toYear}`;
    } else {
      const monthName = isAllMonths ? "جميع الشهور" : (monthNames[Number(effectiveMonth) - 1] || effectiveMonth);
      mainTitle = isAllMonths ? `تقرير الطابعة لجميع شهور سنة ${effectiveYear}` : `تقرير الطابعة لشهر ${monthName} ${effectiveYear}`;
    }
  }
  pdfText(doc, mainTitle, { align: "right" });

  withArabicFont(doc, false).fontSize(10).fillColor("#475569");
  pdfText(doc, formatBidiLine("اسم الطابعة", name), { align: "right" });
  pdfText(doc, formatBidiLine("الفرع", printerBranchName(printer)), { align: "right" });
  pdfText(doc, formatBidiLine("عنوان IP", printer.ipAddress), { align: "right" });
  pdfText(doc, formatBidiLine("الحالة الحالية", arabicStatus(printer.status)), { align: "right" });
  pdfText(doc, formatBidiLine("تاريخ التقرير", formatDate(new Date())), { align: "right" });

  writeSectionTitle(doc, "المعلومات الأساسية");
  writeInfoLines(doc, [
    { label: "اسم الطابعة", value: name },
    { label: "الموديل", value: printer.model || product.productName || "-" },
    { label: "الرقم التسلسلي", value: printer.serialNumber || product.serialNumber || "-" },
    { label: "الشركة", value: printer.vendor || "-" },
    { label: "الفرع", value: printerBranchName(printer) },
    { label: "آخر مزامنة", value: formatDate(printer.lastSyncAt) },
    { label: "العداد الحالي", value: printer.counters?.totalPages || 0 },
    { label: "عداد العمر", value: printer.lifetimeCounters?.totalPages || 0 },
  ]);

  writeSectionTitle(doc, "عدادات الاستخدام");
  writeInfoLines(doc, [
    { label: "إجمالي الصفحات", value: printer.lifetimeCounters?.totalPages || 0 },
    { label: "الصفحات الأحادية", value: printer.lifetimeCounters?.monoPages || 0 },
    { label: "الصفحات الملونة", value: printer.lifetimeCounters?.colorPages || 0 },
    { label: "صفحات الوجهين", value: printer.lifetimeCounters?.duplexPages || 0 },
    { label: "صفحات النسخ", value: printer.lifetimeCounters?.copyPages || 0 },
    { label: "صفحات المسح الضوئي", value: printer.lifetimeCounters?.scanPages || 0 },
    { label: "إجمالي الصفحات المطبوعة", value: usage.totalPrintedPages || "-" },
    { label: "صفحات PCL6", value: usage.pcl6Pages || "-" },
    { label: "صفحات PCL5", value: usage.pcl5Pages || "-" },
    { label: "صفحات PostScript", value: usage.postScriptPages || "-" },
    { label: "مكافئ A4", value: usage.a4EquivalentPages || "-" },
  ]);

  if (monthlyConsumption && Array.isArray(monthlyConsumption.consumption)) {
    let printerConsumption = null;
    for (const b of monthlyConsumption.consumption) {
      const p = b.printers?.find((item) => item.printerId === printer._id.toString());
      if (p) {
        printerConsumption = p;
        break;
      }
    }
    if (printerConsumption) {
      const monthNames = [
        "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
        "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"
      ];
      const isAllMonths = Number(month) === 0;
      const monthName = isAllMonths ? "جميع الشهور" : (monthNames[Number(month) - 1] || month);
      writeSectionTitle(doc, isAllMonths ? `الاستهلاك للفترة - سنة ${year}` : `الاستهلاك الشهري - شهر ${monthName} ${year}`);
      writeInfoLines(doc, [
        { label: isAllMonths ? "استهلاك أبيض وأسود للفترة" : "استهلاك أبيض وأسود خلال الشهر", value: printerConsumption.monoPages || 0 },
        { label: isAllMonths ? "استهلاك ملون للفترة" : "استهلاك ملون خلال الشهر", value: printerConsumption.colorPages || 0 },
        { label: isAllMonths ? "إجمالي الاستهلاك للفترة" : "إجمالي الاستهلاك خلال الشهر", value: printerConsumption.totalPages || 0 },
      ]);
    }
  }

  writeSectionTitle(doc, "الحالة والمستهلكات");
  writeInfoLines(doc, [
    { label: "أسود", value: toner.black == null ? "-" : `${toner.black}%` },
    { label: "سماوي", value: toner.cyan == null ? "-" : `${toner.cyan}%` },
    { label: "أرجواني", value: toner.magenta == null ? "-" : `${toner.magenta}%` },
    { label: "أصفر", value: toner.yellow == null ? "-" : `${toner.yellow}%` },
    { label: "مرات الانحشار", value: maintenance.paperJams || 0 },
  ]);
  writeBullets(doc, maintenance.errorMessages || [], 15);
  writeBullets(doc, maintenance.warnings || [], 15);

  if (Object.keys(product).length > 0) {
    writeSectionTitle(doc, "معلومات الجهاز الموسعة");
    writeInfoLines(
      doc,
      Object.entries(product).map(([key, value]) => ({
        label: humanizeKey(key),
        value,
      })),
    );
  }

  writeRows(
    doc,
    "تفاصيل الخراطيش والمستهلكات",
    supplies.map((item) => ({
      اللون: item.color || item.family || "-",
      الحالة: item.status || "-",
      "الرقم التسلسلي": item.serialNumber || "-",
      "رقم الجزء": item.partNumber || "-",
      النوع: item.type || "-",
      "تاريخ التركيب": item.firstInstallDate || "-",
      "آخر استخدام": item.lastUseDate || "-",
      "صفحات مطبوعة": item.pagesPrinted || "-",
      "صفحات متبقية": item.remainingPages || "-",
    })),
    30,
  );

  writeRows(
    doc,
    "استخدام الورق حسب المقاس",
    media.map((item) => ({
      المقاس: item.mediaSize || "-",
      الوحدات: item.units || item.duplexSheets || "-",
      "إجمالي الصفحات": item.totalPages || item.totalImpressions || "-",
    })),
    40,
  );

  writeRows(
    doc,
    "سجل الأحداث",
    events.map((item) => ({
      الكود: item.code || "-",
      النوع: item.type || "-",
      التاريخ: item.dateTime || "-",
      التكرار: item.count || "-",
      العداد: item.cycles || "-",
      الوصف: item.description || "-",
    })),
    60,
  );

  writeRows(
    doc,
    "سجل الوظائف",
    jobs.map((item) => ({
      الاسم: item.name || "-",
      المستخدم: item.user || "-",
      الحالة: item.status || "-",
      التاريخ: item.dateTime || "-",
      التفاصيل: item.details || "-",
    })),
    40,
  );

  writeRows(
    doc,
    "آخر القراءات التاريخية",
    snapshots.slice(-30).reverse().map((snapshot) => ({
      التاريخ: formatDate(snapshot.snapshotAt),
      الحالة: arabicStatus(snapshot.status),
      "العداد الحالي": snapshot.counters?.totalPages || 0,
      "عداد العمر": snapshot.lifetimeCounters?.totalPages || 0,
      "الانحشار": snapshot.maintenance?.paperJams || 0,
    })),
    30,
  );

  doc.end();
  await done;
  const suffix = (month && year) ? `-${year}-${month}` : "";
  const fileName = `printer-detail-${printer.ipAddress}${suffix}-${Date.now()}.pdf`;
  await createReportRecord({
    type: "printer",
    format: "pdf",
    branchId: printer.branchId?._id || printer.branchId || null,
    actor,
    fileName,
  });
  return { buffer: Buffer.concat(chunks), fileName };
}

module.exports = {
  buildExcelReport,
  buildPdfReport,
  buildPrinterPdfReport,
};
