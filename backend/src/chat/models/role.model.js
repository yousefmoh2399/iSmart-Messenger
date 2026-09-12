const mongoose = require("mongoose");

const permissionsSchema = new mongoose.Schema(
  {
    canCreateUsers: { type: Boolean, default: false },
    canCreateDepartments: { type: Boolean, default: false },
    canCreateRooms: { type: Boolean, default: false },
    canSendBroadcast: { type: Boolean, default: false },
    canDeleteMessages: { type: Boolean, default: false },
    canUploadFiles: { type: Boolean, default: true },
    canModerateDepartment: { type: Boolean, default: false },
    canViewDepartmentLogs: { type: Boolean, default: false },
    canManageAnnouncements: { type: Boolean, default: false },
    canManageFiles: { type: Boolean, default: false },
    canManageBranches: { type: Boolean, default: false },
    canManageRoles: { type: Boolean, default: false },
    canManageSystem: { type: Boolean, default: false },
    canManageUpdates: { type: Boolean, default: false },
    canManageBackups: { type: Boolean, default: false },
    canManageTickets: { type: Boolean, default: false },
    canViewSnipeit: { type: Boolean, default: false },
    canViewPrinters: { type: Boolean, default: false },
    canManagePrinters: { type: Boolean, default: false },
    canSyncPrinters: { type: Boolean, default: false },
    canExportPrinterReports: { type: Boolean, default: false },
    canViewItAssets: { type: Boolean, default: false },
    canManageItAssets: { type: Boolean, default: false },
    canExecuteItAssets: { type: Boolean, default: false },
    canAuditItAssets: { type: Boolean, default: false },
    canManageItInventory: { type: Boolean, default: false },
    canInspectDamagedItAssets: { type: Boolean, default: false },
    canManageItProcurement: { type: Boolean, default: false },
    canExportItReports: { type: Boolean, default: false },
    canManageItSettings: { type: Boolean, default: false },
    canCloseItPeriods: { type: Boolean, default: false },
    canScanItAssets: { type: Boolean, default: false },
    canScanItSpareParts: { type: Boolean, default: false },
    canScanItInventory: { type: Boolean, default: false },
    canDeleteItAssets: { type: Boolean, default: false },
  },
  { _id: false }
);

const roleSchema = new mongoose.Schema(
  {
    roleName: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      lowercase: true,
    },
    permissions: {
      type: permissionsSchema,
      required: true,
      default: () => ({}),
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model("Role", roleSchema);
