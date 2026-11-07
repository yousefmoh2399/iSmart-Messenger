const assert = require("node:assert/strict");
const test = require("node:test");
const { errorHandler } = require("../src/middleware/error.middleware");

function mockRes() {
  return {
    statusCode: null,
    body: null,
    headersSent: false,
    destroyed: false,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

test("errorHandler: handles CastError with 400 Bad Request", () => {
  const req = { originalUrl: "/api/test", method: "GET", ip: "127.0.0.1" };
  const res = mockRes();
  const castErr = new Error("Cast to ObjectId failed");
  castErr.name = "CastError";
  castErr.path = "conversationId";

  errorHandler(castErr, req, res, () => {});
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.success, false);
  assert.ok(res.body.message.includes("conversationId"));
});

test("errorHandler: handles ValidationError with 400 and details", () => {
  const req = { originalUrl: "/api/test", method: "POST", ip: "127.0.0.1" };
  const res = mockRes();
  const valErr = new Error("Validation failed");
  valErr.name = "ValidationError";
  valErr.errors = {
    title: { path: "title", message: "Title is required." },
  };

  errorHandler(valErr, req, res, () => {});
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.success, false);
  assert.equal(res.body.details[0].field, "title");
});

test("errorHandler: handles duplicate key error (11000) with 409 Conflict", () => {
  const req = { originalUrl: "/api/test", method: "POST", ip: "127.0.0.1" };
  const res = mockRes();
  const dupErr = new Error("E11000 duplicate key error");
  dupErr.code = 11000;
  dupErr.keyValue = { username: "yousef" };

  errorHandler(dupErr, req, res, () => {});
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.success, false);
  assert.ok(res.body.message.includes("username"));
});

test("errorHandler: does not hang when req.destroyed is true if res is alive", () => {
  const req = { originalUrl: "/api/test", method: "POST", ip: "127.0.0.1", destroyed: true };
  const res = mockRes();
  const err = new Error("Something went wrong");

  errorHandler(err, req, res, () => {});
  assert.equal(res.statusCode, 500);
  assert.equal(res.body.success, false);
});
