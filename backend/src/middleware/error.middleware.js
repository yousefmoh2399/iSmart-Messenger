const multer = require("multer");
const ApiError = require("../utils/api-error");
const { logSystemError } = require("../chat/services/system-error.service");
const logger = require("../utils/logger");

function sanitizeObject(value) {
  if (!value || typeof value !== "object") {
    return value;
  }
  const clone = Array.isArray(value) ? [...value] : { ...value };
  for (const key of Object.keys(clone)) {
    if (/token|password|secret/i.test(key)) {
      clone[key] = "***";
    }
  }
  return clone;
}

function notFoundHandler(req, res) {
  res.status(404).json({
    success: false,
    data: null,
    error: "المسار غير موجود.",
    message: "المسار غير موجود.",
  });
}

function translateApiErrorMessage(message, statusCode) {
  const raw = String(message || "").trim();
  const lower = raw.toLowerCase();

  if (statusCode === 429 || lower.includes("too many")) {
    return "تم تجاوز عدد المحاولات المسموح. حاول مرة أخرى بعد قليل.";
  }
  if (statusCode === 401) {
    if (lower.includes("invalid username or password")) {
      return "اسم المستخدم أو كلمة المرور غير صحيحة.";
    }
    return "انتهت صلاحية الجلسة أو فشل التحقق. سجل الدخول مرة أخرى.";
  }
  if (statusCode === 403) {
    // Do not collapse every 403 into one message (e.g. inactive account on login).
    if (lower.includes("inactive") || lower.includes("this account is inactive")) {
      return "هذا الحساب معطل. تواصل مع المسؤول لتفعيله.";
    }
    if (lower.includes("admin access required")) {
      return "هذه العملية مخصصة لمشرفي النظام فقط.";
    }
    if (lower.includes("permission denied")) {
      return "ليس لديك صلاحية لتنفيذ هذا الإجراء.";
    }
    if (/[\u0600-\u06FF]/.test(raw)) {
      return raw;
    }
    if (raw.length > 0) {
      return raw;
    }
    return "ليس لديك صلاحية لتنفيذ هذا الإجراء.";
  }
  if (statusCode === 404) {
    return "العنصر المطلوب غير موجود.";
  }
  if (statusCode === 409) {
    return "هذه البيانات موجودة بالفعل.";
  }

  return raw || "حدث خطأ غير متوقع.";
}

function errorHandler(error, req, res, next) {
  const requestMeta = {
    ip: req.ip,
    query: sanitizeObject(req.query),
    body:
      req.method === "GET" || req.method === "HEAD"
        ? null
        : sanitizeObject(req.body),
  };

  if (error instanceof multer.MulterError && error.code === "LIMIT_FILE_SIZE") {
    void logSystemError({
      actorId: req.user?.id || null,
      method: req.method,
      path: req.originalUrl,
      statusCode: 400,
      errorName: error.name,
      message: error.message,
      meta: requestMeta,
    });
    res.status(400).json({
      success: false,
      data: null,
      error: "حجم الملف المرفوع أكبر من الحد المسموح لمرفقات الشات.",
      message: "حجم الملف المرفوع أكبر من الحد المسموح لمرفقات الشات.",
    });
    return;
  }

  if (error instanceof ApiError) {
    const translatedMessage = translateApiErrorMessage(
      error.message,
      error.statusCode,
    );

    // Structured audit logs for auth-related failures.
    if (error.statusCode === 401 || error.statusCode === 403 || error.statusCode === 429) {
      logger.warn("request.rejected", {
        statusCode: error.statusCode,
        path: req.originalUrl,
        method: req.method,
        actorId: req.user?.id || null,
        ip: req.ip,
        errorName: error.name,
        errorMessage: error.message,
      });
    }

    if (error.statusCode >= 500) {
      void logSystemError({
        actorId: req.user?.id || null,
        method: req.method,
        path: req.originalUrl,
        statusCode: error.statusCode,
        errorName: error.name,
        message: error.message,
        stack: error.stack,
        meta: {
          ...requestMeta,
          details: error.details || null,
        },
      });
    }
    res.status(error.statusCode).json({
      success: false,
      data: null,
      error: translatedMessage,
      message: translatedMessage,
      details: error.details,
    });
    return;
  }

  if (
    error?.name === "MongooseError" ||
    error?.name === "MongoServerSelectionError" ||
    error?.name === "MongoNetworkError"
  ) {
    console.error(error);
    void logSystemError({
      actorId: req.user?.id || null,
      method: req.method,
      path: req.originalUrl,
      statusCode: 503,
      errorName: error.name,
      message: error.message || "Database unavailable.",
      stack: error.stack,
      meta: requestMeta,
    });
    res.status(503).json({
      success: false,
      data: null,
      error: "قاعدة البيانات غير متاحة حاليًا. حاول مرة أخرى لاحقًا.",
      message: "قاعدة البيانات غير متاحة حاليًا. حاول مرة أخرى لاحقًا.",
    });
    return;
  }

  console.error(error);
  void logSystemError({
    actorId: req.user?.id || null,
    method: req.method,
    path: req.originalUrl,
    statusCode: 500,
    errorName: error?.name || "Error",
    message: error?.message || "Internal server error.",
    stack: error?.stack || null,
    meta: requestMeta,
  });
  res.status(500).json({
    success: false,
    data: null,
    error: "حدث خطأ داخلي في الخادم.",
    message: "حدث خطأ داخلي في الخادم.",
  });
}

module.exports = {
  notFoundHandler,
  errorHandler,
};
