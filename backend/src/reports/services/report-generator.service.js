const path = require("path");
const fs = require("fs");
const ExcelJS = require("exceljs");
const PDFDocument = require("pdfkit");

function processArabicText(text) {
  const input = String(text ?? "");
  if (!/[\u0600-\u06FF]/.test(input)) return input;

  const swapped = input
    .replace(/\(/g, "\x01")
    .replace(/\)/g, "(")
    .replace(/\x01/g, ")");

  return swapped.split(" ").reverse().join("  ");
}

function resolveFonts() {
  const candidatesRegular = [
    path.join(__dirname, "../../assets/fonts/Arial.ttf"),
    path.join(__dirname, "../../../assets/fonts/Arial.ttf"),
  ];
  const candidatesBold = [
    path.join(__dirname, "../../assets/fonts/Arial-Bold.ttf"),
    path.join(__dirname, "../../../assets/fonts/Arial-Bold.ttf"),
  ];
  const fontRegular = candidatesRegular.find((p) => fs.existsSync(p)) || candidatesRegular[0];
  const fontBold = candidatesBold.find((p) => fs.existsSync(p)) || candidatesBold[0];
  return { fontRegular, fontBold };
}

function resolveLogos() {
  const candidates1 = [
    path.join(__dirname, "../../assets/logo1.png"),
    path.join(__dirname, "../../../assets/logo1.png"),
  ];
  const candidates2 = [
    path.join(__dirname, "../../assets/logo2.png"),
    path.join(__dirname, "../../../assets/logo2.png"),
  ];
  const logo1Path = candidates1.find((p) => fs.existsSync(p)) || candidates1[0];
  const logo2Path = candidates2.find((p) => fs.existsSync(p)) || candidates2[0];
  const logo1 = fs.existsSync(logo1Path) ? fs.readFileSync(logo1Path) : null;
  const logo2 = fs.existsSync(logo2Path) ? fs.readFileSync(logo2Path) : null;
  return { logo1, logo2, logo1Path, logo2Path };
}

function formatValue(value) {
  if (value == null) return "—";
  if (typeof value === "number") {
    return Number.isInteger(value) ? value.toLocaleString("en-US") : value.toFixed(2);
  }
  return String(value);
}

function isNumericValue(val) {
  if (typeof val === "number") return !Number.isNaN(val);
  if (typeof val === "string") {
    const trimmed = val.trim();
    if (trimmed === "" || trimmed === "—") return false;
    return !Number.isNaN(Number(trimmed));
  }
  return false;
}

function getEnabledColumns(template) {
  const rawCols = Array.isArray(template.columns) ? template.columns : [];
  return rawCols
    .filter((c) => c.enabled !== false)
    .sort((a, b) => (Number(a.order) || 0) - (Number(b.order) || 0));
}

async function buildDynamicPdfReport({
  template,
  data = [],
  reportTitle = "",
  month = null,
  year = null,
  entityName = "الفروع",
}) {
  const { fontRegular, fontBold } = resolveFonts();
  const { logo1, logo2 } = resolveLogos();

  const isLandscape = template.options?.orientation !== "portrait";
  const pageWidth = isLandscape ? 841 : 595;
  const pageHeight = isLandscape ? 595 : 841;
  const margin = 30;
  const availableWidth = pageWidth - margin * 2;

  const enabledCols = getEnabledColumns(template);
  if (!enabledCols.length) {
    throw new Error("No columns enabled in report template.");
  }

  // Calculate proportional column widths
  const sumWidths = enabledCols.reduce(
    (sum, c) => sum + (Number(c.width) || 100),
    0,
  );
  const colWidths = enabledCols.map((c) =>
    Math.max(35, Math.round(((Number(c.width) || 100) / sumWidths) * availableWidth)),
  );
  // Adjust last column to match exactly availableWidth
  const currentTotalW = colWidths.reduce((a, b) => a + b, 0);
  const diff = availableWidth - currentTotalW;
  if (colWidths.length > 0) {
    colWidths[colWidths.length - 1] += diff;
  }

  const headerConfig = template.headerConfig || {};
  let finalTitle = reportTitle;
  if (headerConfig.titleFormat && headerConfig.titleFormat.trim()) {
    finalTitle = headerConfig.titleFormat
      .replace(/\{month\}/gi, month || "")
      .replace(/\{year\}/gi, year || "")
      .replace(/\{entity\}/gi, entityName || "")
      .replace(/\{ticketType\}/gi, reportTitle || "");
  }

  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      margin,
      size: "A4",
      layout: isLandscape ? "landscape" : "portrait",
    });

    const chunks = [];
    doc.on("data", (c) => chunks.push(c));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    if (fs.existsSync(fontRegular)) doc.registerFont("Arabic", fontRegular);
    if (fs.existsSync(fontBold)) doc.registerFont("ArabicBold", fontBold);

    function drawHeaderAndBranding() {
      // Logos
      if (headerConfig.showLogo1 !== false && logo1) {
        try {
          doc.image(logo1, margin, margin, { width: 75 });
        } catch (_) {}
      }
      if (headerConfig.showLogo2 !== false && logo2) {
        try {
          doc.image(logo2, pageWidth - margin - 75, margin, { width: 75 });
        } catch (_) {}
      }

      // Organization Header text
      doc.font("ArabicBold").fontSize(14);
      if (headerConfig.line1) {
        doc.text(processArabicText(headerConfig.line1), 0, 36, {
          width: pageWidth,
          align: "center",
        });
      }
      doc.fontSize(12);
      if (headerConfig.line2) {
        doc.text(processArabicText(headerConfig.line2), 0, 56, {
          width: pageWidth,
          align: "center",
        });
      }
      doc.fontSize(10);
      if (headerConfig.line3) {
        doc.text(processArabicText(headerConfig.line3), 0, 74, {
          width: pageWidth,
          align: "center",
        });
      }

      // Main Report Title
      doc.moveDown(1.5);
      doc.font("ArabicBold").fontSize(15);
      doc.text(processArabicText(finalTitle), 0, 105, {
        width: pageWidth,
        align: "center",
      });
    }

    drawHeaderAndBranding();

    const tableTop = 138;
    const rowHeight = Math.max(34, Number(template.options?.rowHeight) || 44);
    let currentY = tableTop;

    function drawRow(y, rowData, isHeader = false, isTotal = false) {
      doc
        .font(isHeader || isTotal ? "ArabicBold" : "Arabic")
        .fontSize(isHeader ? 11 : isTotal ? 10.5 : 10);

      let currentX = pageWidth - margin;

      for (let i = 0; i < rowData.length; i++) {
        const text = rowData[i];
        const width = colWidths[i];
        const x = currentX - width;

        if (isHeader) {
          doc.rect(x, y, width, rowHeight).fillAndStroke("#F1F5F9", "#CBD5E1");
          doc.fillColor("#0F172A");
        } else if (isTotal) {
          doc.rect(x, y, width, rowHeight).fillAndStroke("#E2E8F0", "#94A3B8");
          doc.fillColor("#0F172A");
        } else {
          doc.rect(x, y, width, rowHeight).strokeColor("#CBD5E1").stroke();
          doc.fillColor("#1E293B");
        }

        const lines = String(text ?? "").split("\n");
        const lineHeight = 12;
        const totalTextHeight = lines.length * lineHeight;
        let textY = y + (rowHeight - totalTextHeight) / 2 - 1;

        for (const line of lines) {
          doc.text(processArabicText(line), x + 2, textY, {
            width: width - 4,
            align: isHeader ? "center" : (enabledCols[i].align || "center"),
          });
          textY += lineHeight;
        }

        currentX = x;
      }
    }

    // Header row
    const headers = enabledCols.map((c) => c.label);
    drawRow(currentY, headers, true);
    currentY += rowHeight;

    // Data rows
    let autoIndex = 1;
    for (const item of data) {
      if (currentY + rowHeight > pageHeight - margin - 35) {
        doc.addPage({
          margin,
          size: "A4",
          layout: isLandscape ? "landscape" : "portrait",
        });
        currentY = margin + 10;
        drawRow(currentY, headers, true);
        currentY += rowHeight;
      }

      const rowValues = enabledCols.map((c) => {
        if (c.key === "index") {
          return item.index != null ? item.index : autoIndex;
        }
        return formatValue(item[c.key]);
      });

      drawRow(currentY, rowValues, false);
      currentY += rowHeight;
      autoIndex++;
    }

    // Summary / Totals row
    if (template.options?.includeSummaryRow !== false && data.length > 0) {
      if (currentY + rowHeight > pageHeight - margin - 35) {
        doc.addPage({
          margin,
          size: "A4",
          layout: isLandscape ? "landscape" : "portrait",
        });
        currentY = margin + 10;
        drawRow(currentY, headers, true);
        currentY += rowHeight;
      }

      const totalRow = enabledCols.map((c, idx) => {
        if (idx === 0) return "الإجمالي العام";
        if (idx === 1 && c.key !== "monoPages") return `عدد السجلات: ${data.length}`;

        // If numeric column, calculate sum
        const hasNumbers = data.some((item) => isNumericValue(item[c.key]));
        if (hasNumbers) {
          const sum = data.reduce((acc, item) => {
            const num = Number(item[c.key]);
            return acc + (Number.isNaN(num) ? 0 : num);
          }, 0);
          return Number.isInteger(sum) ? sum.toLocaleString("en-US") : sum.toFixed(2);
        }
        return "—";
      });

      drawRow(currentY, totalRow, false, true);
      currentY += rowHeight;
    }

    // Footer note
    if (headerConfig.footerNote && currentY + 30 <= pageHeight - margin) {
      doc.moveDown(1);
      doc
        .font("Arabic")
        .fontSize(10)
        .fillColor("#475569")
        .text(processArabicText(headerConfig.footerNote), margin, currentY + 12, {
          width: availableWidth,
          align: "right",
        });
    }

    doc.end();
  });
}

async function buildDynamicExcelReport({
  template,
  data = [],
  reportTitle = "",
  month = null,
  year = null,
  entityName = "الفروع",
}) {
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet(reportTitle || "التقرير", {
    views: [{ rightToLeft: true }],
  });

  const { logo1, logo2, logo1Path, logo2Path } = resolveLogos();
  const headerConfig = template.headerConfig || {};

  let logo1Id, logo2Id;
  if (headerConfig.showLogo1 !== false && logo1Path && fs.existsSync(logo1Path)) {
    logo1Id = workbook.addImage({ filename: logo1Path, extension: "png" });
  }
  if (headerConfig.showLogo2 !== false && logo2Path && fs.existsSync(logo2Path)) {
    logo2Id = workbook.addImage({ filename: logo2Path, extension: "png" });
  }

  const enabledCols = getEnabledColumns(template);
  if (!enabledCols.length) {
    throw new Error("No columns enabled in report template.");
  }

  // Setup sheet columns
  sheet.columns = enabledCols.map((c) => ({
    key: c.key,
    width: Math.max(12, Math.round((Number(c.width) || 100) / 7)),
  }));

  sheet.getRow(1).height = 24;
  sheet.getRow(2).height = 24;
  sheet.getRow(3).height = 24;
  sheet.getRow(4).height = 12;
  sheet.getRow(5).height = 30;

  const numCols = enabledCols.length;
  const colLetter = (num) => {
    let s = "";
    let n = num;
    while (n > 0) {
      const m = (n - 1) % 26;
      s = String.fromCharCode(65 + m) + s;
      n = Math.floor((n - m) / 26);
    }
    return s;
  };

  const midStart = Math.max(2, Math.floor(numCols / 4) + 1);
  const midEnd = Math.max(midStart + 1, numCols - Math.floor(numCols / 4));
  const startLetter = colLetter(midStart);
  const endLetter = colLetter(midEnd);

  // Merge header cells
  sheet.mergeCells(`${startLetter}1:${endLetter}1`);
  sheet.mergeCells(`${startLetter}2:${endLetter}2`);
  sheet.mergeCells(`${startLetter}3:${endLetter}3`);
  sheet.mergeCells(`${startLetter}5:${endLetter}5`);

  if (headerConfig.line1) {
    const c1 = sheet.getCell(`${startLetter}1`);
    c1.value = headerConfig.line1;
    c1.font = { name: "Arial", bold: true, size: 13 };
    c1.alignment = { horizontal: "center", vertical: "middle" };
  }
  if (headerConfig.line2) {
    const c2 = sheet.getCell(`${startLetter}2`);
    c2.value = headerConfig.line2;
    c2.font = { name: "Arial", bold: true, size: 12 };
    c2.alignment = { horizontal: "center", vertical: "middle" };
  }
  if (headerConfig.line3) {
    const c3 = sheet.getCell(`${startLetter}3`);
    c3.value = headerConfig.line3;
    c3.font = { name: "Arial", bold: false, size: 11 };
    c3.alignment = { horizontal: "center", vertical: "middle" };
  }

  let finalTitle = reportTitle;
  if (headerConfig.titleFormat && headerConfig.titleFormat.trim()) {
    finalTitle = headerConfig.titleFormat
      .replace(/\{month\}/gi, month || "")
      .replace(/\{year\}/gi, year || "")
      .replace(/\{entity\}/gi, entityName || "")
      .replace(/\{ticketType\}/gi, reportTitle || "");
  }

  const titleCell = sheet.getCell(`${startLetter}5`);
  titleCell.value = finalTitle;
  titleCell.font = { name: "Arial", bold: true, size: 14 };
  titleCell.alignment = { horizontal: "center", vertical: "middle" };

  // Add logos
  if (logo2Id) {
    sheet.addImage(logo2Id, {
      tl: { col: 0, row: 0 },
      ext: { width: 75, height: 75 },
    });
  }
  if (logo1Id && numCols > 3) {
    sheet.addImage(logo1Id, {
      tl: { col: numCols - 1, row: 0 },
      ext: { width: 75, height: 75 },
    });
  }

  // Header Row
  const headerRowIndex = 7;
  const headerRow = sheet.getRow(headerRowIndex);
  headerRow.values = enabledCols.map((c) => c.label);
  headerRow.font = { name: "Arial", bold: true, size: 11, color: { argb: "FF0F172A" } };
  headerRow.alignment = { vertical: "middle", horizontal: "center", wrapText: true };
  headerRow.height = 32;

  for (let i = 1; i <= numCols; i++) {
    const cell = headerRow.getCell(i);
    cell.fill = {
      type: "pattern",
      pattern: "solid",
      fgColor: { argb: "FFF1F5F9" },
    };
    cell.border = {
      top: { style: "thin", color: { argb: "FFCBD5E1" } },
      left: { style: "thin", color: { argb: "FFCBD5E1" } },
      bottom: { style: "medium", color: { argb: "FF94A3B8" } },
      right: { style: "thin", color: { argb: "FFCBD5E1" } },
    };
  }

  // Data rows
  let autoIndex = 1;
  let currentRow = headerRowIndex + 1;

  for (const item of data) {
    const row = sheet.getRow(currentRow++);
    row.values = enabledCols.map((c) => {
      if (c.key === "index") {
        return item.index != null ? item.index : autoIndex;
      }
      return item[c.key] ?? "";
    });

    row.height = 24;
    for (let i = 1; i <= numCols; i++) {
      const cell = row.getCell(i);
      cell.font = { name: "Arial", size: 10 };
      cell.alignment = {
        vertical: "middle",
        horizontal: enabledCols[i - 1].align || "center",
      };
      cell.border = {
        top: { style: "thin", color: { argb: "FFE2E8F0" } },
        left: { style: "thin", color: { argb: "FFE2E8F0" } },
        bottom: { style: "thin", color: { argb: "FFE2E8F0" } },
        right: { style: "thin", color: { argb: "FFE2E8F0" } },
      };
    }
    autoIndex++;
  }

  // Totals row
  if (template.options?.includeSummaryRow !== false && data.length > 0) {
    const totalRow = sheet.getRow(currentRow++);
    totalRow.height = 26;
    totalRow.values = enabledCols.map((c, idx) => {
      if (idx === 0) return "الإجمالي العام";
      if (idx === 1 && c.key !== "monoPages") return `عدد السجلات: ${data.length}`;

      const hasNumbers = data.some((item) => isNumericValue(item[c.key]));
      if (hasNumbers) {
        const sum = data.reduce((acc, item) => {
          const num = Number(item[c.key]);
          return acc + (Number.isNaN(num) ? 0 : num);
        }, 0);
        return Number.isInteger(sum) ? sum : Number(sum.toFixed(2));
      }
      return "";
    });

    for (let i = 1; i <= numCols; i++) {
      const cell = totalRow.getCell(i);
      cell.font = { name: "Arial", bold: true, size: 10.5 };
      cell.alignment = { vertical: "middle", horizontal: "center" };
      cell.fill = {
        type: "pattern",
        pattern: "solid",
        fgColor: { argb: "FFE2E8F0" },
      };
      cell.border = {
        top: { style: "medium", color: { argb: "FF94A3B8" } },
        left: { style: "thin", color: { argb: "FFCBD5E1" } },
        bottom: { style: "medium", color: { argb: "FF94A3B8" } },
        right: { style: "thin", color: { argb: "FFCBD5E1" } },
      };
    }
  }

  // Footer Note
  if (headerConfig.footerNote) {
    currentRow += 1;
    const footerRow = sheet.getRow(currentRow);
    footerRow.getCell(1).value = headerConfig.footerNote;
    footerRow.getCell(1).font = { name: "Arial", italic: true, size: 10, color: { argb: "FF64748B" } };
  }

  return workbook.xlsx.writeBuffer();
}

module.exports = {
  buildDynamicPdfReport,
  buildDynamicExcelReport,
  getEnabledColumns,
};
