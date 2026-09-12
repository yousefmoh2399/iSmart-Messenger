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

function styleWorksheet(worksheet) {
  worksheet.views = [{ rightToLeft: true, state: "frozen", ySplit: 1 }];
  worksheet.getRow(1).height = 24;
  worksheet.getRow(1).eachCell((cell) => {
    cell.font = { bold: true, color: { argb: "FFFFFFFF" }, name: "Arial" };
    cell.fill = {
      type: "pattern",
      pattern: "solid",
      fgColor: { argb: "1F4E78" },
    };
    cell.alignment = { horizontal: "center", vertical: "middle" };
    cell.border = {
      top: { style: "thin", color: { argb: "D9E2F2" } },
      bottom: { style: "thin", color: { argb: "D9E2F2" } },
      left: { style: "thin", color: { argb: "D9E2F2" } },
      right: { style: "thin", color: { argb: "D9E2F2" } },
    };
  });
  worksheet.eachRow((row, rowNumber) => {
    row.alignment = { horizontal: "right", vertical: "middle", wrapText: true };
    row.eachCell((cell) => {
      cell.font = { name: "Arial", size: 11 };
      cell.border = {
        top: { style: "thin", color: { argb: "E5E7EB" } },
        bottom: { style: "thin", color: { argb: "E5E7EB" } },
        left: { style: "thin", color: { argb: "E5E7EB" } },
        right: { style: "thin", color: { argb: "E5E7EB" } },
      };
      if (rowNumber > 1 && rowNumber % 2 === 0) {
        cell.fill = {
          type: "pattern",
          pattern: "solid",
          fgColor: { argb: "F8FAFC" },
        };
      }
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
    "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
    "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"
  ];
  const isAllMonths = month !== null && month !== undefined && Number(month) === 0;
  const monthLabel = isAllMonths
    ? `جميع شهور سنة ${year}`
    : (month && monthNames[Number(month) - 1] ? `${monthNames[Number(month) - 1]} ${year}` : "");
  const hasMonthly = !!monthlyConsumption;

  const summary = workbook.addWorksheet(fixText("الملخص"));
  summary.columns = [
    { header: "البند", key: "metric", width: 32 },
    { header: "القيمة", key: "value", width: 42 },
  ];
  
  const summaryRows = [
    { metric: "نوع التقرير", value: type === "branch" ? "فرع" : "عام" },
    { metric: "الفرع", value: branch?.name || "كل الفروع" },
    { metric: "عدد الفروع", value: branches.length },
    { metric: "عدد الطابعات", value: printers.length },
    { metric: "الطابعات المتصلة", value: printers.filter((item) => item.status === "online").length },
    { metric: "الطابعات غير المتصلة", value: printers.filter((item) => item.status !== "online").length },
  ];

  if (hasMonthly) {
    const totalPages = monthlyConsumption.consumption.reduce((sum, item) => sum + Number(item.totalPages || 0), 0);
    const totalPaper = paperMetrics(totalPages);
    const partialBranches = monthlyConsumption.consumption.filter((item) => item.hasPartialData || item.hasStaleBaseline).length;
    summaryRows.push(
      { metric: isAllMonths ? "تقرير استهلاك الفترة" : "تقرير استهلاك شهر", value: monthLabel },
      {
        metric: isAllMonths ? "إجمالي الاستهلاك للفترة (صفحة)" : "إجمالي استهلاك الشهر (صفحة)",
        value: totalPages,
      },
      {
        metric: "إجمالي استهلاك الرزم (500 ورقة/رزمة)",
        value: `${totalPaper.exactReams.toFixed(2)} رزمة (${totalPaper.fullReams} رزمة و ${totalPaper.remainingSheets} ورقة)`,
      },
      {
        metric: "عدد العملاء التقديري (16 ورقة/عميل)",
        value: `${totalPaper.estimatedClients} عميل`,
      },
      {
        metric: "الرزم المطلوبة محاسبيًا",
        value: totalPaper.requiredReams,
      },
      {
        metric: "فروع تحتاج مراجعة القراءات",
        value: partialBranches,
      },
      {
        metric: isAllMonths ? "استهلاك أبيض وأسود للفترة" : "استهلاك أبيض وأسود للشهر",
        value: monthlyConsumption.consumption.reduce((sum, item) => sum + Number(item.monoPages || 0), 0),
      },
      {
        metric: isAllMonths ? "استهلاك ملون للفترة" : "استهلاك ملون للشهر",
        value: monthlyConsumption.consumption.reduce((sum, item) => sum + Number(item.colorPages || 0), 0),
      }
    );
  } else {
    summaryRows.push(
      {
        metric: "إجمالي صفحات العمر",
        value: printers.reduce((sum, item) => sum + Number(item.lifetimeCounters?.totalPages || 0), 0),
      },
      {
        metric: "إجمالي الهالك التقديري",
        value: waste.reduce((sum, item) => sum + Number(item.estimatedWastePages || 0), 0),
      }
    );
  }

  summaryRows.push({ metric: "تاريخ الإنشاء", value: formatDate(new Date()) });
  summary.addRows(summaryRows);
  styleWorksheet(summary);
  normalizeWorksheetStrings(summary);

  const printerUsageMap = {};
  if (hasMonthly && Array.isArray(monthlyConsumption.consumption)) {
    for (const b of monthlyConsumption.consumption) {
      if (Array.isArray(b.printers)) {
        for (const p of b.printers) {
          printerUsageMap[p.printerId] = p;
        }
      }
    }
  }

  const printersSheet = workbook.addWorksheet(fixText("الطابعات"));
  printersSheet.columns = [
    { header: "الفرع", key: "branch", width: 22 },
    { header: "اسم الطابعة", key: "name", width: 28 },
    { header: "IP", key: "ip", width: 18 },
    { header: "الموديل", key: "model", width: 28 },
    { header: "الرقم التسلسلي", key: "serial", width: 22 },
    { header: "الشركة", key: "vendor", width: 14 },
    { header: "الحالة", key: "status", width: 14 },
    ...(hasMonthly ? [
      { header: "الاستهلاك الشهري (صفحة)", key: "monthlyTotal", width: 20 },
      { header: "أبيض وأسود شهري", key: "monthlyMono", width: 18 },
      { header: "ألوان شهري", key: "monthlyColor", width: 18 },
      { header: "رزم فعلية", key: "monthlyReams", width: 14 },
      { header: "رزم مطلوبة", key: "monthlyRequiredReams", width: 14 },
      { header: "عملاء تقديري", key: "monthlyEstimatedClients", width: 16 },
      { header: "جودة بيانات الشهر", key: "monthlyDataQuality", width: 22 },
    ] : []),
    { header: "العداد الحالي", key: "currentTotal", width: 16 },
    { header: "عداد العمر", key: "lifetimeTotal", width: 16 },
    { header: "أسود %", key: "black", width: 10 },
    { header: "سماوي %", key: "cyan", width: 10 },
    { header: "أرجواني %", key: "magenta", width: 10 },
    { header: "أصفر %", key: "yellow", width: 10 },
  ];

  printersSheet.addRows(
    printers.map((printer) => {
      const u = printerUsageMap[printer._id.toString()] || { totalPages: 0, monoPages: 0, colorPages: 0 };
      const paper = paperMetrics(u.totalPages);
      return {
        branch: printerBranchName(printer),
        name: printerDisplayName(printer),
        ip: printer.ipAddress,
        model: printer.model || "",
        serial: printer.serialNumber || "",
        vendor: printer.vendor || "",
        status: arabicStatus(printer.status),
        ...(hasMonthly ? {
          monthlyTotal: u.totalPages,
          monthlyMono: u.monoPages,
          monthlyColor: u.colorPages,
          monthlyReams: Number(paper.exactReams.toFixed(2)),
          monthlyRequiredReams: paper.requiredReams,
          monthlyEstimatedClients: paper.estimatedClients,
          monthlyDataQuality: dataQualityLabel(u),
        } : {}),
        currentTotal: printer.counters?.totalPages || 0,
        lifetimeTotal: printer.lifetimeCounters?.totalPages || 0,
        black: printer.tonerLevels?.black ?? "",
        cyan: printer.tonerLevels?.cyan ?? "",
        magenta: printer.tonerLevels?.magenta ?? "",
        yellow: printer.tonerLevels?.yellow ?? "",
      };
    }),
  );
  styleWorksheet(printersSheet);
  normalizeWorksheetStrings(printersSheet);

  if (hasMonthly) {
    const branchConsumptionSheet = workbook.addWorksheet(fixText("استهلاك الفروع"));
    branchConsumptionSheet.columns = [
      { header: "كود الفرع", key: "branchCode", width: 15 },
      { header: "اسم الفرع", key: "branchName", width: 25 },
      { header: "عدد الطابعات", key: "printersCount", width: 15 },
      { header: "إجمالي الصفحات", key: "totalPages", width: 20 },
      { header: "استهلاك الرزم (500 ورقة/رزمة)", key: "reams", width: 28 },
      { header: "الرزم المطلوبة محاسبيًا", key: "requiredReams", width: 22 },
      { header: "العملاء المفترضين (16 ورقة/عميل)", key: "estimatedClients", width: 28 },
      { header: "متوسط صفحات/طابعة", key: "avgPagesPerPrinter", width: 18 },
      { header: "طابعات بقراءات جزئية", key: "partialPrintersCount", width: 22 },
      { header: "طابعات باستهلاك مرتفع جدًا", key: "suspiciousPrintersCount", width: 26 },
      { header: "جودة البيانات", key: "dataQuality", width: 24 },
      { header: "أبيض وأسود", key: "monoPages", width: 18 },
      { header: "ملون", key: "colorPages", width: 18 },
    ];
    branchConsumptionSheet.addRows(
      monthlyConsumption.consumption.map((b) => {
        const pages = Number(b.totalPages || 0);
        const paper = paperMetrics(pages);
        const printersCount = Number(b.printersCount || 0);
        return {
          branchCode: b.branchCode || "",
          branchName: b.branchName || "",
          printersCount,
          totalPages: pages,
          reams: `${paper.exactReams.toFixed(2)} رزمة (${paper.fullReams} رزمة + ${paper.remainingSheets} ورقة)`,
          requiredReams: paper.requiredReams,
          estimatedClients: paper.estimatedClients,
          avgPagesPerPrinter: printersCount > 0 ? Math.round(pages / printersCount) : 0,
          partialPrintersCount: b.partialPrintersCount || 0,
          suspiciousPrintersCount: b.suspiciousPrintersCount || 0,
          dataQuality: dataQualityLabel(b),
          monoPages: b.monoPages || 0,
          colorPages: b.colorPages || 0,
        };
      })
    );
    styleWorksheet(branchConsumptionSheet);
    normalizeWorksheetStrings(branchConsumptionSheet);

    const printerConsumptionSheet = workbook.addWorksheet(fixText("تفاصيل استهلاك الطابعات"));
    printerConsumptionSheet.columns = [
      { header: "كود الفرع", key: "branchCode", width: 15 },
      { header: "اسم الفرع", key: "branchName", width: 25 },
      { header: "اسم الطابعة", key: "printerName", width: 30 },
      { header: "IP", key: "ipAddress", width: 18 },
      { header: "الموديل", key: "model", width: 28 },
      { header: "إجمالي الصفحات", key: "totalPages", width: 18 },
      { header: "أبيض وأسود", key: "monoPages", width: 16 },
      { header: "ملون", key: "colorPages", width: 16 },
      { header: "رزم فعلية", key: "reams", width: 14 },
      { header: "رزم مطلوبة", key: "requiredReams", width: 14 },
      { header: "عملاء تقديري", key: "estimatedClients", width: 16 },
      { header: "أول قراءة في الفترة", key: "firstSnapshotAt", width: 22 },
      { header: "آخر قراءة في الفترة", key: "lastSnapshotAt", width: 22 },
      { header: "ثقة الهوية", key: "identityConfidence", width: 14 },
      { header: "ملاحظات النظام", key: "anomalyFlags", width: 28 },
      { header: "جودة البيانات", key: "dataQuality", width: 24 },
    ];
    const printerConsumptionRows = [];
    for (const b of monthlyConsumption.consumption) {
      for (const p of b.printers || []) {
        const pages = Number(p.totalPages || 0);
        const paper = paperMetrics(pages);
        printerConsumptionRows.push({
          branchCode: b.branchCode || "",
          branchName: b.branchName || "",
          printerName: p.printerName || "",
          ipAddress: p.ipAddress || "",
          model: p.model || "",
          totalPages: pages,
          monoPages: p.monoPages || 0,
          colorPages: p.colorPages || 0,
          reams: Number(paper.exactReams.toFixed(2)),
          requiredReams: paper.requiredReams,
          estimatedClients: paper.estimatedClients,
          firstSnapshotAt: formatDate(p.firstSnapshotAt),
          lastSnapshotAt: formatDate(p.lastSnapshotAt),
          identityConfidence: p.identityConfidence || "",
          anomalyFlags: (p.anomalyFlags || []).join(", "),
          dataQuality: dataQualityLabel(p),
        });
      }
    }
    printerConsumptionSheet.addRows(printerConsumptionRows);
    styleWorksheet(printerConsumptionSheet);
    normalizeWorksheetStrings(printerConsumptionSheet);
  }

  const wasteSheet = workbook.addWorksheet(fixText("الهالك"));
  wasteSheet.columns = [
    { header: "الفرع", key: "branch", width: 22 },
    { header: "الطابعة", key: "printer", width: 28 },
    { header: "صفحات الهالك", key: "waste", width: 16 },
    { header: "مرات الانحشار", key: "jams", width: 16 },
    { header: "أخطاء الطابعة", key: "errors", width: 16 },
    { header: "التاريخ", key: "date", width: 24 },
  ];
  wasteSheet.addRows(
    waste.map((entry) => ({
      branch: entry.branchId?.name || "",
      printer: entry.printerId?.printerName || "",
      waste: entry.estimatedWastePages || 0,
      jams: entry.paperJams || 0,
      errors: entry.printerErrors || 0,
      date: formatDate(entry.calculatedAt),
    })),
  );
  styleWorksheet(wasteSheet);
  normalizeWorksheetStrings(wasteSheet);

  const historySheet = workbook.addWorksheet(fixText("اللقطات"));
  historySheet.columns = [
    { header: "الفرع", key: "branch", width: 22 },
    { header: "الطابعة", key: "printer", width: 28 },
    { header: "التاريخ", key: "date", width: 24 },
    { header: "إجمالي الصفحات", key: "total", width: 16 },
    { header: "عداد العمر", key: "lifetime", width: 16 },
    { header: "الانحشار", key: "jams", width: 14 },
    { header: "الحالة", key: "status", width: 14 },
  ];
  historySheet.addRows(
    snapshots.map((entry) => ({
      branch: entry.branchId?.name || "",
      printer: entry.printerId?.printerName || "",
      date: formatDate(entry.snapshotAt),
      total: entry.counters?.totalPages || 0,
      lifetime: entry.lifetimeCounters?.totalPages || 0,
      jams: entry.maintenance?.paperJams || 0,
      status: arabicStatus(entry.status),
    })),
  );
  styleWorksheet(historySheet);
  normalizeWorksheetStrings(historySheet);

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
      { label: "عدد العملاء التقديري (16 ورقة/عميل)", value: `${mPaper.estimatedClients} عميل` },
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
  if (month && year) {
    const monthNames = [
      "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
      "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"
    ];
    const isAllMonths = Number(month) === 0;
    const monthName = isAllMonths ? "جميع الشهور" : (monthNames[Number(month) - 1] || month);
    mainTitle = isAllMonths ? `تقرير الطابعة لجميع شهور سنة ${year}` : `تقرير الطابعة لشهر ${monthName} ${year}`;
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
