const test = require("node:test");
const assert = require("node:assert/strict");

const {
  DEFAULT_JOB_TEMPLATES,
  getNextAvailableIndex,
  generateUsernames,
  resolveDepartmentForTitle,
} = require("../src/services/user-batch-generator.service");

test("user-batch-generator: DEFAULT_JOB_TEMPLATES contains all required enterprise roles", () => {
  const keys = DEFAULT_JOB_TEMPLATES.map((t) => t.key);
  const required = ["man", "vman", "acc", "cashier", "acash", "ghead", "csup", "spec", "coord", "collect"];
  for (const req of required) {
    assert.ok(keys.includes(req), `Expected ${req} to be in DEFAULT_JOB_TEMPLATES`);
  }
});

test("user-batch-generator: generateUsernames correctly handles single role (man-110) on empty branch", () => {
  const result = generateUsernames([], "man", "110", 1, true);
  assert.equal(result.length, 1);
  assert.equal(result[0].username, "man-110");
  assert.equal(result[0].isNumbered, false);
});

test("user-batch-generator: generateUsernames generates numbered accounts when man-110 already exists", () => {
  const result = generateUsernames(["man-110"], "man", "110", 1, true);
  assert.equal(result.length, 1);
  assert.equal(result[0].username, "man2-110");
  assert.equal(result[0].isNumbered, true);
});

test("user-batch-generator: generateUsernames correctly numbers coordinators on clean branch", () => {
  const result = generateUsernames([], "coord", "110", 5, false);
  assert.equal(result.length, 5);
  assert.equal(result[0].username, "coord1-110");
  assert.equal(result[1].username, "coord2-110");
  assert.equal(result[2].username, "coord3-110");
  assert.equal(result[3].username, "coord4-110");
  assert.equal(result[4].username, "coord5-110");
});

test("user-batch-generator: generateUsernames resumes numbering without duplicating existing users", () => {
  const existing = ["coord1-110", "coord2-110", "coord3-110"];
  const result = generateUsernames(existing, "coord", "110", 3, false);
  assert.equal(result.length, 3);
  assert.equal(result[0].username, "coord4-110");
  assert.equal(result[1].username, "coord5-110");
  assert.equal(result[2].username, "coord6-110");
});

test("user-batch-generator: getNextAvailableIndex works with mixed case and spacing", () => {
  const existing = ["SPEC1-110", "spec2-110 ", "spec3-110"];
  const nextIdx = getNextAvailableIndex(existing, "spec", "110");
  assert.equal(nextIdx, 4);
});

test("user-batch-generator: resolveDepartmentForTitle prioritizes branch departments over HQ", () => {
  const mockDepartments = [
    { _id: "hq_acc_id", name: "ACC-HQ", code: "100.20" },
    { _id: "branch_acc_id", name: "ACC Branches", code: ".20" },
    { _id: "branch_man_id", name: "Branch Managers", code: "5" },
    { _id: "branch_cash_id", name: "Cashier Branches", code: "65" },
    { _id: "branch_spec_id", name: "spec branches", code: "spec" },
  ];

  // acc should match ACC Branches, not ACC-HQ
  const accDept = resolveDepartmentForTitle(mockDepartments, {
    departmentKeywords: ["acc branches", "acc", "accounting"],
  });
  assert.equal(accDept, "branch_acc_id");

  // man should match Branch Managers
  const manDept = resolveDepartmentForTitle(mockDepartments, {
    departmentKeywords: ["branch managers", "branch manager", "man"],
  });
  assert.equal(manDept, "branch_man_id");

  // spec should match spec branches
  const specDept = resolveDepartmentForTitle(mockDepartments, {
    departmentKeywords: ["spec branches", "spec"],
  });
  assert.equal(specDept, "branch_spec_id");

  // cashier / acash should match Cashier Branches
  const cashDept = resolveDepartmentForTitle(mockDepartments, {
    departmentKeywords: ["cashier branches", "cashier", "cash"],
  });
  assert.equal(cashDept, "branch_cash_id");

  // Unknown role returns null, NOT a random department
  const unknownDept = resolveDepartmentForTitle(mockDepartments, {
    departmentKeywords: ["nonexistent_keyword"],
  });
  assert.equal(unknownDept, null);
});
