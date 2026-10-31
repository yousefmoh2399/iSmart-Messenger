const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const { jwtSecret } = require("../config/env");
const User = require("../models/user.model");
const UpdateDevice = require("../admin/updates/device.model");
const ApiError = require("../utils/api-error");
const { getEffectivePermissionsForUser } = require("../chat/services/role.service");
const {
  getUserConnectedSocketsSnapshot,
  forceLogoutUserDevices,
} = require("../chat/sockets/chat.socket");
const { serializeUser } = require("./user.service");

function resolveTokenVersion(value) {
  return Number.isInteger(value) && value > 0 ? value : 1;
}

function normalizeDeviceUid(value) {
  const raw = String(value || "").trim();
  if (!raw) return null;
  return raw.slice(0, 160);
}

function cleanIpAddress(value) {
  const raw = String(value || "")
    .split(",")[0]
    .trim();
  if (!raw) return null;
  return raw.replace(/^::ffff:/i, "").slice(0, 80);
}

function inferPlatform({ platform, deviceUid, userAgent } = {}) {
  const rawPlatform = String(platform || "")
    .trim()
    .toLowerCase();
  if (rawPlatform.includes("windows") || rawPlatform === "desktop") {
    return "windows";
  }
  if (rawPlatform.includes("android") || rawPlatform === "mobile") {
    return "android";
  }
  if (rawPlatform.includes("ios") || rawPlatform.includes("iphone") || rawPlatform.includes("ipad")) {
    return "ios";
  }
  if (rawPlatform.includes("mac")) {
    return "macos";
  }
  if (rawPlatform.includes("linux")) {
    return "linux";
  }
  if (rawPlatform.includes("web")) {
    return "web";
  }

  const uid = String(deviceUid || "").trim().toLowerCase();
  if (uid.startsWith("dev-")) {
    return "windows";
  }

  const ua = String(userAgent || "").toLowerCase();
  if (ua.includes("android")) return "android";
  if (ua.includes("iphone") || ua.includes("ipad") || ua.includes("ios")) return "ios";
  if (ua.includes("windows")) return "windows";
  if (ua.includes("macintosh") || ua.includes("mac os")) return "macos";
  if (ua.includes("linux")) return "linux";
  if (ua.includes("dart")) {
    // Dart client without explicit prefix defaults to mobile android if UUID
    return uid && !uid.startsWith("dev-") ? "android" : "unknown";
  }
  return "unknown";
}

function defaultDeviceNameForPlatform(platform, hostName = null) {
  const cleanHost = String(hostName || "").trim();
  switch (platform) {
    case "windows":
      return cleanHost ? `كمبيوتر Windows (${cleanHost})` : "كمبيوتر المكتب Windows";
    case "android":
      return cleanHost ? `هاتف Android (${cleanHost})` : "هاتف Android";
    case "ios":
      return cleanHost ? `جهاز iPhone (${cleanHost})` : "جهاز iPhone / iPad";
    case "macos":
      return cleanHost ? `جهاز Mac (${cleanHost})` : "جهاز Mac";
    case "linux":
      return cleanHost ? `جهاز Linux (${cleanHost})` : "جهاز Linux";
    case "web":
      return "متصفح الويب";
    default:
      return cleanHost || "جهاز متصل";
  }
}

function normalizeSessionMetadata({
  deviceUid,
  deviceName,
  platform,
  appVersion,
  ipAddress,
  userAgent,
} = {}) {
  const resolvedPlatform = inferPlatform({ platform, deviceUid, userAgent });
  const rawName = String(deviceName || "").trim().slice(0, 120);
  const resolvedName =
    rawName || defaultDeviceNameForPlatform(resolvedPlatform);
  const resolvedVersion =
    String(appVersion || "").trim().slice(0, 40) || null;
  const resolvedIp = cleanIpAddress(ipAddress);
  const resolvedUa = String(userAgent || "").trim().slice(0, 240) || null;

  return {
    platform: resolvedPlatform,
    deviceName: resolvedName,
    appVersion: resolvedVersion,
    ipAddress: resolvedIp,
    userAgent: resolvedUa,
  };
}

function buildToken(user, deviceUid = null) {
  const normalizedDid = normalizeDeviceUid(deviceUid);
  const payload = {
    sub: user._id.toString(),
    username: user.username,
    role: user.role,
    tokenVersion: resolveTokenVersion(user.tokenVersion),
  };
  if (normalizedDid && normalizedDid !== "unknown") {
    payload.did = normalizedDid;
  }
  return jwt.sign(payload, jwtSecret, {
    // Keep long enough for sockets / attachment fetches; refresh still rotates per-device.
    expiresIn: process.env.JWT_ACCESS_EXPIRES_IN || "1h",
  });
}

const defaultRefreshExpiresIn = process.env.JWT_REFRESH_EXPIRES_IN || "3650d";

function buildRefreshToken(user, refreshNonce) {
  return jwt.sign(
    {
      sub: user._id.toString(),
      type: "refresh",
      rn: refreshNonce,
    },
    jwtSecret,
    {
      expiresIn: defaultRefreshExpiresIn,
    },
  );
}

async function buildUserResponse(user) {
  const permissions = await getEffectivePermissionsForUser(user);
  return serializeUser(user, permissions);
}

async function loginUser({
  username,
  password,
  deviceUid,
  deviceName,
  platform,
  appVersion,
  ipAddress,
  userAgent,
}) {
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
  const meta = normalizeSessionMetadata({
    deviceUid: normalizedDeviceUid,
    deviceName,
    platform,
    appVersion,
    ipAddress,
    userAgent,
  });
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
                  deviceName: meta.deviceName,
                  platform: meta.platform,
                  appVersion: meta.appVersion,
                  ipAddress: meta.ipAddress,
                  userAgent: meta.userAgent,
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
    token: buildToken(user, normalizedDeviceUid),
    refreshToken: jwt.sign(
      {
        sub: user._id.toString(),
        type: "refresh",
        rn: refreshNonce,
        did: normalizedDeviceUid,
      },
      jwtSecret,
      { expiresIn: defaultRefreshExpiresIn },
    ),
    user: await buildUserResponse(user),
  };
}

async function refreshAccessToken(
  refreshToken,
  { deviceUid, deviceName, platform, appVersion, ipAddress, userAgent } = {},
) {
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
    const storedPreviousRn = currentSession?.previousNonce ? String(currentSession.previousNonce) : null;
    const previousExpiresAt = currentSession?.previousNonceExpiresAt ? new Date(currentSession.previousNonceExpiresAt) : null;

    if (!incomingRn) {
      throw new ApiError(401, "Invalid refresh token");
    }

    const now = new Date();
    let isGracePeriodMatch = false;

    // Prefer multi-device session nonce when available.
    if (storedSessionRn) {
      if (incomingRn !== storedSessionRn) {
        // Allow a 60-second grace period for retried requests on mobile network drops
        if (
          storedPreviousRn &&
          incomingRn === storedPreviousRn &&
          previousExpiresAt &&
          previousExpiresAt > now
        ) {
          isGracePeriodMatch = true;
        } else {
          throw new ApiError(401, "Invalid refresh token");
        }
      }
    } else if (storedLegacyRn) {
      // Migration path: accept legacy nonce once, then move to device session.
      if (incomingRn !== storedLegacyRn) {
        throw new ApiError(401, "Invalid refresh token");
      }
    } else {
      throw new ApiError(401, "Invalid refresh token");
    }

    if (isGracePeriodMatch) {
      // Return fresh access token and existing active refresh token without re-rotating
      return {
        token: buildToken(user, effectiveDeviceUid),
        refreshToken: jwt.sign(
          {
            sub: user._id.toString(),
            type: "refresh",
            rn: storedSessionRn,
            did: effectiveDeviceUid,
          },
          jwtSecret,
          { expiresIn: defaultRefreshExpiresIn },
        ),
      };
    }

    const meta = normalizeSessionMetadata({
      deviceUid: effectiveDeviceUid,
      deviceName: deviceName || currentSession?.deviceName,
      platform: platform || currentSession?.platform,
      appVersion: appVersion || currentSession?.appVersion,
      ipAddress: ipAddress || currentSession?.ipAddress,
      userAgent: userAgent || currentSession?.userAgent,
    });

    const newNonce = crypto.randomBytes(16).toString("hex");
    const graceExpiresAt = new Date(now.getTime() + 60000); // 60s grace period for previous nonce
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
                    previousNonce: storedSessionRn,
                    previousNonceExpiresAt: graceExpiresAt,
                    deviceName: meta.deviceName,
                    platform: meta.platform,
                    appVersion: meta.appVersion,
                    ipAddress: meta.ipAddress,
                    userAgent: meta.userAgent,
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
      token: buildToken(user, effectiveDeviceUid),
      refreshToken: jwt.sign(
        {
          sub: user._id.toString(),
          type: "refresh",
          rn: newNonce,
          did: effectiveDeviceUid,
        },
        jwtSecret,
        { expiresIn: defaultRefreshExpiresIn },
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

async function listUserActiveSessions(
  userId,
  {
    currentDeviceUid,
    deviceName,
    platform,
    appVersion,
    ipAddress,
    userAgent,
  } = {},
) {
  const user = await User.findById(userId).select("+refreshSessions").lean();
  if (!user) {
    throw new ApiError(404, "User not found.");
  }

  const effectiveCurrentUid = normalizeDeviceUid(currentDeviceUid);
  const now = new Date();
  let rawSessions = Array.isArray(user.refreshSessions)
    ? [...user.refreshSessions]
    : [];

  // If current device sent metadata, keep its entry fresh in DB
  if (effectiveCurrentUid) {
    const existingIdx = rawSessions.findIndex(
      (s) => s && s.deviceUid === effectiveCurrentUid,
    );
    const currentMeta = normalizeSessionMetadata({
      deviceUid: effectiveCurrentUid,
      deviceName:
        deviceName ||
        (existingIdx >= 0 ? rawSessions[existingIdx].deviceName : null),
      platform:
        platform ||
        (existingIdx >= 0 ? rawSessions[existingIdx].platform : null),
      appVersion:
        appVersion ||
        (existingIdx >= 0 ? rawSessions[existingIdx].appVersion : null),
      ipAddress:
        ipAddress ||
        (existingIdx >= 0 ? rawSessions[existingIdx].ipAddress : null),
      userAgent:
        userAgent ||
        (existingIdx >= 0 ? rawSessions[existingIdx].userAgent : null),
    });

    if (existingIdx >= 0) {
      const existing = rawSessions[existingIdx];
      const updatedSession = {
        ...existing,
        deviceName: currentMeta.deviceName || existing.deviceName,
        platform:
          currentMeta.platform !== "unknown"
            ? currentMeta.platform
            : existing.platform || "unknown",
        appVersion: currentMeta.appVersion || existing.appVersion,
        ipAddress: currentMeta.ipAddress || existing.ipAddress,
        userAgent: currentMeta.userAgent || existing.userAgent,
        lastUsedAt: now,
      };
      rawSessions[existingIdx] = updatedSession;

      // Persist updated metadata asynchronously without blocking response
      User.updateOne(
        { _id: userId, "refreshSessions.deviceUid": effectiveCurrentUid },
        {
          $set: {
            "refreshSessions.$.deviceName": updatedSession.deviceName,
            "refreshSessions.$.platform": updatedSession.platform,
            "refreshSessions.$.appVersion": updatedSession.appVersion,
            "refreshSessions.$.ipAddress": updatedSession.ipAddress,
            "refreshSessions.$.userAgent": updatedSession.userAgent,
            "refreshSessions.$.lastUsedAt": now,
          },
        },
      )
        .exec()
        .catch(() => {});
    }
  }

  // Enrich from UpdateDevice registry if any session lacks deviceName/platform/appVersion
  const deviceUids = rawSessions
    .map((s) => s?.deviceUid)
    .filter((uid) => uid && uid !== "unknown");
  const updateDevices = deviceUids.length
    ? await UpdateDevice.find({ deviceUid: { $in: deviceUids } })
        .select("deviceUid deviceName hostName platform appVersion osVersion lastSeenAt")
        .lean()
        .catch(() => [])
    : [];
  const updateDeviceByUid = new Map(
    updateDevices.map((d) => [String(d.deviceUid), d]),
  );

  // Check currently connected sockets for real-time online status
  const liveSockets = getUserConnectedSocketsSnapshot(userId);

  const enriched = rawSessions.map((session) => {
    const uid = String(session.deviceUid || "unknown");
    const regDevice = updateDeviceByUid.get(uid);
    const isCurrent = Boolean(
      effectiveCurrentUid && uid === effectiveCurrentUid,
    );

    const resolvedPlatform = inferPlatform({
      platform: session.platform || regDevice?.platform,
      deviceUid: uid,
      userAgent: session.userAgent,
    });

    const matchedSocket = liveSockets.find((sock) => {
      if (sock.deviceUid && sock.deviceUid === uid) {
        return true;
      }
      if (!sock.deviceUid) {
        if (resolvedPlatform === "windows" && sock.clientType === "desktop") {
          return true;
        }
        if (
          (resolvedPlatform === "android" || resolvedPlatform === "ios") &&
          sock.clientType === "mobile"
        ) {
          return true;
        }
      }
      return false;
    });

    const hostHint =
      regDevice?.deviceName ||
      regDevice?.hostName ||
      matchedSocket?.deviceInfo?.hostname ||
      null;

    const resolvedName =
      session.deviceName ||
      defaultDeviceNameForPlatform(resolvedPlatform, hostHint);

    const resolvedVersion =
      session.appVersion || regDevice?.appVersion || null;
    const resolvedIp =
      cleanIpAddress(session.ipAddress) ||
      cleanIpAddress(matchedSocket?.ipAddress) ||
      null;

    const lastUsedAtDate = session.lastUsedAt
      ? new Date(session.lastUsedAt)
      : session.createdAt
        ? new Date(session.createdAt)
        : now;
    const createdAtDate = session.createdAt
      ? new Date(session.createdAt)
      : lastUsedAtDate;

    const isOnline =
      isCurrent ||
      Boolean(matchedSocket) ||
      now.getTime() - lastUsedAtDate.getTime() < 2 * 60 * 1000;

    return {
      deviceUid: uid,
      deviceName: resolvedName,
      platform: resolvedPlatform,
      appVersion: resolvedVersion,
      ipAddress: resolvedIp,
      isCurrent,
      isOnline,
      createdAt: createdAtDate.toISOString(),
      lastUsedAt: (isCurrent ? now : lastUsedAtDate).toISOString(),
    };
  });

  // If currentDeviceUid wasn't in refreshSessions yet (legacy login), synthesize current entry at top
  if (
    effectiveCurrentUid &&
    !enriched.some((entry) => entry.deviceUid === effectiveCurrentUid)
  ) {
    const meta = normalizeSessionMetadata({
      deviceUid: effectiveCurrentUid,
      deviceName,
      platform,
      appVersion,
      ipAddress,
      userAgent,
    });
    enriched.unshift({
      deviceUid: effectiveCurrentUid,
      deviceName: meta.deviceName,
      platform: meta.platform,
      appVersion: meta.appVersion,
      ipAddress: meta.ipAddress,
      isCurrent: true,
      isOnline: true,
      createdAt: now.toISOString(),
      lastUsedAt: now.toISOString(),
    });
  }

  enriched.sort((a, b) => {
    if (a.isCurrent !== b.isCurrent) {
      return a.isCurrent ? -1 : 1;
    }
    if (a.isOnline !== b.isOnline) {
      return a.isOnline ? -1 : 1;
    }
    return new Date(b.lastUsedAt).getTime() - new Date(a.lastUsedAt).getTime();
  });

  const otherSessionsCount = enriched.filter((s) => !s.isCurrent).length;

  return {
    currentDeviceUid: effectiveCurrentUid,
    totalCount: enriched.length,
    otherSessionsCount,
    sessions: enriched,
  };
}

async function revokeUserDeviceSession(
  userId,
  targetDeviceUid,
  { currentDeviceUid = null, io = null } = {},
) {
  const normalizedTarget = normalizeDeviceUid(targetDeviceUid);
  if (!normalizedTarget) {
    throw new ApiError(400, "معرّف الجهاز مطلوب.");
  }

  const normalizedCurrent = normalizeDeviceUid(currentDeviceUid);
  if (normalizedCurrent && normalizedTarget === normalizedCurrent) {
    throw new ApiError(
      400,
      "لا يمكن إنهاء الجلسة الحالية من هذا الخيار. استخدم تسجيل الخروج العادي.",
    );
  }

  const user = await User.findById(userId).select("+refreshSessions").exec();
  if (!user) {
    throw new ApiError(404, "المستخدم غير موجود.");
  }

  const beforeCount = Array.isArray(user.refreshSessions)
    ? user.refreshSessions.length
    : 0;
  await revokeDeviceRefreshSession(userId, normalizedTarget);

  forceLogoutUserDevices(io, userId, {
    targetDeviceUid: normalizedTarget,
    excludeDeviceUid: normalizedCurrent,
    reason: "session_revoked_by_user",
  });

  return {
    success: true,
    revokedDeviceUid: normalizedTarget,
    remainingCount: Math.max(0, beforeCount - 1),
  };
}

async function revokeOtherUserDeviceSessions(
  userId,
  { currentDeviceUid, io = null } = {},
) {
  const normalizedCurrent = normalizeDeviceUid(currentDeviceUid);
  if (!normalizedCurrent) {
    throw new ApiError(400, "معرّف الجهاز الحالي مطلوب للاحتفاظ بالجلسة الحالية.");
  }

  const user = await User.findById(userId).select("+refreshSessions").lean();
  if (!user) {
    throw new ApiError(404, "المستخدم غير موجود.");
  }

  const sessions = Array.isArray(user.refreshSessions)
    ? user.refreshSessions
    : [];
  const otherSessions = sessions.filter(
    (s) => s && s.deviceUid !== normalizedCurrent,
  );

  await User.updateOne(
    { _id: userId },
    [
      {
        $set: {
          refreshTokenNonce: null,
          refreshSessions: {
            $filter: {
              input: { $ifNull: ["$refreshSessions", []] },
              as: "s",
              cond: { $eq: ["$$s.deviceUid", normalizedCurrent] },
            },
          },
        },
      },
    ],
  ).exec();

  forceLogoutUserDevices(io, userId, {
    excludeDeviceUid: normalizedCurrent,
    reason: "other_sessions_revoked_by_user",
  });

  return {
    success: true,
    revokedCount: otherSessions.length,
  };
}

module.exports = {
  loginUser,
  refreshAccessToken,
  buildUserResponse,
  revokeDeviceRefreshSession,
  listUserActiveSessions,
  revokeUserDeviceSession,
  revokeOtherUserDeviceSessions,
};
