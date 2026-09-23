const dotenv = require("dotenv");
const path = require("path");
const fs = require("fs");

// When deployed as a standalone EXE (via pkg), the deployment scripts
// write all settings to a JSON file and pass its path via ISMART_CONFIG_PATH.
// We load that first so its values are available as process.env vars.
const configFilePath = String(process.env.ISMART_CONFIG_PATH || "").trim();
if (configFilePath && fs.existsSync(configFilePath)) {
  try {
    const fileConfig = JSON.parse(fs.readFileSync(configFilePath, "utf8"));
    for (const [key, value] of Object.entries(fileConfig)) {
      if (process.env[key] === undefined) {
        process.env[key] = String(value);
      }
    }
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error(`[env] Failed to load config file at ${configFilePath}: ${err.message}`);
  }
}

// Fallback to .env file for local development (ignored inside pkg snapshot)
dotenv.config({
  path: path.resolve(__dirname, "../../.env"),
});

const port = Number(process.env.PORT || 5000);
const maxFileSizeMb = Number(process.env.MAX_FILE_SIZE_MB || 20);
const updateArtifactMaxMb = Number(process.env.UPDATE_ARTIFACT_MAX_MB || 1024);
const redisUrl = String(process.env.REDIS_URL || "").trim() || null;
const env = process.env.NODE_ENV || "development";
const bootstrapAdminEnabled =
  String(process.env.BOOTSTRAP_ADMIN_ENABLED || "")
    .trim()
    .toLowerCase() === "true";
const bootstrapAdminForce =
  String(process.env.BOOTSTRAP_ADMIN_FORCE || "")
    .trim()
    .toLowerCase() === "true";

function parseBootstrapAdmin(index) {
  const suffix = index === 1 ? "" : String(index);
  const username = String(
    process.env[`BOOTSTRAP_ADMIN${suffix}_USERNAME`] || "",
  )
    .trim()
    .toLowerCase();
  const password = String(
    process.env[`BOOTSTRAP_ADMIN${suffix}_PASSWORD`] || "",
  ).trim();
  const fullName = String(
    process.env[`BOOTSTRAP_ADMIN${suffix}_FULL_NAME`] || "",
  )
    .trim()
    .slice(0, 120);
  if (!username || !password) return null;
  return {
    username: username.slice(0, 50),
    password,
    fullName: fullName || "System Administrator",
  };
}

const bootstrapAdmins = [parseBootstrapAdmin(1), parseBootstrapAdmin(2)].filter(
  Boolean,
);

function parseBoolean(value, fallback = false) {
  const raw = String(value ?? "")
    .trim()
    .toLowerCase();
  if (!raw) return fallback;
  return ["1", "true", "yes", "on"].includes(raw);
}

function parseCorsOrigins(value) {
  const raw = String(value || "").trim();
  if (!raw || raw === "*") {
    return raw || "*";
  }
  return raw
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function resolveJwtSecret() {
  const secret = String(process.env.JWT_SECRET || "").trim();
  const unsafeSecrets = new Set([
    "",
    "change-me-in-production",
    "replace_with_a_long_random_secret",
  ]);
  if (env === "production" && unsafeSecrets.has(secret)) {
    throw new Error(
      "JWT_SECRET must be set to a strong unique value in production.",
    );
  }
  return secret || "change-me-in-development";
}

function parseTrustProxy(value) {
  const raw = String(value ?? "")
    .trim()
    .toLowerCase();
  if (!raw) {
    return 1;
  }

  if (raw === "false" || raw === "0" || raw === "off" || raw === "no") {
    return false;
  }

  if (raw === "true" || raw === "on" || raw === "yes") {
    return 1;
  }

  const asNumber = Number(raw);
  if (Number.isFinite(asNumber) && asNumber >= 0) {
    return asNumber;
  }

  return value;
}

module.exports = {
  env,
  port,
  host: process.env.HOST || "0.0.0.0",
  mongodbUri:
    process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/workplace_documents",
  redisUrl,
  bootstrapAdminEnabled,
  bootstrapAdminForce,
  bootstrapAdmins,
  jwtSecret: resolveJwtSecret(),
  baseUrl: process.env.BASE_URL || `http://localhost:${port}`,
  uploadDir: process.env.UPLOADS_DIR || process.env.UPLOAD_DIR || "uploads",
  backupsDir: process.env.BACKUPS_DIR || "backups",
  updateReleasesDir:
    process.env.UPDATE_RELEASES_DIR || process.env.RELEASES_DIR || "releases",
  maxFileSizeBytes: maxFileSizeMb * 1024 * 1024,
  updateArtifactMaxBytes: updateArtifactMaxMb * 1024 * 1024,
  corsOrigin: parseCorsOrigins(process.env.CORS_ORIGIN || "*"),
  allowQueryTokens: parseBoolean(
    process.env.ALLOW_QUERY_TOKENS,
    env !== "production",
  ),
  allowDetailedHealth: parseBoolean(
    process.env.ALLOW_DETAILED_HEALTH,
    env !== "production",
  ),
  allowUnsafeCors: parseBoolean(
    process.env.ALLOW_UNSAFE_CORS,
    env !== "production",
  ),
  restoreEmergencyToken: String(
    process.env.RESTORE_EMERGENCY_TOKEN || "",
  ).trim(),
  restoreEmergencyAllowNonEmpty: parseBoolean(
    process.env.RESTORE_EMERGENCY_ALLOW_NON_EMPTY,
    false,
  ),
  backupPreRestoreSnapshot: parseBoolean(
    process.env.BACKUP_PRE_RESTORE_SNAPSHOT,
    true,
  ),
  trustProxy: parseTrustProxy(process.env.TRUST_PROXY),
};
