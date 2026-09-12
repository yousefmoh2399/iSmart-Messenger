const assert = require("node:assert/strict");
const test = require("node:test");

const ApiError = require("../src/utils/api-error");

test("ApiError preserves status, message, and details", () => {
  const details = { field: "email" };
  const error = new ApiError(422, "Invalid request", details);

  assert.equal(error.name, "Error");
  assert.equal(error.message, "Invalid request");
  assert.equal(error.statusCode, 422);
  assert.equal(error.details, details);
  assert.ok(error instanceof Error);
});

test("ApiError defaults details to null", () => {
  const error = new ApiError(404, "Not found");

  assert.equal(error.details, null);
});
