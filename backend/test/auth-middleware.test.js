const assert = require("node:assert/strict");
const test = require("node:test");
const jwt = require("jsonwebtoken");
const { jwtSecret } = require("../src/config/env");
const User = require("../src/models/user.model");
const Role = require("../src/chat/models/role.model");
const {
  AUTH_USER_PROJECTION,
  optionalAuth,
  requireAuth,
  authenticateRequest,
} = require("../src/middleware/auth.middleware");
const { buildToken, buildRefreshToken } = require("../src/services/auth.service");

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

const { invalidateRoleCache } = require("../src/chat/services/role.service");

test("AUTH_USER_PROJECTION and auth refresh projection compile in Mongoose without literal + prefix bugs", () => {
  const query = User.findById("000000000000000000000001")
    .select(AUTH_USER_PROJECTION)
    .lean();
  query._applyPaths();
  const fields = query._fieldsForExec();

  assert.equal(fields.tokenVersion, 1);
  assert.equal(fields.refreshSessions, 1);
  assert.equal(fields["+tokenVersion"], undefined);
  assert.equal(fields["+refreshSessions"], undefined);
  assert.equal(fields.passwordHash, undefined);

  const refreshQuery = User.findById("000000000000000000000001")
    .select("_id username role isActive tokenVersion +refreshTokenNonce +refreshSessions")
    .lean();
  refreshQuery._applyPaths();
  const refreshFields = refreshQuery._fieldsForExec();
  assert.equal(refreshFields.tokenVersion, 1);
  assert.equal(refreshFields.refreshTokenNonce, 1);
  assert.equal(refreshFields.refreshSessions, 1);
  assert.equal(refreshFields["+tokenVersion"], undefined);
});

test("requireAuth and authenticateRequest accept bumped tokenVersion (>= 2) and reject stale versions", async () => {
  const origFindById = User.findById;
  const origRoleFindOne = Role.findOne;
  let capturedSelect = null;

  const dbUser = {
    _id: "6af000000000000000000001",
    username: "branch.user",
    role: "user",
    fullName: "Branch User",
    branchCode: "CAI",
    isActive: true,
    tokenVersion: 3,
    refreshSessions: [{ deviceUid: "dev-abc" }],
  };

  User.findById = () => ({
    select(proj) {
      capturedSelect = proj;
      return {
        lean: async () => dbUser,
      };
    },
  });
  Role.findOne = () => ({
    lean: async () => null,
  });
  invalidateRoleCache();

  try {
    const validToken = buildToken(dbUser, "dev-abc");
    const validRefresh = buildRefreshToken(dbUser, "nonce-1", "dev-abc");
    const decodedRefresh = jwt.verify(validRefresh, jwtSecret);
    assert.equal(decodedRefresh.tokenVersion, 3);

    const req = {
      headers: { authorization: `Bearer ${validToken}` },
      query: {},
      method: "GET",
    };
    let nextErr = null;
    await requireAuth(req, {}, (err) => {
      nextErr = err || null;
    });
    assert.equal(nextErr, null);
    assert.equal(capturedSelect, AUTH_USER_PROJECTION);
    assert.equal(req.user.tokenVersion, 3);

    const optUser = await authenticateRequest({
      headers: { authorization: `Bearer ${validToken}` },
      query: {},
      method: "GET",
    });
    assert.equal(optUser.tokenVersion, 3);

    const staleToken = buildToken({ ...dbUser, tokenVersion: 2 }, "dev-abc");
    let staleErr = null;
    await requireAuth(
      {
        headers: { authorization: `Bearer ${staleToken}` },
        query: {},
        method: "GET",
      },
      {},
      (err) => {
        staleErr = err;
      },
    );
    assert.ok(staleErr);
    assert.equal(staleErr.statusCode, 401);
    assert.match(staleErr.message, /Token version mismatch/);
  } finally {
    User.findById = origFindById;
    Role.findOne = origRoleFindOne;
    invalidateRoleCache();
  }
});
