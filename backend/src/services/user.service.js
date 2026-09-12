const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const fs = require("fs/promises");
const path = require("path");

const User = require("../models/user.model");
const Department = require("../chat/models/department.model");
const Branch = require("../chat/models/branch.model");
const ApiError = require("../utils/api-error");
const { deleteFileIfExists } = require("../utils/file.util");
const {
  getAvatarUploadsDir,
  resolveStoredUploadPath,
} = require("../utils/storage-paths");
const {
  getEffectivePermissionsForUser,
  normalizePermissionOverrides,
} = require("../chat/services/role.service");
const { logAuditEvent } = require("../chat/services/audit.service");
const {
  registerPushDevice,
  unregisterPushDevice,
} = require("./push-notification.service");

function buildAvatarUrl(value) {
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

function normalizeColorHex(value, fallback) {
  const raw = String(value ?? "").trim();
  if (!raw) {
    return fallback;
  }
  const normalized = raw.startsWith("#") ? raw : `#${raw}`;
  return /^#[0-9A-Fa-f]{6}$/.test(normalized)
    ? normalized.toUpperCase()
    : fallback;
}

function normalizeColorHexList(value, fallback, { min = 1, max = 4 } = {}) {
  if (!Array.isArray(value)) {
    return fallback;
  }
  const normalized = value
    .map((entry) => normalizeColorHex(entry, ""))
    .filter(Boolean)
    .slice(0, max);
  return normalized.length >= min ? normalized : fallback;
}

function defaultCustomTheme() {
  return {
    accentColorHex: "#3390EC",
    outgoingBubbleColorHexes: ["#5BA9FF", "#2F8CFF"],
    incomingBubbleColorHex: "#182533",
    wallpaperColorHexes: ["#0E1621", "#111B26", "#17212B"],
  };
}

function serializeUser(user, permissions = null) {
  const customTheme = user.chatPreferences?.customTheme || defaultCustomTheme();
  return {
    id: user._id.toString(),
    username: user.username,
    fullName: user.fullName,
    role: user.role,
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
    avatarUrl: buildAvatarUrl(user.avatarUrl),
    lastSeen: user.lastSeen,
    lastActiveAt: user.lastActiveAt || null,
    permissions,
    chatPreferences: {
      themeId: user.chatPreferences?.themeId || "system",
      wallpaperId: user.chatPreferences?.wallpaperId || "default",
      customTheme,
    },
    createdAt: user.createdAt,
    updatedAt: user.updatedAt,
  };
}

function isDuplicateUsernameError(error) {
  if (!error || typeof error !== "object") {
    return false;
  }
  if (error.code === 11000) {
    return true;
  }
  const message = String(error.message || "").toLowerCase();
  return message.includes("username") && message.includes("duplicate");
}

async function resolveDepartmentAssignment(departmentId) {
  if (!departmentId) {
    return null;
  }

  const department = await Department.findOne({
    _id: departmentId,
    deletedAt: null,
  }).lean();
  if (!department) {
    throw new ApiError(400, "Department not found.");
  }

  return department._id;
}

async function resolveDepartmentAssignments(departmentIds, fallbackDepartmentId) {
  const rawIds = Array.isArray(departmentIds)
    ? departmentIds
    : fallbackDepartmentId
      ? [fallbackDepartmentId]
      : [];
  const uniqueIds = [
    ...new Set(
      rawIds
        .map((entry) => String(entry || "").trim())
        .filter((entry) => entry.length > 0),
    ),
  ];

  if (!uniqueIds.length) {
    return [];
  }

  const departments = await Department.find({
    _id: { $in: uniqueIds },
    deletedAt: null,
  })
    .select("_id")
    .lean();

  if (departments.length !== uniqueIds.length) {
    throw new ApiError(400, "One or more departments were not found.");
  }

  return departments.map((entry) => entry._id);
}

async function resolveBranchAssignment(branchId) {
  if (!branchId) {
    return { branchId: null, branchCode: "MAIN" };
  }

  const branch = await Branch.findOne({
    _id: branchId,
    deletedAt: null,
  }).lean();
  if (!branch) {
    throw new ApiError(400, "Branch not found.");
  }

  return {
    branchId: branch._id,
    branchCode: String(branch.code || "MAIN")
      .trim()
      .toUpperCase(),
  };
}

function buildUserSearchRegex(value) {
  const query = String(value || "").trim();
  if (!query) {
    return null;
  }
  return new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i");
}

function addDepartmentMembershipFilter(query, departmentId) {
  if (!departmentId) {
    return;
  }
  query.$and = [
    ...(query.$and || []),
    {
      $or: [
        { departmentId },
        { departmentIds: departmentId },
      ],
    },
  ];
}

async function resolveNamedIds(Model, value) {
  const regex = buildUserSearchRegex(value);
  if (!regex) {
    return [];
  }
  const entries = await Model.find({
    deletedAt: null,
    $or: [{ name: regex }, { code: regex }],
  })
    .select("_id")
    .lean();
  return entries.map((entry) => entry._id);
}

async function listUsers(actor = null, filters = {}) {
  const page = Math.max(1, Math.min(Number(filters.page || 1), 100000));
  const limit = Math.max(1, Math.min(Number(filters.limit || 50), 100));
  const skip = (page - 1) * limit;
  const query = {};
  if (actor?.role === "manager" && actor.departmentId) {
    addDepartmentMembershipFilter(query, actor.departmentId);
  } else if (filters.departmentId) {
    addDepartmentMembershipFilter(query, filters.departmentId);
  }
  if (filters.branchId) {
    query.branchId = filters.branchId;
  }
  if (filters.role) {
    query.role = String(filters.role).trim().toLowerCase();
  }
  if (filters.status === "active") {
    query.isActive = { $ne: false };
  } else if (filters.status === "inactive") {
    query.isActive = false;
  }

  const or = [];
  const searchRegex = buildUserSearchRegex(filters.search || filters.q);
  if (searchRegex) {
    or.push(
      { username: searchRegex },
      { fullName: searchRegex },
      { branchCode: searchRegex },
    );
  }

  const departmentIds = await resolveNamedIds(Department, filters.department);
  if (departmentIds.length) {
    or.push(
      { departmentId: { $in: departmentIds } },
      { departmentIds: { $in: departmentIds } },
    );
  }

  const branchIds = await resolveNamedIds(Branch, filters.branch);
  if (branchIds.length) {
    or.push({ branchId: { $in: branchIds } });
  }

  if (or.length) {
    query.$or = or;
  }

  const [users, total] = await Promise.all([
    User.find(query)
      .sort({ createdAt: -1, _id: -1 })
      .skip(skip)
      .limit(limit)
      .lean(),
    User.countDocuments(query),
  ]);
  const serializedUsers = await Promise.all(
    users.map(async (user) =>
      serializeUser(user, await getEffectivePermissionsForUser(user)),
    ),
  );
  return {
    users: serializedUsers,
    pagination: {
      page,
      limit,
      total,
      hasMore: page * limit < total,
    },
  };
}

async function getUserById(userId) {
  const user = await User.findById(userId);
  if (!user) {
    throw new ApiError(404, "User not found.");
  }
  return user;
}

async function createUser(
  {
    username,
    password,
    fullName,
    role,
    departmentId,
    departmentIds,
    branchId,
    permissions,
  },
  actor = null,
) {
  const normalizedUsername = String(username).trim().toLowerCase();
  const existingUser = await User.findOne({
    username: normalizedUsername,
  }).lean();
  if (existingUser) {
    throw new ApiError(409, "Username already exists.");
  }

  const passwordHash = await bcrypt.hash(password, 10);
  const resolvedDepartmentIds = await resolveDepartmentAssignments(
    departmentIds,
    departmentId,
  );
  const resolvedDepartmentId = resolvedDepartmentIds[0] || null;
  const branchAssignment = await resolveBranchAssignment(branchId);
  let user;
  try {
    user = await User.create({
      username: normalizedUsername,
      passwordHash,
      fullName: String(fullName).trim(),
      role: role || "user",
      permissionOverrides: normalizePermissionOverrides(permissions),
      departmentId: resolvedDepartmentId,
      departmentIds: resolvedDepartmentIds,
      branchId: branchAssignment.branchId,
      branchCode: branchAssignment.branchCode,
    });
  } catch (error) {
    if (isDuplicateUsernameError(error)) {
      throw new ApiError(409, "Username already exists.");
    }
    throw error;
  }

  for (const deptId of resolvedDepartmentIds) {
    await Department.updateOne(
      { _id: deptId, deletedAt: null },
      { $inc: { membersCount: 1 } },
    );
  }
  if (branchAssignment.branchId) {
    await Branch.updateOne(
      { _id: branchAssignment.branchId, deletedAt: null },
      { $inc: { membersCount: 1 } },
    );
  }

  await logAuditEvent({
    actorId: actor?.id || user._id,
    action: "user.created",
    entityType: "User",
    entityId: user._id,
    payload: {
      role: user.role,
      departmentId: resolvedDepartmentId?.toString?.() || null,
      branchId: branchAssignment.branchId?.toString?.() || null,
      branchCode: branchAssignment.branchCode,
    },
  });

  return serializeUser(user, await getEffectivePermissionsForUser(user));
}

async function incrementTokenVersion(user) {
  user.tokenVersion = (user.tokenVersion || 0) + 1;
}

async function updateUser(actor, userId, payload) {
  const user = await getUserById(userId);

  const actorIsAdmin = actor.role === "admin";
  const actorCanManageUsers = actor.permissions?.canCreateUsers === true;
  const actorIsManagerInSameDepartment =
    actor.role === "manager" &&
    actor.departmentId &&
    user.departmentId &&
    actor.departmentId === user.departmentId.toString();

  if (!actorIsAdmin && !actorCanManageUsers && !actorIsManagerInSameDepartment) {
    throw new ApiError(403, "Permission denied.");
  }

  const triesRestrictedRoleOrPermissionsUpdate =
    payload.role != null || payload.permissions != null;
  const triesRestrictedOrgUpdate =
    Object.prototype.hasOwnProperty.call(payload, "departmentId") ||
    Object.prototype.hasOwnProperty.call(payload, "departmentIds") ||
    Object.prototype.hasOwnProperty.call(payload, "branchId");
  if (
    (triesRestrictedRoleOrPermissionsUpdate || triesRestrictedOrgUpdate) &&
    !actorIsAdmin &&
    !actorCanManageUsers
  ) {
    throw new ApiError(
      403,
      "Permission denied for updating role/permissions/department/branch.",
    );
  }

  if (payload.username != null) {
    const normalizedUsername = String(payload.username).trim().toLowerCase();
    if (normalizedUsername !== user.username) {
      const exists = await User.findOne({
        _id: { $ne: user._id },
        username: normalizedUsername,
      }).lean();
      if (exists) {
        throw new ApiError(409, "Username already exists.");
      }
      user.username = normalizedUsername;
    }
  }

  if (payload.fullName != null) {
    user.fullName = String(payload.fullName).trim();
  }

  if (payload.role != null && (actorIsAdmin || actorCanManageUsers)) {
    user.role = payload.role;
  }

  if (payload.permissions != null && (actorIsAdmin || actorCanManageUsers)) {
    user.permissionOverrides = normalizePermissionOverrides(payload.permissions);
    incrementTokenVersion(user);
  }

  if (
    (Object.prototype.hasOwnProperty.call(payload, "departmentId") ||
      Object.prototype.hasOwnProperty.call(payload, "departmentIds")) &&
    (actorIsAdmin || actorCanManageUsers)
  ) {
    const previousDepartmentIds = Array.isArray(user.departmentIds)
      ? user.departmentIds.map((entry) => entry.toString())
      : user.departmentId
        ? [user.departmentId.toString()]
        : [];
    const nextDepartmentIds = (
      await resolveDepartmentAssignments(
        payload.departmentIds,
        payload.departmentId,
      )
    ).map((entry) => entry.toString());
    user.departmentIds = nextDepartmentIds;
    user.departmentId = nextDepartmentIds[0] || null;

    const removedDepartmentIds = previousDepartmentIds.filter(
      (entry) => !nextDepartmentIds.includes(entry),
    );
    const addedDepartmentIds = nextDepartmentIds.filter(
      (entry) => !previousDepartmentIds.includes(entry),
    );

    for (const deptId of removedDepartmentIds) {
      await Department.updateOne(
        { _id: deptId, deletedAt: null },
        { $inc: { membersCount: -1 } },
      );
    }
    for (const deptId of addedDepartmentIds) {
      await Department.updateOne(
        { _id: deptId, deletedAt: null },
        { $inc: { membersCount: 1 } },
      );
    }
  }

  if (
    Object.prototype.hasOwnProperty.call(payload, "branchId") &&
    (actorIsAdmin || actorCanManageUsers)
  ) {
    const previousBranchId = user.branchId?.toString() || null;
    const nextBranchAssignment = await resolveBranchAssignment(
      payload.branchId,
    );
    user.branchId = nextBranchAssignment.branchId;
    user.branchCode = nextBranchAssignment.branchCode;
    const nextBranchId = user.branchId?.toString() || null;

    if (previousBranchId && previousBranchId !== nextBranchId) {
      await Branch.updateOne(
        { _id: previousBranchId, deletedAt: null },
        { $inc: { membersCount: -1 } },
      );
    }
    if (nextBranchId && previousBranchId !== nextBranchId) {
      await Branch.updateOne(
        { _id: nextBranchId, deletedAt: null },
        { $inc: { membersCount: 1 } },
      );
    }
  }

  if (payload.password) {
    user.passwordHash = await bcrypt.hash(payload.password, 10);
    user.refreshTokenNonce = crypto.randomBytes(16).toString("hex");
    user.refreshSessions = [];
    incrementTokenVersion(user);
  }

  try {
    await user.save();
  } catch (error) {
    if (isDuplicateUsernameError(error)) {
      throw new ApiError(409, "Username already exists.");
    }
    throw error;
  }
  await logAuditEvent({
    actorId: actor.id,
    action: "user.updated",
    entityType: "User",
    entityId: user._id,
    payload: {
      role: user.role,
      departmentId: user.departmentId?.toString() || null,
      branchId: user.branchId?.toString() || null,
      branchCode: user.branchCode || "MAIN",
    },
  });
  return serializeUser(user, await getEffectivePermissionsForUser(user));
}

async function patchUserStatus(actor, userId, isActive) {
  if (actor.role !== "admin" && actor.permissions?.canCreateUsers !== true) {
    throw new ApiError(403, "Admin access required.");
  }

  const user = await getUserById(userId);
  user.isActive = Boolean(isActive);
  if (!user.isActive) {
    user.isOnline = false;
    user.presenceStatus = "offline";
    user.lastSeen = new Date();
  }
  await user.save();
  await logAuditEvent({
    actorId: actor.id,
    action: "user.status.updated",
    entityType: "User",
    entityId: user._id,
    payload: { isActive: user.isActive },
  });
  return serializeUser(user, await getEffectivePermissionsForUser(user));
}

async function resetUserPassword(actor, userId, password) {
  if (actor.role !== "admin" && actor.permissions?.canCreateUsers !== true) {
    throw new ApiError(403, "Admin access required.");
  }

  const user = await getUserById(userId);
  user.passwordHash = await bcrypt.hash(password, 10);
  user.refreshTokenNonce = crypto.randomBytes(16).toString("hex");
  user.refreshSessions = [];
  incrementTokenVersion(user);
  await user.save();

  await logAuditEvent({
    actorId: actor.id,
    action: "user.password.reset",
    entityType: "User",
    entityId: user._id,
    payload: {
      targetUsername: user.username,
    },
  });

  return serializeUser(user, await getEffectivePermissionsForUser(user));
}

async function getProfile(actor) {
  const user = await getUserById(actor.id);
  return serializeUser(user, await getEffectivePermissionsForUser(user));
}

async function updateProfile(actor, payload) {
  const user = await getUserById(actor.id);

  if (payload.fullName != null) {
    user.fullName = String(payload.fullName).trim().slice(0, 120);
  }

  if (payload.chatPreferences && typeof payload.chatPreferences === "object") {
    const rawThemeId = payload.chatPreferences.themeId;
    const rawWallpaperId = payload.chatPreferences.wallpaperId;
    const currentCustomTheme =
      user.chatPreferences?.customTheme || defaultCustomTheme();
    const incomingCustomTheme =
      payload.chatPreferences.customTheme &&
      typeof payload.chatPreferences.customTheme === "object"
        ? payload.chatPreferences.customTheme
        : null;
    user.chatPreferences = {
      themeId:
        rawThemeId != null
          ? String(rawThemeId).trim().slice(0, 60)
          : user.chatPreferences?.themeId || "system",
      wallpaperId:
        rawWallpaperId != null
          ? String(rawWallpaperId).trim().slice(0, 60)
          : user.chatPreferences?.wallpaperId || "default",
      customTheme: {
        accentColorHex: normalizeColorHex(
          incomingCustomTheme?.accentColorHex,
          currentCustomTheme.accentColorHex,
        ),
        outgoingBubbleColorHexes: normalizeColorHexList(
          incomingCustomTheme?.outgoingBubbleColorHexes,
          currentCustomTheme.outgoingBubbleColorHexes,
          { min: 1, max: 2 },
        ),
        incomingBubbleColorHex: normalizeColorHex(
          incomingCustomTheme?.incomingBubbleColorHex,
          currentCustomTheme.incomingBubbleColorHex,
        ),
        wallpaperColorHexes: normalizeColorHexList(
          incomingCustomTheme?.wallpaperColorHexes,
          currentCustomTheme.wallpaperColorHexes,
          { min: 2, max: 4 },
        ),
      },
    };
  }

  if (payload.password) {
    user.passwordHash = await bcrypt.hash(payload.password, 10);
    user.refreshTokenNonce = crypto.randomBytes(16).toString("hex");
    user.refreshSessions = [];
    incrementTokenVersion(user);
  }

  await user.save();
  await logAuditEvent({
    actorId: actor.id,
    action: "user.profile.updated",
    entityType: "User",
    entityId: user._id,
    payload: {
      fullName: user.fullName,
      chatPreferences: user.chatPreferences || null,
    },
  });
  return serializeUser(user, await getEffectivePermissionsForUser(user));
}

async function updateUserAvatar(actor, file) {
  if (!file) {
    throw new ApiError(400, "Avatar image is required.");
  }

  const user = await getUserById(actor.id);
  user.avatarUrl = `/api/users/${actor.id}/avatar?v=${Date.now()}`;
  await user.save();

  const avatarDirectory = getAvatarUploadsDir(actor.id);
  const entries = await fs.readdir(avatarDirectory);
  for (const entry of entries) {
    const candidatePath = path.join(avatarDirectory, entry);
    if (candidatePath !== resolveStoredUploadPath(file.path)) {
      await deleteFileIfExists(candidatePath);
    }
  }

  await logAuditEvent({
    actorId: actor.id,
    action: "user.avatar.updated",
    entityType: "User",
    entityId: user._id,
    payload: { avatarUrl: user.avatarUrl },
  });
  return serializeUser(user, await getEffectivePermissionsForUser(user));
}

async function getAvatarFilePath(userId) {
  const user = await User.findById(userId).lean();
  if (!user) {
    throw new ApiError(404, "Avatar not found.");
  }

  const avatarDirectory = getAvatarUploadsDir(userId);
  let entries = [];
  try {
    entries = await fs.readdir(avatarDirectory);
  } catch (_) {
    throw new ApiError(404, "Avatar not found.");
  }
  if (!entries.length) {
    throw new ApiError(404, "Avatar not found.");
  }
  const latestEntry = entries
    .map((fileName) => ({
      fileName,
      filePath: path.join(avatarDirectory, fileName),
    }))
    .sort((a, b) => (a.fileName < b.fileName ? 1 : -1))[0];
  return latestEntry.filePath;
}

const allowedPresenceStatuses = new Set([
  "online",
  "idle",
  "meeting",
  "lunch",
  "offline",
]);

function normalizePresenceStatus(value, fallback = "offline") {
  const normalized = String(value || "")
    .trim()
    .toLowerCase();
  if (allowedPresenceStatuses.has(normalized)) {
    return normalized;
  }
  return fallback;
}

async function setUserPresence(userId, stateOrOnline, maybeStatus = null) {
  const now = new Date();
  const isObject = typeof stateOrOnline === "object" && stateOrOnline !== null;
  const isOnline = isObject
    ? Boolean(stateOrOnline.isOnline)
    : Boolean(stateOrOnline);
  const status = normalizePresenceStatus(
    isObject
      ? stateOrOnline.status || (isOnline ? "online" : "offline")
      : maybeStatus || (isOnline ? "online" : "offline"),
    isOnline ? "online" : "offline",
  );

  const update = {
    isOnline: isOnline && status !== "offline",
    presenceStatus: status,
  };

  if (status !== "offline") {
    update.lastActiveAt = now;
  }

  if (!isOnline || status === "offline") {
    update.lastSeen = now;
  }

  await User.updateOne({ _id: userId }, { $set: update });
}

async function touchUserActivity(userId, status = "online") {
  const now = new Date();
  const normalizedStatus = normalizePresenceStatus(status, "online");
  await User.updateOne(
    { _id: userId },
    {
      $set: {
        isOnline: normalizedStatus !== "offline",
        presenceStatus: normalizedStatus,
        lastActiveAt: now,
      },
    },
  );
}

async function registerCurrentPushDevice(actor, payload) {
  return registerPushDevice(actor, payload);
}

async function unregisterCurrentPushDevice(actor, payload) {
  return unregisterPushDevice(actor, payload);
}

async function logoutUserAll(actor, userId, io = null) {
  const user = await getUserById(userId);
  if (actor.role !== "admin" && actor.id !== user._id.toString()) {
    throw new ApiError(403, "Permission denied.");
  }

  user.refreshSessions = [];
  incrementTokenVersion(user);
  await user.save();

  if (io) {
    io.to(`user:${userId}`).emit("force_logout", {
      reason: "admin_force_logout",
    });
  }

  await logAuditEvent({
    actorId: actor.id,
    action: "user.logout_all",
    entityType: "User",
    entityId: user._id,
    payload: {
      targetUsername: user.username,
    },
  });

  return serializeUser(user, await getEffectivePermissionsForUser(user));
}

async function deleteUser(actor, userId) {
  if (actor.role !== "admin" && actor.permissions?.canCreateUsers !== true) {
    throw new ApiError(403, "Admin access required.");
  }

  const user = await User.findById(userId).lean();
  if (!user) {
    throw new ApiError(404, "User not found.");
  }

  const Conversation = require("../chat/models/conversation.model");
  // Delete direct conversations where this user is a member
  await Conversation.deleteMany({
    type: "direct",
    members: userId,
  });

  // Pull user from members, admins, and broadcastPublisherIds in non-direct conversations
  await Conversation.updateMany(
    {
      type: { $ne: "direct" },
      $or: [
        { members: userId },
        { admins: userId },
        { broadcastPublisherIds: userId },
      ],
    },
    {
      $pull: {
        members: userId,
        admins: userId,
        broadcastPublisherIds: userId,
      },
    }
  );

  // Set createdBy to null in non-direct conversations created by this user
  await Conversation.updateMany(
    { createdBy: userId, type: { $ne: "direct" } },
    { $set: { createdBy: null } }
  );

  // Cascade delete tickets created by user
  await require("../tickets/models/ticket.model").deleteMany({
    createdBy: userId,
  });

  // Delete user avatar directory
  const avatarDir = require("../utils/storage-paths").getAvatarUploadsDir(
    userId,
  );
  try {
    await require("fs/promises").rm(avatarDir, {
      recursive: true,
      force: true,
    });
  } catch (e) {
    // Ignore if dir doesn't exist
  }

  // Delete user
  await User.deleteOne({ _id: userId });

  // Update department/branch member counts if applicable
  if (user.departmentId) {
    await Department.updateOne(
      { _id: user.departmentId, deletedAt: null },
      { $inc: { membersCount: -1 } },
    );
  }
  if (user.branchId) {
    await Branch.updateOne(
      { _id: user.branchId, deletedAt: null },
      { $inc: { membersCount: -1 } },
    );
  }

  await logAuditEvent({
    actorId: actor.id,
    action: "user.deleted",
    entityType: "User",
    entityId: userId,
    payload: {
      username: user.username,
      role: user.role,
    },
  });

  return { deleted: true, user };
}

module.exports = {
  listUsers,
  createUser,
  updateUser,
  patchUserStatus,
  resetUserPassword,
  logoutUserAll,
  deleteUser,
  getProfile,
  updateProfile,
  updateUserAvatar,
  getAvatarFilePath,
  setUserPresence,
  touchUserActivity,
  serializeUser,
  registerCurrentPushDevice,
  unregisterCurrentPushDevice,
};
