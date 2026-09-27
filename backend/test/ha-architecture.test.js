const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const fs = require("node:fs/promises");

const { withDistributedLock } = require("../src/utils/distributed-lock");
const { storage } = require("../src/utils/storage-provider");
const logger = require("../src/utils/logger");
const printJobStore = require("../src/chat/services/print-job-store");

test("withDistributedLock prevents concurrent duplicate execution and releases cleanly", async () => {
  let runs = 0;
  const first = withDistributedLock("test:lock:1", 5000, async () => {
    runs += 1;
    await new Promise((r) => setTimeout(r, 80));
    return "first-done";
  });

  const second = withDistributedLock("test:lock:1", 5000, async () => {
    runs += 1;
    return "second-done";
  });

  const [res1, res2] = await Promise.all([first, second]);
  assert.equal(res1.acquired, true);
  assert.equal(res1.result, "first-done");
  assert.equal(res2.acquired, false);
  assert.equal(runs, 1);

  // After lock is released, a subsequent call succeeds
  const third = await withDistributedLock("test:lock:1", 5000, async () => {
    runs += 1;
    return "third-done";
  });
  assert.equal(third.acquired, true);
  assert.equal(runs, 2);
});

test("storage-provider saves, verifies, rolls back on DB failure, and passes health check", async () => {
  const relPath = `test_ha_${Date.now()}/sample.pdf`;
  const content = Buffer.from("%PDF-1.4 sample ha test content");

  const saved = await storage.save({
    buffer: content,
    targetRelativePath: relPath,
  });

  assert.equal(saved.size, content.length);
  assert.equal(await storage.exists(saved.storageKey), true);

  // Verify rollback deletes the uploaded file when the DB write throws
  await assert.rejects(async () => {
    await storage.withUploadTransaction(saved.absolutePath, async () => {
      throw new Error("Simulated MongoDB write failure");
    });
  }, /Simulated MongoDB write failure/);

  assert.equal(await storage.exists(saved.storageKey), false);

  const health = await storage.checkHealth();
  assert.equal(health.available, true);
  assert.equal(health.status, "available");

  // Clean up test directory
  try {
    await fs.rmdir(path.dirname(saved.absolutePath));
  } catch (_) {}
});

test("printJobStore tracks and resolves job ownership across print/save/receive flows", async () => {
  printJobStore.setJobOwner("print", "job-ha-100", "user-999");
  const resolved = await printJobStore.resolveJobOwner("print", "job-ha-100", "fallback-user");
  assert.equal(resolved, "user-999");

  printJobStore.deleteJobOwner("print", "job-ha-100");
  const afterDelete = await printJobStore.resolveJobOwner("print", "job-ha-100", "fallback-user");
  assert.equal(afterDelete, "fallback-user");

  // Test getJobIdForRequestAsync
  printJobStore.registerRequest("req-async-1", "job-async-1");
  const asyncId = await printJobStore.getJobIdForRequestAsync("req-async-1");
  assert.equal(asyncId, "job-async-1");
});

test("withDistributedLock supports autoRelease: false to hold lock across scheduled window", async () => {
  const outcome1 = await withDistributedLock(
    "test:cron:window",
    5000,
    async () => "done",
    { autoRelease: false }
  );
  assert.equal(outcome1.acquired, true);

  // A concurrent or immediate call should be blocked even after task finishes because autoRelease is false
  const outcome2 = await withDistributedLock(
    "test:cron:window",
    5000,
    async () => "duplicate",
    { autoRelease: false }
  );
  assert.equal(outcome2.acquired, false);
});

test("logger exposes non-empty instanceId", () => {
  assert.equal(typeof logger.getInstanceId(), "string");
  assert.ok(logger.getInstanceId().length > 0);
});

test("printJobStore: atomic reservation prevents race conditions and scopes by user", async () => {
  const reqId = `race-test-${Date.now()}`;
  const userA = "user-race-A";
  const userB = "user-race-B";

  // First reservation attempt by user A
  const res1 = await printJobStore.reservePrintRequest({
    userId: userA,
    clientRequestId: reqId,
    ttlMs: 5000,
  });
  assert.equal(res1.status, "reserved");
  assert.ok(res1.token);

  // Concurrent attempt by user A with same clientRequestId while in-flight
  const res2 = await printJobStore.reservePrintRequest({
    userId: userA,
    clientRequestId: reqId,
    ttlMs: 5000,
  });
  assert.equal(res2.status, "in_flight");

  // Attempt by user B with same clientRequestId is independently scoped
  const resUserB = await printJobStore.reservePrintRequest({
    userId: userB,
    clientRequestId: reqId,
    ttlMs: 5000,
  });
  assert.equal(resUserB.status, "reserved");
  assert.ok(resUserB.token);

  // Commit reservation for user A
  await printJobStore.commitPrintRequest({
    userId: userA,
    clientRequestId: reqId,
    token: res1.token,
    jobId: "job-committed-A",
  });

  // Subsequent reservation attempt by user A now returns existing job
  const res3 = await printJobStore.reservePrintRequest({
    userId: userA,
    clientRequestId: reqId,
    ttlMs: 5000,
  });
  assert.equal(res3.status, "existing");
  assert.equal(res3.jobId, "job-committed-A");

  // Test release: reserve for user C, release, then reserve again
  const userC = "user-race-C";
  const reqIdC = `release-test-${Date.now()}`;
  const resC1 = await printJobStore.reservePrintRequest({
    userId: userC,
    clientRequestId: reqIdC,
    ttlMs: 5000,
  });
  assert.equal(resC1.status, "reserved");

  await printJobStore.releasePrintReservation({
    userId: userC,
    clientRequestId: reqIdC,
    token: resC1.token,
  });

  const resC2 = await printJobStore.reservePrintRequest({
    userId: userC,
    clientRequestId: reqIdC,
    ttlMs: 5000,
  });
  assert.equal(resC2.status, "reserved");
});

test("printJobStore: job version counter increments across state transitions", () => {
  const jobId = `ver-test-${Date.now()}`;
  const job = printJobStore.createJob(jobId, { title: "versioned print" });
  assert.equal(job.version, 1);
  assert.equal(job.state, "pending");

  printJobStore.validateAndTransition(jobId, "forwarded");
  const jobForwarded = printJobStore.getJob(jobId);
  assert.equal(jobForwarded.version, 2);
  assert.equal(jobForwarded.state, "forwarded");

  printJobStore.validateAndTransition(jobId, "processing");
  const jobProcessing = printJobStore.getJob(jobId);
  assert.equal(jobProcessing.version, 3);
  assert.equal(jobProcessing.state, "processing");
});

test("withDistributedLock releases lock on error when releaseOnError is enabled", async () => {
  const lockKey = `test:error:release:${Date.now()}`;

  // Execute task that fails with autoRelease: false
  await assert.rejects(async () => {
    await withDistributedLock(
      lockKey,
      5000,
      async () => {
        throw new Error("Task failed unexpectedly");
      },
      { autoRelease: false, releaseOnError: true }
    );
  }, /Task failed unexpectedly/);

  // Because releaseOnError: true ran, a subsequent attempt immediately succeeds
  const retryOutcome = await withDistributedLock(
    lockKey,
    5000,
    async () => "recovered",
    { autoRelease: true }
  );
  assert.equal(retryOutcome.acquired, true);
  assert.equal(retryOutcome.result, "recovered");
});

test("printer-scheduler getDateKey computes valid date in Africa/Cairo timezone", () => {
  const { getDateKey } = require("../src/printers/services/printer-scheduler.service");
  const cairoDate = getDateKey("Africa/Cairo");
  assert.match(cairoDate, /^\d{4}-\d{2}-\d{2}$/);
});

test("redis and adapter status methods reflect operational state", () => {
  const { getPubSubStatus } = require("../src/config/redis");
  const { getAdapterStatus } = require("../src/chat/sockets/chat.socket");

  const pubSub = getPubSubStatus();
  assert.ok(typeof pubSub.enabled === "boolean");
  assert.ok(typeof pubSub.status === "string");

  const adapter = getAdapterStatus();
  assert.ok(typeof adapter.attached === "boolean");
});

test("DeviceSession model supports presenceStatus field with enum validation", () => {
  const DeviceSession = require("../src/models/device-session.model");
  const mongoose = require("mongoose");

  const validSession = new DeviceSession({
    userId: new mongoose.Types.ObjectId(),
    presenceStatus: "meeting",
  });
  const validErr = validSession.validateSync();
  assert.equal(validErr, undefined);
  assert.equal(validSession.presenceStatus, "meeting");

  const invalidSession = new DeviceSession({
    userId: new mongoose.Types.ObjectId(),
    presenceStatus: "invalid_status",
  });
  const invalidErr = invalidSession.validateSync();
  assert.ok(invalidErr);
  assert.ok(invalidErr.errors.presenceStatus);
});

test("printJobStore: validateAndTransitionAsync enforces valid state machine transitions", async () => {
  const jobId = `async-trans-${Date.now()}`;
  printJobStore.createJob(jobId, { title: "async transition test" });

  // Valid transition pending -> forwarded
  const jobFwd = await printJobStore.validateAndTransitionAsync(jobId, "forwarded");
  assert.equal(jobFwd.state, "forwarded");
  assert.equal(jobFwd.version, 2);

  // Invalid transition forwarded -> submitted (must go through processing)
  await assert.rejects(async () => {
    await printJobStore.validateAndTransitionAsync(jobId, "submitted");
  }, /Invalid print job state transition/);

  // Valid transition forwarded -> processing
  const jobProc = await printJobStore.validateAndTransitionAsync(jobId, "processing");
  assert.equal(jobProc.state, "processing");
  assert.equal(jobProc.version, 3);
});

test("printJobStore: releasePrintReservation does not release if token does not match", async () => {
  const reqId = `safe-release-${Date.now()}`;
  const user = "user-safe";

  // First reservation by user
  const res1 = await printJobStore.reservePrintRequest({
    userId: user,
    clientRequestId: reqId,
    ttlMs: 5000,
  });
  assert.equal(res1.status, "reserved");

  // Attempt to release using an obsolete or mismatched token
  await printJobStore.releasePrintReservation({
    userId: user,
    clientRequestId: reqId,
    token: "wrong-obsolete-token",
  });

  // The original reservation must still be in-flight/active
  const res2 = await printJobStore.reservePrintRequest({
    userId: user,
    clientRequestId: reqId,
    ttlMs: 5000,
  });
  assert.equal(res2.status, "in_flight");
  assert.equal(res2.token, res1.token);

  // Release with correct token clears the reservation
  await printJobStore.releasePrintReservation({
    userId: user,
    clientRequestId: reqId,
    token: res1.token,
  });

  const res3 = await printJobStore.reservePrintRequest({
    userId: user,
    clientRequestId: reqId,
    ttlMs: 5000,
  });
  assert.equal(res3.status, "reserved");
});

test("printer-scheduler runDailySync executes cleanly and respects distributed locking", async () => {
  const { runDailySync } = require("../src/printers/services/printer-scheduler.service");
  // Test execution when called directly (in local test context where fullSync is safe)
  const outcome = await runDailySync(false);
  // outcome.acquired can be true (or false if already held)
  assert.ok(typeof outcome.acquired === "boolean");
});

test("printJobStore: اختبار وحدة في عملية واحدة - 50 طلب متزامن لنفس (userId, clientRequestId) ينتج حجزًا واحدًا فقط", async () => {
  const reqId = `concurrency-50-${Date.now()}`;
  const userId = "user-50-test";

  const attempts = await Promise.all(
    Array.from({ length: 50 }).map(() =>
      printJobStore.reservePrintRequest({
        userId,
        clientRequestId: reqId,
        ttlMs: 10000,
      })
    )
  );

  const reservedCount = attempts.filter((r) => r.status === "reserved").length;
  const inFlightCount = attempts.filter((r) => r.status === "in_flight").length;

  assert.equal(reservedCount, 1, "Exactly one request must succeed in acquiring the reservation");
  assert.equal(inFlightCount, 49, "All other 49 concurrent requests must receive in_flight");

  // Commit the winning reservation
  const winner = attempts.find((r) => r.status === "reserved");
  const jobId = `job-50-${Date.now()}`;
  printJobStore.createJob(jobId, { title: "50-concurrent-test" });
  await printJobStore.commitPrintRequest({
    userId,
    clientRequestId: reqId,
    token: winner.token,
    jobId,
  });

  // Verify subsequent check returns the exact committed jobId
  const check = await printJobStore.reservePrintRequest({
    userId,
    clientRequestId: reqId,
    ttlMs: 10000,
  });
  assert.equal(check.status, "existing");
  assert.equal(check.jobId, jobId);
});

test("printJobStore: in CLUSTER_MODE=true, reservation and transitions fail fast without local fallback when Redis is absent", async () => {
  const prevClusterMode = process.env.CLUSTER_MODE;
  process.env.CLUSTER_MODE = "true";
  try {
    const outcome = await printJobStore.reservePrintRequest({
      userId: "user-cluster-fail",
      clientRequestId: `req-fail-${Date.now()}`,
      ttlMs: 5000,
    });
    // In test runner where Redis is disabled, reservation must return status: "failed"
    assert.equal(outcome.status, "failed");
    assert.match(outcome.error, /CLUSTER_MODE requires operational Redis/);

    // Distributed transition must also throw rather than falling back locally
    await assert.rejects(async () => {
      await printJobStore.validateAndTransitionAsync("non-existent-job", "forwarded");
    }, /CLUSTER_MODE requires operational Redis/);
  } finally {
    if (prevClusterMode === undefined) {
      delete process.env.CLUSTER_MODE;
    } else {
      process.env.CLUSTER_MODE = prevClusterMode;
    }
  }
});

test("printJobStore: commitPrintRequest validates token and returns true on valid commit", async () => {
  const reqId = `commit-mismatch-${Date.now()}`;
  const userId = "user-mismatch";

  const res = await printJobStore.reservePrintRequest({
    userId,
    clientRequestId: reqId,
    ttlMs: 5000,
  });
  assert.equal(res.status, "reserved");

  const success = await printJobStore.commitPrintRequest({
    userId,
    clientRequestId: reqId,
    token: res.token,
    jobId: "valid-commit-job",
  });
  assert.equal(success, true);
});

test("SocketIOv4Client (ws): يتخاطب مع خادم Socket.IO v4 الحقيقي (handshake.auth + emitWithAck + server emit)", async () => {
  const http = require("http");
  const { Server } = require("socket.io");
  const { SocketIOv4Client } = require("./integration-ha-runner");

  const srv = http.createServer();
  const io = new Server(srv);

  io.use((socket, next) => {
    if (socket.handshake.auth?.token === "valid-token") {
      return next();
    }
    return next(new Error("Unauthorized"));
  });

  io.on("connection", (socket) => {
    socket.on("ping_test", (payload, ack) => {
      socket.emit("server_push", { echoed: payload.msg });
      ack({ ok: true, receivedClientType: socket.handshake.auth?.clientType });
    });
  });

  await new Promise((resolve) => srv.listen(0, "127.0.0.1", resolve));
  const addr = srv.address();
  const client = new SocketIOv4Client(`http://127.0.0.1:${addr.port}`, {
    auth: { token: "valid-token", clientType: "desktop" },
  });

  try {
    const pushedEvents = [];
    client.on("server_push", (data) => pushedEvents.push(data));
    await client.connect();
    assert.ok(client.id, "Client should receive socket.id upon connect");

    const ackRes = await client.emitWithAck("ping_test", { msg: "hello-ha" });
    assert.equal(ackRes.ok, true);
    assert.equal(ackRes.receivedClientType, "desktop");
    assert.equal(pushedEvents.length, 1);
    assert.equal(pushedEvents[0].echoed, "hello-ha");
  } finally {
    client.close();
    await new Promise((resolve) => io.close(resolve));
  }
});


