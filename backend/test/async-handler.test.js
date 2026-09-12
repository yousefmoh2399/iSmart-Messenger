const assert = require("node:assert/strict");
const test = require("node:test");

const asyncHandler = require("../src/utils/async-handler");

test("asyncHandler forwards request arguments to a successful handler", async () => {
  const req = {};
  const res = {};
  const next = () => assert.fail("next should not be called");
  let received;

  const wrapped = asyncHandler(async (...args) => {
    received = args;
  });

  await wrapped(req, res, next);

  assert.deepEqual(received, [req, res, next]);
});

test("asyncHandler sends rejected errors to next", async () => {
  const expected = new Error("failed");
  let received;
  const wrapped = asyncHandler(async () => {
    throw expected;
  });

  await wrapped({}, {}, (error) => {
    received = error;
  });

  assert.equal(received, expected);
});
