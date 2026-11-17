const { validationResult } = require("express-validator");
const ApiError = require("../utils/api-error");

function validateRequest(req, res, next) {
  const validation = validationResult(req);
  if (!validation.isEmpty()) {
    const details = validation.array().map((entry) => ({
      field: entry.path,
      message: entry.msg,
    }));
    const firstMsg = details[0]?.message || "فشل التحقق من البيانات.";
    next(new ApiError(400, firstMsg, details));
    return;
  }

  next();
}

module.exports = validateRequest;
