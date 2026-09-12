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
      continue;
    }

    existing.permissions = {
      ...permissions,
      ...(existing.permissions?.toObject?.() || existing.permissions || {}),
    };
    await existing.save();
  }
}

async function getPermissionsForRole(roleName) {
  const normalizedRoleName = String(roleName || "user").trim().toLowerCase();
  const role = await Role.findOne({ roleName: normalizedRoleName }).lean();
  return {
    ...(DEFAULT_ROLES[normalizedRoleName] || DEFAULT_ROLES.user),
    ...(role?.permissions || {}),
  };
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

module.exports = {
  DEFAULT_ROLES,
  ensureDefaultRoles,
  getPermissionsForRole,
  getEffectivePermissionsForUser,
  normalizePermissionOverrides,
  listRoles,
  createRole,
  updateRolePermissions,
  userHasPermission,
  serializeRole,
};
