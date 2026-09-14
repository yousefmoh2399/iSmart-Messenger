const path = require("path");
const fs = require("fs");
const ExcelJS = require("exceljs");
const PDFDocument = require("pdfkit");

function processArabicText(text) {
  const input = String(text || "");
  if (!/[\u0600-\u06FF]/.test(input)) return input;

  const swapped = input
    .replace(/\(/g, "\x01")
    .replace(/\)/g, "(")
    .replace(/\x01/g, ")");

  return swapped.split(" ").reverse().join("  ");
}

function formatDate(date) {
  if (!date) return "";
  const d = new Date(date);
  return `${d.getFullYear()}/${(d.getMonth() + 1).toString().padStart(2, "0")}/${d.getDate().toString().padStart(2, "0")}`;
}

async function buildCustomPdfReport(data, reportName, reportTitle) {
  const fontRegular = path.join(__dirname, "../../assets/fonts/Arial.ttf");
  const fontBold = path.join(__dirname, "../../assets/fonts/Arial-Bold.ttf");

  const logo1Path = path.join(__dirname, "../../assets/logo1.png");
  const logo2Path = path.join(__dirname, "../../assets/logo2.png");
  const logo1 = fs.existsSync(logo1Path) ? fs.readFileSync(logo1Path) : null;
  const logo2 = fs.existsSync(logo2Path) ? fs.readFileSync(logo2Path) : null;

  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      margin: 30,
      size: "A4",
      layout: "landscape",
    });
    const chunks = [];
    doc.on("data", (c) => chunks.push(c));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    doc.registerFont("Arabic", fontRegular);
    doc.registerFont("ArabicBold", fontBold);

    try {
      if (logo2) doc.image(logo2, 730, 30, { width: 80 });
    } catch (e) {}
    try {
      if (logo1) doc.image(logo1, 30, 30, { width: 80 });
    } catch (e) {}

    doc.font("ArabicBold").fontSize(18);
    const line1 = processArabicText("جمعية رجال الأعمال والمستثمرين بالدقهلية");
    const line2 = processArabicText("مشروع تنمية المنشآت الصغيرة والحرفية");
    const line3 = processArabicText(
      "رقم الإشهار: 777 لسنة 1995 - رقم الترخيص: 1031",
    );

    doc.text(line1, 0, 40, { width: 841, align: "center" });
    doc.text(line2, 0, 65, { width: 841, align: "center" });
    doc.text(line3, 0, 90, { width: 841, align: "center" });

    doc
      .fontSize(16)
      .text(processArabicText(reportTitle), 0, 140, {
        width: 841,
        align: "center",
      });

    doc.moveDown(2);

    const headers = [
      "رقم\nالتذكرة",
      "العنوان",
      "الحالة",
      "الأولوية",
      "القسم",
      "بواسطة",
      "المسؤول",
      "تاريخ\nالإنشاء",
    ];

    const tableTop = 180;
    const colWidths = [60, 150, 70, 70, 100, 100, 110, 80];
    const rowHeight = 55;
    let currentY = tableTop;

    function drawRow(y, rowData, isHeader = false) {
      doc.font(isHeader ? "ArabicBold" : "Arabic").fontSize(13);
      let currentX = 841 - 40; // 40 right margin

      for (let i = 0; i < rowData.length; i++) {
        const text = rowData[i];
        const width = colWidths[i];
        const x = currentX - width;

        doc.rect(x, y, width, rowHeight).stroke();

        const lines = String(text).split("\n");
        const totalTextHeight = lines.length * 14;
        let textY = y + (rowHeight - totalTextHeight) / 2 - 2;

        for (const line of lines) {
          doc.text(processArabicText(line), x, textY, {
            width: width,
            align: "center",
          });
          textY += 14;
        }

        currentX = x;
      }
    }

    drawRow(currentY, headers, true);
    currentY += rowHeight;

    for (const item of data) {
      if (currentY + rowHeight > 550) {
        doc.addPage({ margin: 30, size: "A4", layout: "landscape" });
        currentY = 30;
        drawRow(currentY, headers, true);
        currentY += rowHeight;
      }

      const row = [
        item.ticketNumber,
        item.title,
        item.status,
        item.priority,
        item.department,
        item.createdBy,
        item.assignedTo,
        item.createdAt,
      ];
      drawRow(currentY, row, false);
      currentY += rowHeight;
    }

    doc.end();
  });
}

async function buildCustomExcelReport(data, reportName, reportTitle) {
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet("تقرير التذاكر", {
    views: [{ rightToLeft: true }],
  });

  const logo1Path = path.join(__dirname, "../../../assets/logo1.png");
  const logo2Path = path.join(__dirname, "../../../assets/logo2.png");
  let logo1Id, logo2Id;

  if (fs.existsSync(logo1Path)) {
    logo1Id = workbook.addImage({ filename: logo1Path, extension: "png" });
  }
  if (fs.existsSync(logo2Path)) {
    logo2Id = workbook.addImage({ filename: logo2Path, extension: "png" });
  }

  sheet.columns = [
    { key: "ticketNumber", width: 15 },
    { key: "title", width: 40 },
    { key: "status", width: 15 },
    { key: "priority", width: 15 },
    { key: "createdBy", width: 25 },
    { key: "assignedTo", width: 25 },
    { key: "resolvedBy", width: 25 },
    { key: "department", width: 20 },
    { key: "createdAt", width: 15 },
    { key: "dueDate", width: 15 },
    { key: "lastUpdateAt", width: 15 },
    { key: "resolvedAt", width: 15 },
    { key: "closedAt", width: 15 },
    { key: "minutesBetween", width: 15 },
    { key: "updatesCount", width: 15 },
    { key: "rating", width: 15 },
    { key: "lastPublicMessage", width: 40 },
  ];

  sheet.getRow(1).height = 25;
  sheet.getRow(2).height = 25;
  sheet.getRow(3).height = 25;
  sheet.getRow(4).height = 15;
  sheet.getRow(5).height = 30;

  sheet.mergeCells("D1:N1");
  sheet.mergeCells("D2:N2");
  sheet.mergeCells("D3:N3");
  sheet.mergeCells("D5:N5");

  const line1Cell = sheet.getCell("D1");
  line1Cell.value = "جمعية رجال الأعمال والمستثمرين بالدقهلية";
  line1Cell.font = { name: "Arial", bold: true, size: 14 };
  line1Cell.alignment = { horizontal: "center", vertical: "middle" };

  const line2Cell = sheet.getCell("D2");
  line2Cell.value = "مشروع تنمية المنشآت الصغيرة والحرفية";
  line2Cell.font = { name: "Arial", bold: true, size: 14 };
  line2Cell.alignment = { horizontal: "center", vertical: "middle" };

  const line3Cell = sheet.getCell("D3");
  line3Cell.value = "رقم الإشهار: 777 لسنة 1995 - رقم الترخيص: 1031";
  line3Cell.font = { name: "Arial", bold: true, size: 12 };
  line3Cell.alignment = { horizontal: "center", vertical: "middle" };

  const titleCell = sheet.getCell("D5");
  titleCell.value = reportTitle;
  titleCell.font = { name: "Arial", bold: true, size: 16 };
  titleCell.alignment = { horizontal: "center", vertical: "middle" };

  if (logo2Id) {
    sheet.addImage(logo2Id, {
      tl: { col: 0, row: 0 },
      ext: { width: 80, height: 80 },
    });
  }
  if (logo1Id) {
    sheet.addImage(logo1Id, {
      tl: { col: 16, row: 0 }, // Changed from 7 to 16
      ext: { width: 80, height: 80 },
    });
  }

  const headerRowIndex = 7;
  const headerRow = sheet.getRow(headerRowIndex);
  headerRow.values = [
    "رقم التذكرة",
    "العنوان",
    "الحالة",
    "الأولوية",
    "بواسطة",
    "المسؤول عنها",
    "من قام بالحل",
    "القسم",
    "تاريخ الإنشاء",
    "تاريخ الاستحقاق",
    "آخر تحديث",
    "تاريخ الحل",
    "تاريخ الإغلاق",
    "مدة الحل بالدقائق",
    "عدد التحديثات",
    "التقييم",
    "آخر رسالة",
  ];
  headerRow.font = { name: "Arial", bold: true, size: 12 };
  headerRow.alignment = {
    vertical: "middle",
    horizontal: "center",
    wrapText: true,
  };
  headerRow.height = 30;

  for (let i = 1; i <= 17; i++) {
    const cell = headerRow.getCell(i);
    cell.border = {
      top: { style: "thin" },
      left: { style: "thin" },
      bottom: { style: "thin" },
      right: { style: "thin" },
    };
  }

  let currentRow = headerRowIndex + 1;
  for (const item of data) {
    const row = sheet.getRow(currentRow++);
    row.values = [
      item.ticketNumber,
      item.title,
      item.status,
      item.priority,
      item.createdBy,
      item.assignedTo,
      item.resolvedBy,
      item.department,
      item.createdAt,
      item.dueDate,
      item.lastUpdateAt,
      item.resolvedAt,
      item.closedAt,
      item.minutesBetween,
      item.updatesCount,
      item.rating,
      item.lastPublicMessage,
    ];
    row.alignment = { vertical: "middle", horizontal: "center" };
    for (let i = 1; i <= 17; i++) {
      row.getCell(i).border = {
        top: { style: "thin" },
        left: { style: "thin" },
        bottom: { style: "thin" },
        right: { style: "thin" },
      };
    }
  }

  return workbook.xlsx.writeBuffer();
}

module.exports = {
  buildCustomPdfReport,
  buildCustomExcelReport,
  formatDate,
};
