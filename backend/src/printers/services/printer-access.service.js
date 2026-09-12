const ApiError = require("../../utils/api-error");

function hasPermission(actor, permission) {
  return actor?.role === "admin" || actor?.permissions?.[permission] === true;
}

function requirePrinterAccess(actor) {
  if (
    hasPermission(actor, "canViewPrinters") ||
    hasPermission(actor, "canManagePrinters") ||
    hasPermission(actor, "canSyncPrinters") ||
    hasPermission(actor, "canExportPrinterReports")
  ) {
    return;
  }
  throw new ApiError(403, "Permission denied.");
}

function requirePrinterManagement(actor) {
  if (hasPermission(actor, "canManagePrinters")) return;
  throw new ApiError(403, "Permission denied.");
}

function requirePrinterSync(actor) {
  if (hasPermission(actor, "canSyncPrinters") || hasPermission(actor, "canManagePrinters")) return;
  throw new ApiError(403, "Permission denied.");
}

function requirePrinterReports(actor) {
  if (hasPermission(actor, "canExportPrinterReports") || hasPermission(actor, "canManagePrinters")) return;
  throw new ApiError(403, "Permission denied.");
}

module.exports = {
  hasPermission,
  requirePrinterAccess,
  requirePrinterManagement,
  requirePrinterReports,
  requirePrinterSync,
};
