const { TextEncoder, TextDecoder } = require("text-encoding");
const util = require("util");
global.TextEncoder = TextEncoder;
global.TextDecoder = TextDecoder;
util.TextEncoder = TextEncoder;
util.TextDecoder = TextDecoder;

const express = require("express");
const compression = require("compression");
const cors = require("cors");
const helmet = require("helmet");
const morgan = require("morgan");
const rateLimit = require("express-rate-limit");
const {
  allowDetailedHealth,
  allowUnsafeCors,
  corsOrigin,
  env,
  trustProxy,
} = require("./config/env");
const { getDatabaseStatus } = require("./config/database");
const { getRedisStatus } = require("./config/redis");
const authRoutes = require("./routes/auth.routes");
const documentRoutes = require("./routes/document.routes");
const userRoutes = require("./routes/user.routes");
const adminBackupRoutes = require("./admin/backup/backup.routes");
const adminUpdateRoutes = require("./admin/updates/update-admin.routes");
const updateClientRoutes = require("./admin/updates/update-client.routes");
const announcementRoutes = require("./admin/announcements/announcement.routes");
const adminAppSettingsRoutes = require("./admin/app-settings/app-settings.routes");
const appSettingsRoutes = require("./routes/app-settings.routes");
const departmentRoutes = require("./chat/routes/department.routes");
const adminDepartmentRoutes = require("./chat/routes/admin-department.routes");
const branchRoutes = require("./chat/routes/branch.routes");
const adminBranchRoutes = require("./chat/routes/admin-branch.routes");
const adminRoleRoutes = require("./chat/routes/admin-role.routes");
const chatRoutes = require("./chat/routes/chat.routes");
const ticketRoutes = require("./tickets/routes/ticket.routes");
const printerRoutes = require("./printers/routes/printer.routes");
const itAssetsRoutes = require("./it-assets/it-assets.routes");
const itAssetsAdvancedRoutes = require("./it-assets/it-assets-advanced.routes");
const purchasingRoutes = require("./purchasing/routes/purchasing.routes");
const {
  notFoundHandler,
  errorHandler,
} = require("./middleware/error.middleware");

const app = express();

app.set("trust proxy", trustProxy);

function buildCorsOrigin() {
  if (corsOrigin === "*") {
    if (env === "production" && !allowUnsafeCors) {
      throw new Error(
        "CORS_ORIGIN=* is not allowed in production. Set CORS_ORIGIN to explicit origins.",
      );
    }
    return true;
  }
  return corsOrigin;
}

function sanitizeMorganUrl(url) {
  try {
    const parsed = new URL(url, "http://local");
    for (const key of ["token", "accessToken", "refreshToken"]) {
      if (parsed.searchParams.has(key)) {
        parsed.searchParams.set(key, "[redacted]");
      }
    }
    return `${parsed.pathname}${parsed.search}${parsed.hash}`;
  } catch (_) {
    return String(url || "").replace(
      /([?&](?:token|accessToken|refreshToken)=)[^&]+/gi,
      "$1[redacted]",
    );
  }
}

morgan.token("safe-url", (req) => sanitizeMorganUrl(req.originalUrl || req.url));

app.use(
  cors({
    origin: buildCorsOrigin(),
  }),
);
app.use(compression());
app.use(helmet());
app.use(
  morgan(":method :safe-url :status :response-time ms - :res[content-length]", {
    skip: (req) =>
      req.method === "POST" &&
      /^\/api\/updates\/tasks\/[a-f0-9]{24}\/progress$/i.test(
        req.originalUrl || req.url || "",
      ),
  }),
);
app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true, limit: "1mb" }));

app.use(
  "/api",
  rateLimit({
    windowMs: 60 * 1000,
    max: 600,
    skip: (req) =>
      req.method === "POST" &&
      /^\/api\/updates\/tasks\/[a-f0-9]{24}\/progress$/i.test(
        req.originalUrl || req.url || "",
      ),
    standardHeaders: true,
    legacyHeaders: false,
    message: {
      success: false,
      message: "تم تجاوز عدد الطلبات المسموح. حاول مرة أخرى بعد قليل.",
    },
  }),
);

// Increase timeout for upload endpoints
app.use("/api/admin/updates/releases", (req, res, next) => {
  req.setTimeout(15 * 60 * 1000); // 15 minutes for releases upload
  res.setTimeout(15 * 60 * 1000);
  next();
});
app.use("/api/updates", (req, res, next) => {
  req.setTimeout(10 * 60 * 1000); // 10 minutes for update endpoints
  res.setTimeout(10 * 60 * 1000);
  next();
});
app.use("/api/chat/transfers", (req, res, next) => {
  req.setTimeout(15 * 60 * 1000);
  res.setTimeout(15 * 60 * 1000);
  next();
});

app.get("/", (req, res) => {
  res.status(200).json({
    status: "ok",
    service: "workplace-document-backend",
  });
});

app.get("/health", (req, res) => {
  const payload = {
    status: "ok",
    service: "workplace-document-backend",
  };
  if (allowDetailedHealth) {
    payload.database = getDatabaseStatus();
    payload.redis = getRedisStatus();
  }
  res.status(200).json(payload);
});

app.use("/api/auth", authRoutes);
app.use("/api/documents", documentRoutes);
app.use("/api/users", userRoutes);
app.use("/api/admin/users", userRoutes);

// Increase timeout for admin backup operations
app.use("/api/admin/backup", (req, res, next) => {
  req.setTimeout(15 * 60 * 1000); // 15 minutes
  res.setTimeout(15 * 60 * 1000);
  next();
});
app.use("/api/admin/backup", adminBackupRoutes);

app.use("/api/admin/updates", adminUpdateRoutes);
app.use("/api/admin/app-settings", adminAppSettingsRoutes);
app.use("/api/updates", updateClientRoutes);
app.use("/api/announcements", announcementRoutes);
app.use("/api/app-settings", appSettingsRoutes);
app.use("/api/departments", departmentRoutes);
app.use("/api/admin/departments", adminDepartmentRoutes);
app.use("/api/branches", branchRoutes);
app.use("/api/admin/branches", adminBranchRoutes);
app.use("/api/admin/roles", adminRoleRoutes);
app.use("/api/chat", chatRoutes);


app.use("/api/tickets", ticketRoutes);
app.use("/api/admin/tickets", ticketRoutes);
app.use("/api/printers", printerRoutes);
app.use("/api/admin/printers", printerRoutes);
app.use("/api/it-assets", itAssetsRoutes);
app.use("/api/it-assets", itAssetsAdvancedRoutes);
app.use("/api/purchase-requests", purchasingRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

module.exports = app;
