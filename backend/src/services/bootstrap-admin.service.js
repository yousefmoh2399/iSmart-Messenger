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

  return { enabled: true, created, updated };
}

module.exports = {
  ensureBootstrapAdmins,
};

