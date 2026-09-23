const bcrypt = require("bcryptjs");
const User = require("../models/user.model");
const logger = require("../utils/logger");
const {
  bootstrapAdminEnabled,
  bootstrapAdminForce,
  bootstrapAdmins,
} = require("../config/env");

async function ensureBootstrapAdmins() {
  if (!bootstrapAdminEnabled) {
    return { enabled: false, created: 0, updated: 0 };
  }

  if (!bootstrapAdmins.length) {
    logger.warn("bootstrap_admin.misconfigured", {
      message: "BOOTSTRAP_ADMIN_ENABLED=true but no admins configured",
    });
    return { enabled: true, created: 0, updated: 0 };
  }

  const usersCount = await User.estimatedDocumentCount();
  if (usersCount > 0 && !bootstrapAdminForce) {
    return { enabled: true, skipped: true, created: 0, updated: 0 };
  }

  let created = 0;
  let updated = 0;

  for (const admin of bootstrapAdmins) {
    const username = String(admin.username || "").trim().toLowerCase().slice(0, 50);
    const fullName = String(admin.fullName || "System Administrator")
      .trim()
      .slice(0, 120);
    const password = String(admin.password || "");
    if (!username || !password) {
      continue;
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const existing = await User.findOne({ username }).lean();
    await User.updateOne(
      { username },
      {
        $set: {
          username,
          fullName,
          role: "admin",
          isActive: true,
          passwordHash,
          refreshTokenNonce: null,
          refreshSessions: [],
        },
      },
      { upsert: true }
    );

    if (existing) {
      updated += 1;
    } else {
      created += 1;
    }
  }

  logger.warn("bootstrap_admin.ready", {
    created,
    updated,
    forced: bootstrapAdminForce,
  });

  // Clear the plain-text password from the config file on disk (security).
  // The account is already created in MongoDB with a bcrypt hash.
  _clearBootstrapPasswordFromConfig();

  return { enabled: true, created, updated };
}

/**
 * Removes BOOTSTRAP_ADMIN*_PASSWORD fields from the JSON config file
 * that the installer writes (ISMART_CONFIG_PATH or --config path).
 * Silently no-ops if the file is not found or not writable.
 */
function _clearBootstrapPasswordFromConfig() {
  try {
    const fs   = require("fs");
    const path = require("path");
    const cfgPath = process.env.ISMART_CONFIG_PATH || "";
    if (!cfgPath || !fs.existsSync(cfgPath)) return;
    const raw  = fs.readFileSync(cfgPath, "utf8");
    const obj  = JSON.parse(raw);
    let changed = false;
    for (const key of Object.keys(obj)) {
      if (/BOOTSTRAP_ADMIN.*_PASSWORD/.test(key) || key === "BOOTSTRAP_ADMIN_PASSWORD") {
        delete obj[key];
        changed = true;
      }
    }
    if (changed) {
      fs.writeFileSync(cfgPath, JSON.stringify(obj, null, 2), "utf8");
      logger.info("bootstrap_admin.password_cleared_from_config", { path: cfgPath });
    }
  } catch (_) {
    // Non-critical — don't crash the server
  }
}

module.exports = {
  ensureBootstrapAdmins,
};

