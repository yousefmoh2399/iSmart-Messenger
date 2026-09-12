const asyncHandler = require("../../utils/async-handler");
const fsSync = require("fs");
const path = require("path");
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
  reportTaskProgress,
  getReleaseDownloadInfo,
  validateReleaseDownloadAccess,
  pruneDisabledReleaseArtifact,
  checkForMobileUpdates,
} = require("./update.service");

function emitUpdatesUpdated(req, payload = {}) {
  const io = req.app.get("io");
  if (!io) {
    return;
  }
  io.emit("updates_updated", {
    at: new Date().toISOString(),
    ...payload,
  });
}

const heartbeatDevice = asyncHandler(async (req, res) => {
  const result = await registerDeviceHeartbeat(req.user, req.body || {}, {
    ip: req.ip,
    baseUrlOverride: getRequestBaseUrl(req),
  });
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
    .then(async () => {
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

      const stat = fsSync.statSync(filePath);
      const fileSize = stat.size;

      res.setHeader("Content-Type", "application/octet-stream");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="${fileName}"`,
      );
      res.setHeader("Accept-Ranges", "bytes");
      res.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
      res.setHeader("ETag", `"${stat.ino}-${stat.size}-${stat.mtimeMs}"`);
      res.setHeader("X-Content-Type-Options", "nosniff");

      const range = req.headers.range;
      if (range && range.startsWith("bytes=")) {
        const parts = range.substring(6).split(",")[0].split("-");
        const start = parseInt(parts[0], 10);
        const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;

        if (start < 0 || start >= fileSize || end < start || end >= fileSize) {
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
        stream.on("error", (err) => {
          console.error(
            `[UpdateController] Stream error for ${req.params.id}:`,
            err.message,
          );
          if (!res.headersSent) {
            res.status(500).end();
          }
          stream.destroy();
        });
        res.on("error", (err) => {
          stream.destroy();
        });
        stream.pipe(res);
      } else {
        res.setHeader("Content-Length", fileSize);
        const stream = fsSync.createReadStream(filePath);
        stream.on("error", (err) => {
          console.error(
            `[UpdateController] Stream error for ${req.params.id}:`,
            err.message,
          );
          if (!res.headersSent) {
            res.status(500).end();
          }
          stream.destroy();
        });
        res.on("error", (err) => {
          stream.destroy();
        });
        stream.pipe(res);
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
  res.status(200).json({
    success: true,
    data: { job },
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
};
