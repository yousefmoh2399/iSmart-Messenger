const PrinterBranch = require("../models/printer-branch.model");
const Printer = require("../models/printer.model");
const DailySnapshot = require("../models/daily-snapshot.model");
const SyncLog = require("../models/sync-log.model");
const WasteStatistic = require("../models/waste-statistic.model");
const CounterResetEvent = require("../models/counter-reset-event.model");
const PrinterNotification = require("../models/printer-notification.model");
const ApiError = require("../../utils/api-error");
const { LOG_FILE, logPrinterSync } = require("../../utils/printer-sync-file-logger");
const { discoverPrinters, probePrinter } = require("./snmp-printer.service");
const { buildExcelReport, buildPdfReport, buildPrinterPdfReport } = require("./printer-report.service");

const COUNTER_KEYS = [
  "totalPages",
  "monoPages",
  "colorPages",
  "duplexPages",
  "copyPages",
  "scanPages",
];

const wasteConfig = {
  paperJamWeight: 2,
  failedJobWeight: 1,
  interruptedJobWeight: 1,
  printerErrorWeight: 3,
};

let activeFullSyncPromise = null;
let activeFullSyncLogId = null;
let activeFullSyncStartedAt = null;
let activeFullSyncCancelRequested = false;
let activeFullSyncProgress = null;
let printerIndexMigrationPromise = null;

const NON_PRINTER_MODEL_REGEX =
  /prestige|zyxel|ub-e\d|ethernet interface card|router|gateway|switch|firewall|access point|wireless|mikrotik|fortigate|ubiquiti/i;

const SHEETS_PER_REAM = 500;
const SHEETS_PER_CLIENT = 16;
const MAX_BASELINE_AGE_MS = 36 * 60 * 60 * 1000;
const HIGH_MONTHLY_PRINTER_PAGES = 100_000;
const RESET_COUNTER_RATIO = 0.2;

function sanitizeMonthlyCounterUsage({ totalPages, monoPages, colorPages }) {
  const rawTotalPages = Math.max(0, Number(totalPages || 0));
  const rawMonoPages = Math.max(0, Number(monoPages || 0));
  const rawColorPages = Math.max(0, Number(colorPages || 0));
  const isSuspicious = rawTotalPages > HIGH_MONTHLY_PRINTER_PAGES;

  if (isSuspicious) {
    return {
      totalPages: 0,
      monoPages: 0,
      colorPages: 0,
      rawTotalPages,
      rawMonoPages,
      rawColorPages,
      excludedFromTotals: true,
    };
  }

  return {
    totalPages: rawTotalPages,
    monoPages: rawMonoPages,
    colorPages: rawColorPages,
    rawTotalPages,
    rawMonoPages,
    rawColorPages,
    excludedFromTotals: false,
  };
}

function resolveFullSyncTimeoutMs() {
  const value = Number(process.env.PRINTER_FULL_SYNC_TIMEOUT_MS || 20 * 60 * 1000);
  return Number.isFinite(value) && value > 0 ? value : 20 * 60 * 1000;
}

function isSyncTimedOut(startedAt, now = Date.now()) {
  const startedTime = new Date(startedAt || 0).getTime();
  return Number.isFinite(startedTime) && now - startedTime > resolveFullSyncTimeoutMs();
}

function serializeFullSyncProgress(progress = activeFullSyncProgress) {
  if (!progress) {
    return {
      running: false,
      status: "idle",
      logId: null,
      startedAt: null,
      endedAt: null,
      totalBranches: 0,
      completedBranches: 0,
      totalPrinters: 0,
      processedPrinters: 0,
      onlinePrinters: 0,
      offlinePrinters: 0,
      percent: 0,
      currentBranches: [],
      errors: [],
    };
  }
  const totalPrinters = Number(progress.totalPrinters || 0);
  const processedPrinters = Number(progress.processedPrinters || 0);
  const percent = totalPrinters > 0
    ? Math.max(0, Math.min(100, Math.round((processedPrinters / totalPrinters) * 100)))
    : Number(progress.completedBranches || 0) >= Number(progress.totalBranches || 0)
      ? 100
      : 0;
  return {
    ...progress,
    running: progress.status === "running",
    percent,
  };
}

function updateActiveFullSyncProgress(patch) {
  if (!activeFullSyncProgress) return;
  activeFullSyncProgress = {
    ...activeFullSyncProgress,
    ...patch,
    updatedAt: new Date(),
  };
}

function buildPaperConsumptionMetrics(totalPages) {
  const pages = Math.max(0, Number(totalPages || 0));
  return {
    sheetsPerReam: SHEETS_PER_REAM,
    sheetsPerClient: SHEETS_PER_CLIENT,
    exactReams: pages / SHEETS_PER_REAM,
    fullReams: Math.floor(pages / SHEETS_PER_REAM),
    remainingSheets: pages % SHEETS_PER_REAM,
    requiredReams: pages === 0 ? 0 : Math.ceil(pages / SHEETS_PER_REAM),
    estimatedClientsExact: pages / SHEETS_PER_CLIENT,
    estimatedClientsCeil: pages === 0 ? 0 : Math.ceil(pages / SHEETS_PER_CLIENT),
  };
}

function mergePrinterConsumption(target, source) {
  target.totalPages += Number(source.totalPages || 0);
  target.monoPages += Number(source.monoPages || 0);
  target.colorPages += Number(source.colorPages || 0);
  target.hasPartialData = Boolean(target.hasPartialData || source.hasPartialData);
  target.hasSuspiciousConsumption = Boolean(
    target.hasSuspiciousConsumption || source.hasSuspiciousConsumption,
  );
  target.hasBaselineSnapshot = Boolean(
    target.hasBaselineSnapshot || source.hasBaselineSnapshot,
  );
  target.firstSnapshotAt = target.firstSnapshotAt || source.firstSnapshotAt || null;
  target.lastSnapshotAt = source.lastSnapshotAt || target.lastSnapshotAt || null;
  target.paper = buildPaperConsumptionMetrics(target.totalPages);
}

function cloneBranchConsumption(branchConsumption) {
  const printerMap = new Map();
  for (const printer of branchConsumption.printers || []) {
    printerMap.set(printer.printerId, {
      ...printer,
      paper: buildPaperConsumptionMetrics(printer.totalPages),
    });
  }
  return {
    ...branchConsumption,
    printers: Array.from(printerMap.values()),
    printersCount: printerMap.size,
    paper: buildPaperConsumptionMetrics(branchConsumption.totalPages),
    _printerMap: printerMap,
  };
}

function serializeBranch(branch) {
  return {
    id: branch._id.toString(),
    name: branch.name,
    code: branch.code,
    networkRange: branch.networkRange,
    location: branch.location || "",
    status: branch.status,
    lastSyncAt: branch.lastSyncAt,
    createdAt: branch.createdAt,
    updatedAt: branch.updatedAt,
  };
}

function serializePrinter(printer) {
  return {
    id: printer._id.toString(),
    branchId: printer.branchId?._id?.toString?.() || printer.branchId?.toString?.() || printer.branchId,
    branchName: printer.branchId?.name || "",
    ipAddress: printer.ipAddress,
    hostname: printer.hostname || "",
    model: printer.model || "",
    serialNumber: printer.serialNumber || "",
    printerName: printer.printerName || printer.hostname || printer.ipAddress,
    macAddress: printer.macAddress || "",
    deviceFingerprint: printer.deviceFingerprint || "",
    identityConfidence: printer.identityConfidence || "weak",
    vendor: printer.vendor || "SNMP",
    status: printer.status,
    lastSyncAt: printer.lastSyncAt,
    counters: normalizeCounters(printer.counters),
    previousCounters: normalizeCounters(printer.previousCounters),
    lifetimeCounters: normalizeCounters(printer.lifetimeCounters),
    tonerLevels: printer.tonerLevels || {},
    maintenance: printer.maintenance || {},
    extendedDetails: printer.extendedDetails || {},
    replacedAt: printer.replacedAt,
    replacedByPrinterId: printer.replacedByPrinterId?.toString?.() || "",
    replacementReason: printer.replacementReason || "",
    anomalyFlags: printer.anomalyFlags || [],
    lastAnomalyAt: printer.lastAnomalyAt,
    createdAt: printer.createdAt,
    updatedAt: printer.updatedAt,
  };
}

function normalizeCounters(value = {}) {
  return Object.fromEntries(
    COUNTER_KEYS.map((key) => [key, Number(value?.[key] || 0)]),
  );
}

function buildPrinterIdentity(branchId, payload) {
  const serialNumber = String(payload.serialNumber || "").trim();
  if (serialNumber) return { serialNumber };
  return { branchId, ipAddress: payload.ipAddress };
}

function cleanIdentityValue(value) {
  return String(value || "").trim().toLowerCase();
}

function stableText(value) {
  return cleanIdentityValue(value).replace(/\s+/g, " ");
}

function buildDeviceIdentity(payload) {
  const serial = cleanIdentityValue(payload.serialNumber);
  if (serial) {
    return { fingerprint: `serial:${serial}`, confidence: "strong" };
  }
  const mac = cleanIdentityValue(payload.macAddress);
  if (mac) {
    return { fingerprint: `mac:${mac}`, confidence: "medium" };
  }
  const model = stableText(payload.model);
  const vendor = stableText(payload.vendor);
  const name = stableText(payload.printerName || payload.hostname);
  const parts = [vendor, model, name].filter(Boolean);
  return {
    fingerprint: parts.length ? `weak:${parts.join("|")}` : "",
    confidence: "weak",
  };
}

function identitySignals(existingPrinter, payload) {
  const signals = [];
  const incomingSerial = cleanIdentityValue(payload.serialNumber);
  const existingSerial = cleanIdentityValue(existingPrinter.serialNumber);
  if (incomingSerial && existingSerial && incomingSerial !== existingSerial) {
    signals.push(`serial ${existingPrinter.serialNumber} -> ${payload.serialNumber}`);
  }

  const incomingMac = cleanIdentityValue(payload.macAddress);
  const existingMac = cleanIdentityValue(existingPrinter.macAddress);
  if (incomingMac && existingMac && incomingMac !== existingMac) {
    signals.push(`mac ${existingPrinter.macAddress} -> ${payload.macAddress}`);
  }

  const existingModel = stableText(existingPrinter.model);
  const incomingModel = stableText(payload.model);
  if (existingModel && incomingModel && existingModel !== incomingModel) {
    signals.push(`model ${existingPrinter.model} -> ${payload.model}`);
  }

  const existingName = stableText(existingPrinter.printerName || existingPrinter.hostname);
  const incomingName = stableText(payload.printerName || payload.hostname);
  if (existingName && incomingName && existingName !== incomingName) {
    signals.push(`name ${existingPrinter.printerName || existingPrinter.hostname} -> ${payload.printerName || payload.hostname}`);
  }

  return signals;
}

function isDifferentKnownDevice(existingPrinter, payload) {
  const incomingSerial = cleanIdentityValue(payload.serialNumber);
  const existingSerial = cleanIdentityValue(existingPrinter.serialNumber);
  if (incomingSerial && existingSerial && incomingSerial !== existingSerial) {
    return true;
  }

  const incomingMac = cleanIdentityValue(payload.macAddress);
  const existingMac = cleanIdentityValue(existingPrinter.macAddress);
  if (incomingMac && existingMac && incomingMac !== existingMac) {
    return true;
  }

  const existingHasIdentity = Boolean(existingSerial || existingMac);
  const incomingHasIdentity = Boolean(incomingSerial || incomingMac);
  const existingTotal = Number(existingPrinter.counters?.totalPages || 0);
  const incomingTotal = Number(payload.counters?.totalPages || 0);
  const counterDropped = existingTotal > 0 && incomingTotal > 0 && incomingTotal < existingTotal;
  const weakSignals = identitySignals(existingPrinter, payload).filter((signal) =>
    signal.startsWith("model ") || signal.startsWith("name ")
  );
  if (
    !existingHasIdentity &&
    counterDropped &&
    (incomingHasIdentity || weakSignals.length > 0)
  ) {
    return true;
  }

  return false;
}

function replacementReason(existingPrinter, payload) {
  const reasons = identitySignals(existingPrinter, payload);
  const existingTotal = Number(existingPrinter.counters?.totalPages || 0);
  const incomingTotal = Number(payload.counters?.totalPages || 0);
  if (reasons.length === 0 && incomingTotal > 0 && incomingTotal < existingTotal) {
    reasons.push(`counter ${existingTotal} -> ${incomingTotal} with new device identity`);
  }
  return reasons.join("; ") || "device identity changed on same IP";
}

function shouldTreatAsCounterReset(previous, current) {
  if (previous <= 0 || current < 0 || current >= previous) return false;
  return current <= previous * RESET_COUNTER_RATIO;
}

async function mapWithConcurrency(items, concurrency, iteratee) {
  const workerCount = Math.max(
    1,
    Math.min(Number(concurrency) || 1, items.length || 1),
  );
  let cursor = 0;
  async function worker() {
    while (true) {
      const index = cursor;
      cursor += 1;
      if (index >= items.length) {
        return;
      }
      await iteratee(items[index], index);
    }
  }
  await Promise.all(Array.from({ length: workerCount }, () => worker()));
}

async function cleanupStaleFullSyncLogs() {
  const cutoff = new Date(Date.now() - resolveFullSyncTimeoutMs());
  const result = await SyncLog.updateMany(
    { scope: "full", status: "running", endedAt: null, startedAt: { $lte: cutoff } },
    {
      $set: {
        status: "failed",
        endedAt: new Date(),
        errors: ["Full sync exceeded the configured timeout and was stopped."],
      },
    },
  );
  if (result.modifiedCount > 0) {
    logPrinterSync("full_sync.stale_logs.cleaned", {
      modifiedCount: result.modifiedCount,
      timeoutMs: resolveFullSyncTimeoutMs(),
    });
  }
  if (activeFullSyncPromise && !isSyncTimedOut(activeFullSyncStartedAt)) {
    return;
  }
  if (activeFullSyncPromise) {
    activeFullSyncPromise = null;
    activeFullSyncLogId = null;
    activeFullSyncStartedAt = null;
    activeFullSyncCancelRequested = false;
  }
}

async function listBranches() {
  const branches = await PrinterBranch.find({ deletedAt: null }).sort({ name: 1 }).lean();
  return branches.map(serializeBranch);
}

async function createBranch(actor, payload) {
  const name = String(payload.name || "").trim();
  const code = String(payload.code || "").trim().toUpperCase();
  const networkRange = String(payload.networkRange || "").trim();
  if (!name || !code || !networkRange) {
    throw new ApiError(400, "Branch name, code, and network range are required.");
  }
  const exists = await PrinterBranch.findOne({ code, deletedAt: null }).lean();
  if (exists) throw new ApiError(409, "Branch code already exists.");
  const branch = await PrinterBranch.create({
    name,
    code,
    networkRange,
    location: String(payload.location || "").trim(),
    status: payload.status === "inactive" ? "inactive" : "active",
    createdBy: actor?.id || null,
  });
  return serializeBranch(branch);
}

async function updateBranch(branchId, payload) {
  const branch = await PrinterBranch.findOne({ _id: branchId, deletedAt: null });
  if (!branch) throw new ApiError(404, "Branch not found.");
  if (payload.name != null) branch.name = String(payload.name).trim();
  if (payload.code != null) {
    const code = String(payload.code).trim().toUpperCase();
    const exists = await PrinterBranch.findOne({ _id: { $ne: branch._id }, code, deletedAt: null }).lean();
    if (exists) throw new ApiError(409, "Branch code already exists.");
    branch.code = code;
  }
  if (payload.networkRange != null) branch.networkRange = String(payload.networkRange).trim();
  if (payload.location != null) branch.location = String(payload.location).trim();
  if (payload.status != null) branch.status = payload.status === "inactive" ? "inactive" : "active";
  await branch.save();
  return serializeBranch(branch);
}

async function deleteBranch(branchId) {
  const now = new Date();
  // Soft-delete all printers in this branch
  await Printer.updateMany({ branchId, deletedAt: null }, { $set: { deletedAt: now } });
  // Soft-delete the branch itself
  await PrinterBranch.updateOne({ _id: branchId }, { $set: { deletedAt: now } });
  return { deleted: true };
}

async function deletePrinter(printerId) {
  const printer = await Printer.findOne({ _id: printerId, deletedAt: null });
  if (!printer) throw new ApiError(404, "Printer not found.");
  printer.deletedAt = new Date();
  await printer.save();
  return { deleted: true };
}

async function listPrinters(filters = {}) {
  const query = { deletedAt: null };
  if (filters.branchId) query.branchId = filters.branchId;
  if (filters.status) query.status = filters.status;
  const q = String(filters.q || "").trim();
  if (q) {
    const regex = new RegExp(q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i");
    query.$or = [
      { printerName: regex },
      { hostname: regex },
      { model: regex },
      { serialNumber: regex },
      { ipAddress: regex },
    ];
  }
  const printers = await Printer.find(query).populate("branchId", "name code").sort({ updatedAt: -1 }).lean();
  return printers.map(serializePrinter);
}

async function getPrinterDetails(printerId) {
  const printer = await Printer.findOne({ _id: printerId, deletedAt: null }).populate("branchId", "name code").lean();
  if (!printer) throw new ApiError(404, "Printer not found.");
  const since = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
  const snapshots = await DailySnapshot.find({ printerId, snapshotAt: { $gte: since } })
    .sort({ snapshotAt: 1 })
    .lean();
  return {
    printer: serializePrinter(printer),
    history: snapshots.map((entry) => ({
      id: entry._id.toString(),
      snapshotAt: entry.snapshotAt,
      counters: normalizeCounters(entry.counters),
      lifetimeCounters: normalizeCounters(entry.lifetimeCounters),
      tonerLevels: entry.tonerLevels || {},
      maintenance: entry.maintenance || {},
      status: entry.status,
    })),
  };
}

async function upsertDiscoveredPrinter(branch, payload) {
  await ensurePrinterReplacementIndexes();
  const filter = buildPrinterIdentity(branch._id, payload);
  let printer = await Printer.findOne({ ...filter, deletedAt: null });
  const printerAtIp = await Printer.findOne({
    branchId: branch._id,
    ipAddress: payload.ipAddress,
    deletedAt: null,
  });

  if (printerAtIp && printer && printerAtIp._id.toString() !== printer._id.toString()) {
    const now = new Date();
    printerAtIp.deletedAt = now;
    printerAtIp.replacedAt = now;
    printerAtIp.replacedByPrinterId = printer._id;
    printerAtIp.replacementReason = replacementReason(printerAtIp, payload);
    printerAtIp.status = "offline";
    await printerAtIp.save();
    await PrinterNotification.create({
      type: "printer_replaced",
      severity: "warning",
      title: "Printer replacement detected",
      message: `${printerAtIp.printerName || printerAtIp.ipAddress} was replaced on ${payload.ipAddress}. ${printerAtIp.replacementReason}`,
      branchId: branch._id,
      printerId: printerAtIp._id,
    });
  } else if (!printer && printerAtIp) {
    if (isDifferentKnownDevice(printerAtIp, payload)) {
      const oldPrinter = printerAtIp;
      const now = new Date();
      oldPrinter.deletedAt = now;
      oldPrinter.replacedAt = now;
      oldPrinter.replacementReason = replacementReason(oldPrinter, payload);
      oldPrinter.status = "offline";
      await oldPrinter.save();

      printer = new Printer({
        branchId: branch._id,
        ipAddress: payload.ipAddress,
        previousCounters: {},
        lifetimeCounters: {},
      });
      oldPrinter.replacedByPrinterId = printer._id;
      await oldPrinter.save();
      await PrinterNotification.create({
        type: "printer_replaced",
        severity: "warning",
        title: "Printer replacement detected",
        message: `${oldPrinter.printerName || oldPrinter.ipAddress} was replaced on ${payload.ipAddress}. ${oldPrinter.replacementReason}`,
        branchId: branch._id,
        printerId: oldPrinter._id,
      });
    } else {
      printer = printerAtIp;
    }
  }

  if (!printer) {
    printer = new Printer({
      branchId: branch._id,
      ipAddress: payload.ipAddress,
      previousCounters: {},
      lifetimeCounters: {},
    });
  }

  // Restore printer to active if it was previously soft-deleted
  printer.deletedAt = null;

  printer.hostname = payload.hostname || printer.hostname || "";
  printer.model = payload.model || printer.model || "";
  printer.serialNumber = payload.serialNumber || printer.serialNumber || "";
  printer.printerName = payload.printerName || printer.printerName || payload.hostname || payload.ipAddress;
  printer.macAddress = payload.macAddress || printer.macAddress || "";
  const deviceIdentity = buildDeviceIdentity({
    ...payload,
    serialNumber: printer.serialNumber,
    macAddress: printer.macAddress,
    model: printer.model,
    vendor: payload.vendor || printer.vendor,
    printerName: printer.printerName,
    hostname: printer.hostname,
  });
  printer.deviceFingerprint = deviceIdentity.fingerprint || printer.deviceFingerprint || "";
  printer.identityConfidence = deviceIdentity.confidence || printer.identityConfidence || "weak";
  printer.vendor = payload.vendor || printer.vendor || "SNMP";
  printer.status = payload.status || "online";
  printer.lastSyncAt = new Date();
  printer.tonerLevels = { ...(printer.tonerLevels?.toObject?.() || printer.tonerLevels || {}), ...(payload.tonerLevels || {}) };
  printer.extendedDetails = {
    ...(printer.extendedDetails?.toObject?.() || printer.extendedDetails || {}),
    ...(payload.extendedDetails || {}),
  };
  const incomingMaintenance = { ...(payload.maintenance || {}) };
  if (Array.isArray(incomingMaintenance.errors) && !incomingMaintenance.errorMessages) {
    incomingMaintenance.errorMessages = incomingMaintenance.errors;
    delete incomingMaintenance.errors;
  }
  printer.maintenance = { ...(printer.maintenance?.toObject?.() || printer.maintenance || {}), ...incomingMaintenance };

  const previousCounters = normalizeCounters(printer.counters);
  const incomingCounters = normalizeCounters(payload.counters);
  const nextCounters = { ...previousCounters };
  const anomalyFlags = new Set(printer.anomalyFlags || []);
  const ignoredCounterDrops = [];

  for (const key of COUNTER_KEYS) {
    // Ignore 0 values from payload if we already have a non-zero counter (prevents SNMP read failures from resetting counters)
    if (
      incomingCounters[key] > 0 &&
      previousCounters[key] > 0 &&
      incomingCounters[key] < previousCounters[key] &&
      !shouldTreatAsCounterReset(previousCounters[key], incomingCounters[key])
    ) {
      ignoredCounterDrops.push(`${key}: ${previousCounters[key]} -> ${incomingCounters[key]}`);
      anomalyFlags.add(`ignored_${key}_drop`);
      continue;
    }
    if (incomingCounters[key] > 0 || nextCounters[key] === 0) {
      nextCounters[key] = incomingCounters[key];
    }
  }

  if (ignoredCounterDrops.length > 0) {
    printer.lastAnomalyAt = new Date();
    await PrinterNotification.create({
      type: "counter_anomaly",
      severity: "warning",
      title: "Suspicious printer counter ignored",
      message: `${printer.printerName || printer.ipAddress}: ${ignoredCounterDrops.join(", ")}.`,
      branchId: branch._id,
      printerId: printer._id,
    });
  }

  const lifetimeCounters = normalizeCounters(printer.lifetimeCounters);

  for (const key of COUNTER_KEYS) {
    const current = nextCounters[key];
    const previous = previousCounters[key];
    if (current > previous) {
      lifetimeCounters[key] += current - previous;
    } else if (current < previous) {
      const before = lifetimeCounters[key];
      lifetimeCounters[key] += current;
      await CounterResetEvent.create({
        printerId: printer._id,
        branchId: branch._id,
        counterName: key,
        previousValue: previous,
        currentValue: current,
        lifetimeBefore: before,
        lifetimeAfter: lifetimeCounters[key],
      });
      await PrinterNotification.create({
        type: "counter_reset",
        severity: "warning",
        title: "Counter reset detected",
        message: `${printer.printerName || printer.ipAddress} ${key} changed from ${previous} to ${current}.`,
        branchId: branch._id,
        printerId: printer._id,
      });
    }
  }

  printer.previousCounters = previousCounters;
  printer.counters = nextCounters;
  printer.lifetimeCounters = lifetimeCounters;
  printer.anomalyFlags = Array.from(anomalyFlags).slice(-20);
  await printer.save();
  await createSnapshotAndWaste(printer);
  await createOperationalNotifications(printer);
  return printer;
}

async function createSnapshotAndWaste(printer) {
  await DailySnapshot.create({
    printerId: printer._id,
    branchId: printer.branchId,
    counters: normalizeCounters(printer.counters),
    lifetimeCounters: normalizeCounters(printer.lifetimeCounters),
    tonerLevels: printer.tonerLevels || {},
    maintenance: printer.maintenance || {},
    extendedDetails: printer.extendedDetails || {},
    status: printer.status,
  });

  const errorMessages = Array.isArray(printer.maintenance?.errorMessages)
    ? printer.maintenance.errorMessages
    : [];
  const errors = errorMessages.length;
  const paperJams = Number(printer.maintenance?.paperJams || 0);
  const estimatedWastePages =
    paperJams * wasteConfig.paperJamWeight +
    errors * wasteConfig.printerErrorWeight;
  await WasteStatistic.create({
    printerId: printer._id,
    branchId: printer.branchId,
    paperJams,
    printerErrors: errors,
    estimatedWastePages,
    config: wasteConfig,
  });
}

async function createOperationalNotifications(printer) {
  if (printer.status === "offline" || printer.status === "error") {
    await PrinterNotification.create({
      type: "offline",
      severity: printer.status === "error" ? "critical" : "warning",
      title: "Printer offline",
      message: `${printer.printerName || printer.ipAddress} is ${printer.status}.`,
      branchId: printer.branchId,
      printerId: printer._id,
    });
  }
  const toner = (printer.tonerLevels && typeof printer.tonerLevels.toObject === "function")
    ? printer.tonerLevels.toObject()
    : printer.tonerLevels || {};
  for (const [name, value] of Object.entries(toner)) {
    if (typeof value === "number" && value <= 15) {
      await PrinterNotification.create({
        type: "toner_low",
        severity: value <= 5 ? "critical" : "warning",
        title: "Low toner",
        message: `${printer.printerName || printer.ipAddress} ${name} toner is ${value}%.`,
        branchId: printer.branchId,
        printerId: printer._id,
      });
    }
  }
}

async function discoverBranchPrinters(actor, branchId, options = {}) {
  const startedAt = Date.now();
  const includePrinters = options.includePrinters !== false;
  const skipWebDetails = options.skipWebDetails !== false;
  const fastDiscovery = skipWebDetails;
  const branch = await PrinterBranch.findOne({ _id: branchId, deletedAt: null });
  if (!branch) throw new ApiError(404, "Branch not found.");
  logPrinterSync("branch_sync.start", {
    branchId: branch._id.toString(),
    branchCode: branch.code,
    branchName: branch.name,
    networkRange: branch.networkRange,
    includePrinters,
    skipWebDetails,
  });
  await ensurePrinterReplacementIndexes();
  const log = await SyncLog.create({ scope: "branch", branchId, triggeredBy: actor?.id || null });
  logPrinterSync("branch_sync.log_created", {
    branchId: branch._id.toString(),
    branchCode: branch.code,
    logId: log._id.toString(),
  });
  try {
    await Printer.updateMany(
      {
        branchId,
        vendor: "Network Printer",
        serialNumber: "",
        model: /^Network printer port/i,
        deletedAt: null,
      },
      { $set: { deletedAt: new Date() } },
    );
    await Printer.updateMany(
      {
        branchId,
        deletedAt: null,
        $or: [
          { model: NON_PRINTER_MODEL_REGEX },
          { printerName: NON_PRINTER_MODEL_REGEX },
          { hostname: NON_PRINTER_MODEL_REGEX },
        ],
        "counters.totalPages": { $lte: 0 },
      },
      { $set: { deletedAt: new Date() } },
    );
    const discovered = await discoverPrinters(branch.networkRange, {
      skipWebDetails,
      snmpTimeoutMs: fastDiscovery
        ? Number(process.env.PRINTER_DISCOVERY_TIMEOUT_MS || 1200)
        : undefined,
      snmpRetries: fastDiscovery
        ? Number(process.env.PRINTER_DISCOVERY_RETRIES || 0)
        : undefined,
      snmpOperationTimeoutMs: fastDiscovery
        ? Number(process.env.PRINTER_DISCOVERY_OPERATION_TIMEOUT_MS || 1500)
        : undefined,
      hostTimeoutMs: fastDiscovery
        ? Number(process.env.PRINTER_DISCOVERY_HOST_TIMEOUT_MS || 12000)
        : undefined,
    });
    logPrinterSync("branch_sync.discovered", {
      branchId: branch._id.toString(),
      branchCode: branch.code,
      logId: log._id.toString(),
      discoveredCount: discovered.length,
      durationMs: Date.now() - startedAt,
    });
    await mapWithConcurrency(
      discovered,
      Number(process.env.PRINTER_PERSIST_CONCURRENCY || 8),
      async (item) => {
        logPrinterSync("branch_sync.persist.start", {
          branchId: branch._id.toString(),
          branchCode: branch.code,
          ipAddress: item.ipAddress,
          printerName: item.printerName,
          model: item.model,
        });
        await upsertDiscoveredPrinter(branch, item);
        logPrinterSync("branch_sync.persist.done", {
          branchId: branch._id.toString(),
          branchCode: branch.code,
          ipAddress: item.ipAddress,
          printerName: item.printerName,
        });
      },
    );
    branch.lastSyncAt = new Date();
    await branch.save();
    log.status = discovered.length > 0 ? "success" : "partial";
    log.devicesSynced = discovered.length;
    if (discovered.length === 0) {
      log.errors = [
        `No printers discovered in ${branch.networkRange}. Verify that the backend server can reach this network and that printers allow SNMP UDP/161 with community ${process.env.PRINTER_SNMP_COMMUNITIES || process.env.PRINTER_SNMP_COMMUNITY || "public"}. Ping alone is not enough for SNMP discovery.`,
      ];
    }
    log.endedAt = new Date();
    await log.save();
    logPrinterSync("branch_sync.done", {
      branchId: branch._id.toString(),
      branchCode: branch.code,
      logId: log._id.toString(),
      status: log.status,
      devicesSynced: log.devicesSynced,
      errors: log.errors,
      durationMs: Date.now() - startedAt,
    });
    return {
      discovered: discovered.length,
      printers: includePrinters ? await listPrinters({ branchId }) : [],
    };
  } catch (error) {
    log.status = "failed";
    log.errors = [error?.message || String(error)];
    log.endedAt = new Date();
    await log.save();
    logPrinterSync("branch_sync.failed", {
      branchId: branch._id.toString(),
      branchCode: branch.code,
      logId: log._id.toString(),
      message: error?.message || String(error),
      stack: error?.stack,
      durationMs: Date.now() - startedAt,
    });
    await PrinterNotification.create({
      type: "sync_failure",
      severity: "critical",
      title: "Printer sync failed",
      message: error?.message || String(error),
      branchId,
    });
    throw error;
  }
}

async function syncBranchRegisteredPrinters(actor, branch, options = {}) {
  const startedAt = Date.now();
  const printers = await Printer.find({ branchId: branch._id, deletedAt: null });
  const concurrency = Math.max(
    1,
    Number(options.concurrency || process.env.PRINTER_REGISTERED_SYNC_CONCURRENCY || 8),
  );
  const probeOptions = {
    skipWebDetails: options.skipWebDetails !== false,
    snmpTimeoutMs: Number(process.env.PRINTER_REGISTERED_SYNC_TIMEOUT_MS || 1500),
    snmpRetries: Number(process.env.PRINTER_REGISTERED_SYNC_RETRIES || 0),
    snmpOperationTimeoutMs: Number(
      process.env.PRINTER_REGISTERED_SYNC_OPERATION_TIMEOUT_MS || 2000,
    ),
    hostTimeoutMs: Number(process.env.PRINTER_REGISTERED_SYNC_HOST_TIMEOUT_MS || 15000),
  };
  let processed = 0;
  let online = 0;
  let offline = 0;
  const errors = [];

  logPrinterSync("registered_branch_sync.start", {
    branchId: branch._id.toString(),
    branchCode: branch.code,
    printerCount: printers.length,
    concurrency,
    probeOptions,
  });

  await mapWithConcurrency(printers, concurrency, async (printer) => {
    const printerStartedAt = Date.now();
    logPrinterSync("registered_printer_sync.start", {
      branchId: branch._id.toString(),
      branchCode: branch.code,
      printerId: printer._id.toString(),
      ipAddress: printer.ipAddress,
      printerName: printer.printerName,
    });
    try {
      const payload = await probePrinter(printer.ipAddress, probeOptions);
      if (!payload) {
        printer.status = "offline";
        printer.lastSyncAt = new Date();
        await printer.save();
        await createSnapshotAndWaste(printer);
        await createOperationalNotifications(printer);
        offline += 1;
        processed += 1;
        options.onPrinterDone?.({ status: "offline", printer, branch });
        logPrinterSync("registered_printer_sync.offline", {
          branchId: branch._id.toString(),
          branchCode: branch.code,
          printerId: printer._id.toString(),
          ipAddress: printer.ipAddress,
          durationMs: Date.now() - printerStartedAt,
        });
        return;
      }

      await upsertDiscoveredPrinter(branch, payload);
      online += 1;
      processed += 1;
      options.onPrinterDone?.({ status: "online", printer, branch, payload });
      logPrinterSync("registered_printer_sync.done", {
        branchId: branch._id.toString(),
        branchCode: branch.code,
        printerId: printer._id.toString(),
        ipAddress: printer.ipAddress,
        printerName: payload.printerName,
        model: payload.model,
        durationMs: Date.now() - printerStartedAt,
      });
    } catch (error) {
      errors.push(`${printer.ipAddress}: ${error?.message || error}`);
      processed += 1;
      options.onPrinterDone?.({ status: "error", printer, branch, error });
      logPrinterSync("registered_printer_sync.failed", {
        branchId: branch._id.toString(),
        branchCode: branch.code,
        printerId: printer._id.toString(),
        ipAddress: printer.ipAddress,
        message: error?.message || String(error),
        stack: error?.stack,
        durationMs: Date.now() - printerStartedAt,
      });
    }
  });

  branch.lastSyncAt = new Date();
  await branch.save();
  logPrinterSync("registered_branch_sync.done", {
    branchId: branch._id.toString(),
    branchCode: branch.code,
    printerCount: printers.length,
    processed,
    online,
    offline,
    errors,
    durationMs: Date.now() - startedAt,
  });

  return { processed, online, offline, errors };
}

async function syncPrinter(actor, printerId) {
  const startedAt = Date.now();
  const printer = await Printer.findOne({ _id: printerId, deletedAt: null });
  if (!printer) throw new ApiError(404, "Printer not found.");
  const branch = await PrinterBranch.findById(printer.branchId);
  const log = await SyncLog.create({ scope: "printer", printerId, branchId: printer.branchId, triggeredBy: actor?.id || null });
  logPrinterSync("single_printer_sync.start", {
    printerId: printer._id.toString(),
    branchId: printer.branchId?.toString?.() || "",
    ipAddress: printer.ipAddress,
    printerName: printer.printerName,
    logId: log._id.toString(),
  });
  try {
    const payload = await probePrinter(printer.ipAddress);
    if (!payload) {
      printer.status = "offline";
      printer.lastSyncAt = new Date();
      await printer.save();
      await createSnapshotAndWaste(printer);
      await createOperationalNotifications(printer);
      log.status = "partial";
      log.errors = ["Printer did not respond to SNMP."];
    } else {
      await upsertDiscoveredPrinter(branch, payload);
      log.status = "success";
      log.devicesSynced = 1;
    }
    log.endedAt = new Date();
    await log.save();
    logPrinterSync("single_printer_sync.done", {
      printerId: printer._id.toString(),
      ipAddress: printer.ipAddress,
      logId: log._id.toString(),
      status: log.status,
      errors: log.errors,
      durationMs: Date.now() - startedAt,
    });
    return getPrinterDetails(printerId);
  } catch (error) {
    log.status = "failed";
    log.errors = [error?.message || String(error)];
    log.endedAt = new Date();
    await log.save();
    logPrinterSync("single_printer_sync.failed", {
      printerId: printer._id.toString(),
      ipAddress: printer.ipAddress,
      logId: log._id.toString(),
      message: error?.message || String(error),
      stack: error?.stack,
      durationMs: Date.now() - startedAt,
    });
    throw error;
  }
}

async function fullSync(actor = null) {
  const branches = await PrinterBranch.find({ deletedAt: null, status: "active" });
  const log = await SyncLog.create({ scope: "full", triggeredBy: actor?.id || null });
  let devicesSynced = 0;
  const errors = [];
  for (const branch of branches) {
    try {
      const result = await syncBranchRegisteredPrinters(actor, branch, {
        skipWebDetails: true,
      });
      devicesSynced += result.processed;
      errors.push(...result.errors.map((item) => `${branch.code}: ${item}`));
    } catch (error) {
      errors.push(`${branch.code}: ${error?.message || error}`);
    }
  }
  log.devicesSynced = devicesSynced;
  log.errors = errors;
  log.status = errors.length ? (devicesSynced ? "partial" : "failed") : "success";
  log.endedAt = new Date();
  await log.save();
  return { devicesSynced, errors };
}

async function startFullSync(actor = null) {
  await cleanupStaleFullSyncLogs();
  if (activeFullSyncPromise) {
    logPrinterSync("full_sync.start_rejected_already_running", {
      activeFullSyncLogId,
      activeFullSyncStartedAt,
      logFile: LOG_FILE,
    });
    return {
      started: false,
      status: "running",
      logId: activeFullSyncLogId,
      message: "A full printer sync is already running.",
    };
  }

  const log = await SyncLog.create({ scope: "full", triggeredBy: actor?.id || null });
  activeFullSyncLogId = log._id.toString();
  activeFullSyncStartedAt = log.startedAt || new Date();
  activeFullSyncCancelRequested = false;
  logPrinterSync("full_sync.start", {
    logId: activeFullSyncLogId,
    triggeredBy: actor?.id || null,
    timeoutMs: resolveFullSyncTimeoutMs(),
    logFile: LOG_FILE,
  });
  activeFullSyncPromise = (async () => {
    const startedAt = Date.now();
    const branches = await PrinterBranch.find({ deletedAt: null, status: "active" });
    const branchPrinterCounts = new Map(
      await Promise.all(
        branches.map(async (branch) => [
          branch._id.toString(),
          await Printer.countDocuments({ branchId: branch._id, deletedAt: null }),
        ]),
      ),
    );
    const totalPrinters = Array.from(branchPrinterCounts.values()).reduce(
      (sum, count) => sum + Number(count || 0),
      0,
    );
    const concurrency = Math.max(
      1,
      Number(process.env.PRINTER_BRANCH_SYNC_CONCURRENCY || 4),
    );
    let devicesSynced = 0;
    const errors = [];
    let timeoutRecorded = false;
    let cancelRecorded = false;
    activeFullSyncProgress = {
      running: true,
      status: "running",
      logId: log._id.toString(),
      startedAt: log.startedAt || new Date(),
      endedAt: null,
      totalBranches: branches.length,
      completedBranches: 0,
      totalPrinters,
      processedPrinters: 0,
      onlinePrinters: 0,
      offlinePrinters: 0,
      currentBranches: [],
      errors: [],
      updatedAt: new Date(),
    };
    logPrinterSync("full_sync.branches_loaded", {
      logId: activeFullSyncLogId,
      branchCount: branches.length,
      totalPrinters,
      concurrency,
      branches: branches.map((branch) => ({
        id: branch._id.toString(),
        code: branch.code,
        networkRange: branch.networkRange,
      })),
    });
    try {
      let cursor = 0;
      async function worker() {
        while (true) {
          if (activeFullSyncCancelRequested) {
            if (!cancelRecorded) {
              cancelRecorded = true;
              errors.push("Full sync was cancelled by user.");
            }
            return;
          }
          if (isSyncTimedOut(log.startedAt)) {
            if (!timeoutRecorded) {
              timeoutRecorded = true;
              errors.push("Full sync timed out before all branches were scanned.");
            }
            return;
          }
          const index = cursor;
          cursor += 1;
          if (index >= branches.length) {
            return;
          }
          const branch = branches[index];
          try {
            updateActiveFullSyncProgress({
              currentBranches: [
                ...(activeFullSyncProgress?.currentBranches || []),
                {
                  id: branch._id.toString(),
                  code: branch.code,
                  name: branch.name,
                  printerCount: branchPrinterCounts.get(branch._id.toString()) || 0,
                },
              ].slice(-concurrency),
            });
            logPrinterSync("full_sync.branch.start", {
              logId: log._id.toString(),
              branchId: branch._id.toString(),
              branchCode: branch.code,
              networkRange: branch.networkRange,
              mode: "registered_printers",
            });
            const result = await syncBranchRegisteredPrinters(actor, branch, {
              skipWebDetails: true,
              onPrinterDone: ({ status, printer }) => {
                const next = {
                  processedPrinters: Number(activeFullSyncProgress?.processedPrinters || 0) + 1,
                };
                if (status === "online") {
                  next.onlinePrinters = Number(activeFullSyncProgress?.onlinePrinters || 0) + 1;
                } else {
                  next.offlinePrinters = Number(activeFullSyncProgress?.offlinePrinters || 0) + 1;
                }
                updateActiveFullSyncProgress({
                  ...next,
                  lastPrinter: {
                    id: printer._id.toString(),
                    ipAddress: printer.ipAddress,
                    name: printer.printerName,
                    status,
                    branchCode: branch.code,
                  },
                });
              },
            });
            devicesSynced += result.processed;
            errors.push(...result.errors.map((item) => `${branch.code}: ${item}`));
            updateActiveFullSyncProgress({
              completedBranches: Number(activeFullSyncProgress?.completedBranches || 0) + 1,
              currentBranches: (activeFullSyncProgress?.currentBranches || []).filter(
                (item) => item.id !== branch._id.toString(),
              ),
              errors: errors.slice(-20),
            });
            logPrinterSync("full_sync.branch.done", {
              logId: log._id.toString(),
              branchId: branch._id.toString(),
              branchCode: branch.code,
              processed: result.processed,
              online: result.online,
              offline: result.offline,
              devicesSynced,
            });
          } catch (error) {
            errors.push(`${branch.code}: ${error?.message || error}`);
            updateActiveFullSyncProgress({
              completedBranches: Number(activeFullSyncProgress?.completedBranches || 0) + 1,
              currentBranches: (activeFullSyncProgress?.currentBranches || []).filter(
                (item) => item.id !== branch._id.toString(),
              ),
              errors: errors.slice(-20),
            });
            logPrinterSync("full_sync.branch.failed", {
              logId: log._id.toString(),
              branchId: branch._id.toString(),
              branchCode: branch.code,
              message: error?.message || String(error),
              stack: error?.stack,
            });
          }
        }
      }
      await Promise.all(
        Array.from(
          { length: Math.min(concurrency, Math.max(branches.length, 1)) },
          () => worker(),
        ),
      );
      log.devicesSynced = devicesSynced;
      log.errors = errors;
      log.status = activeFullSyncCancelRequested
        ? (devicesSynced ? "partial" : "failed")
        : errors.length ? (devicesSynced ? "partial" : "failed") : "success";
      log.endedAt = new Date();
      await log.save();
      updateActiveFullSyncProgress({
        running: false,
        status: log.status,
        endedAt: log.endedAt,
        currentBranches: [],
        errors: errors.slice(-20),
      });
      logPrinterSync("full_sync.done", {
        logId: log._id.toString(),
        status: log.status,
        devicesSynced,
        errors,
        durationMs: Date.now() - startedAt,
      });
    } catch (error) {
      log.devicesSynced = devicesSynced;
      log.errors = [...errors, error?.message || String(error)];
      log.status = devicesSynced ? "partial" : "failed";
      log.endedAt = new Date();
      await log.save();
      updateActiveFullSyncProgress({
        running: false,
        status: log.status,
        endedAt: log.endedAt,
        currentBranches: [],
        errors: log.errors.slice(-20),
      });
      logPrinterSync("full_sync.failed", {
        logId: log._id.toString(),
        status: log.status,
        devicesSynced,
        errors: log.errors,
        message: error?.message || String(error),
        stack: error?.stack,
        durationMs: Date.now() - startedAt,
      });
    } finally {
      logPrinterSync("full_sync.cleanup", {
        logId: log._id.toString(),
        activeFullSyncLogId,
      });
      if (activeFullSyncLogId === log._id.toString()) {
        activeFullSyncPromise = null;
        activeFullSyncLogId = null;
        activeFullSyncStartedAt = null;
        activeFullSyncCancelRequested = false;
      }
    }
  })();

  return {
    started: true,
    status: "running",
    logId: activeFullSyncLogId,
    message: "Full printer sync started in background.",
  };
}

async function stopFullSync(actor = null) {
  const stoppedLogId = activeFullSyncLogId;
  const wasActive = Boolean(activeFullSyncPromise || activeFullSyncLogId);
  activeFullSyncCancelRequested = true;
  if (!activeFullSyncPromise) {
    activeFullSyncLogId = null;
    activeFullSyncStartedAt = null;
    activeFullSyncCancelRequested = false;
  }

  const result = await SyncLog.updateMany(
    { scope: "full", status: "running", endedAt: null },
    {
      $set: {
        status: "failed",
        endedAt: new Date(),
      },
      $push: {
        errors: `Full sync cancelled by user${actor?.id ? ` ${actor.id}` : ""}.`,
      },
    },
  );

  logPrinterSync("full_sync.stop_requested", {
    stoppedLogId,
    wasActive,
    modifiedCount: result.modifiedCount,
    triggeredBy: actor?.id || null,
  });
  if (activeFullSyncProgress) {
    updateActiveFullSyncProgress({
      running: false,
      status: "failed",
      endedAt: new Date(),
      currentBranches: [],
      errors: [
        ...(activeFullSyncProgress.errors || []),
        "Full sync cancelled by user.",
      ].slice(-20),
    });
  }

  return {
    stopped: wasActive || result.modifiedCount > 0,
    logId: stoppedLogId,
    modifiedLogs: result.modifiedCount,
    message: "Full printer sync cancellation requested.",
  };
}

async function getFullSyncStatus() {
  await cleanupStaleFullSyncLogs();
  if (activeFullSyncProgress) {
    return serializeFullSyncProgress();
  }
  const latest = await SyncLog.findOne({ scope: "full" }).sort({ startedAt: -1 }).lean();
  if (!latest) {
    return serializeFullSyncProgress(null);
  }
  return {
    ...serializeFullSyncProgress({
      running: latest.status === "running",
      status: latest.status,
      logId: latest._id.toString(),
      startedAt: latest.startedAt,
      endedAt: latest.endedAt,
      totalBranches: 0,
      completedBranches: 0,
      totalPrinters: Number(latest.devicesSynced || 0),
      processedPrinters: latest.status === "running" ? 0 : Number(latest.devicesSynced || 0),
      onlinePrinters: 0,
      offlinePrinters: 0,
      currentBranches: [],
      errors: latest.errors || [],
      updatedAt: latest.updatedAt || latest.endedAt || latest.startedAt,
    }),
  };
}

async function getDashboard(branchId = null) {
  const branchQuery = { deletedAt: null };
  if (branchId) branchQuery._id = branchId;
  const printerQuery = { deletedAt: null };
  if (branchId) printerQuery.branchId = branchId;

  const now = new Date();
  const currentMonth = now.getMonth() + 1;
  const currentYear = now.getFullYear();

  const [branches, printers, waste, notifications, snapshots, consumptionResult] = await Promise.all([
    PrinterBranch.find(branchQuery).lean(),
    Printer.find(printerQuery).populate("branchId", "name code").lean(),
    WasteStatistic.find(branchId ? { branchId } : {}).sort({ calculatedAt: -1 }).limit(500).lean(),
    PrinterNotification.find(branchId ? { branchId, readAt: null } : { readAt: null }).sort({ createdAt: -1 }).limit(30).lean(),
    DailySnapshot.find(branchId ? { branchId } : {}).sort({ snapshotAt: -1 }).limit(90).lean(),
    calculateMonthlyConsumption({ branchId, month: currentMonth, year: currentYear }),
  ]);

  const totalPages = printers.reduce((sum, item) => sum + Number(item.lifetimeCounters?.totalPages || 0), 0);
  const wastePages = waste.reduce((sum, item) => sum + Number(item.estimatedWastePages || 0), 0);
  const monthlyUsage = consumptionResult.consumption.reduce((sum, item) => sum + Number(item.totalPages || 0), 0);

  return {
    totals: {
      branches: branches.length,
      printers: printers.length,
      onlinePrinters: printers.filter((item) => item.status === "online").length,
      offlinePrinters: printers.filter((item) => item.status !== "online").length,
      totalPages,
      wastePages,
      monthlyUsage,
      tonerAlerts: notifications.filter((item) => item.type === "toner_low").length,
    },
    topPrinters: printers
      .map(serializePrinter)
      .sort((a, b) => (b.lifetimeCounters.totalPages || 0) - (a.lifetimeCounters.totalPages || 0))
      .slice(0, 10),
    branches: branches.map(serializeBranch),
    notifications: notifications.map((item) => ({
      id: item._id.toString(),
      type: item.type,
      severity: item.severity,
      title: item.title,
      message: item.message,
      branchId: item.branchId?.toString?.() || "",
      printerId: item.printerId?.toString?.() || "",
      createdAt: item.createdAt,
    })),
    activity: snapshots.reverse().map((item) => ({
      date: item.snapshotAt,
      totalPages: item.counters?.totalPages || 0,
      lifetimePages: item.lifetimeCounters?.totalPages || 0,
    })),
  };
}

async function listSyncLogs() {
  await cleanupStaleFullSyncLogs();
  const logs = await SyncLog.find().sort({ startedAt: -1 }).limit(100).lean();
  return logs.map((log) => ({
    id: log._id.toString(),
    scope: log.scope,
    status: log.status,
    startedAt: log.startedAt,
    endedAt: log.endedAt,
    branchId: log.branchId?.toString?.() || "",
    printerId: log.printerId?.toString?.() || "",
    devicesSynced: log.devicesSynced,
    errors: log.errors || [],
  }));
}

async function calculateMonthlyConsumption({ branchId = null, printerId = null, fromMonth = null, fromYear = null, toMonth = null, toYear = null, month = null, year = null }) {
  const now = new Date();
  
  if (month !== null || year !== null) {
    const isAllMonths = month !== null && month !== undefined && Number(month) === 0;
    if (isAllMonths) {
      fromMonth = 1;
      toMonth = 12;
      fromYear = year ? Number(year) : now.getFullYear();
      toYear = fromYear;
    } else {
      fromMonth = month ? Number(month) : now.getMonth() + 1;
      toMonth = fromMonth;
      fromYear = year ? Number(year) : now.getFullYear();
      toYear = fromYear;
    }
  } else {
    fromMonth = fromMonth ? Number(fromMonth) : now.getMonth() + 1;
    fromYear = fromYear ? Number(fromYear) : now.getFullYear();
    toMonth = toMonth ? Number(toMonth) : now.getMonth() + 1;
    toYear = toYear ? Number(toYear) : now.getFullYear();
  }

  const printerQuery = { deletedAt: null };
  if (branchId) printerQuery.branchId = branchId;
  if (printerId) printerQuery._id = printerId;

  const printers = await Printer.find(printerQuery).populate("branchId", "name code").lean();
  const results = []; 

  let currentYear = fromYear;
  let currentMonth = fromMonth;

  while (currentYear < toYear || (currentYear === toYear && currentMonth <= toMonth)) {
    const startDate = new Date(currentYear, currentMonth - 1, 1);
    const endDate = new Date(currentYear, currentMonth, 1);
    const consumptionData = [];

    for (const printer of printers) {
      const monthlySnapshots = await DailySnapshot.find({
        printerId: printer._id,
        snapshotAt: { $gte: startDate, $lt: endDate }
      }).sort({ snapshotAt: 1 }).lean();

      // No 32-days restriction. 
      // The baseline is strictly the last snapshot BEFORE the month starts.
      // This ensures any un-synced pages are naturally attributed to the month they are finally synced in, 
      // without losing any pages and without overlapping.
      const baselineSnapshot = await DailySnapshot.findOne({
        printerId: printer._id,
        snapshotAt: { $lt: startDate }
      }).sort({ snapshotAt: -1 }).lean();

      const baselineAgeMs = baselineSnapshot
        ? startDate.getTime() - new Date(baselineSnapshot.snapshotAt).getTime()
        : null;
      const hasFreshBaseline =
        baselineAgeMs !== null && baselineAgeMs >= 0 && baselineAgeMs <= MAX_BASELINE_AGE_MS;

      let startTotal = 0;
      let startMono = 0;
      let startColor = 0;

      if (hasFreshBaseline) {
        startTotal = baselineSnapshot.lifetimeCounters?.totalPages || baselineSnapshot.counters?.totalPages || 0;
        startMono = baselineSnapshot.lifetimeCounters?.monoPages || baselineSnapshot.counters?.monoPages || 0;
        startColor = baselineSnapshot.lifetimeCounters?.colorPages || baselineSnapshot.counters?.colorPages || 0;
      } else if (monthlySnapshots.length > 0) {
        startTotal = monthlySnapshots[0].lifetimeCounters?.totalPages || monthlySnapshots[0].counters?.totalPages || 0;
        startMono = monthlySnapshots[0].lifetimeCounters?.monoPages || monthlySnapshots[0].counters?.monoPages || 0;
        startColor = monthlySnapshots[0].lifetimeCounters?.colorPages || monthlySnapshots[0].counters?.colorPages || 0;
      }

      let endTotal = startTotal;
      let endMono = startMono;
      let endColor = startColor;

      if (monthlySnapshots.length > 0) {
        const lastSnapshot = monthlySnapshots[monthlySnapshots.length - 1];
        endTotal = lastSnapshot.lifetimeCounters?.totalPages || lastSnapshot.counters?.totalPages || 0;
        endMono = lastSnapshot.lifetimeCounters?.monoPages || lastSnapshot.counters?.monoPages || 0;
        endColor = lastSnapshot.lifetimeCounters?.colorPages || lastSnapshot.counters?.colorPages || 0;
      }

      const usage = sanitizeMonthlyCounterUsage({
        totalPages: endTotal - startTotal,
        monoPages: endMono - startMono,
        colorPages: endColor - startColor,
      });
      const { totalPages, monoPages, colorPages } = usage;
      const firstSnapshot = monthlySnapshots[0] || null;
      const lastSnapshot = monthlySnapshots[monthlySnapshots.length - 1] || null;
      const hasBaselineSnapshot = Boolean(hasFreshBaseline);
      const hasStaleBaseline = Boolean(baselineSnapshot && !hasFreshBaseline);
      const hasPartialData = monthlySnapshots.length === 0 || !hasFreshBaseline || hasStaleBaseline;
      const hasSuspiciousConsumption = usage.excludedFromTotals;

      if (totalPages > 0 || usage.rawTotalPages > 0 || printerId || branchId || monthlySnapshots.length > 0) {
        consumptionData.push({
          printerId: printer._id.toString(),
          printerName: printer.printerName || printer.hostname || printer.ipAddress,
          ipAddress: printer.ipAddress,
          model: printer.model || "",
          branchId: printer.branchId?._id?.toString() || printer.branchId?.toString() || "",
          branchName: printer.branchId?.name || "",
          branchCode: printer.branchId?.code || "",
          totalPages,
          monoPages,
          colorPages,
          rawTotalPages: usage.rawTotalPages,
          rawMonoPages: usage.rawMonoPages,
          rawColorPages: usage.rawColorPages,
          excludedFromTotals: usage.excludedFromTotals,
          identityConfidence: printer.identityConfidence || "weak",
          anomalyFlags: printer.anomalyFlags || [],
          paper: buildPaperConsumptionMetrics(totalPages),
          hasBaselineSnapshot,
          hasStaleBaseline,
          hasSuspiciousConsumption,
          baselineSnapshotAt: baselineSnapshot?.snapshotAt || null,
          baselineAgeHours: baselineAgeMs == null ? null : Math.round(baselineAgeMs / 36_000) / 100,
          hasPartialData,
          firstSnapshotAt: firstSnapshot?.snapshotAt || null,
          lastSnapshotAt: lastSnapshot?.snapshotAt || null,
        });
      }
    }

    const grouped = {};
    for (const item of consumptionData) {
      const bId = item.branchId;
      if (!grouped[bId]) {
        grouped[bId] = {
          branchId: bId,
          branchName: item.branchName,
          branchCode: item.branchCode,
          printersCount: 0,
          totalPages: 0,
          monoPages: 0,
          colorPages: 0,
          partialPrintersCount: 0,
          suspiciousPrintersCount: 0,
          hasPartialData: false,
          hasSuspiciousConsumption: false,
          hasCounterAnomalies: false,
          paper: buildPaperConsumptionMetrics(0),
          printers: [],
        };
      }
      grouped[bId].printersCount += 1;
      grouped[bId].totalPages += item.totalPages;
      grouped[bId].monoPages += item.monoPages;
      grouped[bId].colorPages += item.colorPages;
      if (item.hasPartialData) grouped[bId].partialPrintersCount += 1;
      if (item.hasSuspiciousConsumption) grouped[bId].suspiciousPrintersCount += 1;
      grouped[bId].hasPartialData = grouped[bId].hasPartialData || item.hasPartialData;
      grouped[bId].hasSuspiciousConsumption = grouped[bId].hasSuspiciousConsumption || item.hasSuspiciousConsumption;
      if ((item.anomalyFlags || []).length > 0) grouped[bId].hasCounterAnomalies = true;
      grouped[bId].paper = buildPaperConsumptionMetrics(grouped[bId].totalPages);
      grouped[bId].printers.push(item);
    }

    results.push({
      year: currentYear,
      month: currentMonth,
      consumption: Object.values(grouped),
    });

    currentMonth++;
    if (currentMonth > 12) {
      currentMonth = 1;
      currentYear++;
    }
  }

  // Group flat consumption for backward compatibility
  const flatGrouped = {};
  for (const r of results) {
    for (const c of r.consumption) {
      const bId = c.branchId;
      if (!flatGrouped[bId]) {
        flatGrouped[bId] = cloneBranchConsumption(c);
      } else {
        flatGrouped[bId].totalPages += c.totalPages;
        flatGrouped[bId].monoPages += c.monoPages;
        flatGrouped[bId].colorPages += c.colorPages;
        flatGrouped[bId].partialPrintersCount += Number(c.partialPrintersCount || 0);
        flatGrouped[bId].suspiciousPrintersCount += Number(c.suspiciousPrintersCount || 0);
        flatGrouped[bId].hasPartialData = Boolean(flatGrouped[bId].hasPartialData || c.hasPartialData);
        flatGrouped[bId].hasSuspiciousConsumption = Boolean(flatGrouped[bId].hasSuspiciousConsumption || c.hasSuspiciousConsumption);
        flatGrouped[bId].hasCounterAnomalies = Boolean(flatGrouped[bId].hasCounterAnomalies || c.hasCounterAnomalies);
        flatGrouped[bId].paper = buildPaperConsumptionMetrics(flatGrouped[bId].totalPages);

        for (const printer of c.printers || []) {
          const printerMap = flatGrouped[bId]._printerMap;
          const existing = printerMap.get(printer.printerId);
          if (existing) {
            mergePrinterConsumption(existing, printer);
          } else {
            printerMap.set(printer.printerId, {
              ...printer,
              paper: buildPaperConsumptionMetrics(printer.totalPages),
            });
          }
        }
      }
    }
  }

  const flatConsumption = Object.values(flatGrouped).map((branchConsumption) => {
    const printers = Array.from(branchConsumption._printerMap?.values?.() || []);
    const { _printerMap, ...publicConsumption } = branchConsumption;
    return {
      ...publicConsumption,
      printers,
      printersCount: printers.length,
      paper: buildPaperConsumptionMetrics(publicConsumption.totalPages),
    };
  });

  return {
    year: fromYear,
    month: (fromMonth === toMonth && fromYear === toYear) ? fromMonth : 0,
    consumption: flatConsumption,
    months: results
  };
}

async function ensurePrinterReplacementIndexes() {
  if (!printerIndexMigrationPromise) {
    printerIndexMigrationPromise = (async () => {
      const exists = await Printer.db.db
        .listCollections({ name: Printer.collection.name })
        .hasNext();
      const indexes = exists ? await Printer.collection.indexes() : [];
      const legacyIpIndex = indexes.find((index) =>
        index.unique &&
        index.key?.branchId === 1 &&
        index.key?.ipAddress === 1 &&
        !index.partialFilterExpression
      );
      if (legacyIpIndex) {
        await Printer.collection.dropIndex(legacyIpIndex.name);
      }
      await Printer.syncIndexes();
    })().catch((error) => {
      printerIndexMigrationPromise = null;
      throw error;
    });
  }
  return printerIndexMigrationPromise;
}

async function exportReport(actor, { type = "global", format = "pdf", branchId = null, printerId = null, fromMonth = null, fromYear = null, toMonth = null, toYear = null, month = null, year = null }) {
  if (type === "printer") {
    const printer = await Printer.findOne({ _id: printerId, deletedAt: null })
      .populate("branchId", "name code")
      .lean();
    if (!printer) throw new ApiError(404, "Printer not found.");
    const snapshots = await DailySnapshot.find({ printerId: printer._id })
      .sort({ snapshotAt: -1 })
      .limit(200)
      .lean();

    let monthlyConsumption = null;
    if (fromMonth && fromYear) {
      monthlyConsumption = await calculateMonthlyConsumption({ printerId, fromMonth, fromYear, toMonth, toYear, month, year });
    } else if (month && year) {
      monthlyConsumption = await calculateMonthlyConsumption({ printerId, month, year });
    }

    return buildPrinterPdfReport({ printer, snapshots, actor, month, year, fromMonth, fromYear, toMonth, toYear, monthlyConsumption });
  }
  const branch = branchId ? await PrinterBranch.findById(branchId).lean() : null;
  const printerQuery = { deletedAt: null };
  const branchQuery = { deletedAt: null };
  if (branchId) {
    printerQuery.branchId = branchId;
    branchQuery._id = branchId;
  }

  let monthlyConsumption = null;
  if (fromMonth && fromYear) {
    monthlyConsumption = await calculateMonthlyConsumption({ branchId, fromMonth, fromYear, toMonth, toYear, month, year });
  } else if (month && year) {
    monthlyConsumption = await calculateMonthlyConsumption({ branchId, month, year });
  }

  const [branches, printers, snapshots, waste] = await Promise.all([
    PrinterBranch.find(branchQuery).lean(),
    Printer.find(printerQuery).populate("branchId", "name code").lean(),
    DailySnapshot.find(branchId ? { branchId } : {}).populate("printerId", "printerName").populate("branchId", "name").sort({ snapshotAt: -1 }).limit(1000).lean(),
    WasteStatistic.find(branchId ? { branchId } : {}).populate("printerId", "printerName").populate("branchId", "name").sort({ calculatedAt: -1 }).limit(1000).lean(),
  ]);
  const data = { type, branch, branches, printers, snapshots, waste, actor, month, year, fromMonth, fromYear, toMonth, toYear, monthlyConsumption };
  return format === "xlsx" ? buildExcelReport(data) : buildPdfReport(data);
}

module.exports = {
  createBranch,
  deleteBranch,
  deletePrinter,
  discoverBranchPrinters,
  exportReport,
  fullSync,
  startFullSync,
  stopFullSync,
  getFullSyncStatus,
  getDashboard,
  getPrinterDetails,
  listBranches,
  listPrinters,
  listSyncLogs,
  syncPrinter,
  updateBranch,
  upsertDiscoveredPrinter,
  calculateMonthlyConsumption,
};
