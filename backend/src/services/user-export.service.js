const fs = require("fs");
const path = require("path");
const ExcelJS = require("exceljs");
const PDFDocument = require("pdfkit");

const User = require("../models/user.model");
const Department = require("../chat/models/department.model");
const Branch = require("../chat/models/branch.model");

const ARABIC_REGEX = /[\u0600-\u06FF]/;
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

function hasArabic(text) {
  return ARABIC_REGEX.test(fixText(text));
}

function processArabicText(text) {
  if (text == null) return "";
  const input = fixText(text);
  if (!/[\u0600-\u06FF]/.test(input)) return input;

  const swapped = input
    .replace(/\(/g, "\x01")
    .replace(/\)/g, "(")
    .replace(/\x01/g, ")");

  return swapped.split(" ").reverse().join("  ");
}

function resolveFonts() {
  const candidatesRegular = [
    path.join(__dirname, "../assets/fonts/Arial.ttf"),
    path.join(__dirname, "../../assets/fonts/Arial.ttf"),
    path.join(__dirname, "../assets/fonts/Amiri-Regular.ttf"),
  ];
  const candidatesBold = [
    path.join(__dirname, "../assets/fonts/Arial-Bold.ttf"),
    path.join(__dirname, "../../assets/fonts/Arial-Bold.ttf"),
    path.join(__dirname, "../assets/fonts/Amiri-Bold.ttf"),
  ];
  const fontRegular = candidatesRegular.find((p) => fs.existsSync(p)) || candidatesRegular[0];
  const fontBold = candidatesBold.find((p) => fs.existsSync(p)) || candidatesBold[0];
  return { fontRegular, fontBold };
}

function configureArabicPdf(doc) {
  const { fontRegular, fontBold } = resolveFonts();
  if (fs.existsSync(fontRegular)) {
    doc.registerFont("Arabic", fontRegular);
  }
  if (fs.existsSync(fontBold)) {
    doc.registerFont("ArabicBold", fontBold);
  }
  doc.font(fs.existsSync(fontRegular) ? "Arabic" : "Helvetica");
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
  return `${date.getFullYear()}/${String(date.getMonth() + 1).padStart(2, "0")}/${String(date.getDate()).padStart(2, "0")}`;
}

function roleLabel(role, forPdf = false) {
  switch (String(role || "").toLowerCase()) {
    case "admin":
      return forPdf ? "مسؤول نظام" : "مسؤول نظام (Admin)";
    case "manager":
      return forPdf ? "مدير قسم" : "مدير قسم (Manager)";
    default:
      return forPdf ? "مستخدم عادي" : "مستخدم عادي (User)";
  }
}

function statusLabel(isActive) {
  return isActive !== false ? "نشط" : "معطل";
}

async function exportUsersReport(actor, {
  format = "xlsx",
  branchId = null,
  departmentId = null,
  role = null,
  status = null,
  search = null,
} = {}) {
  const query = {};

  if (branchId) {
    query.branchId = branchId;
  }
  if (departmentId) {
    query.$or = [
      { departmentId: departmentId },
      { departmentIds: departmentId },
    ];
  }
  if (role) {
    query.role = String(role).trim().toLowerCase();
  }
  if (status === "active") {
    query.isActive = { $ne: false };
  } else if (status === "inactive") {
    query.isActive = false;
  }

  if (search && search.trim()) {
    const term = search.trim();
    const regex = new RegExp(term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i");
    const searchFilter = [
      { username: regex },
      { fullName: regex },
      { branchCode: regex },
    ];
    if (query.$or) {
      query.$and = [{ $or: query.$or }, { $or: searchFilter }];
      delete query.$or;
    } else {
      query.$or = searchFilter;
    }
  }

  // Fetch target branch & department details if filtered
  const [selectedBranch, selectedDept] = await Promise.all([
    branchId ? Branch.findById(branchId).lean() : null,
    departmentId ? Department.findById(departmentId).lean() : null,
  ]);

  const users = await User.find(query)
    .populate("branchId", "name code")
    .populate("departmentId", "name")
    .populate("departmentIds", "name")
    .sort({ branchCode: 1, fullName: 1, username: 1 })
    .lean();

  const isPdf = format === "pdf";
  const now = new Date();
  const dateStr = now.toISOString().slice(0, 10);
  const branchNameSafe = selectedBranch?.name ? selectedBranch.name.replace(/\s+/g, "_") : "All_Branches";
  const fileName = `users-list-${branchNameSafe}-${dateStr}.${isPdf ? "pdf" : "xlsx"}`;

  if (isPdf) {
    const buffer = await buildUsersPdfReport({
      users,
      actor,
      selectedBranch,
      selectedDept,
      generatedAt: now,
    });
    return { buffer, fileName, contentType: "application/pdf" };
  }

  const buffer = await buildUsersExcelReport({
    users,
    actor,
    selectedBranch,
    selectedDept,
    generatedAt: now,
  });
  return {
    buffer,
    fileName,
    contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  };
}

async function buildUsersExcelReport({
  users,
  actor,
  selectedBranch,
  selectedDept,
  generatedAt,
}) {
  const workbook = new ExcelJS.Workbook();
  workbook.creator = "iSmart Messenger";
  workbook.created = generatedAt;

  // 1. Users Sheet (RTL)
  const worksheet = workbook.addWorksheet(fixText("قائمة المستخدمين"));
  worksheet.views = [{ rtl: true }];

  worksheet.columns = [
    { header: "م", key: "index", width: 8 },
    { header: "اسم المستخدم", key: "username", width: 22 },
    { header: "الاسم الكامل", key: "fullName", width: 28 },
    { header: "المسمى الوظيفي", key: "jobTitle", width: 22 },
    { header: "الفرع", key: "branch", width: 22 },
    { header: "كود الفرع", key: "branchCode", width: 14 },
    { header: "القسم", key: "department", width: 24 },
    { header: "الدور والصلاحية", key: "role", width: 24 },
    { header: "حالة الحساب", key: "status", width: 14 },
    { header: "تاريخ الإنشاء", key: "createdAt", width: 20 },
    { header: "آخر تواجد", key: "lastActiveAt", width: 20 },
    { header: "ملاحظات", key: "notes", width: 24 },
  ];

  users.forEach((user, idx) => {
    const branchName = user.branchId?.name || (user.branchCode === "MAIN" ? "الفرع الرئيسي" : "-");
    const deptName = user.departmentId?.name ||
      (Array.isArray(user.departmentIds) && user.departmentIds.length > 0
        ? user.departmentIds.map((d) => d?.name || "").filter(Boolean).join("، ")
        : "-");

    worksheet.addRow({
      index: idx + 1,
      username: user.username,
      fullName: user.fullName || "-",
      jobTitle: user.jobTitle || "-",
      branch: branchName,
      branchCode: user.branchCode || "-",
      department: deptName,
      role: roleLabel(user.role),
      status: statusLabel(user.isActive),
      createdAt: formatDate(user.createdAt),
      lastActiveAt: formatDate(user.lastActiveAt),
      notes: user.isActive === false ? "الحساب معطل" : "نشط",
    });
  });

  // Header styling
  worksheet.getRow(1).height = 30;
  worksheet.getRow(1).eachCell((cell) => {
    cell.font = { bold: true, color: { argb: "FFFFFFFF" }, name: "Arial", size: 11 };
    cell.fill = {
      type: "pattern",
      pattern: "solid",
      fgColor: { argb: "1E3A8A" }, // Deep Navy
    };
    cell.alignment = { horizontal: "center", vertical: "middle" };
    cell.border = {
      top: { style: "thin", color: { argb: "93C5FD" } },
      bottom: { style: "medium", color: { argb: "1E40AF" } },
      left: { style: "thin", color: { argb: "93C5FD" } },
      right: { style: "thin", color: { argb: "93C5FD" } },
    };
  });

  // Row styling
  worksheet.eachRow((row, rowNumber) => {
    if (rowNumber === 1) return;
    row.height = 24;
    row.alignment = { horizontal: "right", vertical: "middle", wrapText: false };
    row.eachCell((cell, colNumber) => {
      cell.font = { name: "Arial", size: 10 };
      cell.border = {
        top: { style: "thin", color: { argb: "E2E8F0" } },
        bottom: { style: "thin", color: { argb: "E2E8F0" } },
        left: { style: "thin", color: { argb: "E2E8F0" } },
        right: { style: "thin", color: { argb: "E2E8F0" } },
      };

      if (rowNumber % 2 === 0) {
        cell.fill = {
          type: "pattern",
          pattern: "solid",
          fgColor: { argb: "F8FAFC" },
        };
      }

      // Center align for index, branch code, and status
      if (colNumber === 1 || colNumber === 6 || colNumber === 9) {
        cell.alignment = { horizontal: "center", vertical: "middle" };
      }

      // Status color highlighting
      if (colNumber === 9) {
        if (cell.value === "نشط") {
          cell.font = { name: "Arial", size: 10, bold: true, color: { argb: "15803D" } };
        } else {
          cell.font = { name: "Arial", size: 10, bold: true, color: { argb: "B91C1C" } };
        }
      }
    });
  });

  // 2. Summary Sheet
  const summary = workbook.addWorksheet(fixText("الملخص"));
  summary.views = [{ rtl: true }];
  summary.columns = [
    { header: "البند", key: "metric", width: 28 },
    { header: "القيمة", key: "value", width: 36 },
  ];

  const totalUsers = users.length;
  const activeUsers = users.filter((u) => u.isActive !== false).length;
  const inactiveUsers = totalUsers - activeUsers;
  const branchText = selectedBranch ? `${selectedBranch.name} (${selectedBranch.code || ""})` : "كافة الفروع";
  const deptText = selectedDept ? selectedDept.name : "كافة الأقسام";

  const summaryRows = [
    { metric: "اسم المنظومة", value: "iSmart Messenger" },
    { metric: "نوع التقرير", value: "كشف حسابات وبيانات المستخدمين" },
    { metric: "الفرع المحدد", value: branchText },
    { metric: "القسم المحدد", value: deptText },
    { metric: "إجمالي عدد المستخدمين", value: totalUsers },
    { metric: "المستخدمين النشطين", value: activeUsers },
    { metric: "المستخدمين المعطلين", value: inactiveUsers },
    { metric: "تاريخ الاستخراج", value: formatDate(generatedAt) },
    { metric: "المسؤول المنفذ", value: actor?.fullName || actor?.username || "Admin" },
  ];

  summary.addRows(summaryRows);
  summary.getRow(1).height = 28;
  summary.getRow(1).eachCell((cell) => {
    cell.font = { bold: true, color: { argb: "FFFFFFFF" }, name: "Arial", size: 11 };
    cell.fill = {
      type: "pattern",
      pattern: "solid",
      fgColor: { argb: "1E3A8A" },
    };
    cell.alignment = { horizontal: "center", vertical: "middle" };
  });

  summary.eachRow((row, rowNumber) => {
    if (rowNumber === 1) return;
    row.height = 24;
    row.eachCell((cell) => {
      cell.font = { name: "Arial", size: 10 };
      cell.border = {
        top: { style: "thin", color: { argb: "E2E8F0" } },
        bottom: { style: "thin", color: { argb: "E2E8F0" } },
        left: { style: "thin", color: { argb: "E2E8F0" } },
        right: { style: "thin", color: { argb: "E2E8F0" } },
      };
    });
  });

  const buffer = await workbook.xlsx.writeBuffer();
  return Buffer.from(buffer);
}

async function buildUsersPdfReport({
  users,
  actor,
  selectedBranch,
  selectedDept,
  generatedAt,
}) {
  const doc = new PDFDocument({
    margin: 36,
    size: "A4",
    layout: "landscape",
  });
  configureArabicPdf(doc);

  const chunks = [];
  doc.on("data", (chunk) => chunks.push(chunk));
  const done = new Promise((resolve) => doc.on("end", resolve));

  const branchText = selectedBranch ? `${selectedBranch.name}` : "كافة الفروع";
  const deptText = selectedDept ? selectedDept.name : "كافة الأقسام";
  const totalUsers = users.length;
  const activeUsers = users.filter((u) => u.isActive !== false).length;
  const usableWidth = doc.page.width - 72; // 841.89 - 72 = 769.89

  // Header Banner
  doc.rect(36, 36, usableWidth, 58).fill("#1E3A8A");

  withArabicFont(doc, true).fontSize(16).fillColor("#FFFFFF");
  const titleText = processArabicText("منظومة iSmart Messenger - كشف حسابات وبيانات المستخدمين");
  doc.text(titleText, 36, 46, { align: "center", width: usableWidth });

  withArabicFont(doc, false).fontSize(9.5).fillColor("#DBEAFE");
  const subTitle = processArabicText(
    `الفرع: ${branchText}   |   القسم: ${deptText}   |   إجمالي المستخدمين: ${totalUsers}   |   النشط: ${activeUsers}   |   تاريخ: ${formatDate(generatedAt)}`
  );
  doc.text(subTitle, 36, 70, { align: "center", width: usableWidth });

  // Columns definition (Right to Left):
  // 1: م (35pt)
  // 2: اسم المستخدم (110pt)
  // 3: الاسم الكامل (154pt)
  // 4: الفرع (110pt)
  // 5: القسم (110pt)
  // 6: الدور (110pt)
  // 7: الحالة (60pt)
  // 8: تاريخ الإنشاء (80pt)
  // Total = 769 pt (matches usableWidth)
  const columns = [
    { label: "م", width: 35 },
    { label: "اسم المستخدم", width: 110 },
    { label: "الاسم الكامل", width: 154 },
    { label: "الفرع", width: 110 },
    { label: "القسم", width: 110 },
    { label: "الدور", width: 110 },
    { label: "الحالة", width: 60 },
    { label: "تاريخ الإنشاء", width: 80 },
  ];

  const startY = 108;
  let currentY = startY;
  const headerHeight = 24;
  const rowHeight = 22;

  function drawTableHeader(y) {
    withArabicFont(doc, true).fontSize(9.5);
    let currentX = doc.page.width - 36; // Start from right margin

    for (const col of columns) {
      const x = currentX - col.width;
      doc.rect(x, y, col.width, headerHeight).fill("#2563EB");
      doc.rect(x, y, col.width, headerHeight).strokeColor("#1D4ED8").stroke();
      doc.fillColor("#FFFFFF");
      doc.text(processArabicText(col.label), x + 2, y + 6, {
        width: col.width - 4,
        align: "center",
      });
      currentX = x;
    }
  }

  drawTableHeader(currentY);
  currentY += headerHeight;

  users.forEach((user, idx) => {
    // Check page break
    if (currentY + rowHeight > doc.page.height - 40) {
      doc.addPage({ margin: 36, size: "A4", layout: "landscape" });
      currentY = 40;
      drawTableHeader(currentY);
      currentY += headerHeight;
    }

    const branchName = user.branchId?.name || (user.branchCode === "MAIN" ? "الفرع الرئيسي" : "-");
    const deptName = user.departmentId?.name ||
      (Array.isArray(user.departmentIds) && user.departmentIds.length > 0
        ? user.departmentIds.map((d) => d?.name || "").filter(Boolean).join("، ")
        : "-");

    const isEven = idx % 2 === 0;
    const rowBg = isEven ? "#F8FAFC" : "#FFFFFF";

    const rowData = [
      String(idx + 1),
      user.username || "-",
      user.fullName || "-",
      branchName,
      deptName,
      roleLabel(user.role, true),
      statusLabel(user.isActive),
      formatDate(user.createdAt),
    ];

    withArabicFont(doc, false).fontSize(8.5);
    let currentX = doc.page.width - 36;

    for (let c = 0; c < columns.length; c++) {
      const col = columns[c];
      const val = rowData[c];
      const x = currentX - col.width;

      doc.rect(x, currentY, col.width, rowHeight).fill(rowBg);
      doc.rect(x, currentY, col.width, rowHeight).strokeColor("#E2E8F0").stroke();

      if (c === 6) { // الحالة (Status)
        doc.fillColor(user.isActive !== false ? "#15803D" : "#B91C1C");
      } else {
        doc.fillColor("#0F172A");
      }

      doc.text(processArabicText(val), x + 2, currentY + 6, {
        width: col.width - 4,
        align: "center",
        ellipsis: true,
        lineBreak: false,
      });

      currentX = x;
    }

    currentY += rowHeight;
  });

  // Footer on last page
  withArabicFont(doc, false).fontSize(8).fillColor("#64748B");
  doc.text(
    processArabicText(`تم استخراج هذا التقرير آلياً بواسطة ${actor?.fullName || actor?.username || "Admin"} - منظومة iSmart Messenger`),
    36,
    doc.page.height - 26,
    { align: "center", width: usableWidth }
  );

  doc.end();
  await done;
  return Buffer.concat(chunks);
}

module.exports = {
  exportUsersReport,
  buildUsersPdfReport,
  buildUsersExcelReport,
  processArabicText,
};
