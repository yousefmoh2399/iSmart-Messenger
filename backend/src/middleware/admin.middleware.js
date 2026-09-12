const ApiError = require("../utils/api-error");

function requireAdmin(req, res, next) {
  if (req.user?.role !== "admin") {
    next(new ApiError(403, "Admin access required."));
    return;
  }

  next();
}

module.exports = {
  requireAdmin,
};
