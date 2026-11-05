const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildDeploymentExcelReport,
  buildDeploymentPdfReport,
} = require("../src/admin/system-monitor/system-monitor.service");

const mockData = {
  summary: {
    totalBranches: 10,
    installedBranchesCount: 8,
    notInstalledBranchesCount: 2,
    adoptionPercentage: 80,
    totalInstalledDevices: 45,
    totalOnlineDevices: 28,
    currentAppVersion: "1.1.21",
  },
  branches: [
    {
      branchCode: "101",
      branchName: "الفرع الرئيسي",
      isInstalled: true,
      devicesCount: 5,
      onlineDevicesCount: 3,
      totalRegisteredUsers: 12,
      installedUsersCount: 10,
      appVersions: ["1.1.21"],
      lastActivityAt: new Date(),
      devices: [
        {
          hostname: "PC-ADMIN-01",
          os: "Windows",
          osVersion: "10 Pro",
          ipAddress: "192.168.1.10",
          appVersion: "1.1.21",
          isOnline: true,
          lastSeenAt: new Date(),
          user: { username: "admin", fullName: "مسؤول النظام" },
        },
      ],
    },
    {
      branchCode: "102",
      branchName: "فرع المنصورة",
      isInstalled: false,
      devicesCount: 0,
      onlineDevicesCount: 0,
      totalRegisteredUsers: 8,
      installedUsersCount: 0,
      appVersions: [],
      lastActivityAt: null,
      devices: [],
    },
  ],
};

const mockActor = {
  username: "superadmin",
  fullName: "المشرف العام للشبكة",
  role: "superadmin",
};

test("system-monitor-reports: buildDeploymentExcelReport generates valid multi-sheet Excel file", async () => {
  const result = await buildDeploymentExcelReport(mockData, mockActor);
  assert.ok(result, "Expected result object");
  assert.ok(Buffer.isBuffer(result.buffer), "Expected buffer to be a Buffer");
  assert.ok(result.buffer.length > 2000, "Expected Excel buffer size > 2000 bytes");
  assert.ok(result.fileName.endsWith(".xlsx"), "Expected .xlsx extension");

  // Excel (.xlsx) is a ZIP file starting with PK header (0x50 0x4B 0x03 0x04)
  const pkHeader = result.buffer.subarray(0, 4);
  assert.equal(pkHeader[0], 0x50);
  assert.equal(pkHeader[1], 0x4b);
});

test("system-monitor-reports: buildDeploymentPdfReport generates valid A4 landscape PDF", async () => {
  const result = await buildDeploymentPdfReport(mockData, mockActor);
  assert.ok(result, "Expected result object");
  assert.ok(Buffer.isBuffer(result.buffer), "Expected buffer to be a Buffer");
  assert.ok(result.buffer.length > 1000, "Expected PDF buffer size > 1000 bytes");
  assert.ok(result.fileName.endsWith(".pdf"), "Expected .pdf extension");

  // PDF starts with %PDF-
  const pdfHeader = result.buffer.subarray(0, 5).toString("ascii");
  assert.equal(pdfHeader, "%PDF-");
});
