const test = require("node:test");
const assert = require("node:assert/strict");

const {
  emitUpdateTelemetry,
  emitUpdatesUpdated,
  _downloadAdmission,
} = require("../src/admin/updates/update.controller");
const { recordTelemetryEntry } = require("../src/middleware/request-telemetry.middleware");
const { _presenceGrace } = require("../src/chat/sockets/chat.socket");
const { closeRedisClient } = require("../src/config/redis");
const User = require("../src/models/user.model");

test.after(async () => {
  await closeRedisClient();
});

function createMockIo() {
  const globalEmits = [];
  const roomEmits = [];
  const liveSockets = new Map();

  const buildChain = (rooms = []) => ({
    to(room) {
      return buildChain([...rooms, room]);
    },
    emit(event, payload) {
      roomEmits.push({ rooms, event, payload });
    },
  });

  return {
    globalEmits,
    roomEmits,
    sockets: { sockets: liveSockets },
    emit(event, payload) {
      globalEmits.push({ event, payload });
    },
    to(room) {
      return buildChain([room]);
    },
  };
}

test("emitUpdateTelemetry scopes update_telemetry to admin rooms and never broadcasts globally", () => {
  const io = createMockIo();
  const req = { app: { get: (k) => (k === "io" ? io : null) } };

  emitUpdateTelemetry(req, {
    action: "download_progress",
    deviceUid: "dev-1",
    progress: 50,
  });

  assert.equal(io.globalEmits.length, 0);
  assert.equal(io.roomEmits.length, 1);
  assert.deepEqual(io.roomEmits[0].rooms, ["admin:updates", "admin:monitor"]);
  assert.equal(io.roomEmits[0].event, "update_telemetry");
  assert.equal(io.roomEmits[0].payload.action, "download_progress");
  assert.equal(io.roomEmits[0].payload.progress, 50);
});

test("emitUpdatesUpdated emits updates_updated only for explicit release/job actions", () => {
  const io = createMockIo();
  const req = { app: { get: (k) => (k === "io" ? io : null) } };

  emitUpdatesUpdated(req, { action: "job_created", releaseVersion: "1.1.24" });

  assert.equal(io.globalEmits.length, 1);
  assert.equal(io.globalEmits[0].event, "updates_updated");
  assert.equal(io.globalEmits[0].payload.action, "job_created");
});

test("recordTelemetryEntry scopes api_request_telemetry strictly to admin:monitor", () => {
  const io = createMockIo();
  recordTelemetryEntry(io, {
    id: "req-1",
    method: "GET",
    path: "/api/chat/conversations",
    statusCode: 200,
  });

  assert.equal(io.globalEmits.length, 0);
  assert.equal(io.roomEmits.length, 1);
  assert.deepEqual(io.roomEmits[0].rooms, ["admin:monitor"]);
  assert.equal(io.roomEmits[0].event, "api_request_telemetry");
});

test("download admission control limits concurrent transfers per branch/subnet and globally", () => {
  _downloadAdmission.resetDownloadSlots();
  try {
    assert.equal(
      _downloadAdmission.extractBranchDownloadBucket({
        branchCode: "B105",
        clientIp: "10.10.5.12",
      }),
      "branch:B105",
    );
    assert.equal(
      _downloadAdmission.extractBranchDownloadBucket({
        branchCode: "MAIN",
        clientIp: "::ffff:192.168.44.88",
      }),
      "subnet:192.168.44",
    );

    const b1a = _downloadAdmission.tryAcquireDownloadSlot({
      branchCode: "B105",
      clientIp: "10.10.5.10",
      deviceKey: "dev-b1-1",
    });
    const b1b = _downloadAdmission.tryAcquireDownloadSlot({
      branchCode: "B105",
      clientIp: "10.10.5.11",
      deviceKey: "dev-b1-2",
    });
    assert.equal(b1a.acquired, true);
    assert.equal(b1b.acquired, true);

    // 3rd simultaneous PC from same branch must receive backoff
    const b1c = _downloadAdmission.tryAcquireDownloadSlot({
      branchCode: "B105",
      clientIp: "10.10.5.12",
      deviceKey: "dev-b1-3",
    });
    assert.equal(b1c.acquired, false);
    assert.ok(b1c.retryAfterSeconds >= 15 && b1c.retryAfterSeconds < 40);

    // Releasing one slot frees capacity immediately for that branch
    _downloadAdmission.releaseDownloadSlot(b1a.slotId);
    const b1Retry = _downloadAdmission.tryAcquireDownloadSlot({
      branchCode: "B105",
      clientIp: "10.10.5.12",
      deviceKey: "dev-b1-3",
    });
    assert.equal(b1Retry.acquired, true);

    // Same device retrying reuses its slot cleanly instead of double-counting
    const b1SameDevice = _downloadAdmission.tryAcquireDownloadSlot({
      branchCode: "B105",
      clientIp: "10.10.5.12",
      deviceKey: "dev-b1-3",
    });
    assert.equal(b1SameDevice.acquired, true);
  } finally {
    _downloadAdmission.resetDownloadSlots();
  }
});

test("presence disconnect grace cancels offline/online flap when socket reconnects quickly", async () => {
  const origUpdateOne = User.updateOne;
  User.updateOne = async () => ({ acknowledged: true });
  const io = createMockIo();
  const userId = "650000000000000000000901";

  try {
    _presenceGrace.userSockets.delete(userId);
    _presenceGrace.publishedPresenceState.delete(userId);
    _presenceGrace.cancelPendingOfflinePublish(userId);

    io.sockets.sockets.set("sock-1", { id: "sock-1" });
    _presenceGrace.registerUserSocket(userId, "sock-1");
    await _presenceGrace.publishAggregatedPresence(io, userId);

    assert.equal(io.roomEmits.length, 2); // initial presence_updated + user_online

    // Simulate VPN flap disconnect
    io.sockets.sockets.delete("sock-1");
    _presenceGrace.unregisterUserSocket(userId, "sock-1");
    _presenceGrace.scheduleOfflineGracePublish(io, userId, 80);

    // Immediately reconnect within grace window
    io.sockets.sockets.set("sock-2", { id: "sock-2" });
    _presenceGrace.registerUserSocket(userId, "sock-2");
    await _presenceGrace.publishAggregatedPresence(io, userId);

    await new Promise((r) => setTimeout(r, 120));

    // Zero additional presence events emitted (no offline/online storm)
    assert.equal(io.roomEmits.length, 2);

    // Now disconnect permanently without reconnecting
    io.sockets.sockets.delete("sock-2");
    _presenceGrace.unregisterUserSocket(userId, "sock-2");
    _presenceGrace.scheduleOfflineGracePublish(io, userId, 30);

    await new Promise((r) => setTimeout(r, 80));

    // Now offline event IS emitted cleanly once
    assert.equal(io.roomEmits.length, 4);
    assert.equal(io.roomEmits[3].event, "user_offline");
  } finally {
    _presenceGrace.cancelPendingOfflinePublish(userId);
    _presenceGrace.userSockets.delete(userId);
    _presenceGrace.publishedPresenceState.delete(userId);
    User.updateOne = origUpdateOne;
  }
});
