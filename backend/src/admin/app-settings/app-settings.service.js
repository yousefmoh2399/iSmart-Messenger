const AppSettings = require("./app-settings.model");
const ApiError = require("../../utils/api-error");

function normalizeUrl(value) {
  const trimmed = String(value || "").trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizePorts(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  const seen = new Set();
  const ports = [];
  for (const entry of value) {
    const port = Number.parseInt(String(entry ?? "").trim(), 10);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      continue;
    }
    if (seen.has(port)) {
      continue;
    }
    seen.add(port);
    ports.push(port);
  }
  return ports;
}

function normalizeServerTargets(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((entry) => {
      const title = String(entry?.title || "").trim();
      const baseUrl = String(entry?.baseUrl || "").trim();
      const ports = normalizePorts(entry?.ports);
      if (!title || !baseUrl) {
        return null;
      }
      return {
        title: title.slice(0, 120),
        baseUrl: baseUrl.slice(0, 500),
        ports,
      };
    })
    .filter(Boolean);
}

async function getOrCreateSettings() {
  const existing = await AppSettings.findOne({
    singletonKey: "default",
  }).lean();
  if (existing) {
    return existing;
  }
  const created = await AppSettings.create({
    singletonKey: "default",
    desktopBaseUrl: null,
    mobileBaseUrl: null,
    snipeitUrl: null,
    serverTargets: [],
    showServersShortcut: true,
  });
  return created.toObject();
}

function serializeSettings(settings) {
  if (!settings) {
    return {
      desktopBaseUrl: null,
      mobileBaseUrl: null,
      snipeitUrl: null,
      serverTargets: [],
      showServersShortcut: true,
      updatedAt: null,
      updatedBy: null,
    };
  }
  return {
    desktopBaseUrl: settings.desktopBaseUrl || null,
    mobileBaseUrl: settings.mobileBaseUrl || null,
    snipeitUrl: settings.snipeitUrl || null,
    serverTargets: Array.isArray(settings.serverTargets)
      ? settings.serverTargets.map((entry) => ({
          title: String(entry.title || "").trim(),
          baseUrl: String(entry.baseUrl || "").trim(),
          ports: normalizePorts(entry.ports),
        }))
      : [],
    showServersShortcut: settings.showServersShortcut !== false,
    updatedAt: settings.updatedAt || null,
    updatedBy: settings.updatedBy?.toString?.() || settings.updatedBy || null,
  };
}

async function getAppSettings() {
  const settings = await getOrCreateSettings();
  return serializeSettings(settings);
}

async function updateAppSettings(currentUser, payload = {}) {
  if (!currentUser || currentUser.role !== "admin") {
    throw new ApiError(403, "Admin access required.");
  }

  const desktopBaseUrl = normalizeUrl(payload.desktopBaseUrl);
  const mobileBaseUrl = normalizeUrl(payload.mobileBaseUrl);
  const snipeitUrl = normalizeUrl(payload.snipeitUrl);
  const serverTargets = normalizeServerTargets(payload.serverTargets);
  const showServersShortcut = payload.showServersShortcut !== false;

  const settings = await AppSettings.findOneAndUpdate(
    { singletonKey: "default" },
    {
      $set: {
        desktopBaseUrl,
        mobileBaseUrl,
        snipeitUrl,
        serverTargets,
        showServersShortcut,
        updatedBy: currentUser.id,
      },
    },
    { upsert: true, new: true, setDefaultsOnInsert: true },
  ).lean();

  return serializeSettings(settings);
}

module.exports = {
  getAppSettings,
  updateAppSettings,
};
