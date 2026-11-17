const asyncHandler = require("../../utils/async-handler");
const fsSync = require("fs");
const path = require("path");
const { Transform } = require("stream");
const {
  registerDeviceHeartbeat,
  listBranchPeerDevices,
  listDevices,
  updateDeviceActiveState,
  createRelease,
  listReleases,
  updateRelease,
  createUpdateJob,
  listUpdateJobs,
  getUpdateJobDetails,
  cancelUpdateJob,
  cancelAllActiveUpdates,
  reportTaskProgress,
  getReleaseDownloadInfo,
  validateReleaseDownloadAccess,
  pruneDisabledReleaseArtifact,
  checkForMobileUpdates,
} = require("./update.service");

const MAX_CONCURRENT_UPDATES_GLOBAL = Math.max(
  1,
  Number(process.env.UPDATE_MAX_CONCURRENT_GLOBAL) || 6,
);
const MAX_CONCURRENT_UPDATES_PER_BRANCH = Math.max(
  1,
  Number(process.env.UPDATE_MAX_CONCURRENT_PER_BRANCH) || 2,
);
const DEFAULT_UPDATE_MAX_BYTES_PER_SEC = (() => {
  const raw = process.env.UPDATE_MAX_BYTES_PER_SEC;
  if (raw !== undefined && String(raw).trim() !== "") {
    const parsed = Number(raw);
    return Number.isFinite(parsed) && parsed >= 0 ? parsed : 768 * 1024;
  }
  return 768 * 1024; // ~6 Mbps per download stream to prevent branch VPN bufferbloat
})();
const STALE_DOWNLOAD_SLOT_MS = 15 * 60 * 1000;
const activeDownloadSlots = new Map();
let downloadSlotSequence = 0;

function createByteRateLimiter(bytesPerSecond = DEFAULT_UPDATE_MAX_BYTES_PER_SEC) {
  const rate = Number(bytesPerSecond);
  if (!Number.isFinite(rate) || rate <= 0) {
    return null;
  }
  const chunkSliceBytes = Math.max(
    256,
    Math.min(rate, Math.min(32 * 1024, Math.floor(rate / 4) || rate)),
  );
  let tokens = chunkSliceBytes;
  let lastRefillAt = Date.now();
  let delayTimer = null;

  return new Transform({
    transform(chunk, _encoding, callback) {
      let offset = 0;
      const flushSlice = () => {
        if (offset >= chunk.length) {
          callback();
          return;
        }
        const now = Date.now();
        const elapsedMs = Math.max(0, now - lastRefillAt);
        if (elapsedMs > 0) {
          tokens = Math.min(rate, tokens + (rate * elapsedMs) / 1000);
          lastRefillAt = now;
        }
        const toSend = Math.min(chunkSliceBytes, chunk.length - offset);
        if (tokens >= toSend) {
          tokens -= toSend;
          this.push(chunk.subarray(offset, offset + toSend));
          offset += toSend;
          if (offset >= chunk.length) {
            callback();
            return;
          }
          setImmediate(flushSlice);
          return;
        }
        const deficitBytes = toSend - tokens;
        const waitMs = Math.max(5, Math.ceil((deficitBytes / rate) * 1000));
        delayTimer = setTimeout(() => {
          delayTimer = null;
          flushSlice();
        }, waitMs);
      };
      flushSlice();
    },
    destroy(err, callback) {
      if (delayTimer) {
        clearTimeout(delayTimer);
        delayTimer = null;
      }
      callback(err);
    },
  });
}

function extractIpv4SubnetBucket(clientIp) {
  const clean = String(clientIp || "")
    .split(",")[0]
    .trim()
    .replace(/^::ffff:/i, "");
  const match = clean.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.\d{1,3}$/);
  if (!match) {
    return null;
  }
  const a = Number(match[1]);
  const b = Number(match[2]);
  const c = Number(match[3]);
  if (a === 127 && b === 0 && c === 0) {
    return null;
  }
  return `${a}.${b}.${c}`;
}

function extractBranchDownloadBucket({ branchCode, clientIp }) {
  const normalizedBranch = String(branchCode || "")
    .trim()
    .toUpperCase();
  if (normalizedBranch && normalizedBranch !== "MAIN") {
    return `branch:${normalizedBranch}`;
  }
  const subnet = extractIpv4SubnetBucket(clientIp);
  if (subnet) {
    return `subnet:${subnet}`;
  }
  return "branch:MAIN";
}

function pruneStaleDownloadSlots(now = Date.now()) {
  for (const [slotId, slot] of activeDownloadSlots.entries()) {
    if (now - slot.startedAt > STALE_DOWNLOAD_SLOT_MS) {
      activeDownloadSlots.delete(slotId);
    }
  }
}

function tryAcquireDownloadSlot({ branchCode, clientIp, deviceKey } = {}) {
  const now = Date.now();
  pruneStaleDownloadSlots(now);

  // If the exact same device starts a fresh attempt (e.g., reconnect), free any
  // previous lingering slot belonging to it before evaluating capacity.
  if (deviceKey) {
    for (const [slotId, slot] of activeDownloadSlots.entries()) {
      if (slot.deviceKey && slot.deviceKey === deviceKey) {
        activeDownloadSlots.delete(slotId);
      }
    }
  }

  const branchBucket = extractBranchDownloadBucket({ branchCode, clientIp });
  let branchActive = 0;
  for (const slot of activeDownloadSlots.values()) {
    if (slot.branchBucket === branchBucket) {
      branchActive += 1;
    }
  }

  if (
    activeDownloadSlots.size >= MAX_CONCURRENT_UPDATES_GLOBAL ||
    branchActive >= MAX_CONCURRENT_UPDATES_PER_BRANCH
  ) {
    const retryAfterSeconds = 15 + Math.floor(Math.random() * 25);
    return {
      acquired: false,
      branchBucket,
      branchActive,
      globalActive: activeDownloadSlots.size,
      retryAfterSeconds,
    };
  }

  const slotId = `dl_${now}_${++downloadSlotSequence}`;
  activeDownloadSlots.set(slotId, {
    slotId,
    branchBucket,
    deviceKey: deviceKey || null,
    startedAt: now,
  });
  return {
    acquired: true,
    slotId,
    branchBucket,
    branchActive: branchActive + 1,
    globalActive: activeDownloadSlots.size,
  };
}

function releaseDownloadSlot(slotId) {
  if (!slotId) return;
  activeDownloadSlots.delete(slotId);
}

function resetDownloadSlots() {
  activeDownloadSlots.clear();
}

function getActiveDownloadStats() {
  pruneStaleDownloadSlots();
  return {
    globalActive: activeDownloadSlots.size,
    maxGlobal: MAX_CONCURRENT_UPDATES_GLOBAL,
    maxPerBranch: MAX_CONCURRENT_UPDATES_PER_BRANCH,
  };
}

function emitUpdatesUpdated(req, payload = {}) {
  const io = req.app?.get ? req.app.get("io") : null;
  if (!io) {
    return;
  }
  io.emit("updates_updated", {
    at: new Date().toISOString(),
    ...payload,
  });
}

function emitUpdateTelemetry(req, payload = {}) {
  const io = req.app?.get ? req.app.get("io") : null;
  if (!io) {
    return;
  }
  const eventPayload = {
    at: new Date().toISOString(),
    ...payload,
  };
  // Scope update telemetry strictly to admin monitor / update manager rooms so
  // hundreds of branch clients do not wake up and poll /heartbeat on every tick.
  io.to("admin:updates").to("admin:monitor").emit("update_telemetry", eventPayload);
}

const heartbeatDevice = asyncHandler(async (req, res) => {
  const result = await registerDeviceHeartbeat(req.user, req.body || {}, {
    ip: req.ip,
    baseUrlOverride: getRequestBaseUrl(req),
  });

  if (
    result?.activeTask &&
    ["acknowledged", "downloading", "installing"].includes(
      result.activeTask.status,
    )
  ) {
    emitUpdateTelemetry(req, {
      action: "heartbeat_active_task",
      taskId: result.activeTask.id,
      deviceId: result.device?.id,
      deviceUid: result.device?.deviceUid,
      deviceName: result.device?.deviceName || result.device?.hostName,
      hostName: result.device?.hostName,
      branchCode: result.device?.branchCode,
      platform: result.device?.platform,
      status: result.activeTask.status,
      phase: "pulling",
      progress: result.activeTask.progress || 10,
      targetVersion: result.activeTask.releaseVersion,
      currentVersion: result.device?.appVersion,
      message: result.activeTask.message || "جاري سحب التحديث",
      connectionStatus: result.device?.connectionStatus || "online",
    });
  }

  res.status(200).json({
    success: true,
    data: result,
  });
});

function getRequestBaseUrl(req) {
  const forwardedProto = String(req.headers["x-forwarded-proto"] || "")
    .split(",")[0]
    .trim();
  const protocol = forwardedProto || req.protocol || "http";
  const host = req.get("host");
  if (!host) {
    return `${protocol}://${req.hostname}`.replace(/\/+$/, "");
  }
  return `${protocol}://${host}`.replace(/\/+$/, "");
}

const reportTaskState = asyncHandler(async (req, res) => {
  const result = await reportTaskProgress(req.user, {
    ...req.body,
    taskId: req.params.taskId,
  });

  if (result && !result.throttled) {
    const rawStatus = String(
      result.task?.status || req.body?.status || "",
    ).toLowerCase();
    const isCompleted = rawStatus === "completed";
    const isFailed = rawStatus === "failed" || rawStatus === "cancelled";
    const isPulling =
      rawStatus === "downloading" ||
      rawStatus === "acknowledged" ||
      rawStatus === "pending" ||
      rawStatus === "installing";

    const phase = isCompleted
      ? "completed"
      : isFailed
        ? "failed"
        : isPulling
          ? "pulling"
          : "outdated";
    const progressVal = Number(
      result.task?.progress ??
        req.body?.progress ??
        (isCompleted ? 100 : 0),
    );

    emitUpdateTelemetry(req, {
      action: "task_progress",
      taskId: result.task?.id || req.params.taskId,
      deviceId: result.device?.id,
      deviceUid: result.device?.deviceUid || req.body?.deviceUid,
      deviceName:
        result.device?.deviceName ||
        result.task?.deviceName ||
        result.device?.hostName ||
        "POS Terminal",
      hostName: result.device?.hostName,
      branchCode:
        result.device?.branchCode || result.task?.branchCode || "110",
      platform:
        result.device?.platform ||
        result.task?.platform ||
        "desktop_windows",
      status: rawStatus,
      phase,
      progress: progressVal,
      targetVersion:
        result.task?.releaseVersion ||
        result.device?.updateState?.targetVersion,
      currentVersion: result.device?.appVersion,
      message: result.task?.message || req.body?.message || "",
      connectionStatus: result.device?.connectionStatus || "online",
      speed: "14.5 MB/s",
    });
  }

  res.status(200).json({
    success: true,
    data: result,
  });
});

const downloadReleaseArtifact = (req, res, next) => {
  validateReleaseDownloadAccess({
    releaseId: req.params.id,
    actor: req.user || null,
    downloadToken: req.query.token,
  })
    .then(async (accessInfo) => {
      const tokenDeviceUid =
        accessInfo && typeof accessInfo === "object" && accessInfo.deviceUid
          ? String(accessInfo.deviceUid).trim()
          : "";
      const clientDeviceUid = String(
        req.query.deviceUid ||
        req.headers["x-device-uid"] ||
        tokenDeviceUid ||
        req.user?.deviceUid ||
        req.user?.deviceInfo?.deviceUid ||
        "",
      ).trim();
      const hostName = String(
        req.headers["x-device-name"] ||
        req.headers["x-host-name"] ||
        req.user?.deviceInfo?.hostName ||
        req.user?.deviceInfo?.deviceName ||
        req.user?.deviceInfo?.hostname ||
        "",
      ).trim();
      const branchCode = String(
        req.headers["x-branch-code"] ||
        req.user?.branchCode ||
        "MAIN",
      ).toUpperCase();
      const clientIp = req.ip || req.headers["x-forwarded-for"] || req.socket?.remoteAddress || "-";
      const targetIdentifier = clientDeviceUid || (hostName ? `host_${hostName}` : (clientIp !== "-" ? `ip_${clientIp}` : "POS-Terminal"));

      const info = await getReleaseDownloadInfo(req.params.id);
      if (info.mode === "redirect") {
        res.redirect(info.externalDownloadUrl);
        return;
      }

      const filePath = info.filePath;
      const fileName = info.fileName;

      if (!fsSync.existsSync(filePath)) {
        return res.status(404).json({
          success: false,
          error: "Release artifact file not found.",
        });
      }

      const slot = tryAcquireDownloadSlot({
        branchCode,
        clientIp,
        deviceKey: targetIdentifier,
      });
      if (!slot.acquired) {
        res.setHeader("Retry-After", String(slot.retryAfterSeconds));
        return res.status(503).json({
          success: false,
          code: "UPDATE_DOWNLOAD_BUSY",
          error: "Update server download queue is busy. Retry after delay.",
          retryAfterSeconds: slot.retryAfterSeconds,
        });
      }

      let slotReleased = false;
      const releaseSlotOnce = () => {
        if (slotReleased) return;
        slotReleased = true;
        releaseDownloadSlot(slot.slotId);
      };
      res.once("close", releaseSlotOnce);
      res.once("finish", releaseSlotOnce);

      emitUpdateTelemetry(req, {
        action: "download_started",
        releaseId: req.params.id,
        deviceUid: clientDeviceUid || targetIdentifier,
        hostName: hostName || null,
        deviceName: hostName || null,
        branchCode: branchCode,
        clientIp: clientIp,
        status: "downloading",
        phase: "pulling",
        progress: 5,
        message: "بدأ سحب حزمة التحديث من السيرفر",
      });

      const stat = fsSync.statSync(filePath);
      const fileSize = stat.size;
      const etag = `"${stat.ino}-${stat.size}-${stat.mtimeMs}"`;

      res.setHeader("Content-Type", "application/octet-stream");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="${fileName}"`,
      );
      res.setHeader("Accept-Ranges", "bytes");
      res.setHeader("Cache-Control", "no-transform, no-cache, no-store, must-revalidate");
      res.setHeader("x-no-compression", "1");
      res.setHeader("Content-Encoding", "identity");
      res.setHeader("X-File-Size", String(fileSize));
      if (info.checksumSha256) {
        res.setHeader("X-Checksum-Sha256", String(info.checksumSha256));
      }
      res.setHeader("ETag", etag);
      res.setHeader("X-Content-Type-Options", "nosniff");

      const ifRange = req.headers["if-range"];
      const rangeAllowed = !ifRange || ifRange === etag;
      const range = req.headers.range;
      if (rangeAllowed && range && range.startsWith("bytes=")) {
        const parts = range.substring(6).split(",")[0].split("-");
        const start = parts[0] ? parseInt(parts[0], 10) : Math.max(0, fileSize - parseInt(parts[1], 10));
        const end = parts[0] && parts[1] ? parseInt(parts[1], 10) : fileSize - 1;

        if (
          Number.isNaN(start) ||
          Number.isNaN(end) ||
          start < 0 ||
          start >= fileSize ||
          end < start ||
          end >= fileSize
        ) {
          releaseSlotOnce();
          res.status(416);
          res.setHeader("Content-Range", `bytes */${fileSize}`);
          res.end();
          return;
        }

        res.status(206);
        res.setHeader("Content-Range", `bytes ${start}-${end}/${fileSize}`);
        res.setHeader("Content-Length", end - start + 1);

        const stream = fsSync.createReadStream(filePath, {
          start,
          end,
        });
        const limiter = createByteRateLimiter();
        const destroyStreams = () => {
          stream.destroy();
          if (limiter) limiter.destroy();
        };
        stream.once("error", (err) => {
          releaseSlotOnce();
          console.error(
            `[UpdateController] Stream error for ${req.params.id}:`,
            err.message,
          );
          if (!res.headersSent) {
            res.status(500).end();
          }
          destroyStreams();
        });
        if (limiter) {
          limiter.once("error", () => {
            releaseSlotOnce();
            destroyStreams();
          });
        }
        res.once("close", destroyStreams);
        res.once("error", () => {
          releaseSlotOnce();
          destroyStreams();
        });
        if (limiter) {
          stream.pipe(limiter).pipe(res);
        } else {
          stream.pipe(res);
        }
      } else {
        res.setHeader("Content-Length", fileSize);
        const stream = fsSync.createReadStream(filePath);
        const limiter = createByteRateLimiter();
        const destroyStreams = () => {
          stream.destroy();
          if (limiter) limiter.destroy();
        };
        let bytesSent = 0;
        let lastEmittedPct = 5;
        stream.on("data", (chunk) => {
          bytesSent += chunk.length;
          if (fileSize > 0) {
            const pct = Math.min(95, Math.round((bytesSent / fileSize) * 100));
            if (pct - lastEmittedPct >= 15) {
              lastEmittedPct = pct;
              emitUpdateTelemetry(req, {
                action: "download_progress",
                releaseId: req.params.id,
                deviceUid: clientDeviceUid || targetIdentifier,
                hostName: hostName || null,
                deviceName: hostName || null,
                branchCode: branchCode,
                clientIp: clientIp,
                status: "downloading",
                phase: "pulling",
                progress: pct,
                message: `جاري سحب حزمة التحديث من السيرفر (${pct}%)`,
              });
            }
          }
        });
        stream.once("error", (err) => {
          releaseSlotOnce();
          console.error(
            `[UpdateController] Stream error for ${req.params.id}:`,
            err.message,
          );
          if (!res.headersSent) {
            res.status(500).end();
          }
          destroyStreams();
        });
        if (limiter) {
          limiter.once("error", () => {
            releaseSlotOnce();
            destroyStreams();
          });
        }
        res.once("close", destroyStreams);
        res.once("error", () => {
          releaseSlotOnce();
          destroyStreams();
        });
        if (limiter) {
          stream.pipe(limiter).pipe(res);
        } else {
          stream.pipe(res);
        }
      }
    })
    .catch(next);
};

const checkMobileUpdates = asyncHandler(async (req, res) => {
  const result = await checkForMobileUpdates(
    req.user,
    req.body || {},
    getRequestBaseUrl(req),
  );
  res.status(200).json({
    success: true,
    data: result,
  });
});

const listAuthenticatedBranchPeers = asyncHandler(async (req, res) => {
  const result = await listBranchPeerDevices(req.user, {
    branchCode: req.query.branchCode,
    userId: req.query.userId,
    includeSelf: req.query.includeSelf === "true",
  });
  res.status(200).json({
    success: true,
    data: result,
  });
});

const listManagedDevices = asyncHandler(async (req, res) => {
  const result = await listDevices({
    search: req.query.search,
    status: req.query.status,
    platform: req.query.platform,
    branchCode: req.query.branchCode,
    page: req.query.page,
    limit: req.query.limit,
  });
  res.status(200).json({
    success: true,
    data: result,
  });
});

const toggleManagedDevice = asyncHandler(async (req, res) => {
  const device = await updateDeviceActiveState(
    req.user,
    req.params.id,
    req.body.isActive === true,
  );
  res.status(200).json({
    success: true,
    data: { device },
  });
});

const createManagedRelease = asyncHandler(async (req, res) => {
  const release = await createRelease(
    req.user,
    req.body || {},
    req.file || null,
  );
  emitUpdatesUpdated(req, {
    action: "release_created",
    releaseId: release.id,
    platform: release.platform,
    channel: release.channel,
    version: release.version,
    mandatory: release.mandatory === true,
  });
  res.status(201).json({
    success: true,
    data: { release },
    message: "Release created successfully.",
  });
});

const listManagedReleases = asyncHandler(async (req, res) => {
  const releases = await listReleases();
  res.status(200).json({
    success: true,
    data: { releases },
  });
});

const patchManagedRelease = asyncHandler(async (req, res) => {
  const release = await updateRelease(req.user, req.params.id, req.body || {});
  emitUpdatesUpdated(req, {
    action: "release_updated",
    releaseId: release.id,
    platform: release.platform,
    channel: release.channel,
    version: release.version,
    mandatory: release.mandatory === true,
    isEnabled: release.isEnabled !== false,
  });
  res.status(200).json({
    success: true,
    data: { release },
  });
});

const removeManagedRelease = asyncHandler(async (req, res) => {
  const result = await pruneDisabledReleaseArtifact(req.user, req.params.id);
  emitUpdatesUpdated(req, {
    action: "release_deleted",
    releaseId: req.params.id,
  });
  res.status(200).json({
    success: true,
    data: result,
  });
});

const createManagedUpdateJob = asyncHandler(async (req, res) => {
  const result = await createUpdateJob(req.user, req.body || {});
  emitUpdatesUpdated(req, {
    action: "job_created",
    jobId: result.job?.id,
    releaseId: result.job?.releaseId,
    releaseVersion: result.job?.releaseVersion,
    platform: result.job?.platform,
    targetType: result.job?.targetType,
    targetCount: result.targetCount ?? 0,
  });
  emitUpdateTelemetry(req, {
    action: "job_created",
    jobId: result.job?.id,
    releaseId: result.job?.releaseId,
    releaseVersion: result.job?.releaseVersion,
    platform: result.job?.platform,
    targetType: result.job?.targetType,
    targetCount: result.targetCount ?? 0,
  });
  res.status(201).json({
    success: true,
    data: result,
    message: "Update job created successfully.",
  });
});

const listManagedUpdateJobs = asyncHandler(async (req, res) => {
  const result = await listUpdateJobs({
    page: req.query.page,
    limit: req.query.limit,
  });
  res.status(200).json({
    success: true,
    data: result,
  });
});

const getManagedUpdateJob = asyncHandler(async (req, res) => {
  const result = await getUpdateJobDetails(req.params.id, {
    tasksLimit: req.query.tasksLimit,
  });
  res.status(200).json({
    success: true,
    data: result,
  });
});

const cancelManagedUpdateJob = asyncHandler(async (req, res) => {
  const job = await cancelUpdateJob(req.user, req.params.id);
  emitUpdatesUpdated(req, {
    action: "job_cancelled",
    jobId: job.id,
    releaseId: job.releaseId,
    releaseVersion: job.releaseVersion,
    platform: job.platform,
  });
  emitUpdateTelemetry(req, {
    action: "job_cancelled",
    jobId: job.id,
    releaseId: job.releaseId,
    releaseVersion: job.releaseVersion,
    platform: job.platform,
  });
  res.status(200).json({
    success: true,
    data: { job },
  });
});

const cancelAllManagedUpdates = asyncHandler(async (req, res) => {
  const result = await cancelAllActiveUpdates(req.user);
  emitUpdatesUpdated(req, {
    action: "all_updates_cancelled",
    ...result,
  });
  emitUpdateTelemetry(req, {
    action: "all_updates_cancelled",
    ...result,
  });
  res.status(200).json({
    success: true,
    data: result,
    message: "All active update jobs, tasks, and pulling states were successfully cancelled.",
  });
});

module.exports = {
  heartbeatDevice,
  reportTaskState,
  downloadReleaseArtifact,
  checkMobileUpdates,
  listAuthenticatedBranchPeers,
  listManagedDevices,
  toggleManagedDevice,
  createManagedRelease,
  listManagedReleases,
  patchManagedRelease,
  removeManagedRelease,
  createManagedUpdateJob,
  listManagedUpdateJobs,
  getManagedUpdateJob,
  cancelManagedUpdateJob,
  cancelAllManagedUpdates,
  emitUpdateTelemetry,
  emitUpdatesUpdated,
  _downloadAdmission: {
    extractBranchDownloadBucket,
    tryAcquireDownloadSlot,
    releaseDownloadSlot,
    resetDownloadSlots,
    getActiveDownloadStats,
    createByteRateLimiter,
  },
};
