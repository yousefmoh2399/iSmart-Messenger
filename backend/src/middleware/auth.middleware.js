const jwt = require("jsonwebtoken");
const { allowQueryTokens, jwtSecret } = require("../config/env");
const User = require("../models/user.model");
const ApiError = require("../utils/api-error");
const asyncHandler = require("../utils/async-handler");
const { getEffectivePermissionsForUser } = require("../chat/services/role.service");

function resolveTokenVersion(value) {
  return Number.isInteger(value) && value > 0 ? value : 1;
}

const requireAuth = asyncHandler(async (req, res, next) => {
  const authorizationHeader = req.headers.authorization || "";
  const token = resolveRequestToken(req, authorizationHeader);

  if (!token) {
    throw new ApiError(401, "Authentication required.");
  }

  let payload;
  try {
    payload = jwt.verify(token, jwtSecret);
  } catch (error) {
    throw new ApiError(401, "Invalid or expired token.");
  }

  const user = await User.findById(payload.sub).select("+tokenVersion").lean();
  if (!user) {
    throw new ApiError(401, "User no longer exists.");
  }

  if (
    resolveTokenVersion(user.tokenVersion) !==
    resolveTokenVersion(payload.tokenVersion)
  ) {
    throw new ApiError(401, "Token version mismatch. Please login again.");
  }

  if (user.isActive === false) {
    throw new ApiError(403, "This account is inactive.");
  }

  const permissions = await getEffectivePermissionsForUser(user);

  req.user = {
    id: user._id.toString(),
    username: user.username,
    role: user.role,
    fullName: user.fullName,
    departmentId: user.departmentId ? user.departmentId.toString() : null,
    departmentIds: Array.isArray(user.departmentIds)
      ? user.departmentIds.map((entry) => entry.toString())
      : user.departmentId
        ? [user.departmentId.toString()]
        : [],
    branchId: user.branchId ? user.branchId.toString() : null,
    branchCode: String(user.branchCode || "main")
      .trim()
      .toUpperCase(),
    isOnline: Boolean(user.isOnline),
    presenceStatus:
      user.presenceStatus || (user.isOnline ? "online" : "offline"),
    isActive: user.isActive !== false,
    avatarUrl: normalizeMediaUrl(user.avatarUrl),
    lastSeen: user.lastSeen,
    lastActiveAt: user.lastActiveAt || null,
    maxAttachmentSizeMB: user.maxAttachmentSizeMB,
    tokenVersion: resolveTokenVersion(user.tokenVersion),
    permissions,
  };

  next();
});

module.exports = {
  requireAuth,
};

function resolveRequestToken(req, authorizationHeader) {
  if (authorizationHeader.startsWith("Bearer ")) {
    return authorizationHeader.slice(7);
  }

  if (req.method !== "GET" && req.method !== "HEAD") {
    return null;
  }
  if (!allowQueryTokens) {
    return null;
  }

  const queryToken = req.query.accessToken || req.query.token;
  if (Array.isArray(queryToken)) {
    return queryToken[0] || null;
  }
  return queryToken || null;
}

function normalizeMediaUrl(value) {
  if (!value) {
    return null;
  }
  try {
    const parsed = new URL(value);
    return `${parsed.pathname}${parsed.search || ""}${parsed.hash || ""}`;
  } catch (_) {
    return value;
  }
}
