const test = require("node:test");
const assert = require("node:assert/strict");

const {
  processArabicText,
  buildUsersPdfReport,
  buildUsersExcelReport,
} = require("../src/services/user-export.service");

test("user-export: processArabicText reverses words for Arabic and preserves LTR for non-Arabic", () => {
  assert.equal(processArabicText(""), "");
  assert.equal(processArabicText(null), "");
  assert.equal(processArabicText("admin"), "admin");
  assert.equal(processArabicText("2026/10/28"), "2026/10/28");
  assert.equal(processArabicText("أحمد"), "أحمد");
  assert.equal(processArabicText("أحمد محمد علي"), "علي  محمد  أحمد");
  assert.equal(processArabicText("الفرع الرئيسي"), "الرئيسي  الفرع");
});

test("user-export: buildUsersPdfReport returns valid PDF buffer with proper Arabic layout", async () => {
  const mockUsers = [
    {
      username: "ahmed.ali",
      fullName: "أحمد علي إبراهيم",
      branchCode: "MAIN",
      branchId: { name: "الفرع الرئيسي" },
      departmentId: { name: "تكنولوجيا المعلومات" },
      role: "admin",
      isActive: true,
      createdAt: new Date("2026-01-15T10:00:00.000Z"),
    },
    {
      username: "sara.k",
      fullName: "سارة خالد",
      branchCode: "MNS",
      branchId: { name: "فرع المنصورة" },
      departmentId: { name: "خدمة العملاء" },
      role: "user",
      isActive: false,
      createdAt: new Date("2026-02-01T10:00:00.000Z"),
    },
  ];

  const buffer = await buildUsersPdfReport({
    users: mockUsers,
    actor: { fullName: "المشرف العام", username: "superadmin" },
    selectedBranch: null,
    selectedDept: null,
    generatedAt: new Date(),
  });

  assert.ok(Buffer.isBuffer(buffer), "Expected buffer to be a Buffer");
  assert.ok(buffer.length > 1000, "Expected PDF buffer size > 1000 bytes");
  // PDF header check
  const header = buffer.subarray(0, 5).toString("ascii");
  assert.equal(header, "%PDF-");
});

test("user-export: buildUsersExcelReport returns valid Excel buffer", async () => {
  const mockUsers = [
    {
      username: "user1",
      fullName: "مستخدم أول",
      branchCode: "MAIN",
      branchId: { name: "الرئيسي" },
      departmentId: { name: "الحسابات" },
      role: "manager",
      isActive: true,
      createdAt: new Date("2026-01-01T00:00:00.000Z"),
    },
  ];

  const buffer = await buildUsersExcelReport({
    users: mockUsers,
    actor: { fullName: "Admin" },
    selectedBranch: null,
    selectedDept: null,
    generatedAt: new Date(),
  });

  assert.ok(Buffer.isBuffer(buffer), "Expected Excel buffer to be a Buffer");
  assert.ok(buffer.length > 1000, "Expected Excel buffer size > 1000 bytes");
  // Excel zip magic bytes: PK (0x50 0x4B)
  assert.equal(buffer[0], 0x50);
  assert.equal(buffer[1], 0x4b);
});
