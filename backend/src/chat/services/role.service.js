const Role = require("../models/role.model");
const ApiError = require("../../utils/api-error");

const DEFAULT_ROLES = {
  admin: {
    canCreateUsers: true,
    canCreateDepartments: true,
    canCreateRooms: true,
    canSendBroadcast: true,
    canDeleteMessages: true,
    canUploadFiles: true,
    canModerateDepartment: true,
    canViewDepartmentLogs: true,
    canManageAnnouncements: true,
    canManageFiles: true,
    canManageBranches: true,
    canManageRoles: true,
    canManageSystem: true,
    canManageUpdates: true,
    canManageBackups: true,
    canManageTickets: true,
    canViewPrinters: true,
    canManagePrinters: true,
    canSyncPrinters: true,
    canExportPrinterReports: true,
    canViewItAssets: true,
    canManageItAssets: true,
    canExecuteItAssets: true,
    canAuditItAssets: true,
    canManageItInventory: true,
    canInspectDamagedItAssets: true,
    canManageItProcurement: true,
    canExportItReports: true,
    canManageItSettings: true,
    canCloseItPeriods: true,
    canScanItAssets: true,
    canScanItSpareParts: true,
    canScanItInventory: true,
    canDeleteItAssets: true,
    canViewPurchaseRequests: true,
    canCreatePurchaseRequests: true,
    canUpdateDraftPurchaseRequests: true,
    canSubmitPurchaseRequests: true,
    canApproveItManagerPurchaseRequests: true,
    canReviewAuditPurchaseRequests: true,
    canApproveAuditPurchaseRequests: true,
    canApproveFinancePurchaseRequests: true,
    canRejectPurchaseRequests: true,
    canCancelPurchaseRequests: true,
    canSendToPurchasing: true,
    canMarkOrderedPurchaseRequests: true,
    canReceivePurchaseRequests: true,
    canClosePurchaseRequests: true,
    canExportPurchaseRequests: true,
    canPrintPdfPurchaseRequests: true,
    canAttachFilesPurchaseRequests: true,
    canViewReportsPurchaseRequests: true,
    canViewSnipeit: true,
    canViewSystemMonitor: true,
  },
  manager: {
    canCreateUsers: false,
    canCreateDepartments: false,
    canCreateRooms: true,
    canSendBroadcast: false,
    canDeleteMessages: true,
    canUploadFiles: true,
    canModerateDepartment: true,
    canViewDepartmentLogs: true,
    canManageAnnouncements: false,
    canManageFiles: false,
    canManageBranches: false,
    canManageRoles: false,
    canManageSystem: false,
    canManageUpdates: false,
    canManageBackups: false,
    canManageTickets: false,
    canViewPrinters: false,
    canManagePrinters: false,
    canSyncPrinters: false,
    canExportPrinterReports: false,
    canViewItAssets: false,
    canManageItAssets: false,
    canExecuteItAssets: false,
    canAuditItAssets: false,
    canManageItInventory: false,
    canInspectDamagedItAssets: false,
    canManageItProcurement: false,
    canExportItReports: false,
    canManageItSettings: false,
    canCloseItPeriods: false,
    canScanItAssets: false,
    canScanItSpareParts: false,
    canScanItInventory: false,
    canDeleteItAssets: false,
    canViewPurchaseRequests: true,
    canCreatePurchaseRequests: true,
    canUpdateDraftPurchaseRequests: true,
    canSubmitPurchaseRequests: true,
    canApproveItManagerPurchaseRequests: true,
    canReviewAuditPurchaseRequests: false,
    canApproveAuditPurchaseRequests: false,
    canApproveFinancePurchaseRequests: true,
    canRejectPurchaseRequests: true,
    canCancelPurchaseRequests: true,
    canSendToPurchasing: true,
    canMarkOrderedPurchaseRequests: true,
    canReceivePurchaseRequests: true,
    canClosePurchaseRequests: true,
    canExportPurchaseRequests: true,
    canPrintPdfPurchaseRequests: true,
    canAttachFilesPurchaseRequests: true,
    canViewReportsPurchaseRequests: true,
    canViewSnipeit: false,
  },
  user: {
    canCreateUsers: false,
    canCreateDepartments: false,
    canCreateRooms: false,
    canSendBroadcast: false,
    canDeleteMessages: false,
    canUploadFiles: true,
    canModerateDepartment: false,
    canViewDepartmentLogs: false,
    canManageAnnouncements: false,
    canManageFiles: false,
    canManageBranches: false,
    canManageRoles: false,
    canManageSystem: false,
    canManageUpdates: false,
    canManageBackups: false,
    canManageTickets: false,
    canViewPrinters: false,
    canManagePrinters: false,
    canSyncPrinters: false,
    canExportPrinterReports: false,
    canViewItAssets: false,
    canManageItAssets: false,
    canExecuteItAssets: false,
    canAuditItAssets: false,
    canManageItInventory: false,
    canInspectDamagedItAssets: false,
    canManageItProcurement: false,
    canExportItReports: false,
    canManageItSettings: false,
    canCloseItPeriods: false,
    canScanItAssets: false,
    canScanItSpareParts: false,
    canScanItInventory: false,
    canDeleteItAssets: false,
    canViewPurchaseRequests: true,
    canCreatePurchaseRequests: true,
    canUpdateDraftPurchaseRequests: true,
    canSubmitPurchaseRequests: true,
    canApproveItManagerPurchaseRequests: false,
    canReviewAuditPurchaseRequests: false,
    canApproveAuditPurchaseRequests: false,
    canApproveFinancePurchaseRequests: false,
    canRejectPurchaseRequests: false,
    canCancelPurchaseRequests: true,
    canSendToPurchasing: false,
    canMarkOrderedPurchaseRequests: false,
    canReceivePurchaseRequests: false,
    canClosePurchaseRequests: false,
    canExportPurchaseRequests: false,
    canPrintPdfPurchaseRequests: true,
    canAttachFilesPurchaseRequests: true,
    canViewReportsPurchaseRequests: false,
    canViewSnipeit: false,
  },
};

function serializeRole(role) {
  return {
    id: role._id.toString(),
    roleName: role.roleName,
    permissions: role.permissions,
    createdAt: role.createdAt,
    updatedAt: role.updatedAt,
  };
}

async function ensureDefaultRoles() {
  for (const [roleName, permissions] of Object.entries(DEFAULT_ROLES)) {
    const existing = await Role.findOne({ roleName });
    if (!existing) {
      await Role.create({ roleName, permissions });
      invalidateRoleCache(roleName);
      continue;
    }

    existing.permissions = {
      ...permissions,
      ...(existing.permissions?.toObject?.() || existing.permissions || {}),
    };
    await existing.save();
    invalidateRoleCache(roleName);
  }
}

const ROLE_CACHE_TTL_MS = Math.max(
  1000,
  Number(process.env.ROLE_CACHE_TTL_MS) || 60 * 1000,
);
const rolePermissionsCache = new Map();
const roleLookupInFlight = new Map();

function invalidateRoleCache(roleName = null) {
  if (!roleName) {
    rolePermissionsCache.clear();
    return;
  }
  rolePermissionsCache.delete(String(roleName).trim().toLowerCase());
}

async function getPermissionsForRole(roleName) {
  const normalizedRoleName = String(roleName || "user").trim().toLowerCase();
  const cached = rolePermissionsCache.get(normalizedRoleName);
  const now = Date.now();
  if (cached && now - cached.at < ROLE_CACHE_TTL_MS) {
    return { ...cached.permissions };
  }

  if (roleLookupInFlight.has(normalizedRoleName)) {
    const permissions = await roleLookupInFlight.get(normalizedRoleName);
    return { ...permissions };
  }

  const lookupPromise = (async () => {
    const role = await Role.findOne({ roleName: normalizedRoleName }).lean();
    const resolved = {
      ...(DEFAULT_ROLES[normalizedRoleName] || DEFAULT_ROLES.user),
      ...(role?.permissions || {}),
    };
    rolePermissionsCache.set(normalizedRoleName, {
      permissions: resolved,
      at: Date.now(),
    });
    return resolved;
  })().finally(() => {
    roleLookupInFlight.delete(normalizedRoleName);
  });

  roleLookupInFlight.set(normalizedRoleName, lookupPromise);
  const permissions = await lookupPromise;
  return { ...permissions };
}

async function preloadPermissionsForRoles(roleNames = []) {
  const normalized = Array.from(
    new Set(
      (roleNames || [])
        .map((r) => String(r || "user").trim().toLowerCase())
        .filter(Boolean),
    ),
  );
  const now = Date.now();
  const missing = normalized.filter((roleName) => {
    const cached = rolePermissionsCache.get(roleName);
    return !cached || now - cached.at >= ROLE_CACHE_TTL_MS;
  });

  if (missing.length > 0) {
    const docs = await Role.find({ roleName: { $in: missing } }).lean();
    const docMap = new Map(
      docs.map((doc) => [String(doc.roleName || "").trim().toLowerCase(), doc]),
    );
    const loadedAt = Date.now();
    for (const roleName of missing) {
      const doc = docMap.get(roleName);
      rolePermissionsCache.set(roleName, {
        permissions: {
          ...(DEFAULT_ROLES[roleName] || DEFAULT_ROLES.user),
          ...(doc?.permissions || {}),
        },
        at: loadedAt,
      });
    }
  }

  const result = new Map();
  for (const roleName of normalized) {
    const cached = rolePermissionsCache.get(roleName);
    result.set(
      roleName,
      cached
        ? { ...cached.permissions }
        : { ...(DEFAULT_ROLES[roleName] || DEFAULT_ROLES.user) },
    );
  }
  return result;
}

function normalizePermissionOverrides(value) {
  if (!value || typeof value !== "object") {
    return {};
  }
  const allowedKeys = new Set(
    Object.keys(DEFAULT_ROLES.admin || DEFAULT_ROLES.user),
  );
  let entries;
  if (value instanceof Map) {
    entries = [...value.entries()];
  } else {
    const source =
      typeof value.toObject === "function" ? value.toObject() : value;
    entries = Object.entries(source);
  }
  return Object.fromEntries(
    entries
      .filter(([key]) => allowedKeys.has(key))
      .map(([key, enabled]) => [key, enabled === true]),
  );
}

async function getEffectivePermissionsForUser(user) {
  const rolePermissions = await getPermissionsForRole(user?.role);
  return {
    ...rolePermissions,
    ...normalizePermissionOverrides(user?.permissionOverrides),
  };
}

async function listRoles() {
  const roles = await Role.find().sort({ roleName: 1 }).lean();
  return roles.map(serializeRole);
}

async function createRole(actor, payload) {
  if (!actor || (actor.role !== "admin" && actor.permissions?.canManageRoles !== true)) {
    throw new ApiError(403, "Permission denied.");
  }

  const roleName = String(payload.roleName || "").trim().toLowerCase();
  if (!roleName) {
    throw new ApiError(400, "roleName is required.");
  }

  const existing = await Role.findOne({ roleName }).lean();
  if (existing) {
    throw new ApiError(409, "Role already exists.");
  }

  const role = await Role.create({
    roleName,
    permissions: {
      ...(DEFAULT_ROLES.user || {}),
      ...(payload.permissions || {}),
    },
  });
  invalidateRoleCache(roleName);

  return serializeRole(role);
}

async function updateRolePermissions(actor, roleId, permissions) {
  if (!actor || (actor.role !== "admin" && actor.permissions?.canManageRoles !== true)) {
    throw new ApiError(403, "Permission denied.");
  }

  const role = await Role.findById(roleId);
  if (!role) {
    throw new ApiError(404, "Role not found.");
  }

  role.permissions = {
    ...role.permissions.toObject(),
    ...permissions,
  };
  await role.save();
  invalidateRoleCache(role.roleName);
  return serializeRole(role);
}

async function userHasPermission(user, permissionName) {
  if (!user) return false;
  if (user.permissions && typeof user.permissions === "object") {
    if (permissionName === "canViewItAssets") {
      return [
        "canViewItAssets",
        "canManageItAssets",
        "canExecuteItAssets",
        "canAuditItAssets",
        "canManageItInventory",
        "canInspectDamagedItAssets",
        "canManageItProcurement",
        "canExportItReports",
        "canManageItSettings",
        "canCloseItPeriods",
        "canScanItAssets",
        "canScanItSpareParts",
        "canScanItInventory",
        "canDeleteItAssets",
      ].some((key) => user.permissions[key] === true);
    }
    return Boolean(user.permissions[permissionName]);
  }
  const permissions = await getEffectivePermissionsForUser(user);
  if (permissionName === "canViewItAssets") {
    return [
      "canViewItAssets",
      "canManageItAssets",
      "canExecuteItAssets",
      "canAuditItAssets",
      "canManageItInventory",
      "canInspectDamagedItAssets",
      "canManageItProcurement",
      "canExportItReports",
      "canManageItSettings",
      "canCloseItPeriods",
      "canScanItAssets",
      "canScanItSpareParts",
      "canScanItInventory",
      "canDeleteItAssets",
    ].some((key) => permissions?.[key] === true);
  }
  return Boolean(permissions?.[permissionName]);
}

async function getEffectivePermissionsMapForUsers(users = []) {
  const roleMap = await preloadPermissionsForRoles(
    (users || []).map((user) => user?.role || "user"),
  );
  const result = new Map();
  for (const user of users || []) {
    if (!user) continue;
    const uid = String(user._id || user.id || "");
    if (!uid) continue;
    const roleName = String(user.role || "user").trim().toLowerCase();
    const rolePermissions = roleMap.get(roleName) || DEFAULT_ROLES.user;
    result.set(uid, {
      ...rolePermissions,
      ...normalizePermissionOverrides(user?.permissionOverrides),
    });
  }
  return result;
}

module.exports = {
  DEFAULT_ROLES,
  ensureDefaultRoles,
  getPermissionsForRole,
  preloadPermissionsForRoles,
  getEffectivePermissionsForUser,
  getEffectivePermissionsMapForUsers,
  invalidateRoleCache,
  normalizePermissionOverrides,
  listRoles,
  createRole,
  updateRolePermissions,
  userHasPermission,
  serializeRole,
};
