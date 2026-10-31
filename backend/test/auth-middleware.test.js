const assert = require("node:assert/strict");
const test = require("node:test");
const { optionalAuth, requireAuth } = require("../src/middleware/auth.middleware");

test("optionalAuth allows unauthenticated requests and sets req.user to null", async () => {
  const req = {
    headers: {},
    query: {},
    method: "GET",
  };
  const res = {};
  let nextCalled = false;

  await optionalAuth(req, res, () => {
    nextCalled = true;
  });

  assert.equal(nextCalled, true);
  assert.equal(req.user, null);
});

test("requireAuth rejects unauthenticated requests with 401", async () => {
  const req = {
    headers: {},
    query: {},
    method: "GET",
  };
  const res = {};

  let errorCaught = null;
  await requireAuth(req, res, (err) => {
    errorCaught = err;
  });

  assert.ok(errorCaught);
  assert.equal(errorCaught.statusCode, 401);
});
