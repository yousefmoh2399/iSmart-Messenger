const {
  loginUser,
  refreshAccessToken,
  revokeDeviceRefreshSession,
  listUserActiveSessions,
  revokeUserDeviceSession,
  revokeOtherUserDeviceSessions,
} = require("../services/auth.service");
const { getProfile } = require("../services/user.service");
const asyncHandler = require("../utils/async-handler");

function resolveRequestIp(req) {
  return (
    req.headers["x-forwarded-for"] ||
    req.ip ||
    req.socket?.remoteAddress ||
    null
  );
}

const login = asyncHandler(async (req, res) => {
  const result = await loginUser({
    username: req.body.username,
    password: req.body.password,
    deviceUid: req.body.deviceUid || req.headers["x-device-uid"],
    deviceName: req.body.deviceName || req.headers["x-device-name"],
    platform: req.body.platform || req.headers["x-device-platform"],
    appVersion: req.body.appVersion || req.headers["x-app-version"],
    ipAddress: resolveRequestIp(req),
    userAgent: req.headers["user-agent"] || null,
  });
  res.status(200).json(result);
});

const me = asyncHandler(async (req, res) => {
  const user = await getProfile(req.user);
  res.status(200).json({
    user,
  });
});

const refresh = asyncHandler(async (req, res) => {
  const result = await refreshAccessToken(req.body.refreshToken, {
    deviceUid: req.body.deviceUid || req.headers["x-device-uid"],
    deviceName: req.body.deviceName || req.headers["x-device-name"],
    platform: req.body.platform || req.headers["x-device-platform"],
    appVersion: req.body.appVersion || req.headers["x-app-version"],
    ipAddress: resolveRequestIp(req),
    userAgent: req.headers["user-agent"] || null,
  });
  res.status(200).json(result);
});

// Revoke refresh session for current device only.
const logout = asyncHandler(async (req, res) => {
  await revokeDeviceRefreshSession(
    req.user.id,
    req.body?.deviceUid || req.user.deviceUid,
  );
  res.status(200).json({ success: true, message: "Logged out." });
});

const getSessions = asyncHandler(async (req, res) => {
  const currentDeviceUid =
    req.query.deviceUid ||
    req.headers["x-device-uid"] ||
    req.user.deviceUid ||
    null;
  const result = await listUserActiveSessions(req.user.id, {
    currentDeviceUid,
    deviceName: req.query.deviceName || req.headers["x-device-name"],
    platform: req.query.platform || req.headers["x-device-platform"],
    appVersion: req.query.appVersion || req.headers["x-app-version"],
    ipAddress: resolveRequestIp(req),
    userAgent: req.headers["user-agent"] || null,
  });
  res.status(200).json(result);
});

const revokeSession = asyncHandler(async (req, res) => {
  const currentDeviceUid =
    req.query.currentDeviceUid ||
    req.headers["x-device-uid"] ||
    req.user.deviceUid ||
    null;
  const result = await revokeUserDeviceSession(
    req.user.id,
    req.params.deviceUid,
    {
      currentDeviceUid,
      io: req.app.get("io"),
    },
  );
  res.status(200).json(result);
});

const revokeOtherSessions = asyncHandler(async (req, res) => {
  const currentDeviceUid =
    req.body?.currentDeviceUid ||
    req.body?.deviceUid ||
    req.headers["x-device-uid"] ||
    req.user.deviceUid ||
    null;
  const result = await revokeOtherUserDeviceSessions(req.user.id, {
    currentDeviceUid,
    io: req.app.get("io"),
  });
  res.status(200).json(result);
});

module.exports = {
  login,
  me,
  refresh,
  logout,
  getSessions,
  revokeSession,
  revokeOtherSessions,
};
