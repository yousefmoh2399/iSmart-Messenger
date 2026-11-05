const fs = require("fs");
const path = require("path");
const ExcelJS = require("exceljs");
const PDFDocument = require("pdfkit");

const Branch = require("../../chat/models/branch.model");
const User = require("../../models/user.model");
const DeviceSession = require("../../models/device-session.model");

const logo1Path = path.join(__dirname, "../../assets/logo1.png");
const logo2Path = path.join(__dirname, "../../assets/logo2.png");

const CURRENT_APP_VERSION = "1.1.21";

function processArabicText(text) {
  if (text == null) return "";
  const input = String(text);
  if (!/[\u0600-\u06FF]/.test(input)) return input;

  const swapped = input
    .replace(/\(/g, "\x01")
    .replace(/\)/g, "(")
    .replace(/\x01/g, ")");

  return swapped.split(" ").reverse().join("  ");
}

function configureArabicPdf(doc) {
  const fontRegular = path.join(__dirname, "../../assets/fonts/Arial.ttf");
  const fontBold = path.join(__dirname, "../../assets/fonts/Arial-Bold.ttf");

  if (fs.existsSync(fontRegular)) doc.registerFont("Arabic", fontRegular);
  if (fs.existsSync(fontBold)) doc.registerFont("ArabicBold", fontBold);

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
  return date.toISOString().replace("T", " ").slice(0, 19);
}

async function getBranchesDeploymentData() {
  const [branches, users, sessions] = await Promise.all([
    Branch.find({ deletedAt: null }).sort({ code: 1, name: 1 }).lean(),
    User.find({ isActive: true })
      .select("_id username fullName role jobTitle branchId branchCode lastActiveAt isOnline")
      .lean(),
    DeviceSession.find({})
      .populate("userId", "_id username fullName role branchId branchCode isOnline")
      .sort({ lastSeenAt: -1 })
      .lean(),
  ]);

  // Group users by branch
  const usersByBranchId = new Map();
  const usersByBranchCode = new Map();
  const allUsersMap = new Map();

  for (const u of users) {
    allUsersMap.set(String(u._id), u);
    if (u.branchId) {
      const bId = String(u.branchId);
      if (!usersByBranchId.has(bId)) usersByBranchId.set(bId, []);
      usersByBranchId.get(bId).push(u);
    }
    if (u.branchCode) {
      const bCode = String(u.branchCode).toUpperCase();
      if (!usersByBranchCode.has(bCode)) usersByBranchCode.set(bCode, []);
      usersByBranchCode.get(bCode).push(u);
    }
  }

  // Group sessions by user
  const sessionsByUser = new Map();
  const versionCounts = {};
  const platformCounts = {};

  for (const s of sessions) {
    const uId = s.userId?._id ? String(s.userId._id) : (s.userId ? String(s.userId) : null);
    if (!uId) continue;
    if (!sessionsByUser.has(uId)) sessionsByUser.set(uId, []);
    sessionsByUser.get(uId).push(s);

    const version = s.deviceInfo?.appVersion || (s.clientType === "desktop" ? CURRENT_APP_VERSION : s.clientType || "unknown");
    versionCounts[version] = (versionCounts[version] || 0) + 1;

    const osName = s.deviceInfo?.os || s.clientType || "unknown";
    platformCounts[osName] = (platformCounts[osName] || 0) + 1;
  }

  // Build branch deployment items
  const branchItems = [];
  let totalInstalledBranches = 0;
  let totalDevices = 0;
  let totalOnlineDevices = 0;

  for (const b of branches) {
    const bId = String(b._id);
    const bCode = (b.code || "").toUpperCase();

    // Get all users associated with this branch
    const branchUsers = usersByBranchId.get(bId) || usersByBranchCode.get(bCode) || [];

    const installedUsers = [];
    const devicesMap = new Map();
    const branchVersions = new Set();
    let branchLastSeen = null;
    let onlineUsersCount = 0;

    for (const u of branchUsers) {
      const uId = String(u._id);
      if (u.isOnline) onlineUsersCount++;

      const uSessions = sessionsByUser.get(uId) || [];
      if (uSessions.length > 0) {
        for (const s of uSessions) {
          const version = s.deviceInfo?.appVersion || CURRENT_APP_VERSION;
          branchVersions.add(version);

          if (!branchLastSeen || new Date(s.lastSeenAt) > new Date(branchLastSeen)) {
            branchLastSeen = s.lastSeenAt;
          }

          // Distinct device key
          const devKey = s.deviceInfo?.hostname
            ? `${s.deviceInfo.hostname}_${s.ipAddress || ""}`
            : (s.ipAddress || String(s._id));

          if (!devicesMap.has(devKey) || s.isOnline) {
            devicesMap.set(devKey, {
              hostname: s.deviceInfo?.hostname || "Unknown Device",
              os: s.deviceInfo?.os || "Windows",
              osVersion: s.deviceInfo?.osVersion || "",
              ipAddress: s.ipAddress || "-",
              clientType: s.clientType || "desktop",
              appVersion: version,
              isOnline: !!s.isOnline,
              lastSeenAt: s.lastSeenAt,
              user: {
                id: u._id,
                username: u.username,
                fullName: u.fullName,
                role: u.role,
              },
            });
          }
        }

        installedUsers.push({
          userId: u._id,
          username: u.username,
          fullName: u.fullName,
          role: u.role,
          jobTitle: u.jobTitle || "-",
          isOnline: !!u.isOnline,
          lastActiveAt: u.lastActiveAt,
          sessionsCount: uSessions.length,
        });
      }
    }

    const isInstalled = devicesMap.size > 0 || installedUsers.length > 0;
    if (isInstalled) totalInstalledBranches++;

    const branchDevices = Array.from(devicesMap.values());
    const branchOnlineDevs = branchDevices.filter((d) => d.isOnline).length;
    totalDevices += branchDevices.length;
    totalOnlineDevices += branchOnlineDevs;

    branchItems.push({
      branchId: b._id,
      branchName: b.name,
      branchCode: b.code,
      isInstalled,
      totalRegisteredUsers: branchUsers.length,
      installedUsersCount: installedUsers.length,
      onlineUsersCount,
      devicesCount: branchDevices.length,
      onlineDevicesCount: branchOnlineDevs,
      appVersions: Array.from(branchVersions),
      lastActivityAt: branchLastSeen,
      devices: branchDevices,
      installedUsers,
    });
  }

  // Sort branches: installed first, then alphabetically
  branchItems.sort((a, b) => {
    if (a.isInstalled !== b.isInstalled) return a.isInstalled ? -1 : 1;
    return a.branchCode.localeCompare(b.branchCode);
  });

  const totalBranchesCount = branches.length;
  const adoptionPercentage = totalBranchesCount > 0 ? Math.round((totalInstalledBranches / totalBranchesCount) * 100) : 0;

  return {
    summary: {
      totalBranches: totalBranchesCount,
      installedBranchesCount: totalInstalledBranches,
      notInstalledBranchesCount: Math.max(0, totalBranchesCount - totalInstalledBranches),
      adoptionPercentage,
      totalInstalledDevices: totalDevices,
      totalOnlineDevices,
      currentAppVersion: CURRENT_APP_VERSION,
      versionBreakdown: versionCounts,
      platformBreakdown: platformCounts,
      calculatedAt: new Date().toISOString(),
    },
    branches: branchItems,
  };
}

async function buildDeploymentExcelReport(data, actor) {
  const workbook = new ExcelJS.Workbook();
  workbook.creator = "iSmart Messenger Operations";
  workbook.created = new Date();

  const summary = data.summary;
  const branches = data.branches;

  const PC = {
    darkBlue: "FF1E3A8A",
    midBlue: "FF2563EB",
    lightBlue: "FFE0E7FF",
    rowAlt: "FFF8FAFC",
    white: "FFFFFFFF",
    borderCol: "FFCBD5E1",
    greenDark: "FF15803D",
    greenBg: "FFF0FDF4",
    redDark: "FFB91C1C",
    redBg: "FFFEF2F2",
  };

  function pcBorder(cell) {
    cell.border = {
      top: { style: "thin", color: { argb: PC.borderCol } },
      bottom: { style: "thin", color: { argb: PC.borderCol } },
      left: { style: "thin", color: { argb: PC.borderCol } },
      right: { style: "thin", color: { argb: PC.borderCol } },
    };
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SHEET 1: ملخص انتشار البرنامج بالفروع
  // ════════════════════════════════════════════════════════════════════════════
  const sheet1 = workbook.addWorksheet("ملخص انتشار المنظومة");
  sheet1.views = [{ rightToLeft: true, showGridLines: true }];
  sheet1.columns = [{ width: 34 }, { width: 44 }];

  sheet1.mergeCells("A1:B1");
  const t1 = sheet1.getCell("A1");
  t1.value = "📊  تقرير انتشار وتثبيت برنامج iSmart Messenger بالفروع";
  t1.font = { name: "Arial", size: 14, bold: true, color: { argb: PC.white } };
  t1.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.darkBlue } };
  t1.alignment = { horizontal: "center", vertical: "middle" };
  sheet1.getRow(1).height = 42;

  sheet1.mergeCells("A2:B2");
  const s1 = sheet1.getCell("A2");
  s1.value = `تاريخ الاستخراج: ${formatDate(new Date())}  |  المسؤول المستخرج: ${actor?.fullName || actor?.username || "Admin"}`;
  s1.font = { name: "Arial", size: 9.5, italic: true, color: { argb: PC.white } };
  s1.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.midBlue } };
  s1.alignment = { horizontal: "center", vertical: "middle" };
  sheet1.getRow(2).height = 24;

  const kpiData = [
    ["إجمالي فروع المنظومة", `${summary.totalBranches} فرع`],
    ["الفروع التي قامت بتثبيت البرنامج", `${summary.installedBranchesCount} فرع`],
    ["الفروع التي لم تُثبت البرنامج بعد", `${summary.notInstalledBranchesCount} فرع`],
    ["نسبة انتشار واعتماد البرنامج بالفروع", `${summary.adoptionPercentage}%`],
    ["إجمالي الأجهزة المثبتة على الشبكة", `${summary.totalInstalledDevices} جهاز`],
    ["الأجهزة المتصلة الآن", `${summary.totalOnlineDevices} جهاز`],
    ["أحدث إصدار رسمي معتمد", summary.currentAppVersion],
  ];

  kpiData.forEach(([label, val], idx) => {
    const row = sheet1.getRow(4 + idx);
    row.height = 24;
    row.values = [label, val];
    row.getCell(1).font = { name: "Arial", size: 10, bold: true, color: { argb: "FF334155" } };
    row.getCell(1).fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF1F5F9" } };
    row.getCell(1).alignment = { horizontal: "right", vertical: "middle" };
    pcBorder(row.getCell(1));

    row.getCell(2).font = { name: "Arial", size: 10.5, bold: true, color: { argb: PC.darkBlue } };
    row.getCell(2).fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.white } };
    row.getCell(2).alignment = { horizontal: "center", vertical: "middle" };
    pcBorder(row.getCell(2));
  });

  // ════════════════════════════════════════════════════════════════════════════
  // SHEET 2: كشف الفروع وتفاصيل التثبيت
  // ════════════════════════════════════════════════════════════════════════════
  const sheet2 = workbook.addWorksheet("موقف انتشار الفروع");
  sheet2.views = [{ rightToLeft: true, showGridLines: true, state: "frozen", ySplit: 2 }];

  const cols2 = [
    { header: "م", key: "idx", width: 6 },
    { header: "كود الفرع", key: "code", width: 14 },
    { header: "اسم الفرع", key: "name", width: 28 },
    { header: "حالة التثبيت", key: "status", width: 18 },
    { header: "عدد الأجهزة المثبتة", key: "devices", width: 20 },
    { header: "الأجهزة المتصلة الآن", key: "onlineDevices", width: 20 },
    { header: "إجمالي المستخدمين", key: "totalUsers", width: 18 },
    { header: "المستخدمين النشطين", key: "installedUsers", width: 18 },
    { header: "إصدارات البرنامج", key: "versions", width: 22 },
    { header: "آخر نشاط مسجل", key: "lastSeen", width: 22 },
  ];
  sheet2.columns = cols2;

  sheet2.getRow(1).height = 32;
  sheet2.getRow(1).eachCell((cell) => {
    cell.font = { name: "Arial", size: 10.5, bold: true, color: { argb: PC.white } };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.darkBlue } };
    cell.alignment = { horizontal: "center", vertical: "middle", wrapText: true };
    pcBorder(cell);
  });

  branches.forEach((b, idx) => {
    const row = sheet2.getRow(2 + idx);
    row.height = 22;
    const isInst = b.isInstalled;
    const vers = b.appVersions && b.appVersions.length > 0 ? b.appVersions.join(", ") : "-";

    row.values = [
      idx + 1,
      b.branchCode,
      b.branchName,
      isInst ? "تم التثبيت ✅" : "لم يُثبت بعد ❌",
      b.devicesCount,
      b.onlineDevicesCount,
      b.totalRegisteredUsers,
      b.installedUsersCount,
      vers,
      formatDate(b.lastActivityAt),
    ];

    const isEven = idx % 2 === 0;
    row.eachCell((cell, ci) => {
      cell.font = { name: "Arial", size: 9.5, color: { argb: "FF0F172A" } };
      cell.alignment = { horizontal: [1, 2, 4, 5, 6, 7, 8, 9, 10].includes(ci) ? "center" : "right", vertical: "middle" };
      cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: isEven ? PC.rowAlt : PC.white } };
      pcBorder(cell);

      // Status pill coloring
      if (ci === 4) {
        cell.font = { name: "Arial", size: 9.5, bold: true, color: { argb: isInst ? PC.greenDark : PC.redDark } };
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: isInst ? PC.greenBg : PC.redBg } };
      }
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // SHEET 3: تفاصيل الأجهزة المسجلة
  // ════════════════════════════════════════════════════════════════════════════
  const sheet3 = workbook.addWorksheet("كشف الأجهزة والمستخدمين");
  sheet3.views = [{ rightToLeft: true, showGridLines: true, state: "frozen", ySplit: 2 }];

  const cols3 = [
    { header: "م", width: 6 },
    { header: "الفرع", width: 24 },
    { header: "اسم الجهاز (Hostname)", width: 24 },
    { header: "نظام التشغيل", width: 20 },
    { header: "عنوان IP", width: 18 },
    { header: "اسم المستخدم", width: 20 },
    { header: "الاسم الكامل", width: 26 },
    { header: "إصدار البرنامج", width: 16 },
    { header: "الحالة الآن", width: 14 },
    { header: "آخر ظهور", width: 22 },
  ];
  sheet3.columns = cols3;

  sheet3.getRow(1).height = 32;
  sheet3.getRow(1).eachCell((cell) => {
    cell.font = { name: "Arial", size: 10.5, bold: true, color: { argb: PC.white } };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.midBlue } };
    cell.alignment = { horizontal: "center", vertical: "middle", wrapText: true };
    pcBorder(cell);
  });

  let devIdx = 1;
  branches.forEach((b) => {
    (b.devices || []).forEach((d) => {
      const row = sheet3.getRow(1 + devIdx);
      row.height = 22;
      row.values = [
        devIdx++,
        `${b.branchName} (${b.branchCode})`,
        d.hostname || "-",
        `${d.os || "Windows"} ${d.osVersion || ""}`.trim(),
        d.ipAddress || "-",
        d.user?.username || "-",
        d.user?.fullName || "-",
        d.appVersion || CURRENT_APP_VERSION,
        d.isOnline ? "متصل" : "غير متصل",
        formatDate(d.lastSeenAt),
      ];

      const isEven = devIdx % 2 === 0;
      row.eachCell((cell, ci) => {
        cell.font = { name: "Arial", size: 9.5, color: { argb: "FF0F172A" } };
        cell.alignment = { horizontal: [1, 5, 8, 9, 10].includes(ci) ? "center" : "right", vertical: "middle" };
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: isEven ? PC.rowAlt : PC.white } };
        pcBorder(cell);

        if (ci === 9) {
          cell.font = { name: "Arial", size: 9.5, bold: true, color: { argb: d.isOnline ? PC.greenDark : "FF64748B" } };
        }
      });
    });
  });

  const buffer = await workbook.xlsx.writeBuffer();
  const fileName = `ismart-branches-deployment-report-${Date.now()}.xlsx`;
  return { buffer: Buffer.from(buffer), fileName };
}

async function buildDeploymentPdfReport(data, actor) {
  const doc = new PDFDocument({ margin: 30, size: "A4", layout: "landscape" });
  configureArabicPdf(doc);
  const chunks = [];
  doc.on("data", (c) => chunks.push(c));
  const done = new Promise((resolve) => doc.on("end", resolve));

  const usableWidth = doc.page.width - 60; // 841.89 - 60 = 781.89 pt
  const summary = data.summary;
  const branches = data.branches;
  const reportDate = formatDate(new Date());

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
    doc.text(processArabicText("تقرير انتشار وتثبيت منظومة iSmart Messenger بالفروع والأجهزة"), 30, 48, { width: usableWidth, align: "center" });
    withArabicFont(doc, false).fontSize(8.5).fillColor("#DBEAFE");
    const sub = `تاريخ التقرير: ${reportDate}   |   المسؤول المستخرج: ${actor?.fullName || actor?.username || "Admin"}   |   الإصدار المعتمد: ${summary.currentAppVersion}`;
    doc.text(processArabicText(sub), 30, 64, { width: usableWidth, align: "center" });
  }

  drawPageHeader();

  // Summary KPI Cards (y: 86)
  const kpiY = 86;
  const kpis = [
    { label: "إجمالي الفروع", val: `${summary.totalBranches} فرع`, col: "#1E3A8A" },
    { label: "الفروع المثبتة", val: `${summary.installedBranchesCount} فرع`, col: "#15803D" },
    { label: "نسبة الانتشار", val: `${summary.adoptionPercentage}%`, col: "#0284C7" },
    { label: "الأجهزة المثبتة", val: `${summary.totalInstalledDevices} جهاز`, col: "#475569" },
    { label: "الأجهزة المتصلة الآن", val: `${summary.totalOnlineDevices} متصل`, col: "#15803D" },
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

  // Branches Table (y: 130)
  const columns = [
    { label: "م", w: 30 },
    { label: "كود الفرع", w: 75 },
    { label: "اسم الفرع", w: 150 },
    { label: "حالة التثبيت", w: 90 },
    { label: "الأجهزة المثبتة", w: 85 },
    { label: "الأجهزة المتصلة", w: 85 },
    { label: "المستخدمين", w: 75 },
    { label: "إصدار البرنامج", w: 90 },
    { label: "آخر نشاط", w: 101 },
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

  for (let idx = 0; idx < branches.length; idx++) {
    if (currentY + rowH > doc.page.height - 40) {
      doc.addPage({ margin: 30, size: "A4", layout: "landscape" });
      drawPageHeader();
      currentY = 90;
      drawTableHeader(currentY);
      currentY += headerH;
    }

    const b = branches[idx];
    const isEven = idx % 2 === 0;
    const rowBg = isEven ? "#F8FAFC" : "#FFFFFF";
    const isInst = b.isInstalled;
    const vers = b.appVersions && b.appVersions.length > 0 ? b.appVersions.join(", ") : "-";

    const rowData = [
      String(idx + 1),
      b.branchCode,
      b.branchName,
      isInst ? "تم التثبيت ✅" : "لم يُثبت بعد ❌",
      String(b.devicesCount),
      String(b.onlineDevicesCount),
      String(b.installedUsersCount),
      vers,
      formatDate(b.lastActivityAt),
    ];

    let rX = 30;
    for (let c = 0; c < columns.length; c++) {
      const col = columns[c];
      doc.rect(rX, currentY, col.w, rowH).fill(rowBg).strokeColor("#E2E8F0").stroke();

      if (c === 3) {
        withArabicFont(doc, true).fontSize(8).fillColor(isInst ? "#15803D" : "#B91C1C");
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
  const footerText = `منظومة iSmart Messenger للتحكم والمراقبة   |   المسؤول المستخرج: ${actor?.fullName || actor?.username || "Admin"}   |   تاريخ وتوقيت التقرير: ${reportDate}`;
  doc.text(processArabicText(footerText), 30, footerY, { width: usableWidth, align: "center" });

  doc.end();
  await done;

  const fileName = `ismart-branches-deployment-report-${Date.now()}.pdf`;
  return { buffer: Buffer.concat(chunks), fileName };
}

module.exports = {
  getBranchesDeploymentData,
  buildDeploymentExcelReport,
  buildDeploymentPdfReport,
};
