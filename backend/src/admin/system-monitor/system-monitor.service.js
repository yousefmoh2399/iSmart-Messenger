const fs = require("fs");
const path = require("path");
const ExcelJS = require("exceljs");
const PDFDocument = require("pdfkit");

const Branch = require("../../chat/models/branch.model");
const User = require("../../models/user.model");
const DeviceSession = require("../../models/device-session.model");
const UpdateDevice = require("../updates/device.model");
const Message = require("../../chat/models/message.model");
const Conversation = require("../../chat/models/conversation.model");
const { exportPollToExcel } = require("../../chat/services/chat.service");

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

// Purge any legacy mock seeded sessions once at startup / execution
let hasPurgedLegacyMocks = false;
async function purgeLegacyMockSessions() {
  if (hasPurgedLegacyMocks) return;
  try {
    await DeviceSession.deleteMany({
      $or: [
        { "deviceInfo.hostname": /^(PC|LAPTOP|POS)-(ACC|MGR|CS|LAW|\d+)/i },
        { "deviceInfo.hostname": /^(PC|LAPTOP|POS)/i },
        { socketId: /^sock_live_/i },
      ],
    });
    hasPurgedLegacyMocks = true;
  } catch (_) {}
}

async function getBranchesDeploymentData() {
  await purgeLegacyMockSessions();

  const [branches, users, updateDevices, rawSessions] = await Promise.all([
    Branch.find({ deletedAt: null }).sort({ code: 1, name: 1 }).lean(),
    User.find({ isActive: true })
      .select("_id username fullName role jobTitle branchId branchCode lastActiveAt isOnline")
      .lean(),
    UpdateDevice.find({}).sort({ lastSeenAt: -1, updatedAt: -1 }).lean(),
    DeviceSession.find({
      "deviceInfo.hostname": { $not: /^(PC|LAPTOP|POS)-/i },
    })
      .populate("userId", "_id username fullName role branchId branchCode isOnline jobTitle")
      .sort({ lastSeenAt: -1 })
      .lean(),
  ]);

  // Group users by branchId and branchCode
  const usersByBranchId = new Map();
  const usersByBranchCode = new Map();
  const allUsersMap = new Map();
  const allUsersByUsername = new Map();

  for (const u of users) {
    allUsersMap.set(String(u._id), u);
    if (u.username) {
      allUsersByUsername.set(u.username.toLowerCase(), u);
    }
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

  // Group UpdateDevices by branchCode and by userId
  const devicesByBranchCode = new Map();
  const devicesByUserId = new Map();

  for (const dev of updateDevices) {
    let bCode = dev.branchCode ? String(dev.branchCode).toUpperCase() : null;
    if (!bCode && dev.lastKnownUserId && allUsersMap.has(String(dev.lastKnownUserId))) {
      const u = allUsersMap.get(String(dev.lastKnownUserId));
      bCode = (u.branchCode || "").toUpperCase();
    }
    if (bCode) {
      if (!devicesByBranchCode.has(bCode)) devicesByBranchCode.set(bCode, []);
      devicesByBranchCode.get(bCode).push(dev);
    }
    if (dev.lastKnownUserId) {
      const uId = String(dev.lastKnownUserId);
      if (!devicesByUserId.has(uId)) devicesByUserId.set(uId, []);
      devicesByUserId.get(uId).push(dev);
    }
  }

  // Group non-mock sessions by user
  const sessionsByUser = new Map();
  for (const s of rawSessions) {
    const uId = s.userId?._id ? String(s.userId._id) : (s.userId ? String(s.userId) : null);
    if (!uId) continue;
    if (!sessionsByUser.has(uId)) sessionsByUser.set(uId, []);
    sessionsByUser.get(uId).push(s);
  }

  const branchItems = [];
  let totalInstalledBranches = 0;
  let totalDevices = 0;
  let totalOnlineDevices = 0;
  let totalOutdatedDevices = 0;
  let totalLatestDevices = 0;
  let totalCriticalOutdated = 0;
  let outdatedBranchesCount = 0;

  const versionCounts = {};
  const platformCounts = {};

  for (const b of branches) {
    const bId = String(b._id);
    const bCode = (b.code || "").toUpperCase();
    const branchUsers = usersByBranchId.get(bId) || usersByBranchCode.get(bCode) || [];

    const devicesMap = new Map();
    const branchVersions = new Set();
    let branchLastSeen = null;
    let onlineUsersCount = 0;

    for (const u of branchUsers) {
      if (u.isOnline) onlineUsersCount++;
      if (u.lastActiveAt) {
        if (!branchLastSeen || new Date(u.lastActiveAt) > new Date(branchLastSeen)) {
          branchLastSeen = u.lastActiveAt;
        }
      }
    }

    // 1. Process physical devices registered in UpdateDevice for this branch
    const bUpdateDevices = devicesByBranchCode.get(bCode) || [];
    for (const dev of bUpdateDevices) {
      const devKey = dev.deviceUid
        ? String(dev.deviceUid).trim().toLowerCase()
        : ((dev.hostName || dev.deviceName)
            ? String(dev.hostName || dev.deviceName).trim().toLowerCase()
            : String(dev._id));
      const appVersion = String(dev.appVersion || "unknown").trim();
      branchVersions.add(appVersion);

      const devLastSeen = dev.lastSeenAt || dev.lastHeartbeatAt || dev.updatedAt;
      if (!branchLastSeen || (devLastSeen && new Date(devLastSeen) > new Date(branchLastSeen))) {
        branchLastSeen = devLastSeen;
      }

      const isOutdated = appVersion !== CURRENT_APP_VERSION;
      const isCritical = isOutdated && (appVersion === "1.0.9" || appVersion < "1.1.20" || appVersion.startsWith("1.0.") || appVersion.startsWith("1.1."));
      const versionStatus = !isOutdated ? "latest" : (isCritical ? "critical" : "previous");
      const versionStatusLabel = !isOutdated
        ? `محدث (v${CURRENT_APP_VERSION})`
        : (isCritical ? `نسخة قديمة حرجة (v${appVersion}) 🚨` : `نسخة سابقة (v${appVersion}) ⚠️`);

      const hostName = (dev.hostName || dev.deviceName || (dev.platform?.includes("mobile") ? "Mobile Device" : "Desktop-PC")).trim();
      const uNameLower = (dev.lastKnownUsername || "").toLowerCase();
      const workstationType = dev.platform?.includes("mobile")
        ? "جهاز ذكي (موبايل)"
        : (uNameLower.startsWith("cash")
          ? "نقطة بيع كاشير"
          : (uNameLower.startsWith("man") ? "حاسب إدارة فرع" : (uNameLower.startsWith("acc") ? "حاسب الحسابات" : (uNameLower.startsWith("cs") ? "خدمة العملاء" : "محطة عمل"))));

      // Live online status verification
      const isOnline = dev.connectionStatus === "online" ||
        (devLastSeen && (Date.now() - new Date(devLastSeen).getTime()) < 5 * 60 * 1000);

      // Resolve user details
      let userObj = {
        id: dev.lastKnownUserId,
        username: dev.lastKnownUsername || "-",
        fullName: dev.lastKnownFullName || "-",
        role: "-",
        jobTitle: "-",
      };
      if (dev.lastKnownUserId && allUsersMap.has(String(dev.lastKnownUserId))) {
        const u = allUsersMap.get(String(dev.lastKnownUserId));
        userObj = {
          id: u._id,
          username: u.username,
          fullName: u.fullName,
          role: u.role,
          jobTitle: u.jobTitle || "-",
        };
      } else if (uNameLower && allUsersByUsername.has(uNameLower)) {
        const u = allUsersByUsername.get(uNameLower);
        userObj = {
          id: u._id,
          username: u.username,
          fullName: u.fullName,
          role: u.role,
          jobTitle: u.jobTitle || "-",
        };
      }

      // Keep latest session if duplicates for the same host
      if (!devicesMap.has(devKey) || (devLastSeen && new Date(devLastSeen) > new Date(devicesMap.get(devKey).lastSeenAt))) {
        devicesMap.set(devKey, {
          hostname: hostName,
          os: dev.osName || (dev.platform?.includes("mobile") ? "Android/iOS" : "Windows"),
          osVersion: dev.osVersion || "",
          ipAddress: dev.localIp || "-",
          clientType: dev.platform?.includes("mobile") ? "mobile" : "desktop",
          appVersion,
          isOutdated,
          versionStatus,
          versionStatusLabel,
          workstationType,
          isOnline: !!isOnline,
          startedAt: dev.createdAt || new Date(),
          lastSeenAt: devLastSeen,
          user: userObj,
        });
      }
    }

    // 2. Also process any real active socket sessions for branch users not in UpdateDevice
    for (const u of branchUsers) {
      const uId = String(u._id);
      const uSessions = sessionsByUser.get(uId) || [];
      for (const s of uSessions) {
        const rawHost = (s.deviceInfo?.hostname || "").trim();
        const clientType = s.clientType || (s.deviceInfo?.platform?.includes("mobile") ? "mobile" : "desktop");
        const hostName = rawHost || (clientType === "mobile" ? `Mobile-${u.username}` : `PC-${u.username}`);
        const devKey = s.deviceInfo?.deviceUid
          ? String(s.deviceInfo.deviceUid).trim().toLowerCase()
          : (rawHost ? `${rawHost.toLowerCase()}_${uId}` : `session_${s._id}`);
        if (devicesMap.has(devKey)) continue; // Already covered by UpdateDevice

        let appVersion = String(s.deviceInfo?.appVersion || "").trim();
        if (!appVersion || appVersion === "unknown") {
          const userDevs = devicesByUserId.get(uId) || [];
          if (userDevs.length > 0 && userDevs[0].appVersion) {
            appVersion = String(userDevs[0].appVersion).trim();
          }
        }
        if (!appVersion) {
          appVersion = "غير محدد";
        }

        if (appVersion !== "غير محدد") {
          branchVersions.add(appVersion);
        }

        if (!branchLastSeen || (s.lastSeenAt && new Date(s.lastSeenAt) > new Date(branchLastSeen))) {
          branchLastSeen = s.lastSeenAt;
        }

        const isKnownVersion = appVersion !== "غير محدد";
        const isOutdated = isKnownVersion && appVersion !== CURRENT_APP_VERSION;
        const isCritical = isOutdated && (appVersion === "1.0.9" || appVersion < "1.1.20" || appVersion.startsWith("1.0.") || appVersion.startsWith("1.1."));
        const versionStatus = !isKnownVersion ? "pending" : (!isOutdated ? "latest" : (isCritical ? "critical" : "previous"));
        const versionStatusLabel = !isKnownVersion
          ? "إصدار غير محدد"
          : (!isOutdated
            ? `محدث (v${CURRENT_APP_VERSION})`
            : (isCritical ? `نسخة قديمة حرجة (v${appVersion}) 🚨` : `نسخة سابقة (v${appVersion}) ⚠️`));

        const uNameLower = (u.username || "").toLowerCase();
        const workstationType = clientType === "mobile"
          ? "جهاز ذكي (موبايل)"
          : (uNameLower.startsWith("cash")
            ? "نقطة بيع كاشير"
            : (uNameLower.startsWith("man") ? "حاسب إدارة فرع" : (uNameLower.startsWith("acc") ? "حاسب الحسابات" : "محطة عمل")));

        devicesMap.set(devKey, {
          hostname: hostName,
          os: s.deviceInfo?.os || (clientType === "mobile" ? "Android/iOS" : "Windows"),
          osVersion: s.deviceInfo?.osVersion || "",
          ipAddress: s.ipAddress || "-",
          clientType,
          appVersion,
          isOutdated,
          versionStatus,
          versionStatusLabel,
          workstationType,
          isOnline: !!s.isOnline,
          startedAt: s.startedAt || s.createdAt || new Date(),
          lastSeenAt: s.lastSeenAt,
          user: {
            id: u._id,
            username: u.username,
            fullName: u.fullName,
            role: u.role,
            jobTitle: u.jobTitle || "-",
          },
        });
      }
    }

    const branchDevices = Array.from(devicesMap.values());
    const isInstalled = branchDevices.length > 0;
    if (isInstalled) totalInstalledBranches++;

    const branchOnlineDevs = branchDevices.filter((d) => d.isOnline).length;
    const branchOutdatedDevs = branchDevices.filter((d) => d.isOutdated).length;
    const branchLatestDevs = branchDevices.filter((d) => !d.isOutdated).length;

    totalDevices += branchDevices.length;
    totalOnlineDevices += branchOnlineDevs;
    totalOutdatedDevices += branchOutdatedDevs;
    totalLatestDevices += branchLatestDevs;

    branchDevices.forEach((d) => {
      if (d.versionStatus === "critical") totalCriticalOutdated++;
      versionCounts[d.appVersion] = (versionCounts[d.appVersion] || 0) + 1;
      platformCounts[d.os] = (platformCounts[d.os] || 0) + 1;
    });

    const hasOutdatedDevices = branchOutdatedDevs > 0;
    if (hasOutdatedDevices) outdatedBranchesCount++;

    const sortedVersions = Array.from(branchVersions).sort();

    branchItems.push({
      branchId: b._id,
      branchName: b.name,
      branchCode: b.code,
      isInstalled,
      hasOutdatedDevices,
      outdatedDevicesCount: branchOutdatedDevs,
      latestDevicesCount: branchLatestDevs,
      totalRegisteredUsers: branchUsers.length,
      installedUsersCount: branchDevices.length,
      onlineUsersCount,
      devicesCount: branchDevices.length,
      totalDevices: branchDevices.length,
      latestVersionDevicesCount: branchLatestDevs,
      onlineDevicesCount: branchOnlineDevs,
      appVersions: sortedVersions,
      versionStatusLabel: !isInstalled
        ? "لم يتم التثبيت بعد"
        : (!hasOutdatedDevices
            ? "محدثة بالكامل ✅"
            : `يوجد إصدارات قديمة ⚠️ (${branchOutdatedDevs} جهاز)`),
      lastActivityAt: branchLastSeen,
      devices: branchDevices,
      installedUsers: branchUsers.map((u) => ({
        userId: u._id,
        username: u.username,
        fullName: u.fullName,
        role: u.role,
        jobTitle: u.jobTitle || "-",
        isOnline: !!u.isOnline,
        lastActiveAt: u.lastActiveAt,
        sessionsCount: 1,
      })),
    });
  }

  // Sort: installed branches first, then by branchCode
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
      latestVersionDevicesCount: totalLatestDevices,
      outdatedDevicesCount: totalOutdatedDevices,
      criticalOutdatedDevicesCount: totalCriticalOutdated,
      outdatedBranchesCount,
      currentAppVersion: CURRENT_APP_VERSION,
      versionBreakdown: versionCounts,
      platformBreakdown: platformCounts,
      calculatedAt: new Date().toISOString(),
    },
    branches: branchItems,
  };
}

async function buildDeploymentExcelReport(data, actor) {
  if (!data) {
    data = await getBranchesDeploymentData();
  }
  const workbook = new ExcelJS.Workbook();
  workbook.creator = "iSmart Messenger Enterprise Monitor";
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
    greenBg: "FFDCFCE7",
    amberDark: "FFB45309",
    amberBg: "FFFEF3C7",
    redDark: "FFB91C1C",
    redBg: "FFFEE2E2",
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
  // SHEET 1: ملخص انتشار المنظومة وموقف الإصدارات
  // ════════════════════════════════════════════════════════════════════════════
  const sheet1 = workbook.addWorksheet("ملخص انتشار المنظومة");
  sheet1.views = [{ rightToLeft: true, showGridLines: true }];
  sheet1.columns = [{ width: 36 }, { width: 44 }];

  sheet1.mergeCells("A1:B1");
  const t1 = sheet1.getCell("A1");
  t1.value = "📊  تقرير انتشار وتثبيت منظومة iSmart Messenger وموقف الإصدارات بالفروع";
  t1.font = { name: "Arial", size: 13.5, bold: true, color: { argb: PC.white } };
  t1.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.darkBlue } };
  t1.alignment = { horizontal: "center", vertical: "middle" };
  sheet1.getRow(1).height = 42;

  sheet1.mergeCells("A2:B2");
  const s1 = sheet1.getCell("A2");
  s1.value = `تاريخ الاستخراج: ${formatDate(new Date())}  |  المسؤول المستخرج: ${actor?.fullName || actor?.username || "Admin"}  |  الإصدار المعتمد: ${summary.currentAppVersion}`;
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
    ["أحدث إصدار رسمي معتمد", `v${summary.currentAppVersion}`],
    ["الأجهزة المحدثة لأحدث إصدار (v" + summary.currentAppVersion + ")", `${summary.latestVersionDevicesCount || 0} جهاز (${summary.totalInstalledDevices > 0 ? Math.round((summary.latestVersionDevicesCount / summary.totalInstalledDevices) * 100) : 0}%)`],
    ["الأجهزة التي تستخدم إصدارات قديمة ⚠️", `${summary.outdatedDevicesCount || 0} جهاز`],
    ["الأجهزة بنسخ قديمة حرجة (< v1.1.20) 🚨", `${summary.criticalOutdatedDevicesCount || 0} جهاز (تتطلب تحديثاً فورياً)`],
    ["الفروع التي بها أجهزة بنسخ قديمة", `${summary.outdatedBranchesCount || 0} فرع`],
  ];

  kpiData.forEach(([label, val], idx) => {
    const row = sheet1.getRow(4 + idx);
    row.height = 24;
    row.values = [label, val];
    row.getCell(1).font = { name: "Arial", size: 10, bold: true, color: { argb: "FF334155" } };
    row.getCell(1).fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF1F5F9" } };
    row.getCell(1).alignment = { horizontal: "right", vertical: "middle" };
    pcBorder(row.getCell(1));

    const isWarning = label.includes("قديمة");
    row.getCell(2).font = { name: "Arial", size: 10.5, bold: true, color: { argb: isWarning ? PC.redDark : PC.darkBlue } };
    row.getCell(2).fill = { type: "pattern", pattern: "solid", fgColor: { argb: isWarning ? PC.redBg : PC.white } };
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
    { header: "إصدارات البرنامج", key: "versions", width: 22 },
    { header: "موقف التحديث بالفروع", key: "versionStatus", width: 26 },
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
    const hasOld = b.hasOutdatedDevices;

    row.values = [
      idx + 1,
      b.branchCode,
      b.branchName,
      isInst ? "تم التثبيت ✅" : "لم يُثبت بعد ❌",
      b.devicesCount,
      b.onlineDevicesCount,
      b.installedUsersCount,
      vers,
      b.versionStatusLabel || (hasOld ? "يوجد أجهزة قديمة ⚠️" : "محدثة بالكامل ✅"),
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

      // Version status column (ci: 9)
      if (ci === 9) {
        cell.font = { name: "Arial", size: 9.5, bold: true, color: { argb: hasOld ? PC.amberDark : PC.greenDark } };
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: hasOld ? PC.amberBg : PC.greenBg } };
      }
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // SHEET 3: تفاصيل جميع الأجهزة ومحطات العمل (بدون تكرار)
  // ════════════════════════════════════════════════════════════════════════════
  const sheet3 = workbook.addWorksheet("كشف الأجهزة ومحطات العمل");
  sheet3.views = [{ rightToLeft: true, showGridLines: true, state: "frozen", ySplit: 2 }];

  const cols3 = [
    { header: "م", width: 6 },
    { header: "كود الفرع", width: 14 },
    { header: "اسم الفرع", width: 22 },
    { header: "اسم الجهاز (Hostname)", width: 22 },
    { header: "نظام التشغيل والمعمارية", width: 24 },
    { header: "عنوان IP الداخلي", width: 18 },
    { header: "نوع المحطة", width: 18 },
    { header: "اسم الموظف المسجل", width: 24 },
    { header: "اسم المستخدم", width: 18 },
    { header: "إصدار البرنامج", width: 16 },
    { header: "حالة التحديث", width: 24 },
    { header: "الحالة الآن", width: 14 },
    { header: "آخر ظهور ونشاط", width: 22 },
  ];
  sheet3.columns = cols3;

  sheet3.getRow(1).height = 32;
  sheet3.getRow(1).eachCell((cell) => {
    cell.font = { name: "Arial", size: 10.5, bold: true, color: { argb: PC.white } };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.midBlue } };
    cell.alignment = { horizontal: "center", vertical: "middle", wrapText: true };
    pcBorder(cell);
  });

  // Deduplicate workstations completely
  const seenWorkstationKeys = new Set();
  const uniqueDeviceRows = [];

  branches.forEach((b) => {
    (b.devices || []).forEach((d) => {
      const uKey = `${b.branchCode}_${d.user?.username || d.username}_${d.hostname}`.toLowerCase();
      if (!seenWorkstationKeys.has(uKey)) {
        seenWorkstationKeys.add(uKey);
        uniqueDeviceRows.push({
          branch: b,
          device: d,
        });
      }
    });
  });

  uniqueDeviceRows.forEach((item, devIdx) => {
    const b = item.branch;
    const d = item.device;
    const row = sheet3.getRow(2 + devIdx);
    row.height = 22;

    const isLatest = d.appVersion === CURRENT_APP_VERSION;
    const isCritical = d.appVersion === "1.0.9" || d.appVersion < "1.1.20";

    row.values = [
      devIdx + 1,
      b.branchCode,
      b.branchName,
      d.hostname || "-",
      `${d.os || "Windows"} ${d.osVersion || ""}`.trim(),
      d.ipAddress || "-",
      d.workstationType || "محطة عمل",
      d.user?.fullName || d.fullName || "-",
      d.user?.username || d.username || "-",
      `v${d.appVersion || CURRENT_APP_VERSION}`,
      d.versionStatusLabel || (isLatest ? "محدث (v1.1.21) ✅" : "نسخة قديمة ⚠️"),
      d.isOnline ? "متصل 🟢" : "غير متصل ⚪",
      formatDate(d.lastSeenAt),
    ];

    const isEven = devIdx % 2 === 0;
    row.eachCell((cell, ci) => {
      cell.font = { name: "Arial", size: 9.5, color: { argb: "FF0F172A" } };
      cell.alignment = { horizontal: [1, 2, 6, 7, 9, 10, 11, 12, 13].includes(ci) ? "center" : "right", vertical: "middle" };
      cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: isEven ? PC.rowAlt : PC.white } };
      pcBorder(cell);

      // Version coloring in col 10
      if (ci === 10) {
        cell.font = { name: "Arial", size: 9.5, bold: true, color: { argb: isLatest ? PC.greenDark : (isCritical ? PC.redDark : PC.amberDark) } };
      }

      // Update status coloring in col 11
      if (ci === 11) {
        cell.font = { name: "Arial", size: 9.5, bold: true, color: { argb: isLatest ? PC.greenDark : (isCritical ? PC.redDark : PC.amberDark) } };
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: isLatest ? PC.greenBg : (isCritical ? PC.redBg : PC.amberBg) } };
      }

      // Online status coloring in col 12
      if (ci === 12) {
        cell.font = { name: "Arial", size: 9.5, bold: true, color: { argb: d.isOnline ? PC.greenDark : "FF64748B" } };
      }
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // SHEET 4: قائمة الأجهزة بنسخ قديمة (للمتابعة والتحديث العاجل)
  // ════════════════════════════════════════════════════════════════════════════
  const sheet4 = workbook.addWorksheet("الأجهزة بنسخ قديمة للمتابعة");
  sheet4.views = [{ rightToLeft: true, showGridLines: true, state: "frozen", ySplit: 2 }];

  const cols4 = [
    { header: "م", width: 6 },
    { header: "كود الفرع", width: 14 },
    { header: "اسم الفرع", width: 22 },
    { header: "اسم الجهاز (Hostname)", width: 22 },
    { header: "الموظف المسؤول", width: 24 },
    { header: "المسمى الوظيفي", width: 18 },
    { header: "اسم المستخدم", width: 18 },
    { header: "عنوان IP", width: 18 },
    { header: "الإصدار القديم الحالي", width: 20 },
    { header: "الإصدار المطلوب المعتمد", width: 22 },
    { header: "الحالة اللحظية", width: 14 },
    { header: "آخر ظهور ونشاط", width: 22 },
  ];
  sheet4.columns = cols4;

  sheet4.getRow(1).height = 32;
  sheet4.getRow(1).eachCell((cell) => {
    cell.font = { name: "Arial", size: 10.5, bold: true, color: { argb: PC.white } };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.redDark } };
    cell.alignment = { horizontal: "center", vertical: "middle", wrapText: true };
    pcBorder(cell);
  });

  const outdatedRows = uniqueDeviceRows.filter(r => r.device.isOutdated);

  outdatedRows.forEach((item, oIdx) => {
    const b = item.branch;
    const d = item.device;
    const row = sheet4.getRow(2 + oIdx);
    row.height = 22;

    const isCritical = d.appVersion === "1.0.9" || d.appVersion < "1.1.20";

    row.values = [
      oIdx + 1,
      b.branchCode,
      b.branchName,
      d.hostname || "-",
      d.user?.fullName || d.fullName || "-",
      d.user?.jobTitle || d.workstationType || "-",
      d.user?.username || d.username || "-",
      d.ipAddress || "-",
      `v${d.appVersion} (${isCritical ? "قديم حرج 🚨" : "سابق ⚠️"})`,
      `v${CURRENT_APP_VERSION} (أحدث إصدار)`,
      d.isOnline ? "متصل 🟢" : "غير متصل ⚪",
      formatDate(d.lastSeenAt),
    ];

    const isEven = oIdx % 2 === 0;
    row.eachCell((cell, ci) => {
      cell.font = { name: "Arial", size: 9.5, color: { argb: "FF0F172A" } };
      cell.alignment = { horizontal: [1, 2, 8, 9, 10, 11, 12].includes(ci) ? "center" : "right", vertical: "middle" };
      cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: isEven ? PC.rowAlt : PC.white } };
      pcBorder(cell);

      // Old version column (ci: 9)
      if (ci === 9) {
        cell.font = { name: "Arial", size: 9.5, bold: true, color: { argb: isCritical ? PC.redDark : PC.amberDark } };
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: isCritical ? PC.redBg : PC.amberBg } };
      }

      // Required version column (ci: 10)
      if (ci === 10) {
        cell.font = { name: "Arial", size: 9.5, bold: true, color: { argb: PC.greenDark } };
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PC.greenBg } };
      }
    });
  });

  const buffer = await workbook.xlsx.writeBuffer();
  const fileName = `ismart-branches-deployment-report-${Date.now()}.xlsx`;
  return { buffer: Buffer.from(buffer), fileName };
}

async function buildDeploymentPdfReport(data, actor) {
  if (!data) {
    data = await getBranchesDeploymentData();
  }
  const doc = new PDFDocument({ margin: 28, size: "A4", layout: "landscape" });
  configureArabicPdf(doc);
  const chunks = [];
  doc.on("data", (c) => chunks.push(c));
  const done = new Promise((resolve) => doc.on("end", resolve));

  const usableWidth = doc.page.width - 56; // 841.89 - 56 = 785.89 pt
  const summary = data.summary;
  const branches = data.branches;
  const reportDate = formatDate(new Date());

  function drawPageHeader(title = "تقرير انتشار وتثبيت منظومة iSmart Messenger وموقف الإصدارات") {
    try {
      if (fs.existsSync(logo1Path)) doc.image(logo1Path, 28, 18, { width: 48 });
      if (fs.existsSync(logo2Path)) doc.image(logo2Path, doc.page.width - 76, 18, { width: 48 });
    } catch (_) {}

    withArabicFont(doc, true).fontSize(10).fillColor("#1E3A8A");
    doc.text(processArabicText("مشروع تنمية المنشآت الصغيرة والحرفية - جمعية رجال الأعمال بالدقهلية"), 80, 20, { width: usableWidth - 104, align: "center" });

    // Banner
    doc.roundedRect(28, 38, usableWidth, 38, 4).fill("#1E3A8A");
    withArabicFont(doc, true).fontSize(12).fillColor("#FFFFFF");
    doc.text(processArabicText(title), 28, 44, { width: usableWidth, align: "center" });
    withArabicFont(doc, false).fontSize(8.5).fillColor("#DBEAFE");
    const sub = `تاريخ التقرير: ${reportDate}   |   المسؤول المستخرج: ${actor?.fullName || actor?.username || "Admin"}   |   الإصدار المعتمد: v${summary.currentAppVersion}`;
    doc.text(processArabicText(sub), 28, 60, { width: usableWidth, align: "center" });
  }

  // ---------------- PAGE 1: BRANCHES TABLE ----------------
  drawPageHeader();

  // Summary KPI Cards (y: 82)
  const kpiY = 82;
  const kpis = [
    { label: "إجمالي الفروع", val: `${summary.totalBranches} فرع`, col: "#1E3A8A" },
    { label: "الفروع المثبتة", val: `${summary.installedBranchesCount} فرع`, col: "#15803D" },
    { label: "نسبة الانتشار", val: `${summary.adoptionPercentage}%`, col: "#0284C7" },
    { label: "الأجهزة المثبتة", val: `${summary.totalInstalledDevices} جهاز`, col: "#475569" },
    { label: "المحدثة لأحدث إصدار", val: `${summary.latestVersionDevicesCount || 0} جهاز`, col: "#15803D" },
    { label: "بنسخ قديمة (مطلوب تحديثها)", val: `${summary.outdatedDevicesCount || 0} جهاز`, col: "#B91C1C" },
  ];

  const cardW = (usableWidth - (kpis.length - 1) * 6) / kpis.length;
  for (let i = 0; i < kpis.length; i++) {
    const k = kpis[i];
    const x = 28 + i * (cardW + 6);
    doc.roundedRect(x, kpiY, cardW, 36, 4).fill("#F8FAFC");
    doc.roundedRect(x, kpiY, cardW, 36, 4).strokeColor("#E2E8F0").lineWidth(0.8).stroke();
    withArabicFont(doc, false).fontSize(7.5).fillColor("#64748B");
    doc.text(processArabicText(k.label), x + 2, kpiY + 4, { width: cardW - 4, align: "center" });
    withArabicFont(doc, true).fontSize(9.5).fillColor(k.col);
    doc.text(processArabicText(k.val), x + 2, kpiY + 18, { width: cardW - 4, align: "center" });
  }

  // Branches Table (y: 126)
  const columns = [
    { label: "م", w: 26 },
    { label: "كود الفرع", w: 60 },
    { label: "اسم الفرع", w: 140 },
    { label: "حالة التثبيت", w: 80 },
    { label: "الأجهزة", w: 65 },
    { label: "المتصلة", w: 65 },
    { label: "المستخدمين", w: 65 },
    { label: "إصدارات البرنامج", w: 100 },
    { label: "موقف التحديث", w: 100 },
    { label: "آخر نشاط", w: 84 },
  ];

  let currentY = 126;
  const rowH = 17;
  const headerH = 20;

  function drawTableHeader(y) {
    let x = 28;
    for (const c of columns) {
      doc.rect(x, y, c.w, headerH).fill("#1E3A8A").strokeColor("#1E40AF").stroke();
      withArabicFont(doc, true).fontSize(8).fillColor("#FFFFFF");
      doc.text(processArabicText(c.label), x + 2, y + 5, { width: c.w - 4, align: "center" });
      x += c.w;
    }
  }

  drawTableHeader(currentY);
  currentY += headerH;

  for (let idx = 0; idx < branches.length; idx++) {
    if (currentY + rowH > doc.page.height - 35) {
      doc.addPage({ margin: 28, size: "A4", layout: "landscape" });
      drawPageHeader();
      currentY = 82;
      drawTableHeader(currentY);
      currentY += headerH;
    }

    const b = branches[idx];
    const isEven = idx % 2 === 0;
    const rowBg = isEven ? "#F8FAFC" : "#FFFFFF";
    const isInst = b.isInstalled;
    const vers = b.appVersions && b.appVersions.length > 0 ? b.appVersions.join(", ") : "-";
    const hasOld = b.hasOutdatedDevices;

    const rowData = [
      String(idx + 1),
      b.branchCode,
      b.branchName,
      isInst ? "تم التثبيت ✅" : "لم يُثبت ❌",
      String(b.devicesCount),
      String(b.onlineDevicesCount),
      String(b.installedUsersCount),
      vers,
      hasOld ? `قديم ⚠️ (${b.outdatedDevicesCount})` : "محدث بالكامل ✅",
      formatDate(b.lastActivityAt),
    ];

    let rX = 28;
    for (let c = 0; c < columns.length; c++) {
      const col = columns[c];
      doc.rect(rX, currentY, col.w, rowH).fill(rowBg).strokeColor("#E2E8F0").stroke();

      if (c === 3) {
        withArabicFont(doc, true).fontSize(7.5).fillColor(isInst ? "#15803D" : "#B91C1C");
      } else if (c === 8) {
        withArabicFont(doc, true).fontSize(7.5).fillColor(hasOld ? "#B45309" : "#15803D");
      } else {
        withArabicFont(doc, false).fontSize(7.5).fillColor("#0F172A");
      }

      doc.text(processArabicText(rowData[c]), rX + 2, currentY + 3.5, {
        width: col.w - 4,
        align: "center",
        ellipsis: true,
        lineBreak: false,
      });
      rX += col.w;
    }
    currentY += rowH;
  }

  // Footer on bottom
  const footerY = doc.page.height - 22;
  withArabicFont(doc, false).fontSize(7).fillColor("#64748B");
  doc.text(
    processArabicText(`منظومة iSmart Messenger للتحكم والمراقبة   |   المسؤول المستخرج: ${actor?.fullName || actor?.username || "Admin"}   |   تاريخ التقرير: ${reportDate}`),
    28,
    footerY,
    { width: usableWidth, align: "center" }
  );

  // ---------------- PAGE 2: OUTDATED WORKSTATIONS PUNCH-LIST ----------------
  // Collect all outdated devices strictly deduplicated
  const seenWorkstationKeysPdf = new Set();
  const allOutdatedDevicesPdf = [];

  branches.forEach((b) => {
    (b.devices || []).forEach((d) => {
      if (d.isOutdated) {
        const uKey = `${b.branchCode}_${d.user?.username || d.username}_${d.hostname}`.toLowerCase();
        if (!seenWorkstationKeysPdf.has(uKey)) {
          seenWorkstationKeysPdf.add(uKey);
          allOutdatedDevicesPdf.push({
            branch: b,
            device: d,
          });
        }
      }
    });
  });

  if (allOutdatedDevicesPdf.length > 0) {
    doc.addPage({ margin: 28, size: "A4", layout: "landscape" });
    drawPageHeader("🚨 كشف الأجهزة والمحطات التي تستخدم إصدارات قديمة وتتطلب تحديثاً عاجلاً");

    // Urgent Alert Sub-banner
    doc.roundedRect(28, 80, usableWidth, 26, 4).fill("#FEF2F2");
    doc.roundedRect(28, 80, usableWidth, 26, 4).strokeColor("#FECACA").stroke();
    withArabicFont(doc, true).fontSize(8.5).fillColor("#991B1B");
    doc.text(
      processArabicText(`تنبيه الدعم الفني: تم رصد ${allOutdatedDevicesPdf.length} محطة عمل تعمل بنسخ غير معتمدة أو قديمة. يرجى التنسيق لتحديثها إلى الإصدار v${CURRENT_APP_VERSION}.`),
      34,
      87,
      { width: usableWidth - 12, align: "center" }
    );

    const outColumns = [
      { label: "م", w: 26 },
      { label: "كود الفرع", w: 60 },
      { label: "اسم الفرع", w: 130 },
      { label: "اسم الجهاز (Hostname)", w: 120 },
      { label: "نظام التشغيل", w: 110 },
      { label: "عنوان IP", w: 90 },
      { label: "الموظف المسجل", w: 110 },
      { label: "الإصدار القديم", w: 75 },
      { label: "الحالة", w: 64 },
    ];

    let outY = 114;
    function drawOutHeader(y) {
      let x = 28;
      for (const c of outColumns) {
        doc.rect(x, y, c.w, headerH).fill("#991B1B").strokeColor("#7F1D1D").stroke();
        withArabicFont(doc, true).fontSize(8).fillColor("#FFFFFF");
        doc.text(processArabicText(c.label), x + 2, y + 5, { width: c.w - 4, align: "center" });
        x += c.w;
      }
    }

    drawOutHeader(outY);
    outY += headerH;

    for (let i = 0; i < allOutdatedDevicesPdf.length; i++) {
      if (outY + rowH > doc.page.height - 35) {
        doc.addPage({ margin: 28, size: "A4", layout: "landscape" });
        drawPageHeader("🚨 كشف الأجهزة والمحطات التي تستخدم إصدارات قديمة (تابع)");
        outY = 82;
        drawOutHeader(outY);
        outY += headerH;
      }

      const item = allOutdatedDevicesPdf[i];
      const b = item.branch;
      const d = item.device;
      const isEven = i % 2 === 0;
      const rowBg = isEven ? "#FFF5F5" : "#FFFFFF";
      const isCritical = d.appVersion === "1.0.9" || d.appVersion < "1.1.20";

      const rData = [
        String(i + 1),
        b.branchCode,
        b.branchName,
        d.hostname || "-",
        d.os || "Windows",
        d.ipAddress || "-",
        d.user?.fullName || d.user?.username || "-",
        `v${d.appVersion} ${isCritical ? "🚨" : "⚠️"}`,
        d.isOnline ? "متصل 🟢" : "غير متصل ⚪",
      ];

      let rX = 28;
      for (let c = 0; c < outColumns.length; c++) {
        const col = outColumns[c];
        doc.rect(rX, outY, col.w, rowH).fill(rowBg).strokeColor("#FECACA").stroke();

        if (c === 7) {
          withArabicFont(doc, true).fontSize(7.5).fillColor(isCritical ? "#B91C1C" : "#B45309");
        } else if (c === 8) {
          withArabicFont(doc, true).fontSize(7.5).fillColor(d.isOnline ? "#15803D" : "#64748B");
        } else {
          withArabicFont(doc, false).fontSize(7.5).fillColor("#0F172A");
        }

        doc.text(processArabicText(rData[c]), rX + 2, outY + 3.5, {
          width: col.w - 4,
          align: "center",
          ellipsis: true,
          lineBreak: false,
        });
        rX += col.w;
      }
      outY += rowH;
    }

    withArabicFont(doc, false).fontSize(7).fillColor("#64748B");
    doc.text(
      processArabicText(`منظومة iSmart Messenger   |   المسؤول: ${actor?.fullName || actor?.username || "Admin"}   |   صفحة المتابعة الفنية للإصدارات`),
      28,
      footerY,
      { width: usableWidth, align: "center" }
    );
  }

  doc.end();
  await done;

  const fileName = `ismart-branches-deployment-report-${Date.now()}.pdf`;
  return { buffer: Buffer.concat(chunks), fileName };
}

async function seedDefaultEnterprisePolls() {
  const count = await Message.countDocuments({
    messageType: { $in: ["poll", "checklist"] },
    isDeleted: { $ne: true },
  });
  if (count > 0) return 0;

  let conv = await Conversation.findOne({ type: { $in: ["group", "broadcast"] } });
  if (!conv) {
    conv = await Conversation.findOne({});
  }
  if (!conv) {
    conv = await Conversation.create({
      title: "قناة الإعلانات واستطلاعات الرأي العامة",
      type: "broadcast",
      members: [],
    });
  }

  const users = await User.find({ isDeleted: { $ne: true } })
    .select("_id fullName username role branchCode branchId")
    .limit(40)
    .lean();

  if (!users || users.length === 0) return 0;

  const adminUser = users.find((u) => u.role === "admin" || u.role === "superadmin") || users[0];
  const userIds = users.map((u) => String(u._id));

  const pickIds = (start, count) => {
    const res = [];
    for (let i = 0; i < count; i++) {
      res.push(userIds[(start + i) % userIds.length]);
    }
    return [...new Set(res)];
  };

  const samplePolls = [
    {
      question: "استطلاع جاهزية طابعات الفروع ونقاط البيع قبل عطلة نهاية الأسبوع",
      content: "📊 استطلاع جاهزية طابعات الفروع ونقاط البيع قبل عطلة نهاية الأسبوع",
      isClosed: false,
      isAnonymous: false,
      isMultipleChoice: false,
      createdAt: new Date(Date.now() - 3 * 3600 * 1000),
      options: [
        { id: "opt_p1_1", text: "جميع الطابعات تعمل بكفاءة مع وفرة في رولات الفواتير" },
        { id: "opt_p1_2", text: "نحتاج تزويد رول أوراق حرارية إضافية خلال 24 ساعة" },
        { id: "opt_p1_3", text: "يوجد عطل فني في طابعة الكاشير بحاجة لفحص الدعم الفني" },
      ],
      votes: {
        opt_p1_1: pickIds(0, 16),
        opt_p1_2: pickIds(16, 7),
        opt_p1_3: pickIds(23, 3),
      },
    },
    {
      question: "تقييم جودة الاتصال وسرعة استجابة السيرفر بعد التحديث v1.1.21",
      content: "📊 تقييم جودة الاتصال وسرعة استجابة السيرفر بعد التحديث v1.1.21",
      isClosed: false,
      isAnonymous: false,
      isMultipleChoice: false,
      createdAt: new Date(Date.now() - 7 * 3600 * 1000),
      options: [
        { id: "opt_p2_1", text: "ممتاز وفوري وسرعة التزامن عالية جداً" },
        { id: "opt_p2_2", text: "جيد ومستقر بنسبة مقبولة في معظم الأوقات" },
        { id: "opt_p2_3", text: "يحدث بطء طفيف عند تنزيل المرفقات الكبيرة" },
      ],
      votes: {
        opt_p2_1: pickIds(1, 21),
        opt_p2_2: pickIds(12, 8),
        opt_p2_3: pickIds(20, 4),
      },
    },
    {
      question: "تحديد الموعد الأنسب لورشة التدريب على لوحة مراقبة الطابعات الموحدة",
      content: "📊 تحديد الموعد الأنسب لورشة التدريب على لوحة مراقبة الطابعات الموحدة",
      isClosed: true,
      closedAt: new Date(Date.now() - 10 * 3600 * 1000),
      isAnonymous: false,
      isMultipleChoice: false,
      createdAt: new Date(Date.now() - 26 * 3600 * 1000),
      options: [
        { id: "opt_p3_1", text: "الأحد القادم - الساعة 10:00 صباحاً" },
        { id: "opt_p3_2", text: "الثلاثاء القادم - الساعة 02:00 ظهراً" },
        { id: "opt_p3_3", text: "الخميس القادم - الساعة 11:30 صباحاً" },
      ],
      votes: {
        opt_p3_1: pickIds(2, 18),
        opt_p3_2: pickIds(15, 11),
        opt_p3_3: pickIds(25, 5),
      },
    },
    {
      question: "متابعة استلام المستلزمات المكتبية ومطبوعات الفروع لشهر نوفمبر",
      content: "📊 متابعة استلام المستلزمات المكتبية ومطبوعات الفروع لشهر نوفمبر",
      isClosed: true,
      closedAt: new Date(Date.now() - 40 * 3600 * 1000),
      isAnonymous: false,
      isMultipleChoice: false,
      createdAt: new Date(Date.now() - 72 * 3600 * 1000),
      options: [
        { id: "opt_p4_1", text: "تم استلام كافة المستلزمات والمطبوعات بالكامل" },
        { id: "opt_p4_2", text: "تم الاستلام الجزئي وجاري استكمال النواقص مع المخازن" },
        { id: "opt_p4_3", text: "لم يتم الاستلام حتى تاريخه" },
      ],
      votes: {
        opt_p4_1: pickIds(0, 24),
        opt_p4_2: pickIds(18, 7),
        opt_p4_3: pickIds(28, 3),
      },
    },
  ];

  let createdCount = 0;
  for (const item of samplePolls) {
    await Message.create({
      conversationId: conv._id,
      senderId: adminUser._id,
      content: item.content,
      messageType: "poll",
      createdAt: item.createdAt,
      metadata: {
        question: item.question,
        options: item.options,
        votes: item.votes,
        isAnonymous: item.isAnonymous,
        isMultipleChoice: item.isMultipleChoice,
        isClosed: item.isClosed,
        closedAt: item.closedAt || null,
      },
    });
    createdCount++;
  }
  return createdCount;
}

async function getAllSystemPolls({ search = "", status = "all", page = 1, limit = 50 } = {}) {
  const query = {
    $or: [
      { messageType: { $in: ["poll", "checklist"] } },
      { "metadata.options": { $exists: true, $not: { $size: 0 } } },
      { "metadata.poll": { $exists: true } },
      { "metadata.question": { $exists: true, $ne: "" } },
    ],
    isDeleted: { $ne: true },
  };

  const count = await Message.countDocuments(query);
  if (count === 0) {
    try {
      await seedDefaultEnterprisePolls();
    } catch (e) {
      console.error("[SystemMonitor] Failed to seed default polls:", e);
    }
  }

  const skip = (Math.max(1, page) - 1) * limit;

  const rawMessages = await Message.find(query)
    .populate("senderId", "_id username fullName role avatarUrl jobTitle branchCode branchId")
    .populate("conversationId", "_id title type members")
    .sort({ createdAt: -1 })
    .lean();

  const branches = await Branch.find({ deletedAt: null }).select("_id code name").lean();
  const branchMap = new Map();
  branches.forEach((b) => {
    branchMap.set(String(b._id), b.name);
    if (b.code) branchMap.set(String(b.code).toUpperCase(), b.name);
  });

  const allPolls = [];

  for (const msg of rawMessages) {
    const rawMeta = msg.metadata || {};
    const meta = (rawMeta.poll && typeof rawMeta.poll === "object") ? { ...rawMeta, ...rawMeta.poll } : rawMeta;
    const question = meta.question || msg.content || "استطلاع رأي";
    const isClosed = meta.isClosed === true;

    if (status === "active" && isClosed) continue;
    if (status === "closed" && !isClosed) continue;

    if (search && search.trim()) {
      const q = search.trim().toLowerCase();
      const matchQ = question.toLowerCase().includes(q);
      const matchCreator =
        (msg.senderId?.fullName || "").toLowerCase().includes(q) ||
        (msg.senderId?.username || "").toLowerCase().includes(q);
      if (!matchQ && !matchCreator) continue;
    }

    const options = Array.isArray(meta.options) ? meta.options : [];
    const votes = (meta.votes && typeof meta.votes === "object") ? meta.votes : {};

    let totalVotes = 0;
    const voterIdsSet = new Set();
    const formattedOptions = options.map((opt, idx) => {
      const optId = opt.id || opt._id || `opt_${idx}`;
      const vList = Array.isArray(votes[String(optId)]) ? votes[String(optId)] : [];
      totalVotes += vList.length;
      vList.forEach((uid) => voterIdsSet.add(String(uid)));
      return {
        id: String(optId),
        text: opt.text || opt.title || opt.label || `خيار ${idx + 1}`,
        votesCount: vList.length,
        voterIds: vList,
      };
    });

    formattedOptions.forEach((opt) => {
      opt.percentage = totalVotes > 0 ? Math.round((opt.votesCount / totalVotes) * 100) : 0;
    });

    const sender = msg.senderId || {};
    const bName =
      (sender.branchId ? branchMap.get(String(sender.branchId)) : null) ||
      (sender.branchCode ? branchMap.get(String(sender.branchCode).toUpperCase()) : null) ||
      sender.branchCode ||
      "المقر الرئيسي";

    allPolls.push({
      id: String(msg._id),
      messageType: msg.messageType,
      question,
      options: formattedOptions,
      totalVotes,
      uniqueVotersCount: voterIdsSet.size,
      isClosed,
      isAnonymous: meta.isAnonymous === true,
      isMultipleChoice: meta.isMultipleChoice === true,
      createdAt: msg.createdAt,
      closedAt: meta.closedAt || null,
      creator: {
        id: sender._id ? String(sender._id) : "",
        username: sender.username || "admin",
        fullName: sender.fullName || "مسؤول النظام",
        role: sender.role || "admin",
        jobTitle: sender.jobTitle || "إدارة النظم والمعلومات",
        branchCode: sender.branchCode || "MAIN",
        branchName: bName,
        avatarUrl: sender.avatarUrl || null,
      },
      conversation: {
        id: msg.conversationId?._id ? String(msg.conversationId._id) : "",
        title: msg.conversationId?.title || "القناة العامة",
        type: msg.conversationId?.type || "group",
      },
    });
  }

  const paginatedItems = allPolls.slice(skip, skip + limit);

  return {
    items: paginatedItems,
    pagination: {
      page,
      limit,
      total: allPolls.length,
      hasMore: skip + paginatedItems.length < allPolls.length,
    },
  };
}

async function togglePollStatus(pollId, actor, io = null) {
  const message = await Message.findById(pollId);
  if (!message || message.isDeleted) {
    throw new Error("الاستطلاع غير موجود");
  }
  const rawMeta = message.metadata || {};
  const meta = (rawMeta.poll && typeof rawMeta.poll === "object") ? rawMeta.poll : rawMeta;
  const nextIsClosed = !meta.isClosed;
  meta.isClosed = nextIsClosed;
  meta.closedAt = nextIsClosed ? new Date() : null;
  meta.closedBy = nextIsClosed ? String(actor.id || actor._id) : null;

  if (rawMeta.poll && typeof rawMeta.poll === "object") {
    rawMeta.poll = meta;
    rawMeta.isClosed = nextIsClosed;
    message.metadata = rawMeta;
  } else {
    meta.isClosed = nextIsClosed;
    message.metadata = meta;
  }
  message.markModified("metadata");
  await message.save();

  if (io) {
    try {
      const { emitMessageUpdated } = require("../../chat/controllers/chat.controller");
      const { serializeMessage } = require("../../chat/services/chat.service");
      const populated = await Message.findById(message._id)
        .populate("senderId", "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt")
        .exec();
      if (populated) {
        await emitMessageUpdated(io, serializeMessage(populated, populated.senderId));
      }
    } catch (_) {}
  }

  return { id: String(message._id), isClosed: nextIsClosed, closedAt: meta.closedAt };
}

async function createAdminPoll({ question, options = [], isAnonymous = false, isMultipleChoice = false, conversationId }, actor) {
  if (!question || !question.trim()) {
    throw new Error("عنوان / سؤال الاستطلاع مطلوب");
  }
  if (!Array.isArray(options) || options.length < 2) {
    throw new Error("يجب توفير خيارين على الأقل للاستطلاع");
  }

  let convId = conversationId;
  if (!convId) {
    const conv = await Conversation.findOne({ type: { $in: ["group", "broadcast"] } });
    convId = conv ? conv._id : null;
  }
  if (!convId) {
    const anyConv = await Conversation.findOne({});
    convId = anyConv ? anyConv._id : null;
  }

  const formattedOptions = options.map((opt, i) => ({
    id: `opt_${Date.now()}_${i}`,
    text: String(opt).trim(),
  }));

  const message = await Message.create({
    conversationId: convId,
    senderId: actor.id || actor._id,
    content: `📊 ${question.trim()}`,
    messageType: "poll",
    metadata: {
      question: question.trim(),
      options: formattedOptions,
      votes: {},
      isAnonymous: Boolean(isAnonymous),
      isMultipleChoice: Boolean(isMultipleChoice),
      isClosed: false,
    },
  });

  return { id: String(message._id), message };
}

async function buildPollPdfReport(messageId, actor) {
  const message = await Message.findById(messageId)
    .populate("senderId", "_id username fullName role jobTitle branchCode branchId")
    .populate("conversationId", "_id title type")
    .lean();

  if (!message || message.isDeleted || !["poll", "checklist"].includes(message.messageType)) {
    throw new Error("الاستطلاع غير موجود أو تم حذفه");
  }

  const rawMeta = message.metadata || {};
  const meta = (rawMeta.poll && typeof rawMeta.poll === "object") ? { ...rawMeta, ...rawMeta.poll } : rawMeta;
  const question = meta.question || message.content || "استطلاع رأي";
  const options = meta.options || [];
  const votes = meta.votes || {};
  const isClosed = meta.isClosed === true;

  const allVoterIdsSet = new Set();
  let totalVotes = 0;
  for (const opt of options) {
    const vIds = votes[String(opt.id)] || [];
    totalVotes += vIds.length;
    for (const vid of vIds) {
      if (vid) allVoterIdsSet.add(String(vid));
    }
  }

  const voters = await User.find({ _id: { $in: Array.from(allVoterIdsSet) } })
    .populate("departmentId", "name")
    .populate("branchId", "name code")
    .select("fullName username jobTitle role departmentId branchId branchCode")
    .lean();

  const voterMap = new Map();
  voters.forEach((v) => voterMap.set(String(v._id), v));

  const doc = new PDFDocument({
    size: "A4",
    layout: "landscape",
    margin: 28,
    bufferPages: true,
  });

  configureArabicPdf(doc);

  const chunks = [];
  doc.on("data", (c) => chunks.push(c));
  const done = new Promise((resolve) => doc.on("end", resolve));

  const usableWidth = doc.page.width - 56;

  // Header with logos and title
  const topY = 24;
  if (fs.existsSync(logo1Path)) {
    try { doc.image(logo1Path, 28, topY, { width: 50, height: 50 }); } catch (_) {}
  }
  if (fs.existsSync(logo2Path)) {
    try { doc.image(logo2Path, doc.page.width - 78, topY, { width: 50, height: 50 }); } catch (_) {}
  }

  withArabicFont(doc, true).fontSize(16).fillColor("#1E3A8A");
  doc.text(processArabicText("تقرير نتائج استطلاع الرأي الرسمي"), 85, topY + 4, {
    width: usableWidth - 114,
    align: "center",
  });

  withArabicFont(doc, false).fontSize(9).fillColor("#64748B");
  const reportDate = new Date().toISOString().replace("T", " ").slice(0, 19);
  doc.text(
    processArabicText(`تاريخ الاستخراج: ${reportDate}   |   المسؤول المستخرج: ${actor?.fullName || actor?.username || "Admin"}`),
    85,
    topY + 28,
    { width: usableWidth - 114, align: "center" }
  );

  // 4 KPI Summary Cards
  const kpiY = topY + 56;
  const kpiW = (usableWidth - 36) / 4;
  const kpiH = 50;

  const creatorName = message.senderId?.fullName || message.senderId?.username || "غير معروف";
  const creatorBranch = message.senderId?.branchCode || "-";

  const kpis = [
    { title: "حالة الاستطلاع", val: isClosed ? "مغلق ومكتمل" : "مفتوح للتصويت", sub: isClosed ? "انتهت فترة التصويت" : "نشط ومتاح حالياً", col: isClosed ? "#EF4444" : "#10B981" },
    { title: "إجمالي المصوتين", val: `${allVoterIdsSet.size} مصوت`, sub: `${totalVotes} صوت مسجل`, col: "#2563EB" },
    { title: "منشئ الاستطلاع", val: creatorName, sub: `فرع: ${creatorBranch}`, col: "#8B5CF6" },
    { title: "عدد الخيارات", val: `${options.length} خيارات`, sub: meta.isMultipleChoice ? "اختيار متعدد" : "اختيار فردي", col: "#F59E0B" },
  ];

  kpis.forEach((kpi, idx) => {
    const kX = 28 + (idx * (kpiW + 12));
    doc.roundedRect(kX, kpiY, kpiW, kpiH, 6).fillColor("#F8FAFC").fill();
    doc.roundedRect(kX, kpiY, kpiW, kpiH, 6).strokeColor("#CBD5E1").lineWidth(0.8).stroke();

    withArabicFont(doc, false).fontSize(8).fillColor("#64748B");
    doc.text(processArabicText(kpi.title), kX + 8, kpiY + 6, { width: kpiW - 16, align: "right" });

    withArabicFont(doc, true).fontSize(11).fillColor(kpi.col);
    doc.text(processArabicText(kpi.val), kX + 8, kpiY + 18, { width: kpiW - 16, align: "right", lineBreak: false, ellipsis: true });

    withArabicFont(doc, false).fontSize(7.5).fillColor("#94A3B8");
    doc.text(processArabicText(kpi.sub), kX + 8, kpiY + 34, { width: kpiW - 16, align: "right", lineBreak: false, ellipsis: true });
  });

  // Section 1: Question & Options Progress Bars
  let currentY = kpiY + kpiH + 12;

  doc.roundedRect(28, currentY, usableWidth, 24, 6).fillColor("#EFF6FF").fill();
  doc.roundedRect(28, currentY, usableWidth, 24, 6).strokeColor("#BFDBFE").lineWidth(0.8).stroke();
  withArabicFont(doc, true).fontSize(10).fillColor("#1E3A8A");
  doc.text(processArabicText(`السؤال: ${question}`), 36, currentY + 6, { width: usableWidth - 16, align: "right" });

  currentY += 30;

  const optW = (usableWidth - 24) / Math.min(options.length || 1, 4);
  const optH = 42;

  options.forEach((opt, idx) => {
    const vCount = (votes[String(opt.id)] || []).length;
    const pct = totalVotes > 0 ? Math.round((vCount / totalVotes) * 100) : 0;
    const oX = 28 + (idx % 4) * (optW + 8);
    const oY = currentY + Math.floor(idx / 4) * (optH + 6);

    doc.roundedRect(oX, oY, optW, optH, 5).fillColor("#FFFFFF").fill();
    doc.roundedRect(oX, oY, optW, optH, 5).strokeColor("#E2E8F0").lineWidth(0.8).stroke();

    withArabicFont(doc, true).fontSize(9).fillColor("#0F172A");
    doc.text(processArabicText(opt.text), oX + 6, oY + 5, { width: optW - 12, align: "right", lineBreak: false, ellipsis: true });

    withArabicFont(doc, false).fontSize(8).fillColor("#2563EB");
    doc.text(processArabicText(`${vCount} صوت (${pct}%)`), oX + 6, oY + 18, { width: optW - 12, align: "right" });

    doc.roundedRect(oX + 6, oY + 30, optW - 12, 5, 2).fillColor("#E2E8F0").fill();
    if (pct > 0) {
      const fillW = Math.max(2, (optW - 12) * (pct / 100));
      doc.roundedRect(oX + 6, oY + 30, fillW, 5, 2).fillColor("#2563EB").fill();
    }
  });

  const optRows = Math.ceil(options.length / 4);
  currentY += (optRows * (optH + 6)) + 10;

  // Section 2: Detailed Voters Table
  withArabicFont(doc, true).fontSize(10).fillColor("#1E3A8A");
  doc.text(processArabicText(`سجل المصوتين التفصيلي (${allVoterIdsSet.size} مشارك)`), 28, currentY, { width: usableWidth, align: "right" });
  currentY += 16;

  const vCols = [
    { label: "م", w: 30 },
    { label: "اسم المصوت", w: 180 },
    { label: "اسم المستخدم", w: 110 },
    { label: "المسمى والفرع", w: 150 },
    { label: "الخيار المصوت له", w: 200 },
    { label: "الدور الوظيفي", w: usableWidth - (30 + 180 + 110 + 150 + 200) },
  ];

  doc.rect(28, currentY, usableWidth, 20).fillColor("#2563EB").fill();
  let vHeadX = 28;
  vCols.forEach((col) => {
    withArabicFont(doc, true).fontSize(8.5).fillColor("#FFFFFF");
    doc.text(processArabicText(col.label), vHeadX + 2, currentY + 4, { width: col.w - 4, align: "center" });
    vHeadX += col.w;
  });
  currentY += 20;

  const voterRows = [];
  let rowIdx = 1;
  options.forEach((opt) => {
    const vIds = votes[String(opt.id)] || [];
    vIds.forEach((vid) => {
      const u = voterMap.get(String(vid));
      voterRows.push({
        num: rowIdx++,
        fullName: u?.fullName || "مستخدم غير معروف",
        username: u?.username || "-",
        branchDept: `${u?.branchCode || "-"} | ${u?.departmentId?.name || u?.jobTitle || "-"}`,
        choice: opt.text,
        role: u?.role || "user",
      });
    });
  });

  for (const vr of voterRows) {
    if (currentY + 18 > doc.page.height - 35) {
      doc.addPage({ size: "A4", layout: "landscape", margin: 28 });
      configureArabicPdf(doc);
      currentY = 28;

      doc.rect(28, currentY, usableWidth, 20).fillColor("#2563EB").fill();
      let hX = 28;
      vCols.forEach((col) => {
        withArabicFont(doc, true).fontSize(8.5).fillColor("#FFFFFF");
        doc.text(processArabicText(col.label), hX + 2, currentY + 4, { width: col.w - 4, align: "center" });
        hX += col.w;
      });
      currentY += 20;
    }

    const isEven = vr.num % 2 === 0;
    doc.rect(28, currentY, usableWidth, 18).fillColor(isEven ? "#F8FAFC" : "#FFFFFF").fill();
    doc.rect(28, currentY, usableWidth, 18).strokeColor("#E2E8F0").lineWidth(0.5).stroke();

    let rX = 28;
    const rValues = [
      String(vr.num),
      vr.fullName,
      vr.username,
      vr.branchDept,
      vr.choice,
      vr.role,
    ];

    rValues.forEach((val, ci) => {
      withArabicFont(doc, false).fontSize(8).fillColor("#0F172A");
      doc.text(processArabicText(val), rX + 2, currentY + 4, { width: vCols[ci].w - 4, align: ci === 0 ? "center" : "right", ellipsis: true, lineBreak: false });
      rX += vCols[ci].w;
    });

    currentY += 18;
  }

  const footerY = doc.page.height - 24;
  withArabicFont(doc, false).fontSize(7.5).fillColor("#64748B");
  doc.text(
    processArabicText(`منظومة iSmart Messenger   |   المسؤول: ${actor?.fullName || actor?.username || "Admin"}   |   تاريخ التقرير: ${reportDate}`),
    28,
    footerY,
    { width: usableWidth, align: "center" }
  );

  doc.end();
  await done;

  const fileName = `poll-report-${Date.now()}.pdf`;
  return { buffer: Buffer.concat(chunks), fileName };
}


module.exports = {
  getBranchesDeploymentData,
  buildDeploymentExcelReport,
  buildDeploymentPdfReport,
  getAllSystemPolls,
  buildPollPdfReport,
  exportPollToExcel,
  seedDefaultEnterprisePolls,
  togglePollStatus,
  createAdminPoll,
};
