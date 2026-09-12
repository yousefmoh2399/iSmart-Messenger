const {
  loginUser,
  refreshAccessToken,
  revokeDeviceRefreshSession,
} = require("../services/auth.service");
const { getProfile } = require("../services/user.service");
const asyncHandler = require("../utils/async-handler");

const login = asyncHandler(async (req, res) => {
  const result = await loginUser({
    username: req.body.username,
    password: req.body.password,
    deviceUid: req.body.deviceUid,
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
    deviceUid: req.body.deviceUid,
  });
  res.status(200).json(result);
});

// Revoke refresh session for current device only.
const logout = asyncHandler(async (req, res) => {
  await revokeDeviceRefreshSession(req.user.id, req.body?.deviceUid);
  res.status(200).json({ success: true, message: "Logged out." });
});

module.exports = {
  login,
  me,
  refresh,
  logout,
};
