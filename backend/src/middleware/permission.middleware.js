const ApiError = require("../utils/api-error");
const { userHasPermission } = require("../chat/services/role.service");

function requirePermission(permissionName) {
  return async function permissionMiddleware(req, res, next) {
    const allowed = await userHasPermission(req.user, permissionName);
    if (!allowed) {
      next(new ApiError(403, "Permission denied."));
      return;
    }

    next();
  };
}

module.exports = {
  requirePermission,
};
