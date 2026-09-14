const path = require("path");
const fs = require("fs");
const ExcelJS = require("exceljs");
const PDFDocument = require("pdfkit");
const WasteStatistic = require("../models/waste-statistic.model");
const PrinterReport = require("../models/printer-report.model");

function processArabicText(text) {
  const input = String(text || "");
  if (!/[\u0600-\u06FF]/.test(input)) return input;
  
  const swapped = input
    .replace(/\(/g, '\x01')
    .replace(/\)/g, '(')
    .replace(/\x01/g, ')');
    
  return swapped.split(" ").reverse().join("  ");
}

async function createReportRecord(data) {
  try {
    return await PrinterReport.create(data);
  } catch (error) {
    console.error("Failed to save custom report record:", error);
  }
}

async function buildCustomPdfReport(data, reportName, month, year, type) {
  // Use Arial to ensure clean, official Arabic AND perfect English characters (no rectangles)
  const fontRegular = path.join(__dirname, "../../assets/fonts/Arial.ttf");
  const fontBold = path.join(__dirname, "../../assets/fonts/Arial-Bold.ttf");
  
  const logo1Path = path.join(__dirname, "../../assets/logo1.png");
  const logo2Path = path.join(__dirname, "../../assets/logo2.png");
  const logo1 = fs.existsSync(logo1Path) ? fs.readFileSync(logo1Path) : null;
  const logo2 = fs.existsSync(logo2Path) ? fs.readFileSync(logo2Path) : null;
  
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ margin: 30, size: "A4", layout: "landscape" });
    const chunks = [];
    doc.on("data", (c) => chunks.push(c));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    doc.registerFont("Arabic", fontRegular);
    doc.registerFont("ArabicBold", fontBold);

    // Keep logos clean without stretching (width 80 keeps original aspect ratio)
    try { if (logo2) doc.image(logo2, 730, 30, { width: 80 }); } catch (e) {}
    try { if (logo1) doc.image(logo1, 30, 30, { width: 80 }); } catch (e) {}

    doc.font("ArabicBold").fontSize(18);
    const line1 = processArabicText("جمعية رجال الأعمال والمستثمرين بالدقهلية");
    const line2 = processArabicText("مشروع تنمية المنشآت الصغيرة والحرفية");
    const line3 = processArabicText("رقم الإشهار: 777 لسنة 1995 - رقم الترخيص: 1031");
    
    doc.text(line1, 0, 40, { width: 841, align: "center" });
    doc.text(line2, 0, 65, { width: 841, align: "center" });
    doc.text(line3, 0, 90, { width: 841, align: "center" });

    const entityName = type === "global" ? "الفروع" : (data[0]?.branchName || "الفرع");
    let titleText = `استهلاك  ${entityName}  للورق عن شهر ${month || ""} ${year || ""}`;
    doc.fontSize(16).text(processArabicText(titleText), 0, 140, { width: 841, align: "center" });

    doc.moveDown(2);

    const headers = [
      "الرقم",
      type === "global" ? "الفرع" : "الطابعة",
      "عدد الصفحات\n(أسود)",
      "عدد الصفحات\n(ملون)",
      "الورق\nالهالك",
      "الاسكان",
      "الإجمالي\nللورق",
      "إجمالي\nالرزم"
    ];

    const tableTop = 180;
    const colWidths = [40, 150, 90, 90, 70, 70, 90, 90]; 
    const rowHeight = 55;
    let currentY = tableTop;

    function drawRow(y, rowData, isHeader = false) {
      doc.font(isHeader ? "ArabicBold" : "Arabic").fontSize(13);
      let currentX = 841 - 30;
      
      for (let i = 0; i < rowData.length; i++) {
        const text = rowData[i];
        const width = colWidths[i];
        const x = currentX - width;
        
        doc.rect(x, y, width, rowHeight).stroke();
        
        const lines = String(text).split("\n");
        const totalTextHeight = lines.length * 14;
        let textY = y + (rowHeight - totalTextHeight) / 2 - 2;
        
        for (const line of lines) {
          doc.text(processArabicText(line), x, textY, { width: width, align: "center" });
          textY += 14;
        }
        
        currentX = x;
      }
    }

    drawRow(currentY, headers, true);
    currentY += rowHeight;

    let index = 1;
    for (const item of data) {
      if (currentY + rowHeight > 550) {
        doc.addPage({ margin: 30, size: "A4", layout: "landscape" });
        currentY = 30;
        drawRow(currentY, headers, true);
        currentY += rowHeight;
      }

      const row = [
        index++,
        type === "global" ? item.branchName : item.printerName,
        item.monoPages,
        item.colorPages,
        item.wastePages,
        item.scanPages,
        item.totalPaper,
        item.overallTotalReams
      ];
      drawRow(currentY, row, false);
      currentY += rowHeight;
    }

    doc.end();
  });
}

async function buildCustomExcelReport(data, reportName, month, year, type) {
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet("تقرير الاستهلاك", { views: [{ rightToLeft: true }] });

  const logo1Path = path.join(__dirname, "../../assets/logo1.png");
  const logo2Path = path.join(__dirname, "../../assets/logo2.png");
  let logo1Id, logo2Id;
  
  if (fs.existsSync(logo1Path)) {
    logo1Id = workbook.addImage({ filename: logo1Path, extension: 'png' });
  }
  if (fs.existsSync(logo2Path)) {
    logo2Id = workbook.addImage({ filename: logo2Path, extension: 'png' });
  }

  sheet.columns = [
    { key: "index", width: 10 },
    { key: "entity", width: 30 },
    { key: "mono", width: 20 },
    { key: "color", width: 20 },
    { key: "waste", width: 15 },
    { key: "scan", width: 15 },
    { key: "totalPaper", width: 25 },
    { key: "overallTotal", width: 20 },
  ];

  sheet.getRow(1).height = 25;
  sheet.getRow(2).height = 25;
  sheet.getRow(3).height = 25;
  sheet.getRow(4).height = 15;
  sheet.getRow(5).height = 30;

  sheet.mergeCells('C1:F1');
  sheet.mergeCells('C2:F2');
  sheet.mergeCells('C3:F3');
  sheet.mergeCells('C5:F5');

  const line1Cell = sheet.getCell('C1');
  line1Cell.value = "جمعية رجال الأعمال والمستثمرين بالدقهلية";
  line1Cell.font = { name: "Arial", bold: true, size: 14 };
  line1Cell.alignment = { horizontal: 'center', vertical: 'middle' };

  const line2Cell = sheet.getCell('C2');
  line2Cell.value = "مشروع تنمية المنشآت الصغيرة والحرفية";
  line2Cell.font = { name: "Arial", bold: true, size: 14 };
  line2Cell.alignment = { horizontal: 'center', vertical: 'middle' };

  const line3Cell = sheet.getCell('C3');
  line3Cell.value = "رقم الإشهار: 777 لسنة 1995 - رقم الترخيص: 1031";
  line3Cell.font = { name: "Arial", bold: true, size: 12 };
  line3Cell.alignment = { horizontal: 'center', vertical: 'middle' };

  const entityName = type === "global" ? "الفروع" : (data[0]?.branchName || "الفرع");
  let titleText = `استهلاك  ${entityName}  للورق عن شهر ${month || ""} ${year || ""}`;
  
  const titleCell = sheet.getCell('C5');
  titleCell.value = titleText;
  titleCell.font = { name: "Arial", bold: true, size: 14 };
  titleCell.alignment = { horizontal: 'center', vertical: 'middle' };

  if (logo2Id) {
    sheet.addImage(logo2Id, {
      tl: { col: 0, row: 0 },
      ext: { width: 80, height: 80 }
    });
  }
  if (logo1Id) {
    sheet.addImage(logo1Id, {
      tl: { col: 6, row: 0 },
      ext: { width: 80, height: 80 }
    });
  }

  const headerRowIndex = 7;
  const headerRow = sheet.getRow(headerRowIndex);
  headerRow.values = [
    "الرقم",
    type === "global" ? "الفرع" : "الطابعة",
    "عدد الصفحات (أسود)",
    "عدد الصفحات (ملون)",
    "الورق الهالك",
    "الاسكان",
    "الإجمالي للورق",
    "إجمالي الرزم"
  ];
  headerRow.font = { name: "Arial", bold: true, size: 12 };
  headerRow.alignment = { vertical: "middle", horizontal: "center", wrapText: true };
  headerRow.height = 30;
  
  for (let i = 1; i <= 8; i++) {
    const cell = headerRow.getCell(i);
    cell.border = { top: { style: "thin" }, left: { style: "thin" }, bottom: { style: "thin" }, right: { style: "thin" } };
  }

  let index = 1;
  let currentRow = headerRowIndex + 1;
  for (const item of data) {
    const row = sheet.getRow(currentRow++);
    row.values = [
      index++,
      type === "global" ? item.branchName : item.printerName,
      item.monoPages,
      item.colorPages,
      item.wastePages,
      item.scanPages,
      item.totalPaper,
      item.overallTotalReams
    ];
    row.alignment = { vertical: "middle", horizontal: "center" };
    for (let i = 1; i <= 8; i++) {
      row.getCell(i).border = { top: { style: "thin" }, left: { style: "thin" }, bottom: { style: "thin" }, right: { style: "thin" } };
    }
  }

  return workbook.xlsx.writeBuffer();
}

async function exportCustomReport(actor, { type = "global", format = "pdf", branchId = null, month = null, year = null }) {
  const printerService = require("./printer.service");
  
  const m = month || new Date().getMonth() + 1;
  const y = year || new Date().getFullYear();

  let consumptionResult = await printerService.calculateMonthlyConsumption({
    branchId,
    month: m,
    year: y,
  });

  const consumptionList = consumptionResult.consumption || [];
  
  const wasteStats = await WasteStatistic.find({
    ...(branchId ? { branchId } : {})
  }).lean();

  let formattedData = [];

  if (type === "global") {
    formattedData = consumptionList.map(c => {
      const branchWaste = wasteStats.filter(w => w.branchId?.toString() === c.branchId?.toString());
      const wastePages = branchWaste.reduce((sum, w) => sum + (w.estimatedWastePages || 0), 0);
      
      let scanPages = 0;
      if (c.printers) {
         for (const p of c.printers) {
            scanPages += (p.scanPages || 0);
         }
      }

      const totalPaper = (c.totalPages || 0) + wastePages;
      const overallTotalReams = (totalPaper / 500).toFixed(2);

      return {
        branchName: c.branchName || "فرع غير معروف",
        monoPages: c.monoPages || 0,
        colorPages: c.colorPages || 0,
        wastePages: wastePages,
        scanPages: scanPages,
        totalPaper: totalPaper,
        overallTotalReams: overallTotalReams
      };
    });
  } else {
    for (const c of consumptionList) {
       for (const p of (c.printers || [])) {
          const printerWaste = wasteStats.filter(w => w.printerId?.toString() === p.printerId?.toString());
          const wastePages = printerWaste.reduce((sum, w) => sum + (w.estimatedWastePages || 0), 0);
          const scanPages = p.scanPages || 0;
          
          const totalPaper = (p.totalPages || 0) + wastePages;
          const overallTotalReams = (totalPaper / 500).toFixed(2);

          formattedData.push({
            branchName: c.branchName,
            printerName: p.printerName || p.ipAddress || "طابعة غير معروفة",
            monoPages: p.monoPages || 0,
            colorPages: p.colorPages || 0,
            wastePages: wastePages,
            scanPages: scanPages,
            totalPaper: totalPaper,
            overallTotalReams: overallTotalReams
          });
       }
    }
  }

  let buffer;
  const reportName = type === "global" ? "printer-global-report" : `printer-branch-report-${y}`;
  
  if (format === "xlsx") {
    buffer = await buildCustomExcelReport(formattedData, reportName, m, y, type);
  } else {
    buffer = await buildCustomPdfReport(formattedData, reportName, m, y, type);
  }

  const fileName = `${reportName}-${Date.now()}.${format === "xlsx" ? "xlsx" : "pdf"}`;
  await createReportRecord({
    type,
    format,
    branchId,
    actor,
    fileName,
  });

  return { buffer, fileName };
}

module.exports = { exportCustomReport };
