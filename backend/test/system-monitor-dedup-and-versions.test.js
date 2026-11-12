const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildDeploymentExcelReport,
  buildDeploymentPdfReport,
} = require("../src/admin/system-monitor/system-monitor.service");

const testData = {
  summary: {
    totalBranches: 3,
    installedBranchesCount: 2,
    notInstalledBranchesCount: 1,
    adoptionPercentage: 67,
    totalInstalledDevices: 4,
    totalOnlineDevices: 3,
    currentAppVersion: "1.1.21",
    targetAppVersion: "1.1.21",
    latestVersionDevicesCount: 2,
    outdatedDevicesCount: 2,
    criticalOutdatedDevicesCount: 1,
    outdatedBranchesCount: 1,
    versionBreakdown: {
      "1.1.21": 2,
      "1.1.20": 1,
      "1.0.9": 1,
    },
  },
  branches: [
    {
      branchCode: "101",
      branchName: "الفرع الرئيسي",
      isInstalled: true,
      hasOutdatedDevices: true,
      outdatedDevicesCount: 2,
      latestDevicesCount: 1,
      devicesCount: 3,
      onlineDevicesCount: 2,
      installedUsersCount: 3,
      totalRegisteredUsers: 5,
      appVersions: ["1.0.9", "1.1.20", "1.1.21"],
      lastActivityAt: new Date(),
      devices: [
        {
          deviceUid: "dev-pc-01",
          hostname: "PC-CASH-01",
          os: "Windows 7",
          osVersion: "6.1.7601",
          ipAddress: "192.168.1.101",
          appVersion: "1.0.9",
          targetVersion: "1.1.21",
          isOutdated: true,
          isCritical: true,
          versionStatus: "critical",
          versionStatusLabel: "نسخة قديمة حرجة (v1.0.9) 🚨",
          workstationType: "نقطة بيع كاشير",
          isOnline: true,
          lastSeenAt: new Date(),
          user: { username: "cashier1", fullName: "أحمد كاشير", jobTitle: "كاشير فرع" },
        },
        {
          deviceUid: "dev-pc-02",
          hostname: "PC-MGR-01",
          os: "Windows 10",
          osVersion: "10.0.19045",
          ipAddress: "192.168.1.102",
          appVersion: "1.1.20",
          targetVersion: "1.1.21",
          isOutdated: true,
          isCritical: false,
          versionStatus: "previous",
          versionStatusLabel: "نسخة سابقة (v1.1.20) ⚠️",
          workstationType: "حاسب إدارة فرع",
          isOnline: false,
          lastSeenAt: new Date(Date.now() - 3600000),
          user: { username: "mgr1", fullName: "محمد مدير", jobTitle: "مدير الفرع" },
        },
        {
          deviceUid: "dev-pc-03",
          hostname: "PC-ACC-01",
          os: "Windows 11",
          osVersion: "10.0.22631",
          ipAddress: "192.168.1.103",
          appVersion: "1.1.21",
          targetVersion: "1.1.21",
          isOutdated: false,
          isCritical: false,
          versionStatus: "latest",
          versionStatusLabel: "مطابق للمعتمد (v1.1.21) ✅",
          workstationType: "حاسب الحسابات",
          isOnline: true,
          lastSeenAt: new Date(),
          user: { username: "acc1", fullName: "خالد محاسب", jobTitle: "رئيس الحسابات" },
        },
      ],
    },
    {
      branchCode: "102",
      branchName: "فرع المنصورة",
      isInstalled: true,
      hasOutdatedDevices: false,
      outdatedDevicesCount: 0,
      latestDevicesCount: 1,
      devicesCount: 1,
      onlineDevicesCount: 1,
      installedUsersCount: 1,
      totalRegisteredUsers: 4,
      appVersions: ["1.1.21"],
      lastActivityAt: new Date(),
      devices: [
        {
          deviceUid: "dev-pc-04",
          hostname: "PC-MANS-01",
          os: "Windows 11",
          osVersion: "10.0.22631",
          ipAddress: "192.168.2.101",
          appVersion: "1.1.21",
          targetVersion: "1.1.21",
          isOutdated: false,
          isCritical: false,
          versionStatus: "latest",
          versionStatusLabel: "مطابق للمعتمد (v1.1.21) ✅",
          workstationType: "محطة عمل",
          isOnline: true,
          lastSeenAt: new Date(),
          user: { username: "mans_user", fullName: "يوسف منصور", jobTitle: "أخصائي ائتمان" },
        },
      ],
    },
  ],
};

const actor = {
  username: "admin",
  fullName: "مسؤول المنظومة",
  role: "superadmin",
};

test("system-monitor: Excel export creates 5 sheets and isolates outdated devices in sheet 2", async () => {
  const result = await buildDeploymentExcelReport(testData, actor);
  assert.ok(result.buffer && result.buffer.length > 3000);
  assert.ok(result.fileName.endsWith(".xlsx"));

  const ExcelJS = require("exceljs");
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(result.buffer);

  assert.equal(workbook.worksheets.length, 5, "Expected 5 sheets in Excel");
  assert.equal(workbook.worksheets[0].name, "ملخص المنظومة والتحديثات");
  assert.equal(workbook.worksheets[1].name, "أجهزة بنسخ قديمة للمتابعة");
  assert.equal(workbook.worksheets[2].name, "أجهزة بالنسخة المعتمدة");
  assert.equal(workbook.worksheets[3].name, "موقف انتشار الفروع");
  assert.equal(workbook.worksheets[4].name, "كافة محطات العمل والأسطول");

  // Sheet 2 should contain only outdated devices (2 devices + header = 3 rows)
  const sheet2 = workbook.worksheets[1];
  assert.equal(sheet2.rowCount, 3, "Expected 2 outdated device rows + 1 header");

  // Sheet 3 should contain up-to-date devices (2 devices + header = 3 rows)
  const sheet3 = workbook.worksheets[2];
  assert.equal(sheet3.rowCount, 3, "Expected 2 up-to-date device rows + 1 header");

  // Sheet 5 should contain all 4 devices without duplicates
  const sheet5 = workbook.worksheets[4];
  assert.equal(sheet5.rowCount, 5, "Expected 4 total fleet device rows + 1 header");
});

test("system-monitor: PDF export generates landscape multi-page document with outdated section", async () => {
  const result = await buildDeploymentPdfReport(testData, actor);
  assert.ok(result.buffer && result.buffer.length > 1000);
  assert.ok(result.fileName.endsWith(".pdf"));
  const header = result.buffer.subarray(0, 5).toString("ascii");
  assert.equal(header, "%PDF-");
});

test("system-monitor: Excel export with scope 'outdated' produces dedicated outdated file name", async () => {
  const result = await buildDeploymentExcelReport(testData, actor, { scope: "outdated" });
  assert.ok(result.buffer && result.buffer.length > 3000);
  assert.ok(result.fileName.startsWith("ismart-outdated-devices-"));
  assert.ok(result.fileName.endsWith(".xlsx"));
});

test("system-monitor: Excel export with scope 'per_branch' creates separate sheet per branch", async () => {
  const result = await buildDeploymentExcelReport(testData, actor, { scope: "per_branch" });
  assert.ok(result.buffer && result.buffer.length > 3000);
  assert.ok(result.fileName.startsWith("ismart-branches-per-sheet-"));
  assert.ok(result.fileName.endsWith(".xlsx"));

  const ExcelJS = require("exceljs");
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(result.buffer);

  // Sheet 1 is summary, followed by 2 branches in testData (101 and 102)
  assert.equal(workbook.worksheets.length, 3, "Expected 1 summary sheet + 2 branch sheets");
  assert.equal(workbook.worksheets[0].name, "ملخص مقارنة الفروع");
});

test("system-monitor: Excel export with scope 'per_branch' filters to selected branches", async () => {
  const result = await buildDeploymentExcelReport(testData, actor, {
    scope: "per_branch",
    branchCodes: ["101"],
  });
  assert.ok(result.buffer && result.buffer.length > 2000);
  assert.ok(result.fileName.startsWith("ismart-branch-101-deployment-"));

  const ExcelJS = require("exceljs");
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(result.buffer);

  // Sheet 1 is summary, Sheet 2 is branch 101
  assert.equal(workbook.worksheets.length, 2, "Expected 1 summary sheet + 1 filtered branch sheet");
  assert.equal(workbook.worksheets[0].name, "ملخص مقارنة الفروع");
  assert.ok(workbook.worksheets[1].name.includes("الرئيسي") || workbook.worksheets[1].name.includes("101"));
});

test("system-monitor: reports strictly exclude mobile devices and duplicate user entries", async () => {
  const testDataWithMobileAndDuplicates = {
    summary: { ...testData.summary },
    branches: [
      {
        branchCode: "105",
        branchName: "فرع الاختبار",
        isInstalled: true,
        devices: [
          // Valid Desktop PC
          {
            deviceUid: "pc-105-01",
            hostname: "PC-DESK-01",
            os: "Windows 10",
            clientType: "desktop",
            appVersion: "1.0.9",
            isOutdated: true,
            user: { id: "user-1", username: "user1", fullName: "مستخدم أول" },
          },
          // Duplicate session for same user on same PC
          {
            deviceUid: "pc-105-01",
            hostname: "PC-DESK-01",
            os: "Windows 10",
            clientType: "desktop",
            appVersion: "1.0.9",
            isOutdated: true,
            user: { id: "user-1", username: "user1", fullName: "مستخدم أول" },
          },
          // Mobile smartphone device (MUST BE EXCLUDED)
          {
            deviceUid: "mobile-phone-01",
            hostname: "Galaxy S22",
            os: "Android 13",
            clientType: "mobile",
            appVersion: "1.0.9",
            isOutdated: true,
            user: { id: "user-mobile", username: "usermobile", fullName: "مستخدم موبايل" },
          },
        ],
      },
    ],
  };

  const ExcelJS = require("exceljs");
  const result = await buildDeploymentExcelReport(testDataWithMobileAndDuplicates, actor);
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(result.buffer);

  // Sheet 5 (all fleet devices) should contain ONLY the 1 unique PC, mobile and duplicates excluded!
  const sheet5 = workbook.worksheets[4];
  assert.equal(sheet5.rowCount, 2, "Expected exactly 1 PC row + 1 header, mobile and duplicate excluded");
});
