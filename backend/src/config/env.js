const fs = require("fs");
const path = require("path");
const os = require("os");
const crypto = require("crypto");

const isWindows = os.platform() === "win32";
const defaultConfigPath = isWindows
  ? "C:\\ProgramData\\iSmart\\config.json"
  : "/etc/ismart/config.json";

const configPath = process.env.ISMART_CONFIG_PATH || defaultConfigPath;

let configObj = {};
try {
  const configContent = fs.readFileSync(configPath, "utf8");
  configObj = JSON.parse(configContent);
} catch (error) {
  console.error(
    `\n[FATAL ERROR] Configuration file missing or invalid.\n` +
    `Expected config file at: ${configPath}\n` +
    `Please create this file with your database and environment settings.\n` +
    `Error details: ${error.message}\n`
  );
  process.exit(1);
}

// Fallback logic for JWT_SECRET
if (!configObj.JWT_SECRET) {
  console.error(
    `\n[FATAL ERROR] JWT_SECRET is missing from the configuration file.\n` +
    `Please set a strong, random string for JWT_SECRET in: ${configPath}\n`
  );
  process.exit(1);
}

// Extract DATA_DIR
const DATA_DIR = configObj.DATA_DIR;
if (!DATA_DIR) {
  console.error(
    `\n[FATAL ERROR] DATA_DIR is missing from the configuration file.\n` +
    `Please set DATA_DIR to an absolute path for persistent storage in: ${configPath}\n`
  );
  process.exit(1);
}

// Extract other values, prioritizing environment variables over config.json
// (so Docker or manual overrides still work if needed)
function getConfigValue(key, fallback = "") {
  return process.env[key] !== undefined ? process.env[key] : (configObj[key] !== undefined ? String(configObj[key]) : fallback);
}

const port = Number(getConfigValue("PORT", "5000"));
const maxFileSizeMb = Number(getConfigValue("MAX_FILE_SIZE_MB", "20"));
const updateArtifactMaxMb = Number(getConfigValue("UPDATE_ARTIFACT_MAX_MB", "1024"));
const redisUrl = String(getConfigValue("REDIS_URL", "")).trim() || null;
const env = getConfigValue("NODE_ENV", "production");
const bootstrapAdminEnabled =
  String(getConfigValue("BOOTSTRAP_ADMIN_ENABLED", ""))
    .trim()
    .toLowerCase() === "true";
const bootstrapAdminForce =
  String(getConfigValue("BOOTSTRAP_ADMIN_FORCE", ""))
    .trim()
    .toLowerCase() === "true";

function parseBootstrapAdmin(index) {
  const suffix = index === 1 ? "" : String(index);
  const username = String(getConfigValue(`BOOTSTRAP_ADMIN${suffix}_USERNAME`, ""))
    .trim()
    .toLowerCase();
  const password = String(getConfigValue(`BOOTSTRAP_ADMIN${suffix}_PASSWORD`, "")).trim();
  const fullName = String(getConfigValue(`BOOTSTRAP_ADMIN${suffix}_FULL_NAME`, ""))
    .trim()
    .slice(0, 120);
  if (!username || !password) return null;
  return {
    username: username.slice(0, 50),
    password,
    fullName: fullName || "System Administrator",
  };
}

const bootstrapAdmins = [parseBootstrapAdmin(1), parseBootstrapAdmin(2)].filter(Boolean);

function parseBoolean(value, fallback = false) {
  const raw = String(value ?? "").trim().toLowerCase();
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

function parseTrustProxy(value) {
  const raw = String(value ?? "").trim().toLowerCase();
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
  host: getConfigValue("HOST", "0.0.0.0"),
  mongodbUri: getConfigValue("MONGODB_URI", "mongodb://127.0.0.1:27017/workplace_documents"),
  redisUrl,
  bootstrapAdminEnabled,
  bootstrapAdminForce,
  bootstrapAdmins,
  jwtSecret: configObj.JWT_SECRET,
  baseUrl: getConfigValue("BASE_URL", `http://localhost:${port}`),
  // Path routing:
  uploadDir: path.join(DATA_DIR, "uploads"),
  backupsDir: path.join(DATA_DIR, "backups"),
  updateReleasesDir: path.join(DATA_DIR, "releases"),
  maxFileSizeBytes: maxFileSizeMb * 1024 * 1024,
  updateArtifactMaxBytes: updateArtifactMaxMb * 1024 * 1024,
  corsOrigin: parseCorsOrigins(getConfigValue("CORS_ORIGIN", "*")),
  allowQueryTokens: parseBoolean(getConfigValue("ALLOW_QUERY_TOKENS"), env !== "production"),
  allowDetailedHealth: parseBoolean(getConfigValue("ALLOW_DETAILED_HEALTH"), env !== "production"),
  allowUnsafeCors: parseBoolean(getConfigValue("ALLOW_UNSAFE_CORS"), env !== "production"),
  restoreEmergencyToken: String(getConfigValue("RESTORE_EMERGENCY_TOKEN", "")).trim(),
  restoreEmergencyAllowNonEmpty: parseBoolean(
    getConfigValue("RESTORE_EMERGENCY_ALLOW_NON_EMPTY"),
    false,
  ),
  backupPreRestoreSnapshot: parseBoolean(
    getConfigValue("BACKUP_PRE_RESTORE_SNAPSHOT"),
    true,
  ),
  trustProxy: parseTrustProxy(getConfigValue("TRUST_PROXY")),
  DATA_DIR,
};
