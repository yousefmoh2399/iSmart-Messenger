const test = require("node:test");
const assert = require("node:assert/strict");

const {
  DEFAULT_JOB_TEMPLATES,
  getNextAvailableIndex,
  generateUsernames,
} = require("../src/services/user-batch-generator.service");

test("user-batch-generator: DEFAULT_JOB_TEMPLATES contains all required enterprise roles", () => {
  const keys = DEFAULT_JOB_TEMPLATES.map((t) => t.key);
  const required = ["man", "vman", "acc", "ghead", "csup", "spec", "coord", "collect"];
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
