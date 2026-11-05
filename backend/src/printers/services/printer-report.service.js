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

const logo1Path = path.join(__dirname, "../../assets/logo1.png");
const logo2Path = path.join(__dirname, "../../assets/logo2.png");

function processArabicText(text) {
  if (text == null) return "";
  const input = fixText(text);
  if (!/[؀-ۿ]/.test(input)) return input;

  const swapped = input
    .replace(/\(/g, "\x01")
    .replace(/\)/g, "(")
    .replace(/\x01/g, ")");

  return swapped.split(" ").reverse().join("  ");
}

function configureArabicPdf(doc) {
  const candidatesRegular = [
    path.join(__dirname, "../../assets/fonts/Arial.ttf"),
    path.join(__dirname, "../../assets/fonts/Amiri-Regular.ttf"),
    path.join(__dirname, "../../assets/fonts/NotoSansArabic-Regular.ttf"),
  ];
  const candidatesBold = [
    path.join(__dirname, "../../assets/fonts/Arial-Bold.ttf"),
    path.join(__dirname, "../../assets/fonts/Amiri-Bold.ttf"),
    path.join(__dirname, "../../assets/fonts/NotoSansArabic-Bold.ttf"),
  ];

  const regularPath = candidatesRegular.find((p) => fs.existsSync(p));
  const boldPath = candidatesBold.find((p) => fs.existsSync(p));

  if (regularPath) {
    doc.registerFont("Arabic", regularPath);
  }
  if (boldPath) {
    doc.registerFont("ArabicBold", boldPath);
  }
  doc.font(regularPath ? "Arabic" : "Helvetica");
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
  try {
    await PrinterReport.create({
      type,
      format,
      branchId: branchId || null,
      generatedBy: actor?._id || actor?.id || null,
      fileName,
    });
  } catch (err) {
    // Non-fatal: log but don't block file download
    console.warn("[printer-report] createReportRecord failed (non-fatal):", err.message);
  }
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
      if ([9, 10, 15, 16, 17].includes(ci) && typeof cell.value === "number") {
        cell.numFmt = "#,##0";
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
  branches = [],
  printers = [],
  waste = [],
  actor,
  month,
  year,
  fromMonth,
  fromYear,
  toMonth,
  toYear,
  monthlyConsumption,
}) {
  const doc = new PDFDocument({ margin: 30, size: "A4", layout: "landscape" });
  configureArabicPdf(doc);
  const chunks = [];
  doc.on("data", (chunk) => chunks.push(chunk));
  const done = new Promise((resolve) => doc.on("end", resolve));

  const usableWidth = doc.page.width - 60; // 841.89 - 60 = 781.89 pt
  const reportDate = formatDate(new Date());

  const monthNames = [
    "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
    "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"
  ];
  const isAllMonths = month !== null && month !== undefined && Number(month) === 0;
  const monthName = isAllMonths ? "جميع الشهور" : (month && monthNames[Number(month) - 1] ? monthNames[Number(month) - 1] : "");
  const title = month && year
    ? (isAllMonths ? `تقرير استهلاك ومتابعة الطابعات لجميع شهور سنة ${year}` : `تقرير استهلاك ومتابعة الطابعات لشهر ${monthName} ${year}`)
    : "تقرير متابعة وحالة الطابعات";

  function drawPageHeader() {
    try {
      if (fs.existsSync(logo1Path)) doc.image(logo1Path, 30, 20, { width: 50 });
      if (fs.existsSync(logo2Path)) doc.image(logo2Path, doc.page.width - 80, 20, { width: 50 });
    } catch (_) {}

    withArabicFont(doc, true).fontSize(11).fillColor("#1E3A8A");
    doc.text(processArabicText("مشروع تنمية المنشآت الصغيرة والحرفية - جمعية رجال الأعمال بالدقهلية"), 85, 22, { width: usableWidth - 110, align: "center" });

    // Banner
    doc.roundedRect(30, 42, usableWidth, 38, 5).fill("#1E3A8A");
    withArabicFont(doc, true).fontSize(13).fillColor("#FFFFFF");
    doc.text(processArabicText(title), 30, 48, { width: usableWidth, align: "center" });
    withArabicFont(doc, false).fontSize(8.5).fillColor("#DBEAFE");
    const sub = `الفرع: ${branch?.name || "كافة الفروع"}   |   إجمالي الطابعات: ${printers.length}   |   تاريخ الإصدار: ${reportDate}`;
    doc.text(processArabicText(sub), 30, 64, { width: usableWidth, align: "center" });
  }

  drawPageHeader();

  // Summary KPI Cards (y: 86)
  const kpiY = 86;
  const totalP = printers.length;
  const onlineP = printers.filter((p) => p.status === "online").length;
  const offlineP = totalP - onlineP;

  let totalPagesMonth = 0;
  if (monthlyConsumption && Array.isArray(monthlyConsumption.consumption)) {
    totalPagesMonth = monthlyConsumption.consumption.reduce((sum, item) => sum + Number(item.totalPages || 0), 0);
  }
  const paper = paperMetrics(totalPagesMonth);

  const kpis = [
    { label: "إجمالي الطابعات", val: `${totalP} طابعة`, col: "#1E3A8A" },
    { label: "الطابعات المتصلة", val: `${onlineP} متصلة`, col: "#15803D" },
    { label: "الطابعات غير المتصلة", val: `${offlineP} غير متصلة`, col: offlineP > 0 ? "#B91C1C" : "#64748B" },
    { label: "استهلاك الشهر", val: `${totalPagesMonth.toLocaleString("en-US")} صفحة`, col: "#0369A1" },
    { label: "الرزم المطلوبة", val: `${paper.requiredReams} رزمة`, col: "#D97706" },
  ];

  const cardW = (usableWidth - (kpis.length - 1) * 8) / kpis.length;
  for (let i = 0; i < kpis.length; i++) {
    const k = kpis[i];
    const x = 30 + i * (cardW + 8);
    doc.roundedRect(x, kpiY, cardW, 36, 4).fill("#F8FAFC");
    doc.roundedRect(x, kpiY, cardW, 36, 4).strokeColor("#E2E8F0").lineWidth(0.8).stroke();
    withArabicFont(doc, false).fontSize(7.5).fillColor("#64748B");
    doc.text(processArabicText(k.label), x + 2, kpiY + 4, { width: cardW - 4, align: "center" });
    withArabicFont(doc, true).fontSize(9.5).fillColor(k.col);
    doc.text(processArabicText(k.val), x + 2, kpiY + 18, { width: cardW - 4, align: "center" });
  }

  // Printers Table (y: 130)
  const columns = [
    { label: "م", w: 30 },
    { label: "الفرع", w: 100 },
    { label: "اسم الطابعة", w: 120 },
    { label: "الموديل", w: 105 },
    { label: "عنوان IP", w: 90 },
    { label: "الحالة", w: 65 },
    { label: "العداد الكلي", w: 85 },
    { label: "استهلاك الشهر", w: 85 },
    { label: "الحبر الأسود", w: 101 },
  ];

  let currentY = 130;
  const rowH = 18;
  const headerH = 22;

  function drawTableHeader(y) {
    let x = 30;
    for (const c of columns) {
      doc.rect(x, y, c.w, headerH).fill("#1E3A8A").strokeColor("#1E40AF").stroke();
      withArabicFont(doc, true).fontSize(8.5).fillColor("#FFFFFF");
      doc.text(processArabicText(c.label), x + 2, y + 6, { width: c.w - 4, align: "center" });
      x += c.w;
    }
  }

  drawTableHeader(currentY);
  currentY += headerH;

  // Map monthly consumption per printer
  const pUsageMap = {};
  if (monthlyConsumption && Array.isArray(monthlyConsumption.consumption)) {
    for (const b of monthlyConsumption.consumption) {
      for (const p of b.printers || []) {
        pUsageMap[String(p.printerId)] = p;
      }
    }
  }

  for (let idx = 0; idx < printers.length; idx++) {
    if (currentY + rowH > doc.page.height - 40) {
      doc.addPage({ margin: 30, size: "A4", layout: "landscape" });
      drawPageHeader();
      currentY = 90;
      drawTableHeader(currentY);
      currentY += headerH;
    }

    const pr = printers[idx];
    const u = pUsageMap[String(pr._id)] || {};
    const isEven = idx % 2 === 0;
    const rowBg = isEven ? "#F8FAFC" : "#FFFFFF";

    const prLifetime = Number(pr.lifetimeCounters?.totalPages || pr.counters?.totalPages || 0);
    const prMonth = Number(u.totalPages || 0);
    const prToner = pr.tonerLevels?.black != null ? `${pr.tonerLevels.black}%` : "-";
    const isOnline = pr.status === "online";

    const rowData = [
      String(idx + 1),
      printerBranchName(pr) || "-",
      printerDisplayName(pr),
      pr.model || "-",
      pr.ipAddress || "-",
      arabicStatus(pr.status),
      prLifetime.toLocaleString("en-US"),
      prMonth > 0 ? prMonth.toLocaleString("en-US") : "-",
      prToner,
    ];

    let rX = 30;
    for (let c = 0; c < columns.length; c++) {
      const col = columns[c];
      doc.rect(rX, currentY, col.w, rowH).fill(rowBg).strokeColor("#E2E8F0").stroke();

      if (c === 5) {
        withArabicFont(doc, true).fontSize(8).fillColor(isOnline ? "#15803D" : "#B91C1C");
      } else {
        withArabicFont(doc, false).fontSize(8).fillColor("#0F172A");
      }

      doc.text(processArabicText(rowData[c]), rX + 2, currentY + 4, {
        width: col.w - 4,
        align: "center",
        ellipsis: true,
        lineBreak: false,
      });
      rX += col.w;
    }
    currentY += rowH;
  }

  // Footer on page bottom
  const footerY = doc.page.height - 26;
  withArabicFont(doc, false).fontSize(7.5).fillColor("#64748B");
  const footerText = `منظومة iSmart Messenger لإدارة ومتابعة الطابعات   |   المسؤول المستخرج: ${actor?.fullName || actor?.username || "Admin"}   |   تاريخ التقرير: ${reportDate}`;
  doc.text(processArabicText(footerText), 30, footerY, { width: usableWidth, align: "center" });

  doc.end();
  await done;

  const suffix = (month && year) ? `-${year}-${month}` : "";
  const fileName = `printers-${type}-report${suffix}-${Date.now()}.pdf`;
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
  snapshots = [],
  actor,
  month,
  year,
  fromMonth,
  fromYear,
  toMonth,
  toYear,
  monthlyConsumption,
}) {
  const doc = new PDFDocument({ margin: 30, size: "A4" });
  configureArabicPdf(doc);
  const chunks = [];
  doc.on("data", (chunk) => chunks.push(chunk));
  const done = new Promise((resolve) => doc.on("end", resolve));

  const usableWidth = doc.page.width - 60; // 595.28 - 60 = 535.28 pt
  const name = printerDisplayName(printer);
  const branchName = printerBranchName(printer);
  const toner = printer.tonerLevels || {};
  const counters = printer.counters || {};
  const lifetime = printer.lifetimeCounters || {};
  const isOnline = printer.status === "online";
  const reportDate = formatDate(new Date());

  // Top header with logos
  try {
    if (fs.existsSync(logo1Path)) doc.image(logo1Path, 30, 24, { width: 55 });
    if (fs.existsSync(logo2Path)) doc.image(logo2Path, doc.page.width - 85, 24, { width: 55 });
  } catch (_) {}

  withArabicFont(doc, true).fontSize(11).fillColor("#1E3A8A");
  doc.text(processArabicText("مشروع تنمية المنشآت الصغيرة والحرفية"), 90, 26, { width: usableWidth - 120, align: "center" });
  withArabicFont(doc, true).fontSize(9.5).fillColor("#475569");
  doc.text(processArabicText("جمعية رجال الأعمال والمستثمرين بالدقهلية"), 90, 41, { width: usableWidth - 120, align: "center" });
  withArabicFont(doc, false).fontSize(8).fillColor("#64748B");
  doc.text(processArabicText("رقم الإشهار: 777 لسنة 1995 - رقم الترخيص: 1031"), 90, 55, { width: usableWidth - 120, align: "center" });

  doc.strokeColor("#CBD5E1").lineWidth(0.8).moveTo(30, 72).lineTo(doc.page.width - 30, 72).stroke();

  // Banner Title
  const bannerY = 80;
  const bannerHeight = 44;
  doc.roundedRect(30, bannerY, usableWidth, bannerHeight, 6).fill("#1E3A8A");
  withArabicFont(doc, true).fontSize(13).fillColor("#FFFFFF");
  doc.text(processArabicText("تقرير الفحص الفني والمواصفات التشغيلية للطابعة"), 30, bannerY + 8, { width: usableWidth, align: "center" });
  withArabicFont(doc, false).fontSize(8.5).fillColor("#DBEAFE");
  const subTitleText = `الفرع: ${branchName || "الرئيسي"}   |   الطابعة: ${name}   |   عنوان IP: ${printer.ipAddress || "-"}   |   التاريخ: ${reportDate}`;
  doc.text(processArabicText(subTitleText), 30, bannerY + 26, { width: usableWidth, align: "center" });

  // 4 KPI Summary Cards (y: 134)
  const kpiY = 134;
  const cardW = (usableWidth - 24) / 4; // ~127.8 pt
  const cardH = 46;

  // Card 1: Status
  doc.roundedRect(30, kpiY, cardW, cardH, 6).fill(isOnline ? "#F0FDF4" : "#FEF2F2");
  doc.roundedRect(30, kpiY, cardW, cardH, 6).strokeColor(isOnline ? "#86EFAC" : "#FECACA").lineWidth(0.8).stroke();
  withArabicFont(doc, false).fontSize(8).fillColor("#64748B");
  doc.text(processArabicText("الحالة الآن"), 34, kpiY + 6, { width: cardW - 8, align: "center" });
  withArabicFont(doc, true).fontSize(10).fillColor(isOnline ? "#15803D" : "#B91C1C");
  doc.text(processArabicText(isOnline ? "متصلة بنشاط" : "غير متصلة"), 34, kpiY + 22, { width: cardW - 8, align: "center" });

  // Card 2: Total Counter
  const totalPages = Number(lifetime.totalPages || counters.totalPages || 0);
  doc.roundedRect(30 + cardW + 8, kpiY, cardW, cardH, 6).fill("#F8FAFC");
  doc.roundedRect(30 + cardW + 8, kpiY, cardW, cardH, 6).strokeColor("#E2E8F0").lineWidth(0.8).stroke();
  withArabicFont(doc, false).fontSize(8).fillColor("#64748B");
  doc.text(processArabicText("إجمالي العداد"), 30 + cardW + 12, kpiY + 6, { width: cardW - 8, align: "center" });
  withArabicFont(doc, true).fontSize(11).fillColor("#1E3A8A");
  doc.text(processArabicText(`${totalPages.toLocaleString("en-US")} صفحة`), 30 + cardW + 12, kpiY + 22, { width: cardW - 8, align: "center" });

  // Card 3: Monthly Pages
  let mPages = 0;
  if (monthlyConsumption && Array.isArray(monthlyConsumption.consumption)) {
    for (const b of monthlyConsumption.consumption) {
      const p = (b.printers || []).find((x) => x.printerId === String(printer._id));
      if (p) { mPages = Number(p.totalPages || 0); break; }
    }
  }
  const reams = (mPages / 500).toFixed(1);
  doc.roundedRect(30 + (cardW + 8) * 2, kpiY, cardW, cardH, 6).fill("#F8FAFC");
  doc.roundedRect(30 + (cardW + 8) * 2, kpiY, cardW, cardH, 6).strokeColor("#E2E8F0").lineWidth(0.8).stroke();
  withArabicFont(doc, false).fontSize(8).fillColor("#64748B");
  doc.text(processArabicText("استهلاك الشهر"), 30 + (cardW + 8) * 2 + 4, kpiY + 6, { width: cardW - 8, align: "center" });
  withArabicFont(doc, true).fontSize(10).fillColor("#0369A1");
  doc.text(processArabicText(`${mPages.toLocaleString("en-US")} (${reams} رزمة)`), 30 + (cardW + 8) * 2 + 4, kpiY + 22, { width: cardW - 8, align: "center" });

  // Card 4: Black Toner
  const blackToner = toner.black != null ? Number(toner.black) : 0;
  doc.roundedRect(30 + (cardW + 8) * 3, kpiY, cardW, cardH, 6).fill("#F8FAFC");
  doc.roundedRect(30 + (cardW + 8) * 3, kpiY, cardW, cardH, 6).strokeColor("#E2E8F0").lineWidth(0.8).stroke();
  withArabicFont(doc, false).fontSize(8).fillColor("#64748B");
  doc.text(processArabicText("الحبر الأساسي"), 30 + (cardW + 8) * 3 + 4, kpiY + 6, { width: cardW - 8, align: "center" });
  withArabicFont(doc, true).fontSize(11).fillColor(blackToner > 20 ? "#1E293B" : "#B91C1C");
  doc.text(processArabicText(`${blackToner}%`), 30 + (cardW + 8) * 3 + 4, kpiY + 22, { width: cardW - 8, align: "center" });

  // Section 1: Specs Table (y: 190)
  let curY = 190;
  doc.roundedRect(30, curY, usableWidth, 22, 4).fill("#2563EB");
  withArabicFont(doc, true).fontSize(9.5).fillColor("#FFFFFF");
  doc.text(processArabicText("البيانات الفنية والشبكية للطابعة"), 30, curY + 5, { width: usableWidth, align: "center" });
  curY += 26;

  const specs = [
    { label: "اسم الطابعة", val: name, label2: "عنوان IP", val2: printer.ipAddress || "-" },
    { label: "الموديل", val: printer.model || "-", label2: "الفرع", val2: branchName || "-" },
    { label: "الرقم التسلسلي", val: printer.serialNumber || "-", label2: "الشركة المصنعة", val2: printer.vendor || "-" },
    { label: "آخر مزامنة", val: formatDate(printer.lastSyncAt), label2: "حالة الطابعة", val2: arabicStatus(printer.status) },
  ];

  const colW1 = 75, colW2 = 192, colW3 = 75, colW4 = 193; // total 535
  for (let i = 0; i < specs.length; i++) {
    const s = specs[i];
    const isEven = i % 2 === 0;
    const rowBg = isEven ? "#F8FAFC" : "#FFFFFF";
    const rowH = 18;

    // Col 1 (label)
    doc.rect(30, curY, colW1, rowH).fill("#F1F5F9").strokeColor("#E2E8F0").stroke();
    withArabicFont(doc, true).fontSize(8).fillColor("#475569");
    doc.text(processArabicText(s.label), 32, curY + 4, { width: colW1 - 4, align: "center" });

    // Col 2 (val)
    doc.rect(30 + colW1, curY, colW2, rowH).fill(rowBg).strokeColor("#E2E8F0").stroke();
    withArabicFont(doc, false).fontSize(8).fillColor("#0F172A");
    doc.text(processArabicText(s.val), 30 + colW1 + 4, curY + 4, { width: colW2 - 8, align: "center", ellipsis: true, lineBreak: false });

    // Col 3 (label2)
    doc.rect(30 + colW1 + colW2, curY, colW3, rowH).fill("#F1F5F9").strokeColor("#E2E8F0").stroke();
    withArabicFont(doc, true).fontSize(8).fillColor("#475569");
    doc.text(processArabicText(s.label2), 30 + colW1 + colW2 + 2, curY + 4, { width: colW3 - 4, align: "center" });

    // Col 4 (val2)
    doc.rect(30 + colW1 + colW2 + colW3, curY, colW4, rowH).fill(rowBg).strokeColor("#E2E8F0").stroke();
    withArabicFont(doc, false).fontSize(8).fillColor("#0F172A");
    doc.text(processArabicText(s.val2), 30 + colW1 + colW2 + colW3 + 4, curY + 4, { width: colW4 - 8, align: "center", ellipsis: true, lineBreak: false });

    curY += rowH;
  }

  curY += 8;

  // Section 2: Toner Levels with Graphical Progress Bars
  doc.roundedRect(30, curY, usableWidth, 22, 4).fill("#2563EB");
  withArabicFont(doc, true).fontSize(9.5).fillColor("#FFFFFF");
  doc.text(processArabicText("مستويات خراطيش الحبر والمستهلكات"), 30, curY + 5, { width: usableWidth, align: "center" });
  curY += 26;

  const tonerItems = [
    { label: "أسود (K)", pct: toner.black, color: "#1E293B" },
    { label: "سماوي (C)", pct: toner.cyan, color: "#0284C7" },
    { label: "أرجواني (M)", pct: toner.magenta, color: "#DB2777" },
    { label: "أصفر (Y)", pct: toner.yellow, color: "#CA8A04" },
  ];

  const tCardW = (usableWidth - 18) / 4; // ~129 pt
  for (let i = 0; i < tonerItems.length; i++) {
    const t = tonerItems[i];
    const x = 30 + i * (tCardW + 6);
    const pct = t.pct != null ? Math.max(0, Math.min(100, Number(t.pct))) : null;

    doc.roundedRect(x, curY, tCardW, 40, 4).fill("#F8FAFC");
    doc.roundedRect(x, curY, tCardW, 40, 4).strokeColor("#E2E8F0").lineWidth(0.8).stroke();

    withArabicFont(doc, true).fontSize(8).fillColor("#475569");
    doc.text(processArabicText(t.label), x + 4, curY + 5, { width: tCardW - 8, align: "center" });

    if (pct != null) {
      const barX = x + 10;
      const barY = curY + 18;
      const barW = tCardW - 20;
      const barH = 7;
      doc.roundedRect(barX, barY, barW, barH, 3).fill("#E2E8F0");
      if (pct > 0) {
        doc.roundedRect(barX, barY, (barW * pct) / 100, barH, 3).fill(t.color);
      }
      withArabicFont(doc, true).fontSize(7.5).fillColor(t.color);
      doc.text(`${pct}%`, x + 4, curY + 28, { width: tCardW - 8, align: "center" });
    } else {
      withArabicFont(doc, false).fontSize(8).fillColor("#94A3B8");
      doc.text(processArabicText("غير متوفر"), x + 4, curY + 22, { width: tCardW - 8, align: "center" });
    }
  }

  curY += 46;

  // Section 3: Detailed Counters (4 boxes)
  doc.roundedRect(30, curY, usableWidth, 22, 4).fill("#2563EB");
  withArabicFont(doc, true).fontSize(9.5).fillColor("#FFFFFF");
  doc.text(processArabicText("تفاصيل عدادات الطباعة"), 30, curY + 5, { width: usableWidth, align: "center" });
  curY += 26;

  const counterItems = [
    { label: "أبيض وأسود", val: Number(lifetime.monoPages || counters.monoPages || 0).toLocaleString("en-US") },
    { label: "ملون", val: Number(lifetime.colorPages || counters.colorPages || 0).toLocaleString("en-US") },
    { label: "طباعة وجهين", val: Number(lifetime.duplexPages || counters.duplexPages || 0).toLocaleString("en-US") },
    { label: "نسخ ومسح ضوئي", val: Number((lifetime.scanPages || counters.scanPages || 0) + (lifetime.copyPages || counters.copyPages || 0)).toLocaleString("en-US") },
  ];

  const cBoxW = (usableWidth - 18) / 4;
  for (let i = 0; i < counterItems.length; i++) {
    const ci = counterItems[i];
    const x = 30 + i * (cBoxW + 6);
    doc.roundedRect(x, curY, cBoxW, 36, 4).fill("#F8FAFC");
    doc.roundedRect(x, curY, cBoxW, 36, 4).strokeColor("#E2E8F0").lineWidth(0.8).stroke();
    withArabicFont(doc, false).fontSize(8).fillColor("#64748B");
    doc.text(processArabicText(ci.label), x + 4, curY + 5, { width: cBoxW - 8, align: "center" });
    withArabicFont(doc, true).fontSize(9.5).fillColor("#0F172A");
    doc.text(processArabicText(ci.val), x + 4, curY + 18, { width: cBoxW - 8, align: "center" });
  }

  curY += 42;

  // Section 4: History Table (Snapshots)
  doc.roundedRect(30, curY, usableWidth, 22, 4).fill("#2563EB");
  withArabicFont(doc, true).fontSize(9.5).fillColor("#FFFFFF");
  doc.text(processArabicText("سجل آخر القراءات التاريخية"), 30, curY + 5, { width: usableWidth, align: "center" });
  curY += 25;

  const histCols = [
    { label: "م", w: 30 },
    { label: "التاريخ والوقت", w: 125 },
    { label: "الحالة", w: 75 },
    { label: "العداد الكلي", w: 105 },
    { label: "انحشار الورق", w: 90 },
    { label: "مستوى الحبر", w: 110 },
  ];

  // Draw Header
  let hX = 30;
  for (const c of histCols) {
    doc.rect(hX, curY, c.w, 18).fill("#1E3A8A").strokeColor("#1E40AF").stroke();
    withArabicFont(doc, true).fontSize(8).fillColor("#FFFFFF");
    doc.text(processArabicText(c.label), hX + 2, curY + 4, { width: c.w - 4, align: "center" });
    hX += c.w;
  }
  curY += 18;

  const recentSnapshots = (snapshots || []).slice(0, 16);
  if (recentSnapshots.length === 0) {
    doc.rect(30, curY, usableWidth, 20).fill("#F8FAFC").strokeColor("#E2E8F0").stroke();
    withArabicFont(doc, false).fontSize(8.5).fillColor("#94A3B8");
    doc.text(processArabicText("لا توجد قراءات تاريخية مسجلة لهذه الطابعة حتى الآن"), 30, curY + 5, { width: usableWidth, align: "center" });
    curY += 20;
  } else {
    for (let i = 0; i < recentSnapshots.length; i++) {
      const snap = recentSnapshots[i];
      const isEven = i % 2 === 0;
      const rowBg = isEven ? "#F8FAFC" : "#FFFFFF";
      const rowH = 16;

      const sTotal = Number(snap.counters?.totalPages || snap.lifetimeCounters?.totalPages || 0);
      const sJams = Number(snap.maintenance?.paperJams || 0);
      const sToner = snap.tonerLevels?.black != null ? `${snap.tonerLevels.black}%` : "-";
      const sDate = formatDate(snap.snapshotAt);
      const sStatus = arabicStatus(snap.status);

      const rowVals = [
        String(i + 1),
        sDate,
        sStatus,
        sTotal.toLocaleString("en-US"),
        String(sJams),
        sToner,
      ];

      let rX = 30;
      for (let c = 0; c < histCols.length; c++) {
        const col = histCols[c];
        doc.rect(rX, curY, col.w, rowH).fill(rowBg).strokeColor("#E2E8F0").stroke();

        if (c === 2) {
          withArabicFont(doc, true).fontSize(7.5).fillColor(snap.status === "online" ? "#15803D" : "#B91C1C");
        } else {
          withArabicFont(doc, false).fontSize(7.5).fillColor("#0F172A");
        }

        doc.text(processArabicText(rowVals[c]), rX + 2, curY + 3, {
          width: col.w - 4,
          align: "center",
          ellipsis: true,
          lineBreak: false,
        });
        rX += col.w;
      }
      curY += rowH;
    }
  }

  // Footer on page bottom
  const footerY = doc.page.height - 32;
  doc.strokeColor("#E2E8F0").lineWidth(0.8).moveTo(30, footerY - 5).lineTo(doc.page.width - 30, footerY - 5).stroke();
  withArabicFont(doc, false).fontSize(7.5).fillColor("#64748B");
  const footerText = `منظومة iSmart Messenger لإدارة ومتابعة الطابعات   |   المسؤول المستخرج: ${actor?.fullName || actor?.username || "Admin"}   |   تاريخ وتوقيت التقرير: ${reportDate}`;
  doc.text(processArabicText(footerText), 30, footerY, { width: usableWidth, align: "center" });

  doc.end();
  await done;

  const suffix = (month && year) ? `-${year}-${month}` : "";
  const fileName = `printer-detail-${printer.ipAddress || printer._id}${suffix}-${Date.now()}.pdf`;
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
