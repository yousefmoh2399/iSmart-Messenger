const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const { jwtSecret } = require("../config/env");
const User = require("../models/user.model");
const ApiError = require("../utils/api-error");
const { getEffectivePermissionsForUser } = require("../chat/services/role.service");
const { serializeUser } = require("./user.service");

function resolveTokenVersion(value) {
  return Number.isInteger(value) && value > 0 ? value : 1;
}

function buildToken(user) {
  return jwt.sign(
    {
      sub: user._id.toString(),
      username: user.username,
      role: user.role,
      tokenVersion: resolveTokenVersion(user.tokenVersion),
    },
    jwtSecret,
    {
      // Keep long enough for sockets / attachment fetches; refresh still rotates per-device.
      expiresIn: process.env.JWT_ACCESS_EXPIRES_IN || "1h",
    },
  );
}

function buildRefreshToken(user, refreshNonce) {
  return jwt.sign(
    {
      sub: user._id.toString(),
      type: "refresh",
      rn: refreshNonce,
    },
    jwtSecret,
    {
      expiresIn: process.env.JWT_REFRESH_EXPIRES_IN || "30d",
    },
  );
}

function normalizeDeviceUid(value) {
  const raw = String(value || "").trim();
  if (!raw) return null;
  return raw.slice(0, 160);
}

async function buildUserResponse(user) {
  const permissions = await getEffectivePermissionsForUser(user);
  return serializeUser(user, permissions);
}

async function loginUser({ username, password, deviceUid }) {
  const normalizedUsername = String(username || "")
    .trim()
    .toLowerCase();
  const user = await User.findOne({ username: normalizedUsername }).exec();

  if (!user) {
    throw new ApiError(401, "Invalid username or password.");
  }

  if (user.isActive === false) {
    throw new ApiError(403, "This account is inactive.");
  }

  const isValidPassword = await bcrypt.compare(password, user.passwordHash);
  if (!isValidPassword) {
    throw new ApiError(401, "Invalid username or password.");
  }

  const normalizedDeviceUid = normalizeDeviceUid(deviceUid) || "unknown";
  const refreshNonce = crypto.randomBytes(16).toString("hex");
  const now = new Date();
  await User.updateOne(
    { _id: user._id },
    [
      {
        $set: {
          refreshSessions: {
            $concatArrays: [
              {
                $filter: {
                  input: { $ifNull: ["$refreshSessions", []] },
                  as: "s",
                  cond: { $ne: ["$$s.deviceUid", normalizedDeviceUid] },
                },
              },
              [
                {
                  deviceUid: normalizedDeviceUid,
                  nonce: refreshNonce,
                  createdAt: now,
                  lastUsedAt: now,
                },
              ],
            ],
          },
        },
      },
    ],
  ).exec();

  return {
    token: buildToken(user),
    refreshToken: jwt.sign(
      {
        sub: user._id.toString(),
        type: "refresh",
        rn: refreshNonce,
        did: normalizedDeviceUid,
      },
      jwtSecret,
      { expiresIn: "30d" },
    ),
    user: await buildUserResponse(user),
  };
}

async function refreshAccessToken(refreshToken, { deviceUid } = {}) {
  try {
    const decoded = jwt.verify(refreshToken, jwtSecret);

    if (decoded.type !== "refresh") {
      throw new ApiError(401, "Invalid refresh token");
    }

    const user = await User.findById(decoded.sub)
      .select("+refreshTokenNonce +refreshSessions")
      .exec();
    if (!user || user.isActive === false) {
      throw new ApiError(401, "User not found or inactive");
    }

    const decodedDeviceUid = normalizeDeviceUid(decoded.did);
    const requestDeviceUid = normalizeDeviceUid(deviceUid);
    const effectiveDeviceUid = decodedDeviceUid || requestDeviceUid || "unknown";

    const incomingRn = decoded.rn ? String(decoded.rn) : null;
    const storedLegacyRn = user.refreshTokenNonce
      ? String(user.refreshTokenNonce)
      : null;

    const sessions = Array.isArray(user.refreshSessions)
      ? user.refreshSessions
      : [];
    const currentSession = sessions.find((s) => s?.deviceUid === effectiveDeviceUid);
    const storedSessionRn = currentSession?.nonce ? String(currentSession.nonce) : null;

    if (!incomingRn) {
      throw new ApiError(401, "Invalid refresh token");
    }

    // Prefer multi-device session nonce when available.
    if (storedSessionRn) {
      if (incomingRn !== storedSessionRn) {
        throw new ApiError(401, "Invalid refresh token");
      }
    } else if (storedLegacyRn) {
      // Migration path: accept legacy nonce once, then move to device session.
      if (incomingRn !== storedLegacyRn) {
        throw new ApiError(401, "Invalid refresh token");
      }
    } else {
      throw new ApiError(401, "Invalid refresh token");
    }

    const newNonce = crypto.randomBytes(16).toString("hex");
    const now = new Date();
    const createdAt = currentSession?.createdAt || now;
    await User.updateOne(
      { _id: user._id },
      [
        {
          $set: {
            refreshTokenNonce: null,
            refreshSessions: {
              $concatArrays: [
                {
                  $filter: {
                    input: { $ifNull: ["$refreshSessions", []] },
                    as: "s",
                    cond: { $ne: ["$$s.deviceUid", effectiveDeviceUid] },
                  },
                },
                [
                  {
                    deviceUid: effectiveDeviceUid,
                    nonce: newNonce,
                    createdAt,
                    lastUsedAt: now,
                  },
                ],
              ],
            },
          },
        },
      ],
    ).exec();

    return {
      token: buildToken(user),
      refreshToken: jwt.sign(
        {
          sub: user._id.toString(),
          type: "refresh",
          rn: newNonce,
          did: effectiveDeviceUid,
        },
        jwtSecret,
        { expiresIn: "30d" },
      ),
    };
  } catch (error) {
    if (error instanceof ApiError) {
      throw error;
    }
    if (error.name === "TokenExpiredError") {
      throw new ApiError(401, "Refresh token expired");
    }
    throw new ApiError(401, "Invalid refresh token");
  }
}

async function revokeDeviceRefreshSession(userId, deviceUid) {
  const normalized = normalizeDeviceUid(deviceUid);
  if (!normalized) {
    return;
  }
  await User.updateOne(
    { _id: userId },
    [
      {
        $set: {
          refreshSessions: {
            $filter: {
              input: { $ifNull: ["$refreshSessions", []] },
              as: "s",
              cond: { $ne: ["$$s.deviceUid", normalized] },
            },
          },
        },
      },
    ],
  ).exec();
}

module.exports = {
  loginUser,
  refreshAccessToken,
  buildUserResponse,
  revokeDeviceRefreshSession,
};
