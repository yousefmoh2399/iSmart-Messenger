const fs = require("fs/promises");
const fsSync = require("fs");
const path = require("path");
const crypto = require("crypto");
const mongoose = require("mongoose");
const jwt = require("jsonwebtoken");
const ApiError = require("../../utils/api-error");
const { baseUrl } = require("../../config/env");
const { jwtSecret } = require("../../config/env");
const { getRedisClient } = require("../../config/redis");
const { logAuditEvent } = require("../../chat/services/audit.service");
const UpdateDevice = require("./device.model");
const UpdateRelease = require("./release.model");
const UpdateJob = require("./update-job.model");
const UpdateTask = require("./update-task.model");
const { resolveStoredUpdateReleasePath } = require("../../utils/storage-paths");

const ONLINE_WINDOW_MS = 90 * 1000;
const BRANCH_PEER_ACTIVE_WINDOW_MS = 24 * 60 * 60 * 1000;

const TASK_STATUS_FLOW = new Set([
  "pending",
  "acknowledged",
  "downloading",
  "installing",
  "completed",
  "failed",
  "cancelled",
]);

const ACTIVE_TASK_STATUSES = ["acknowledged", "downloading", "installing"];
const MAX_TASK_ATTEMPTS = 3;
const PROGRESS_EVENT_MIN_INTERVAL_MS = 2000;
const PROGRESS_SIGNIFICANT_DELTA = 5;
const PROGRESS_THROTTLE_TTL_MS = 5 * 60 * 1000;
const progressThrottleState = new Map();
const redis = getRedisClient();

function progressThrottleRedisKey(throttleKey) {
  return `progress_throttle:${throttleKey}`;
}

async function readProgressThrottle(throttleKey) {
  if (!redis) {
    return progressThrottleState.get(throttleKey) || null;
  }
  try {
    const raw = await redis.get(progressThrottleRedisKey(throttleKey));
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object") return null;
    return parsed;
  } catch (_) {
    return progressThrottleState.get(throttleKey) || null;
  }
}

async function writeProgressThrottle(throttleKey, value) {
  if (!redis) {
    progressThrottleState.set(throttleKey, value);
  } else {
    try {
      await redis.set(
        progressThrottleRedisKey(throttleKey),
        JSON.stringify(value),
        "EX",
        Math.ceil(PROGRESS_THROTTLE_TTL_MS / 1000),
      );
    } catch (_) {
      progressThrottleState.set(throttleKey, value);
    }
  }

  if (progressThrottleState.size > 5000) {
    const nowMs = Date.now();
    for (const [entryKey, entry] of progressThrottleState.entries()) {
      if (nowMs - Number(entry?.at || 0) > PROGRESS_THROTTLE_TTL_MS) {
        progressThrottleState.delete(entryKey);
      }
    }
  }
}

function nowIso() {
  return new Date().toISOString();
}

function normalizeBranchCode(value) {
  const raw = String(value || "")
    .trim()
    .toLowerCase();
  if (!raw) {
    return "main";
  }
  return raw.slice(0, 80);
}

function normalizeChannel(value) {
  const raw = String(value || "")
    .trim()
    .toLowerCase();
  if (!raw) return "stable";
  if (["stable", "beta", "alpha", "internal"].includes(raw)) {
    return raw;
  }
  return "stable";
}

function normalizeVersion(value) {
  return String(value || "")
    .trim()
    .toLowerCase();
}

function normalizeLocalIp(value) {
  let raw = String(value || "").trim();
  if (!raw) {
    return null;
  }
  try {
    const parsed = new URL(raw);
    if (parsed.hostname) {
      raw = parsed.hostname.trim();
    }
  } catch (_) {}
  if (raw.startsWith("[") && raw.endsWith("]")) {
    raw = raw.slice(1, -1).trim();
  }
  const zoneIndex = raw.indexOf("%");
  if (zoneIndex >= 0) {
    raw = raw.slice(0, zoneIndex).trim();
  }
  if (raw.startsWith("::ffff:")) {
    raw = raw.slice("::ffff:".length).trim();
  } else if (raw.startsWith("=ffff:")) {
    raw = raw.slice("=ffff:".length).trim();
  }
  const ipv4Match = raw.match(/(?:\d{1,3}\.){3}\d{1,3}/);
  if (ipv4Match && ipv4Match[0]) {
    return ipv4Match[0].trim();
  }
  return raw || null;
}

function normalizePlatform(value, fallback = "desktop_windows") {
  const raw = String(value || "")
    .trim()
    .toLowerCase();
  if (raw === "mobile" || raw === "android" || raw === "mobile_android") {
    return "mobile_android";
  }
  if (raw === "desktop" || raw === "windows" || raw === "desktop_windows") {
    return "desktop_windows";
  }
  return fallback;
}

function inferInstallerKind(fileName) {
  const ext = path.extname(String(fileName || "")).toLowerCase();
  if (ext === ".msi") return "msi";
  if (ext === ".exe") return "exe";
  if (ext === ".zip") return "zip";
  if (ext === ".apk") return "apk";
  return "unknown";
}

function validateDesktopInstallerKind(platform, installerKind) {
  if (
    normalizePlatform(platform) === "desktop_windows" &&
    !["msi", "exe", "zip"].includes(
      String(installerKind || "").trim().toLowerCase(),
    )
  ) {
    throw new ApiError(
      400,
      "تحديثات ويندوز تتطلب ZIP أو MSI أو setup EXE حقيقي. الأفضل استخدام ZIP للتحديث الصامت.",
    );
  }
}

function inferPlatformFromFileName(fileName) {
  const ext = path.extname(String(fileName || "")).toLowerCase();
  if (ext === ".apk") {
    return "mobile_android";
  }
  return "desktop_windows";
}

function clampNumber(value, min, max, fallback) {
  const asNumber = Number(value);
  if (!Number.isFinite(asNumber)) {
    return fallback;
  }
  return Math.max(min, Math.min(max, asNumber));
}

function isDeviceOnline(lastHeartbeatAt) {
  if (!lastHeartbeatAt) {
    return false;
  }
  return Date.now() - new Date(lastHeartbeatAt).getTime() <= ONLINE_WINDOW_MS;
}

function toObjectId(value, fieldName) {
  if (!mongoose.Types.ObjectId.isValid(value)) {
    throw new ApiError(400, `Invalid ${fieldName}.`);
  }
  return new mongoose.Types.ObjectId(value);
}

async function calculateSha256(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash("sha256");
    const stream = fsSync.createReadStream(filePath);
    stream.on("error", reject);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve(hash.digest("hex")));
  });
}

function findExistingReleaseArtifactPath(storedPath) {
  const candidates = [
    String(storedPath || "").trim(),
    resolveStoredUpdateReleasePath(storedPath),
  ].filter(Boolean);
  for (const candidate of [...new Set(candidates)]) {
    if (fsSync.existsSync(candidate)) {
      return candidate;
    }
  }
  return candidates[0] || null;
}

function releaseDownloadPath(releaseId) {
  return `/api/updates/releases/${releaseId}/download`;
}

function signReleaseDownloadToken({ releaseId, taskId, deviceUid }) {
  return jwt.sign(
    {
      type: "update_release_download",
      rid: String(releaseId || ""),
      tid: String(taskId || ""),
      did: String(deviceUid || ""),
    },
    jwtSecret,
    { expiresIn: "6h" },
  );
}

function verifyReleaseDownloadToken(token) {
  try {
    const payload = jwt.verify(String(token || ""), jwtSecret);
    if (payload?.type !== "update_release_download") {
      return null;
    }
    return payload;
  } catch (_) {
    return null;
  }
}

function resolveReleaseBaseUrl(providedBaseUrl) {
  const rawBaseUrl = String(providedBaseUrl || baseUrl || "").trim();
  return rawBaseUrl.replace(/\/+$/, "");
}

function serializeRelease(
  release,
  { includeDownloadUrl = true, baseUrlOverride, downloadToken } = {},
) {
  if (!release) {
    return null;
  }
  const resolvedBaseUrl = resolveReleaseBaseUrl(baseUrlOverride);
  const item = {
    id: release._id.toString(),
    version: release.version,
    buildNumber: release.buildNumber || null,
    channel: release.channel,
    platform: normalizePlatform(release.platform),
    notes: release.notes || "",
    mandatory: release.mandatory === true,
    isEnabled: release.isEnabled !== false,
    installerKind: release.installerKind || "unknown",
    packageType: release.packageType || "full",
    packageLayout: release.packageLayout || "bundle_zip",
    entryExecutable: release.entryExecutable || "iSmartMessenger.exe",
    minSupportedVersion: release.minSupportedVersion || null,
    targetArchitecture: release.targetArchitecture || "x64",
    minWindowsBuild: release.minWindowsBuild || null,
    rolloutPercentage: clampNumber(release.rolloutPercentage, 1, 100, 100),
    silentInstallArgs: release.silentInstallArgs || "",
    checksumSha256: release.checksumSha256 || null,
    fileName: release.fileName || null,
    fileSize: release.fileSize || 0,
    mimeType: release.mimeType || null,
    externalDownloadUrl: release.externalDownloadUrl || null,
    hasArtifact:
      Boolean(release.externalDownloadUrl) || Boolean(release.filePath),
    createdAt: release.createdAt?.toISOString?.() || null,
    updatedAt: release.updatedAt?.toISOString?.() || null,
    publishedAt: release.publishedAt?.toISOString?.() || null,
  };
  if (includeDownloadUrl) {
    item.downloadPath = releaseDownloadPath(item.id);
    item.downloadUrl = `${resolvedBaseUrl}${item.downloadPath}${
      downloadToken ? `?token=${encodeURIComponent(downloadToken)}` : ""
    }`;
  }
  item.manifest = {
    schemaVersion: 1,
    version: item.version,
    buildNumber: item.buildNumber,
    releaseNotes: item.notes,
    required: item.mandatory,
    minSupportedVersion: item.minSupportedVersion,
    packageUrl: item.downloadUrl || item.externalDownloadUrl || null,
    packageSize: item.fileSize,
    sha256: item.checksumSha256,
    packageType: item.packageType,
    packageLayout: item.packageLayout,
    targetChannel: item.channel,
    targetPlatform: item.platform,
    targetArchitecture: item.targetArchitecture,
    minWindowsBuild: item.minWindowsBuild,
    entryExecutable: item.entryExecutable,
    rollout: {
      percentage: item.rolloutPercentage,
    },
    createdAt: item.createdAt,
    publishedAt: item.publishedAt,
  };
  return item;
}

function serializeDevice(device) {
  if (!device) {
    return null;
  }
  const online = isDeviceOnline(device.lastHeartbeatAt);
  return {
    id: device._id.toString(),
    deviceUid: device.deviceUid,
    deviceName: device.deviceName || null,
    hostName: device.hostName || null,
    localIp: normalizeLocalIp(device.localIp),
    branchCode: device.branchCode || "main",
    channel: device.channel || "stable",
    platform: normalizePlatform(device.platform),
    appVersion: device.appVersion || "unknown",
    osName: device.osName || null,
    osVersion: device.osVersion || null,
    architecture: device.architecture || null,
    localIp: normalizeLocalIp(device.localIp),
    connectionStatus: online ? device.connectionStatus || "online" : "offline",
    isOnline: online,
    isActive: device.isActive !== false,
    lastKnownUserId: device.lastKnownUserId?.toString?.() || null,
    lastKnownUsername: device.lastKnownUsername || null,
    lastKnownFullName: device.lastKnownFullName || null,
    lastHeartbeatAt: device.lastHeartbeatAt?.toISOString?.() || null,
    lastSeenAt: device.lastSeenAt?.toISOString?.() || null,
    updateState: {
      status: device.updateState?.status || "idle",
      targetVersion: device.updateState?.targetVersion || null,
      progress: clampNumber(device.updateState?.progress, 0, 100, 0),
      lastError: device.updateState?.lastError || null,
      currentTaskId: device.updateState?.currentTaskId?.toString?.() || null,
      updatedAt: device.updateState?.updatedAt?.toISOString?.() || null,
    },
    capabilities: {
      autoUpdate: device.capabilities?.autoUpdate !== false,
      silentInstall: device.capabilities?.silentInstall !== false,
    },
    createdAt: device.createdAt?.toISOString?.() || null,
    updatedAt: device.updatedAt?.toISOString?.() || null,
  };
}

function deviceAlreadyHasVersion(deviceVersion, targetVersion) {
  const current = String(deviceVersion || "").trim();
  const target = String(targetVersion || "").trim();
  if (!current || !target || current === "unknown") {
    return false;
  }
  return compareVersions(current, target) >= 0;
}

function serializeTask(task, release = null, { baseUrlOverride } = {}) {
  const releaseDoc = release || task.releaseId;
  const downloadToken =
    releaseDoc && task?._id && task?.deviceUid
      ? signReleaseDownloadToken({
          releaseId: releaseDoc._id || releaseDoc.id,
          taskId: task._id,
          deviceUid: task.deviceUid,
        })
      : null;
  return {
    id: task._id.toString(),
    jobId: task.jobId?.toString?.() || null,
    deviceId: task.deviceId?.toString?.() || null,
    deviceUid: task.deviceUid,
    releaseId:
      task.releaseId?._id?.toString?.() || task.releaseId?.toString?.(),
    releaseVersion: task.releaseVersion,
    platform: normalizePlatform(task.platform),
    status: task.status,
    progress: task.progress || 0,
    message: task.message || null,
    lastError: task.lastError || null,
    attempts: task.attempts || 0,
    requestedAt: task.requestedAt?.toISOString?.() || null,
    acknowledgedAt: task.acknowledgedAt?.toISOString?.() || null,
    completedAt: task.completedAt?.toISOString?.() || null,
    updatedAt: task.updatedAt?.toISOString?.() || null,
    release: releaseDoc
      ? serializeRelease(releaseDoc, { baseUrlOverride, downloadToken })
      : null,
  };
}

function serializeJob(job) {
  if (!job) {
    return null;
  }
  return {
    id: job._id.toString(),
    releaseId:
      job.releaseId?._id?.toString?.() || job.releaseId?.toString?.() || null,
    releaseVersion: job.releaseVersion,
    platform: normalizePlatform(job.platform),
    targetType: job.targetType,
    targetBranches: job.targetBranches || [],
    targetDeviceIds: (job.targetDeviceIds || []).map(
      (id) => id?._id?.toString?.() || id?.toString?.(),
    ),
    status: job.status,
    stats: {
      total: job.stats?.total || 0,
      pending: job.stats?.pending || 0,
      acknowledged: job.stats?.acknowledged || 0,
      downloading: job.stats?.downloading || 0,
      installing: job.stats?.installing || 0,
      completed: job.stats?.completed || 0,
      failed: job.stats?.failed || 0,
      cancelled: job.stats?.cancelled || 0,
    },
    note: job.note || "",
    scheduledAt: job.scheduledAt?.toISOString?.() || null,
    startedAt: job.startedAt?.toISOString?.() || null,
    finishedAt: job.finishedAt?.toISOString?.() || null,
    createdAt: job.createdAt?.toISOString?.() || null,
    updatedAt: job.updatedAt?.toISOString?.() || null,
  };
}

async function recalculateJobStats(jobId) {
  const grouped = await UpdateTask.aggregate([
    { $match: { jobId: toObjectId(jobId, "jobId") } },
    { $group: { _id: "$status", count: { $sum: 1 } } },
  ]);

  const stats = {
    total: 0,
    pending: 0,
    acknowledged: 0,
    downloading: 0,
    installing: 0,
    completed: 0,
    failed: 0,
    cancelled: 0,
  };

  for (const entry of grouped) {
    const key = String(entry._id || "");
    const value = Number(entry.count || 0);
    if (Object.prototype.hasOwnProperty.call(stats, key)) {
      stats[key] = value;
      stats.total += value;
    }
  }

  let status = "running";
  const activeCount =
    stats.pending + stats.acknowledged + stats.downloading + stats.installing;
  if (stats.total === 0) {
    status = "cancelled";
  } else if (activeCount > 0) {
    status = "running";
  } else if (stats.failed > 0 && stats.completed > 0) {
    status = "partial_failed";
  } else if (stats.failed > 0 && stats.completed === 0) {
    status = "failed";
  } else if (stats.completed + stats.cancelled === stats.total) {
    status = stats.completed > 0 ? "completed" : "cancelled";
  } else if (stats.completed === stats.total) {
    status = "completed";
  }

  const terminalStatuses = new Set([
    "completed",
    "partial_failed",
    "failed",
    "cancelled",
  ]);

  const patch = {
    status,
    stats,
  };
  if (status === "running") {
    patch.startedAt = new Date();
    patch.finishedAt = null;
  } else if (terminalStatuses.has(status)) {
    patch.finishedAt = new Date();
  }

  await UpdateJob.findByIdAndUpdate(jobId, patch, { new: false });
}

async function registerDeviceHeartbeat(actor, payload = {}, requestMeta = {}) {
  const deviceUid = String(payload.deviceUid || "")
    .trim()
    .slice(0, 160);
  if (!deviceUid) {
    throw new ApiError(400, "deviceUid is required.");
  }

  const platform = normalizePlatform(payload.platform);
  const appVersion =
    String(payload.appVersion || "")
      .trim()
      .slice(0, 80) || "unknown";

  console.log(
    `[UpdateService] registerDeviceHeartbeat: uid=${deviceUid}, version=${appVersion}, platform=${platform}`,
  );

  const now = new Date();
  const connectionStatus =
    payload.connectionStatus === "idle"
      ? "idle"
      : payload.connectionStatus === "meeting"
        ? "meeting"
        : payload.connectionStatus === "lunch"
          ? "lunch"
          : payload.connectionStatus === "offline"
            ? "offline"
            : "online";

  const branchCode = normalizeBranchCode(
    payload.branchCode || actor.branchCode || "main",
  );
  const channel = normalizeChannel(payload.channel);
  const localIp =
    normalizeLocalIp(payload.localIp) || normalizeLocalIp(requestMeta.ip);

  const device = await UpdateDevice.findOneAndUpdate(
    { deviceUid },
    {
      $set: {
        deviceName:
          String(payload.deviceName || "")
            .trim()
            .slice(0, 160) || null,
        hostName:
          String(payload.hostName || "")
            .trim()
            .slice(0, 160) || null,
        branchCode,
        channel,
        platform,
        appVersion,
        osName:
          String(payload.osName || "")
            .trim()
            .slice(0, 80) || null,
        osVersion:
          String(payload.osVersion || "")
            .trim()
            .slice(0, 120) || null,
        architecture:
          String(payload.architecture || "")
            .trim()
            .slice(0, 80) || null,
        localIp,
        connectionStatus,
        lastKnownUserId: actor.id,
        lastKnownUsername: actor.username || null,
        lastKnownFullName: actor.fullName || null,
        "capabilities.autoUpdate": payload.capabilities?.autoUpdate !== false,
        "capabilities.silentInstall":
          payload.capabilities?.silentInstall !== false,
        lastHeartbeatAt: now,
        lastSeenAt: now,
      },
      $setOnInsert: {
        updateState: {
          status: "idle",
          progress: 0,
          updatedAt: now,
        },
      },
    },
    {
      new: true,
      upsert: true,
      setDefaultsOnInsert: true,
    },
  );

  let activeTask = await UpdateTask.findOne({
    deviceId: device._id,
    status: { $in: ACTIVE_TASK_STATUSES },
  })
    .sort({ updatedAt: -1, createdAt: -1 })
    .populate("releaseId");

  const failTask = async (task, message) => {
    task.status = "failed";
    task.completedAt = now;
    task.lastError = message;
    task.message = message;
    task.logs.push({
      status: "failed",
      progress: task.progress || 0,
      message,
      at: now,
    });
    await task.save();

    device.updateState = {
      status: "failed",
      currentTaskId: task._id,
      targetVersion: task.releaseVersion,
      progress: task.progress || 0,
      lastError: message,
      updatedAt: now,
    };
    await device.save();
    await recalculateJobStats(task.jobId);
  };

  const completeTaskForCurrentVersion = async (task, message) => {
    const completedAt = new Date();
    task.status = "completed";
    task.progress = 100;
    task.completedAt = completedAt;
    task.message = message;
    task.lastError = null;
    task.logs.push({
      status: "completed",
      progress: 100,
      message,
      at: completedAt,
    });
    await task.save();

    device.updateState = {
      status: "completed",
      currentTaskId: task._id,
      targetVersion: task.releaseVersion,
      progress: 100,
      lastError: null,
      updatedAt: completedAt,
    };
    await device.save();
    await recalculateJobStats(task.jobId);
  };

  if (activeTask && (activeTask.attempts || 0) >= MAX_TASK_ATTEMPTS) {
    await failTask(
      activeTask,
      `Exceeded maximum retry attempts (${MAX_TASK_ATTEMPTS}).`,
    );
    activeTask = null;
  }

  if (
    activeTask &&
    deviceAlreadyHasVersion(payload.appVersion, activeTask.releaseVersion)
  ) {
    await completeTaskForCurrentVersion(
      activeTask,
      activeTask.message || "Update completed after client restarted.",
    );
    activeTask = null;
  }

  if (
    activeTask &&
    activeTask.status === "installing" &&
    !deviceAlreadyHasVersion(payload.appVersion, activeTask.releaseVersion)
  ) {
    await failTask(
      activeTask,
      "فشل تحديث ويندوز تلقائيًا لأن الملف المرفوع ليس حزمة تثبيت صالحة أو لأن المثبت لم يغير إصدار التطبيق. استخدم MSI أو setup EXE صامت حقيقي.",
    );
    activeTask = null;
  }

  let pendingTasks = [];
  if (activeTask) {
    pendingTasks = [activeTask];
  } else {
    pendingTasks = await UpdateTask.find({
      deviceId: device._id,
      status: "pending",
    })
      .sort({ createdAt: 1 })
      .limit(3)
      .populate("releaseId");
  }

  if (pendingTasks.length > 0) {
    const validTasks = [];
    for (const task of pendingTasks) {
      if ((task.attempts || 0) >= MAX_TASK_ATTEMPTS) {
        await failTask(
          task,
          `Exceeded maximum retry attempts (${MAX_TASK_ATTEMPTS}).`,
        );
        continue;
      }
      if (deviceAlreadyHasVersion(payload.appVersion, task.releaseVersion)) {
        await completeTaskForCurrentVersion(
          task,
          "Skipped because this device is already on the target version.",
        );
        continue;
      }
      validTasks.push(task);
    }
    pendingTasks = validTasks;
  }

  const baseUrlOverride = requestMeta.baseUrlOverride;

  return {
    device: serializeDevice(device),
    pendingTasks: pendingTasks.map((task) =>
      serializeTask(task, task.releaseId, { baseUrlOverride }),
    ),
    heartbeatIntervalSeconds: 30,
    serverTime: nowIso(),
  };
}

async function listDevices({
  search = "",
  status = "all",
  platform = "",
  branchCode = "",
  page = 1,
  limit = 50,
}) {
  const safeLimit = clampNumber(limit, 1, 200, 50);
  const safePage = clampNumber(page, 1, 100000, 1);
  const query = {};

  if (branchCode) {
    query.branchCode = normalizeBranchCode(branchCode);
  }
  const normalizedPlatform = String(platform || "").trim();
  if (normalizedPlatform) {
    query.platform = normalizePlatform(normalizedPlatform);
  }

  const trimmedSearch = String(search || "").trim();
  if (trimmedSearch) {
    const regex = new RegExp(
      trimmedSearch.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
      "i",
    );
    query.$or = [
      { deviceUid: regex },
      { deviceName: regex },
      { hostName: regex },
      { lastKnownUsername: regex },
      { lastKnownFullName: regex },
      { appVersion: regex },
      { branchCode: regex },
    ];
  }

  const heartbeatCutoff = new Date(Date.now() - BRANCH_PEER_ACTIVE_WINDOW_MS);
  if (status === "online") {
    query.lastHeartbeatAt = { $gte: heartbeatCutoff };
  } else if (status === "offline") {
    query.$and = [
      ...(query.$and || []),
      {
        $or: [
          { lastHeartbeatAt: { $lt: heartbeatCutoff } },
          { lastHeartbeatAt: null },
        ],
      },
    ];
  }

  const [items, total] = await Promise.all([
    UpdateDevice.find(query)
      .sort({ lastHeartbeatAt: -1, updatedAt: -1 })
      .skip((safePage - 1) * safeLimit)
      .limit(safeLimit)
      .lean(),
    UpdateDevice.countDocuments(query),
  ]);

  const versionSummaryRaw = await UpdateDevice.find(query, {
    appVersion: 1,
    lastHeartbeatAt: 1,
  }).lean();
  const byVersion = new Map();
  for (const item of versionSummaryRaw) {
    const version = String(item.appVersion || "unknown");
    const current = byVersion.get(version) || { version, total: 0, online: 0 };
    current.total += 1;
    if (isDeviceOnline(item.lastHeartbeatAt)) {
      current.online += 1;
    }
    byVersion.set(version, current);
  }

  return {
    items: items.map((item) => serializeDevice(item)),
    page: safePage,
    limit: safeLimit,
    total,
    versionSummary: [...byVersion.values()].sort((a, b) =>
      a.version.localeCompare(b.version),
    ),
  };
}

async function updateDeviceActiveState(actor, deviceId, isActive) {
  const device = await UpdateDevice.findByIdAndUpdate(
    toObjectId(deviceId, "device id"),
    {
      $set: {
        isActive: isActive === true,
      },
    },
    { new: true },
  );

  if (!device) {
    throw new ApiError(404, "Device not found.");
  }

  await logAuditEvent({
    actorId: actor.id,
    action: "admin.update.device.toggle",
    entityType: "update-device",
    entityId: device._id.toString(),
    payload: {
      deviceUid: device.deviceUid,
      isActive: device.isActive,
    },
  });

  return serializeDevice(device);
}

async function createRelease(actor, payload = {}, artifactFile = null) {
  const version = String(payload.version || "")
    .trim()
    .slice(0, 120);
  if (!version) {
    throw new ApiError(400, "version is required.");
  }

  const channel = normalizeChannel(payload.channel);
  const buildNumber =
    String(payload.buildNumber || "")
      .trim()
      .slice(0, 80) || null;
  const platform = normalizePlatform(
    payload.platform,
    artifactFile
      ? inferPlatformFromFileName(
          artifactFile.originalname || artifactFile.filename,
        )
      : "desktop_windows",
  );
  const notes = String(payload.notes || "")
    .trim()
    .slice(0, 6000);
  const mandatory = payload.mandatory === true;
  const isEnabled = payload.isEnabled !== false;
  const externalDownloadUrl =
    String(payload.externalDownloadUrl || "")
      .trim()
      .slice(0, 2000) || null;

  if (!artifactFile && !externalDownloadUrl) {
    throw new ApiError(
      400,
      "Release artifact is required (upload file or provide externalDownloadUrl).",
    );
  }

  const checksumSha256Provided =
    String(payload.checksumSha256 || "")
      .trim()
      .toLowerCase() || null;

  let checksumSha256 = checksumSha256Provided;
  let fileName = null;
  let filePath = null;
  let fileSize = 0;
  let mimeType = null;
  let installerKind = "unknown";

  if (artifactFile) {
    fileName =
      artifactFile.originalname || artifactFile.filename || "artifact.bin";
    filePath = artifactFile.path;
    fileSize = Number(artifactFile.size || 0);
    mimeType = artifactFile.mimetype || "application/octet-stream";
    installerKind = inferInstallerKind(fileName);
    if (!checksumSha256) {
      checksumSha256 = await calculateSha256(filePath);
    }
  }

  if (!artifactFile && externalDownloadUrl) {
    installerKind = inferInstallerKind(externalDownloadUrl);
  }

  const resolvedInstallerKind =
    payload.installerKind &&
    ["msi", "exe", "zip", "apk", "unknown"].includes(payload.installerKind)
      ? payload.installerKind
      : installerKind;

  const packageType =
    payload.packageType === "delta" ? "delta" : "full";
  const packageLayout =
    payload.packageLayout === "installer"
      ? "installer"
      : payload.packageLayout === "apk"
        ? "apk"
        : "bundle_zip";
  const entryExecutable =
    String(payload.entryExecutable || "")
      .trim()
      .slice(0, 260) || "iSmartMessenger.exe";
  const minSupportedVersion =
    String(payload.minSupportedVersion || "")
      .trim()
      .slice(0, 120) || null;
  const targetArchitecture =
    String(payload.targetArchitecture || "")
      .trim()
      .toLowerCase()
      .slice(0, 40) || "x64";
  const minWindowsBuild =
    String(payload.minWindowsBuild || "")
      .trim()
      .slice(0, 80) || null;
  const rolloutPercentage = clampNumber(payload.rolloutPercentage, 1, 100, 100);

  validateDesktopInstallerKind(platform, resolvedInstallerKind);

  const release = await UpdateRelease.create({
    version,
    buildNumber,
    channel,
    notes,
    mandatory,
    isEnabled,
    platform,
    installerKind: resolvedInstallerKind,
    packageType,
    packageLayout,
    entryExecutable,
    minSupportedVersion,
    targetArchitecture,
    minWindowsBuild,
    rolloutPercentage,
    silentInstallArgs: String(payload.silentInstallArgs || "")
      .trim()
      .slice(0, 1200),
    checksumSha256,
    externalDownloadUrl,
    fileName,
    filePath,
    fileSize,
    mimeType,
    createdBy: actor.id,
    publishedAt: isEnabled ? new Date() : null,
  });

  await logAuditEvent({
    actorId: actor.id,
    action: "admin.update.release.create",
    entityType: "update-release",
    entityId: release._id.toString(),
    payload: {
      version: release.version,
      buildNumber: release.buildNumber,
      channel: release.channel,
      platform: release.platform,
      mandatory: release.mandatory,
      isEnabled: release.isEnabled,
      packageType: release.packageType,
      hasArtifact: Boolean(release.filePath || release.externalDownloadUrl),
    },
  });

  return serializeRelease(release);
}

async function listReleases() {
  const releases = await UpdateRelease.find({}).sort({ createdAt: -1 }).lean();
  return releases.map((entry) => serializeRelease(entry));
}

async function updateRelease(actor, releaseId, payload = {}) {
  const patch = {};

  if (typeof payload.notes === "string") {
    patch.notes = payload.notes.trim().slice(0, 6000);
  }
  if (typeof payload.mandatory === "boolean") {
    patch.mandatory = payload.mandatory;
  }
  if (typeof payload.isEnabled === "boolean") {
    patch.isEnabled = payload.isEnabled;
    patch.publishedAt = payload.isEnabled ? new Date() : null;
  }
  if (typeof payload.silentInstallArgs === "string") {
    patch.silentInstallArgs = payload.silentInstallArgs.trim().slice(0, 1200);
  }
  if (typeof payload.channel === "string") {
    patch.channel = normalizeChannel(payload.channel);
  }
  if (typeof payload.buildNumber === "string") {
    patch.buildNumber = payload.buildNumber.trim().slice(0, 80) || null;
  }
  if (typeof payload.packageType === "string") {
    patch.packageType = payload.packageType === "delta" ? "delta" : "full";
  }
  if (typeof payload.packageLayout === "string") {
    patch.packageLayout =
      payload.packageLayout === "installer"
        ? "installer"
        : payload.packageLayout === "apk"
          ? "apk"
          : "bundle_zip";
  }
  if (typeof payload.entryExecutable === "string") {
    patch.entryExecutable =
      payload.entryExecutable.trim().slice(0, 260) || "iSmartMessenger.exe";
  }
  if (typeof payload.minSupportedVersion === "string") {
    patch.minSupportedVersion =
      payload.minSupportedVersion.trim().slice(0, 120) || null;
  }
  if (typeof payload.targetArchitecture === "string") {
    patch.targetArchitecture =
      payload.targetArchitecture.trim().toLowerCase().slice(0, 40) || "x64";
  }
  if (typeof payload.minWindowsBuild === "string") {
    patch.minWindowsBuild = payload.minWindowsBuild.trim().slice(0, 80) || null;
  }
  if (payload.rolloutPercentage !== undefined) {
    patch.rolloutPercentage = clampNumber(payload.rolloutPercentage, 1, 100, 100);
  }

  const release = await UpdateRelease.findByIdAndUpdate(
    toObjectId(releaseId, "release id"),
    { $set: patch },
    { new: true },
  );
  if (!release) {
    throw new ApiError(404, "Release not found.");
  }

  await logAuditEvent({
    actorId: actor.id,
    action: "admin.update.release.update",
    entityType: "update-release",
    entityId: release._id.toString(),
    payload: patch,
  });

  return serializeRelease(release);
}

async function resolveTargetDevices(
  targetType,
  releasePlatform,
  targetBranches = [],
  targetDeviceIds = [],
) {
  const platform = normalizePlatform(releasePlatform);
  if (targetType === "all") {
    return UpdateDevice.find({ isActive: true, platform }).lean();
  }

  if (targetType === "branch") {
    const branches = [
      ...new Set(targetBranches.map((entry) => normalizeBranchCode(entry))),
    ];
    if (!branches.length) {
      throw new ApiError(
        400,
        "targetBranches is required for targetType=branch.",
      );
    }
    return UpdateDevice.find({
      isActive: true,
      platform,
      branchCode: { $in: branches },
    }).lean();
  }

  if (targetType === "devices") {
    const ids = [...new Set(targetDeviceIds.map((entry) => String(entry)))];
    if (!ids.length) {
      throw new ApiError(
        400,
        "targetDeviceIds is required for targetType=devices.",
      );
    }
    const objectIds = ids.map((id) => toObjectId(id, "targetDeviceIds"));
    return UpdateDevice.find({
      _id: { $in: objectIds },
      isActive: true,
      platform,
    }).lean();
  }

  throw new ApiError(400, "Invalid targetType.");
}

async function createUpdateJob(actor, payload = {}) {
  const releaseId = toObjectId(payload.releaseId, "releaseId");
  const release = await UpdateRelease.findById(releaseId).lean();
  if (!release) {
    throw new ApiError(404, "Release not found.");
  }
  if (release.isEnabled === false) {
    throw new ApiError(400, "Release is disabled.");
  }

  const targetType =
    payload.targetType === "branch"
      ? "branch"
      : payload.targetType === "devices"
        ? "devices"
        : "all";

  const devices = await resolveTargetDevices(
    targetType,
    release.platform,
    payload.targetBranches || [],
    payload.targetDeviceIds || [],
  );

  const excludeDeviceUids = (payload.excludeDeviceUids || [])
    .map((entry) => String(entry || "").trim())
    .filter((entry) => entry);

  const filteredDevices = devices.filter((device) => {
    if (excludeDeviceUids.length && excludeDeviceUids.includes(device.deviceUid)) {
      return false;
    }
    if (deviceAlreadyHasVersion(device.appVersion, release.version)) {
      return false;
    }
    return true;
  });

  if (!filteredDevices.length) {
    throw new ApiError(404, "No target devices found for this update.");
  }

  const now = new Date();
  const job = await UpdateJob.create({
    releaseId: release._id,
    releaseVersion: release.version,
    platform: normalizePlatform(release.platform),
    targetType,
    targetBranches:
      targetType === "branch"
        ? [
            ...new Set(
              (payload.targetBranches || []).map((entry) =>
                normalizeBranchCode(entry),
              ),
            ),
          ]
        : [],
    targetDeviceIds: filteredDevices.map((entry) => entry._id),
    status: "running",
    stats: {
      total: filteredDevices.length,
      pending: filteredDevices.length,
      acknowledged: 0,
      downloading: 0,
      installing: 0,
      completed: 0,
      failed: 0,
      cancelled: 0,
    },
    createdBy: actor.id,
    startedAt: now,
    note: String(payload.note || "")
      .trim()
      .slice(0, 2000),
  });

  const taskDocs = filteredDevices.map((device) => ({
    jobId: job._id,
    releaseId: release._id,
    releaseVersion: release.version,
    deviceId: device._id,
    deviceUid: device.deviceUid,
    deviceName: device.deviceName || device.hostName || "Managed device",
    branchCode: device.branchCode || "main",
    platform: normalizePlatform(
      device.platform,
      normalizePlatform(release.platform),
    ),
    status: "pending",
    progress: 0,
    attempts: 0,
    createdBy: actor.id,
    requestedAt: now,
    logs: [
      { status: "pending", at: now, progress: 0, message: "Queued by admin." },
    ],
  }));

  await UpdateTask.insertMany(taskDocs);

  await UpdateDevice.updateMany(
    { _id: { $in: filteredDevices.map((entry) => entry._id) } },
    {
      $set: {
        "updateState.status": "pending",
        "updateState.targetVersion": release.version,
        "updateState.progress": 0,
        "updateState.currentTaskId": null,
        "updateState.lastError": null,
        "updateState.updatedAt": now,
      },
    },
  );

  await logAuditEvent({
    actorId: actor.id,
    action: "admin.update.job.create",
    entityType: "update-job",
    entityId: job._id.toString(),
    payload: {
      releaseId: release._id.toString(),
      releaseVersion: release.version,
      targetType,
      targetCount: filteredDevices.length,
      targetBranches:
        targetType === "branch"
          ? [
              ...new Set(
                (payload.targetBranches || []).map((entry) =>
                  normalizeBranchCode(entry),
                ),
              ),
            ]
          : [],
    },
  });

  return {
    job: serializeJob(job),
    targetCount: filteredDevices.length,
  };
}

async function listBranchPeerDevices(actor, options = {}) {
  const requestedBranch = normalizeBranchCode(options.branchCode || actor.branchCode);
  const actorBranch = normalizeBranchCode(actor.branchCode);
  const branchCode = actor.role === "admin" ? requestedBranch : actorBranch;
  const targetUserId = String(options.userId || "").trim() || null;
  const includeSelf = options.includeSelf === true;
  const heartbeatCutoff = new Date(Date.now() - BRANCH_PEER_ACTIVE_WINDOW_MS);

  const query = {
    isActive: true,
    platform: "desktop_windows",
    branchCode,
    lastHeartbeatAt: { $gte: heartbeatCutoff },
    localIp: { $nin: [null, ""] },
  };
  if (targetUserId) {
    query.lastKnownUserId = toObjectId(targetUserId, "userId");
  }
  if (!includeSelf) {
    query.lastKnownUserId = {
      ...(query.lastKnownUserId ? { $eq: query.lastKnownUserId } : {}),
      $ne: toObjectId(actor.id, "actor.id"),
    };
  }

  const devices = await UpdateDevice.find(query)
    .sort({ lastHeartbeatAt: -1, updatedAt: -1 })
    .lean();

  const seen = new Set();
  const items = [];
  for (const device of devices) {
    const key = String(device.deviceUid || "");
    if (!key || seen.has(key)) {
      continue;
    }
    seen.add(key);
    items.push({
      id: device._id.toString(),
      deviceUid: device.deviceUid,
      deviceName: device.deviceName || null,
      hostName: device.hostName || null,
      localIp: normalizeLocalIp(device.localIp),
      branchCode: device.branchCode || "main",
      appVersion: device.appVersion || "unknown",
      connectionStatus: device.connectionStatus || "online",
      lastKnownUserId: device.lastKnownUserId?.toString?.() || null,
      lastKnownUsername: device.lastKnownUsername || null,
      lastKnownFullName: device.lastKnownFullName || null,
      lastHeartbeatAt: device.lastHeartbeatAt?.toISOString?.() || null,
    });
  }

  return {
    branchCode,
    peers: items,
  };
}

async function listUpdateJobs({ page = 1, limit = 50 } = {}) {
  const safeLimit = clampNumber(limit, 1, 200, 50);
  const safePage = clampNumber(page, 1, 100000, 1);
  const [jobs, total] = await Promise.all([
    UpdateJob.find({})
      .populate("releaseId")
      .sort({ createdAt: -1 })
      .skip((safePage - 1) * safeLimit)
      .limit(safeLimit)
      .lean(),
    UpdateJob.countDocuments({}),
  ]);

  return {
    items: jobs.map((job) => ({
      ...serializeJob(job),
      release: serializeRelease(job.releaseId),
    })),
    page: safePage,
    limit: safeLimit,
    total,
  };
}

async function getUpdateJobDetails(jobId, { tasksLimit = 500 } = {}) {
  const safeTasksLimit = clampNumber(tasksLimit, 1, 2000, 500);
  const job = await UpdateJob.findById(toObjectId(jobId, "job id"))
    .populate("releaseId")
    .lean();
  if (!job) {
    throw new ApiError(404, "Update job not found.");
  }

  const tasks = await UpdateTask.find({ jobId: job._id })
    .sort({ createdAt: 1 })
    .limit(safeTasksLimit)
    .populate("releaseId")
    .lean();

  return {
    job: {
      ...serializeJob(job),
      release: serializeRelease(job.releaseId),
    },
    tasks: tasks.map((task) => serializeTask(task, task.releaseId)),
  };
}

async function cancelUpdateJob(actor, jobId) {
  const objectId = toObjectId(jobId, "job id");
  const job = await UpdateJob.findById(objectId);
  if (!job) {
    throw new ApiError(404, "Update job not found.");
  }

  if (
    ["completed", "failed", "partial_failed", "cancelled"].includes(job.status)
  ) {
    return serializeJob(job);
  }

  const now = new Date();
  await UpdateTask.updateMany(
    {
      jobId: objectId,
      status: { $in: ["pending", "acknowledged", "downloading", "installing"] },
    },
    {
      $set: {
        status: "cancelled",
        completedAt: now,
        message: "Cancelled by admin.",
      },
      $push: {
        logs: {
          status: "cancelled",
          at: now,
          message: "Cancelled by admin.",
          progress: 0,
        },
      },
    },
  );

  await recalculateJobStats(objectId);
  const updated = await UpdateJob.findById(objectId).lean();

  await logAuditEvent({
    actorId: actor.id,
    action: "admin.update.job.cancel",
    entityType: "update-job",
    entityId: objectId.toString(),
    payload: {
      cancelledAt: nowIso(),
    },
  });

  return serializeJob(updated);
}

async function reportTaskProgress(actor, payload = {}) {
  const deviceUid = String(payload.deviceUid || "")
    .trim()
    .slice(0, 160);
  if (!deviceUid) {
    throw new ApiError(400, "deviceUid is required.");
  }

  const taskIdRaw = String(payload.taskId || "")
    .trim()
    .slice(0, 80);
  const statusRaw = String(payload.status || "")
    .trim()
    .toLowerCase();
  const progressRaw = clampNumber(payload.progress, 0, 100, 0);
  const nowMs = Date.now();
  const throttleKey = `${taskIdRaw}:${deviceUid}`;
  const previousReport = await readProgressThrottle(throttleKey);
  const isTerminalStatus = ["completed", "failed", "cancelled"].includes(
    statusRaw,
  );
  if (previousReport) {
    const statusUnchanged = previousReport.status === statusRaw;
    const progressDelta = Math.abs(
      Number(progressRaw || 0) - Number(previousReport.progress || 0),
    );
    const tooSoon =
      nowMs - Number(previousReport.at || 0) < PROGRESS_EVENT_MIN_INTERVAL_MS;
    if (
      !isTerminalStatus &&
      statusUnchanged &&
      progressDelta < PROGRESS_SIGNIFICANT_DELTA &&
      tooSoon
    ) {
      return {
        throttled: true,
        taskId: taskIdRaw,
        status: statusRaw,
        progress: progressRaw,
        deviceUid,
      };
    }
  }
  await writeProgressThrottle(throttleKey, {
    status: statusRaw,
    progress: progressRaw,
    at: nowMs,
  });

  const taskId = toObjectId(payload.taskId, "taskId");
  const status = String(payload.status || "")
    .trim()
    .toLowerCase();
  if (!TASK_STATUS_FLOW.has(status)) {
    throw new ApiError(400, "Invalid task status.");
  }

  const device = await UpdateDevice.findOne({ deviceUid });
  if (!device) {
    throw new ApiError(404, "Device not registered.");
  }

  const task = await UpdateTask.findById(taskId);
  if (!task) {
    throw new ApiError(404, "Task not found.");
  }

  if (task.deviceId.toString() !== device._id.toString()) {
    throw new ApiError(403, "Task does not belong to this device.");
  }

  const now = new Date();
  const progress = clampNumber(payload.progress, 0, 100, task.progress || 0);
  const message =
    String(payload.message || "")
      .trim()
      .slice(0, 1000) || null;

  task.status = status;
  task.progress = progress;
  task.message = message;
  if (status === "acknowledged" && !task.acknowledgedAt) {
    task.acknowledgedAt = now;
  }
  if (status === "completed") {
    task.completedAt = now;
    task.progress = 100;
    task.lastError = null;
  }
  if (status === "failed") {
    task.completedAt = now;
    task.lastError = message || "Update failed.";
  }
  if (status === "cancelled") {
    task.completedAt = now;
  }
  if (status === "acknowledged") {
    task.attempts = (task.attempts || 0) + 1;
  }
  task.logs.push({
    status,
    progress: task.progress,
    message,
    at: now,
  });
  await task.save();

  device.connectionStatus =
    payload.connectionStatus === "idle"
      ? "idle"
      : payload.connectionStatus === "meeting"
        ? "meeting"
        : payload.connectionStatus === "lunch"
          ? "lunch"
          : payload.connectionStatus === "offline"
            ? "offline"
            : "online";
  device.lastHeartbeatAt = now;
  device.lastSeenAt = now;
  device.updateState = {
    status,
    currentTaskId: task._id,
    targetVersion: task.releaseVersion,
    progress: task.progress,
    lastError: task.lastError || null,
    updatedAt: now,
  };
  await device.save();

  await recalculateJobStats(task.jobId);

  return {
    task: serializeTask(task),
    device: serializeDevice(device),
  };
}

async function getReleaseDownloadInfo(releaseId) {
  const release = await UpdateRelease.findById(
    toObjectId(releaseId, "release id"),
  ).lean();
  if (!release) {
    throw new ApiError(404, "Release not found.");
  }
  if (release.isEnabled === false) {
    throw new ApiError(403, "Release is disabled.");
  }
  if (release.externalDownloadUrl) {
    return {
      mode: "redirect",
      externalDownloadUrl: release.externalDownloadUrl,
    };
  }
  if (!release.filePath) {
    throw new ApiError(404, "Release artifact is missing.");
  }
  const artifactPath = findExistingReleaseArtifactPath(release.filePath);
  if (!artifactPath || !fsSync.existsSync(artifactPath)) {
    throw new ApiError(
      404,
      "Release artifact file is not available on server.",
    );
  }
  return {
    mode: "file",
    filePath: artifactPath,
    fileName: release.fileName || path.basename(artifactPath),
  };
}

async function validateReleaseDownloadAccess({
  releaseId,
  actor = null,
  downloadToken = null,
}) {
  const resolvedReleaseId = String(releaseId || "");
  if (actor) {
    return true;
  }

  const payload = verifyReleaseDownloadToken(downloadToken);
  if (!payload) {
    throw new ApiError(401, "Authentication required.");
  }

  if (String(payload.rid || "") !== resolvedReleaseId) {
    throw new ApiError(403, "Download token is not valid for this release.");
  }

  const taskId = String(payload.tid || "");
  const deviceUid = String(payload.did || "");
  if (!taskId || !deviceUid) {
    throw new ApiError(403, "Invalid download token payload.");
  }

  const task = await UpdateTask.findById(taskId).lean();
  if (!task) {
    throw new ApiError(404, "Task not found for download token.");
  }

  if (String(task.releaseId || "") !== resolvedReleaseId) {
    throw new ApiError(403, "Task release mismatch.");
  }

  if (String(task.deviceUid || "") !== deviceUid) {
    throw new ApiError(403, "Task device mismatch.");
  }

  if (!["pending", "acknowledged", "downloading", "installing"].includes(task.status)) {
    throw new ApiError(403, "Task is not active for download.");
  }

  return true;
}

async function pruneDisabledReleaseArtifact(actor, releaseId) {
  const release = await UpdateRelease.findById(
    toObjectId(releaseId, "release id"),
  );
  if (!release) {
    throw new ApiError(404, "Release not found.");
  }
  const artifactPath = findExistingReleaseArtifactPath(release.filePath);
  if (artifactPath && fsSync.existsSync(artifactPath)) {
    await fs.rm(artifactPath, { force: true });
  }
  await UpdateRelease.findByIdAndDelete(release._id);

  await logAuditEvent({
    actorId: actor.id,
    action: "admin.update.release.delete",
    entityType: "update-release",
    entityId: release._id.toString(),
    payload: {
      version: release.version,
      channel: release.channel,
    },
  });

  return {
    deleted: true,
    releaseId: release._id.toString(),
  };
}

async function checkForMobileUpdates(
  actor,
  payload = {},
  baseUrlOverride = baseUrl,
) {
  const deviceUid = String(payload.deviceUid || "").trim();
  if (!deviceUid) {
    throw new ApiError(400, "deviceUid is required.");
  }

  const currentVersion = String(payload.currentVersion || "").trim();
  const branchCode = normalizeBranchCode(payload.branchCode);

  console.log(
    `[UpdateService] checkForMobileUpdates: deviceUid=${deviceUid}, version=${currentVersion}, branch=${branchCode}`,
  );

  // Find or create device for this user
  const device = await UpdateDevice.findOneAndUpdate(
    { deviceUid },
    {
      $set: {
        platform: "mobile_android",
        branchCode,
        channel: normalizeChannel(payload.channel),
        appVersion: currentVersion,
        lastKnownUserId: actor.id,
        lastKnownUsername: actor.username,
        lastKnownFullName: actor.fullName,
        lastHeartbeatAt: new Date(),
        isActive: true,
      },
      $setOnInsert: {
        createdAt: new Date(),
      },
    },
    { upsert: true, new: true },
  );

  console.log(`[UpdateService] Device registered: ${device._id.toString()}`);

  // IMPORTANT: Only return updates that were explicitly assigned to this device via admin
  // Step 1: Look for pending update tasks for this device
  const pendingTask = await UpdateTask.findOne({
    deviceId: device._id,
    status: { $in: ["pending", "acknowledged", "downloading", "installing"] },
  })
    .sort({ createdAt: 1 })
    .populate("releaseId")
    .lean();

  if (pendingTask && pendingTask.releaseId) {
    const release = pendingTask.releaseId;
    console.log(
      `[UpdateService] Found pending task: ${pendingTask._id.toString()}, release: ${release.version}`,
    );

    if (release.isEnabled) {
      console.log(`[UpdateService] Returning update task to device`);
      const serializedTask = serializeTask(pendingTask, release, {
        baseUrlOverride,
      });
      // Keep `release` and `task.release` consistent and tokenized.
      // Mobile client currently reads top-level `release.downloadUrl`.
      const tokenizedRelease =
        serializedTask.release || serializeRelease(release, { baseUrlOverride });
      return {
        release: tokenizedRelease,
        task: serializedTask,
        requiresUpdate: true,
        isMandatory: release.mandatory === true,
      };
    }
  }

  console.log(
    `[UpdateService] No pending tasks for device, returning empty response`,
  );
  // Step 2: No pending task = no update to offer
  // Updates only sent when admin explicitly creates job and assigns device
  return {
    release: null,
    task: null,
    requiresUpdate: false,
    isMandatory: false,
  };
}

function compareVersions(v1, v2) {
  const parse = (v) => {
    return String(v || "0")
      .split(".")
      .map((x) => {
        const num = parseInt(x, 10);
        return isNaN(num) ? 0 : num;
      });
  };

  const parsed1 = parse(v1);
  const parsed2 = parse(v2);
  const maxLength = Math.max(parsed1.length, parsed2.length);

  for (let i = 0; i < maxLength; i++) {
    const a = parsed1[i] || 0;
    const b = parsed2[i] || 0;
    if (a < b) return -1;
    if (a > b) return 1;
  }

  return 0;
}

module.exports = {
  registerDeviceHeartbeat,
  listDevices,
  listBranchPeerDevices,
  updateDeviceActiveState,
  createRelease,
  listReleases,
  updateRelease,
  createUpdateJob,
  listUpdateJobs,
  getUpdateJobDetails,
  cancelUpdateJob,
  reportTaskProgress,
  getReleaseDownloadInfo,
  validateReleaseDownloadAccess,
  pruneDisabledReleaseArtifact,
  checkForMobileUpdates,
};
