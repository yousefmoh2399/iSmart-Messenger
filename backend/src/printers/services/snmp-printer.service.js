const net = require("net");
const { collectPrinterWebDetails, mergeExtendedDetails } = require("./printer-web-detail.service");
const { logPrinterSync } = require("../../utils/printer-sync-file-logger");

let snmp = null;
try {
  snmp = require("net-snmp");
} catch (_) {
  snmp = null;
}

const SCALAR_OIDS = {
  sysName: "1.3.6.1.2.1.1.5.0",
  sysDescr: "1.3.6.1.2.1.1.1.0",
  printerName: "1.3.6.1.2.1.43.5.1.1.16.1",
  serialNumber: "1.3.6.1.2.1.43.5.1.1.17.1",
  hrPrinterStatus: "1.3.6.1.2.1.25.3.5.1.1.1",
  hrPrinterDetectedErrorState: "1.3.6.1.2.1.25.3.5.1.2.1",
  
  // Kyocera Private MIB OIDs
  kyoceraTotalPages: "1.3.6.1.4.1.1347.43.10.1.1.12.1.1",
  kyoceraPrintMono: "1.3.6.1.4.1.1347.42.3.1.2.1.1.1.1",
  kyoceraPrintColor: "1.3.6.1.4.1.1347.42.3.1.2.1.1.1.3",
  kyoceraCopyMono: "1.3.6.1.4.1.1347.42.3.1.2.1.1.2.1",
  kyoceraCopyColor: "1.3.6.1.4.1.1347.42.3.1.2.1.1.2.3",
  kyoceraScanPages: "1.3.6.1.4.1.1347.46.10.1.1.5.3",
  kyoceraDuplex: "1.3.6.1.4.1.1347.42.3.1.4.1.1.1",

  // HP Private MIB OIDs
  hpMonoPages: "1.3.6.1.4.1.11.2.3.9.4.2.1.4.1.2.6.0",
  hpColorPages: "1.3.6.1.4.1.11.2.3.9.4.2.1.4.1.2.7.0",
  hpDuplexPages: "1.3.6.1.4.1.11.2.3.9.4.2.1.4.1.2.22.0",
  hpAdfScan: "1.3.6.1.4.1.11.2.3.9.4.2.1.2.2.1.20.0",
  hpFlatbedScan: "1.3.6.1.4.1.11.2.3.9.4.2.1.2.2.1.21.0",
};

const STANDARD_SCALAR_KEYS = [
  "sysName",
  "sysDescr",
  "printerName",
  "serialNumber",
  "hrPrinterStatus",
  "hrPrinterDetectedErrorState",
];

const KYOCERA_SCALAR_KEYS = [
  "kyoceraTotalPages",
  "kyoceraPrintMono",
  "kyoceraPrintColor",
  "kyoceraCopyMono",
  "kyoceraCopyColor",
  "kyoceraScanPages",
  "kyoceraDuplex",
];

const HP_SCALAR_KEYS = [
  "hpMonoPages",
  "hpColorPages",
  "hpDuplexPages",
  "hpAdfScan",
  "hpFlatbedScan",
];

const TABLE_OIDS = {
  hrDeviceDescr: "1.3.6.1.2.1.25.3.2.1.3",
  hrPrinterStatus: "1.3.6.1.2.1.25.3.5.1.1",
  hrPrinterDetectedErrorState: "1.3.6.1.2.1.25.3.5.1.2",
  markerLifeCount: "1.3.6.1.2.1.43.10.2.1.4",
  suppliesDescription: "1.3.6.1.2.1.43.11.1.1.6",
  suppliesMaxCapacity: "1.3.6.1.2.1.43.11.1.1.8",
  suppliesLevel: "1.3.6.1.2.1.43.11.1.1.9",
  prtMarkerColorantValue: "1.3.6.1.2.1.43.12.1.1.4",
  alertSeverity: "1.3.6.1.2.1.43.18.1.1.2",
  alertDescription: "1.3.6.1.2.1.43.18.1.1.8",
};

const NON_PRINTER_DEVICE_REGEX =
  /router|gateway|switch|firewall|mikrotik|fortigate|ubiquiti|access point|wireless|camera|nvr|dvr|server|nas|storage|proxy|voip|phone|ethernet interface card/i;

const PRINTER_MODEL_REGEX =
  /(HP\s+LaserJet[\w\s.-]+|HP\s+Color\s+LaserJet[\w\s.-]+|TASKalfa\s+[\w.-]+|ECOSYS\s+[\w.-]+|Kyocera\s+[\w\s.-]+|Canon\s+[\w\s.-]+|Xerox\s+[\w\s.-]+|Brother\s+[\w\s.-]+|UTAX\s+[\w\s_.-]+|Triumph-Adler\s+[\w\s_.-]+|CDC\s+[\w\s_.-]+|DCC\s+[\w\s_.-]+|\b\d{4}ci\b)/i;

function ipToInt(address) {
  if (!net.isIP(address)) return null;
  const parts = address.split(".").map(Number);
  return (
    ((parts[0] << 24) >>> 0) +
    (parts[1] << 16) +
    (parts[2] << 8) +
    parts[3]
  ) >>> 0;
}

function intToIp(value) {
  return [value >>> 24, (value >>> 16) & 255, (value >>> 8) & 255, value & 255].join(".");
}

function expandRange(startAddress, endAddress, limit) {
  const start = ipToInt(startAddress);
  const end = ipToInt(endAddress);
  if (start == null || end == null || end < start) {
    return [];
  }
  const count = Math.min(end - start + 1, limit);
  return Array.from({ length: count }, (_, index) => intToIp((start + index) >>> 0));
}

function expandCidr(cidr, limit) {
  const [address, prefixText] = String(cidr || "").trim().split("/");
  const prefix = Number(prefixText);
  if (!net.isIP(address) || !Number.isInteger(prefix) || prefix < 16 || prefix > 30) {
    return [];
  }
  const base = ipToInt(address);
  if (base == null) return [];
  const hostCount = Math.min(2 ** (32 - prefix) - 2, limit);
  const mask = (0xffffffff << (32 - prefix)) >>> 0;
  const network = base & mask;
  const ips = [];
  for (let i = 1; i <= hostCount; i += 1) {
    ips.push(intToIp((network + i) >>> 0));
  }
  return ips;
}

function expandTarget(target, limit) {
  const value = String(target || "").trim();
  if (!value) return [];
  if (value.includes("/")) {
    return expandCidr(value, limit);
  }
  if (net.isIP(value)) {
    const lastOctet = Number(value.split(".").at(-1));
    if (lastOctet === 1 || lastOctet === 254) {
      return expandCidr(`${value.split(".").slice(0, 3).join(".")}.0/24`, limit);
    }
    return [value];
  }
  const rangeMatch = value.match(/^(\d{1,3}(?:\.\d{1,3}){3})\s*-\s*(\d{1,3}(?:\.\d{1,3}){0,3})$/);
  if (!rangeMatch) {
    return [];
  }
  const startAddress = rangeMatch[1];
  const rawEnd = rangeMatch[2];
  const endAddress = rawEnd.includes(".")
    ? rawEnd
    : `${startAddress.split(".").slice(0, 3).join(".")}.${rawEnd}`;
  return expandRange(startAddress, endAddress, limit);
}

function expandNetworkRange(networkRange, limit = 1024) {
  const seen = new Set();
  const hosts = [];
  for (const target of String(networkRange || "").split(",")) {
    const remaining = Math.max(limit - hosts.length, 0);
    if (remaining === 0) break;
    for (const host of expandTarget(target, remaining)) {
      if (seen.has(host)) continue;
      seen.add(host);
      hosts.push(host);
    }
  }
  return hosts;
}

function resolveTimeout(options = {}) {
  const value = Number(
    options.snmpTimeoutMs ?? process.env.PRINTER_SNMP_TIMEOUT_MS ?? 2500,
  );
  return Number.isFinite(value) && value > 0 ? value : 2500;
}

function resolveRetries(options = {}) {
  const value = Number(
    options.snmpRetries ?? process.env.PRINTER_SNMP_RETRIES ?? 1,
  );
  return Number.isInteger(value) && value >= 0 ? value : 1;
}

function resolveOperationTimeout(options = {}) {
  const timeout = resolveTimeout(options);
  const retries = resolveRetries(options);
  const value = Number(
    options.snmpOperationTimeoutMs ??
      process.env.PRINTER_SNMP_OPERATION_TIMEOUT_MS ??
      timeout * (retries + 1) + 1000,
  );
  return Number.isFinite(value) && value > 0 ? value : timeout * (retries + 1) + 1000;
}

function resolveHostTimeout(options = {}) {
  const timeout = resolveTimeout(options);
  const retries = resolveRetries(options);
  const operationTimeout = resolveOperationTimeout(options);
  const value = Number(
    options.hostTimeoutMs ??
      process.env.PRINTER_DISCOVERY_HOST_TIMEOUT_MS ??
      operationTimeout * 12 + timeout * (retries + 1),
  );
  return Number.isFinite(value) && value > 0 ? value : operationTimeout * 12 + timeout * (retries + 1);
}

function createDeadline(ms, onTimeout) {
  let finished = false;
  const timer = setTimeout(() => {
    if (finished) return;
    finished = true;
    onTimeout();
  }, ms);
  timer.unref?.();
  return {
    get finished() {
      return finished;
    },
    finish(callback) {
      if (finished) return false;
      finished = true;
      clearTimeout(timer);
      callback();
      return true;
    },
  };
}

function resolveCommunities() {
  return String(process.env.PRINTER_SNMP_COMMUNITIES || process.env.PRINTER_SNMP_COMMUNITY || "public")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function normalizeValue(value) {
  if (Buffer.isBuffer(value)) {
    return value.toString("utf8").replace(/\u0000/g, "").trim();
  }
  if (value == null) {
    return "";
  }
  return value;
}

function snmpGet(session, oids, options = {}) {
  return new Promise((resolve) => {
    const operationTimeoutMs = resolveOperationTimeout(options);
    const deadline = createDeadline(operationTimeoutMs, () => {
      logPrinterSync("snmp.get.timeout", {
        host: session?.target,
        oidCount: oids.length,
        timeoutMs: operationTimeoutMs,
      });
      resolve(null);
    });
    session.get(oids, (error, varbinds) => {
      deadline.finish(() => {
        if (error || !Array.isArray(varbinds)) {
          resolve(null);
          return;
        }
        const result = {};
        for (const item of varbinds) {
          if (!item || snmp.isVarbindError(item)) continue;
          result[item.oid] = item.oid === SCALAR_OIDS.hrPrinterDetectedErrorState
            ? item.value
            : normalizeValue(item.value);
        }
        resolve(result);
      });
    });
  });
}

async function snmpGetGraceful(session, oids, options = {}) {
  const result = await snmpGet(session, oids, options);
  if (result) {
    return result;
  }
  const individualResults = {};
  for (const oid of oids) {
    try {
      const res = await snmpGet(session, [oid], options);
      if (res) {
        Object.assign(individualResults, res);
      }
    } catch (_) {}
  }
  return individualResults;
}

function snmpSubtree(session, oid, options = {}) {
  return new Promise((resolve) => {
    const result = {};
    const operationTimeoutMs = resolveOperationTimeout(options);
    const deadline = createDeadline(operationTimeoutMs, () => {
      logPrinterSync("snmp.subtree.timeout", {
        host: session?.target,
        oid,
        collectedCount: Object.keys(result).length,
        timeoutMs: operationTimeoutMs,
      });
      resolve(result);
    });
    session.subtree(
      oid,
      20,
      (varbinds) => {
        if (deadline.finished) return;
        const entries = Array.isArray(varbinds) ? varbinds : [varbinds];
        for (const varbind of entries) {
          if (!varbind || snmp.isVarbindError(varbind)) continue;
          result[varbind.oid] = oid === TABLE_OIDS.hrPrinterDetectedErrorState
            ? varbind.value
            : normalizeValue(varbind.value);
        }
      },
      () => deadline.finish(() => resolve(result)),
    );
  });
}

async function withSnmpSession(host, community, options = {}) {
  const startedAt = Date.now();
  logPrinterSync("snmp.session.start", {
    host,
    community,
    timeoutMs: resolveTimeout(options),
    retries: resolveRetries(options),
  });
  const session = snmp.createSession(host, community, {
    timeout: resolveTimeout(options),
    retries: resolveRetries(options),
    version: snmp.Version2c,
  });
  try {
    const standardOids = STANDARD_SCALAR_KEYS.map((key) => SCALAR_OIDS[key]);
    const scalars = await snmpGet(session, standardOids, options);
    if (!scalars) return null;

    const sysDescr = String(scalars[SCALAR_OIDS.sysDescr] || "");
    const vendor = resolveVendor(sysDescr);

    let privateOids = [];
    if (vendor === "Kyocera") {
      privateOids = KYOCERA_SCALAR_KEYS.map((key) => SCALAR_OIDS[key]);
    } else if (vendor === "HP") {
      privateOids = HP_SCALAR_KEYS.map((key) => SCALAR_OIDS[key]);
    }

    if (privateOids.length > 0) {
      const privateScalars = await snmpGetGraceful(session, privateOids, options);
      if (privateScalars) {
        Object.assign(scalars, privateScalars);
      }
    }

    const tables = {};
    for (const [key, oid] of Object.entries(TABLE_OIDS)) {
      tables[key] = await snmpSubtree(session, oid, options);
    }
    logPrinterSync("snmp.session.done", {
      host,
      community,
      durationMs: Date.now() - startedAt,
      tableCounts: Object.fromEntries(
        Object.entries(tables).map(([key, value]) => [key, Object.keys(value || {}).length]),
      ),
    });
    return { scalars, tables, community };
  } finally {
    session.close();
  }
}

async function getSnmpData(host, options = {}) {
  if (!snmp) {
    logPrinterSync("snmp.package.missing", { host });
    return null;
  }
  for (const community of resolveCommunities()) {
    try {
      const data = await withSnmpSession(host, community, options);
      if (data && hasPrinterIdentity(data)) {
        logPrinterSync("snmp.identity.accepted", { host, community });
        return data;
      }
      logPrinterSync("snmp.identity.rejected", { host, community });
    } catch (error) {
      logPrinterSync("snmp.session.error", {
        host,
        community,
        message: error?.message || String(error),
        stack: error?.stack,
      });
    }
  }
  return null;
}

function hasPrinterIdentity(data) {
  const descriptorValues = Object.values(data.tables.hrDeviceDescr || {});
  const text = [
    data.scalars[SCALAR_OIDS.sysDescr],
    data.scalars[SCALAR_OIDS.printerName],
    data.scalars[SCALAR_OIDS.serialNumber],
    ...descriptorValues,
  ]
    .join(" ")
    .toLowerCase();
  if (NON_PRINTER_DEVICE_REGEX.test(text)) {
    return false;
  }
  const hasPrinterMib =
    Object.keys(data.tables.markerLifeCount || {}).length > 0 ||
    Object.keys(data.tables.suppliesLevel || {}).length > 0 ||
    Object.keys(data.tables.alertDescription || {}).length > 0;
  const hasScalarPrinterHints = Boolean(
    String(data.scalars[SCALAR_OIDS.printerName] || "").trim() ||
      String(data.scalars[SCALAR_OIDS.serialNumber] || "").trim() ||
      String(data.scalars[SCALAR_OIDS.hrPrinterStatus] || "").trim(),
  );
  const hasDescriptorPrinterHints = descriptorValues.some((value) =>
    /printer|laserjet|officejet|taskalfa|ecosys|kyocera|canon|xerox|brother|mfp|multifunction/i.test(
      String(value || ""),
    ),
  );
  return hasPrinterMib || (hasScalarPrinterHints && hasDescriptorPrinterHints);
}

function resolveVendor(text) {
  const value = String(text || "").toLowerCase();
  if (value.includes("hp") || value.includes("hewlett")) return "HP";
  if (
    value.includes("kyocera") ||
    value.includes("taskalfa") ||
    value.includes("ecosys") ||
    value.includes("utax") ||
    value.includes("triumph") ||
    value.includes("cdc 19") ||
    value.includes("dcc 29") ||
    value.includes("cdc 35") ||
    value.includes("dcc 35") ||
    /\b(3005|3050|3051|3550|3551)ci\b/.test(value)
  ) {
    return "Kyocera";
  }
  if (value.includes("canon")) return "Canon";
  if (value.includes("xerox")) return "Xerox";
  if (value.includes("brother")) return "Brother";
  if (value.includes("ricoh")) return "Ricoh";
  if (value.includes("epson")) return "Epson";
  return "SNMP";
}

function firstText(values, predicate = null) {
  for (const value of Object.values(values || {})) {
    const text = String(value || "").trim();
    if (!text) continue;
    if (!predicate || predicate(text)) return text;
  }
  return "";
}

function resolveModel(data) {
  const sysDescr = String(data.scalars[SCALAR_OIDS.sysDescr] || "").trim();
  const deviceDescr = firstText(data.tables.hrDeviceDescr, (value) =>
    /printer|laser|officejet|taskalfa|ecosys|kyocera|canon|xerox|brother|mfp|multifunction/i.test(value),
  );
  const combined = `${deviceDescr} ${sysDescr}`.trim();
  const matched = combined.match(PRINTER_MODEL_REGEX)?.[1];
  const rawModel = matched || deviceDescr || sysDescr;
  return String(rawModel)
    .replace(/\bHP ETHERNET MULTI-ENVIRONMENT\b.*$/i, "")
    .replace(/\bKPDL\b.*$/i, "")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function tableIndex(oid, baseOid) {
  return oid.startsWith(`${baseOid}.`) ? oid.slice(baseOid.length + 1) : oid;
}

function maxNumber(values) {
  let result = 0;
  for (const value of Object.values(values || {})) {
    const number = Number(value);
    if (Number.isFinite(number) && number > result) {
      result = number;
    }
  }
  return result;
}

function readSupplyPercent(description, level, maxCapacity) {
  const current = Number(level);
  const max = Number(maxCapacity);
  if (!Number.isFinite(current) || current < 0) return null;
  if (current <= 100 && (!Number.isFinite(max) || max <= 0 || max === 100)) {
    return Math.round(current);
  }
  if (!Number.isFinite(max) || max <= 0) return null;
  return Math.max(0, Math.min(100, Math.round((current / max) * 100)));
}

function assignToner(tonerLevels, description, percent, isMonochrome = false) {
  if (percent == null) return;
  const text = String(description || "").toLowerCase();
  if (/\bwaste\b|\bdrum\b|\bfuser\b|\bmaintenance\b|\btransfer\b|\bbelt\b|\bstaple\b/.test(text)) {
    return;
  }
  if (/\bblack\b|\bbk\b|\bk toner\b|toner k\b|\btk-[\w-]*k\b/.test(text)) {
    tonerLevels.black = percent;
  } else if (/\bcyan\b|\bc toner\b|toner c\b|\btk-[\w-]*c\b/.test(text)) {
    tonerLevels.cyan = percent;
  } else if (/\bmagenta\b|\bm toner\b|toner m\b|\btk-[\w-]*m\b/.test(text)) {
    tonerLevels.magenta = percent;
  } else if (/\byellow\b|\by toner\b|toner y\b|\btk-[\w-]*y\b/.test(text)) {
    tonerLevels.yellow = percent;
  } else if (isMonochrome || /\bcf\d+\w*|\bce\d+\w*|\bcb\d+\w*|\bcc\d+\w*|\bq\d+\w*/.test(text)) {
    tonerLevels.black = percent;
  }
}

function getTonerFallbackLevel(data, colorName) {
  const alerts = Object.values(data.tables.alertDescription || {})
    .map(val => String(val).toLowerCase());
  
  const errorStates = decodeErrorState(data.scalars[SCALAR_OIDS.hrPrinterDetectedErrorState] || "");
  const hasNoTonerGeneral = errorStates.includes("no toner");
  const hasLowTonerGeneral = errorStates.includes("low toner");
  
  const colorLower = colorName.toLowerCase();
  
  // Check if there is a color-specific alert
  const hasNoColorToner = alerts.some(msg => msg.includes(colorLower) && /empty|no toner|replace|missing/i.test(msg));
  const hasLowColorToner = alerts.some(msg => msg.includes(colorLower) && /low|near empty/i.test(msg));
  
  if (hasNoColorToner || (hasNoTonerGeneral && colorLower === "black")) {
    return 0;
  }
  if (hasLowColorToner || (hasLowTonerGeneral && colorLower === "black")) {
    return 10;
  }
  
  return 100;
}

function resolveTonerLevels(data) {
  const descriptions = data.tables.suppliesDescription || {};
  const maxCapacities = data.tables.suppliesMaxCapacity || {};
  const levels = data.tables.suppliesLevel || {};
  const colorants = data.tables.prtMarkerColorantValue || {};
  const tonerLevels = {};
  
  const tonerOids = Object.keys(descriptions).filter(oid => {
    const desc = String(descriptions[oid] || "").toLowerCase();
    return !/waste|drum|fuser|maintenance|transfer|belt|staple/.test(desc);
  });
  
  for (const [oid, description] of Object.entries(descriptions)) {
    const index = tableIndex(oid, TABLE_OIDS.suppliesDescription);
    const level = levels[`${TABLE_OIDS.suppliesLevel}.${index}`];
    const maxCapacity = maxCapacities[`${TABLE_OIDS.suppliesMaxCapacity}.${index}`];
    
    let desc = description;
    if (!desc) {
      const colorantOid = `${TABLE_OIDS.prtMarkerColorantValue}.${index}`;
      const colorant = colorants[colorantOid];
      if (colorant) {
        desc = colorant;
      } else if (tonerOids.length === 1) {
        desc = "black";
      } else {
        const idxParts = index.split(".");
        const idx = idxParts[idxParts.length - 1];
        if (idx === "1") desc = "cyan";
        else if (idx === "2") desc = "magenta";
        else if (idx === "3") desc = "yellow";
        else if (idx === "4") desc = "black";
      }
    }
    
    let percent = readSupplyPercent(desc, level, maxCapacity);
    if (percent == null && (level === "-2" || level === "-3" || Number(level) === -2 || Number(level) === -3)) {
      let colorName = "black";
      const text = String(desc || "").toLowerCase();
      if (/\bcyan\b|\bc toner\b|toner c\b|\btk-[\w-]*c\b/.test(text)) colorName = "cyan";
      else if (/\bmagenta\b|\bm toner\b|toner m\b|\btk-[\w-]*m\b/.test(text)) colorName = "magenta";
      else if (/\byellow\b|\by toner\b|toner y\b|\btk-[\w-]*y\b/.test(text)) colorName = "yellow";
      
      percent = getTonerFallbackLevel(data, colorName);
    }
    
    assignToner(tonerLevels, desc, percent, tonerOids.length === 1);
  }
  return tonerLevels;
}

function decodeErrorState(value) {
  if (!Buffer.isBuffer(value) && typeof value !== "string") return [];
  const buffer = Buffer.isBuffer(value) ? value : Buffer.from(value, "binary");
  if (buffer.length === 0) return [];
  const labels = [
    "low paper",
    "no paper",
    "low toner",
    "no toner",
    "door open",
    "jammed",
    "offline",
    "service requested",
    "input tray missing",
    "output tray missing",
    "marker supply missing",
    "output near full",
    "output full",
    "input tray empty",
    "overdue preventive maintenance",
  ];
  const detected = [];
  for (let index = 0; index < labels.length; index += 1) {
    const byte = buffer[Math.floor(index / 8)];
    const bit = 7 - (index % 8);
    if ((byte & (1 << bit)) !== 0) {
      detected.push(labels[index]);
    }
  }
  return detected;
}

function resolveMaintenance(data) {
  const alerts = Object.entries(data.tables.alertDescription || {})
    .map(([oid, value]) => {
      const index = tableIndex(oid, TABLE_OIDS.alertDescription);
      const severity = Number(data.tables.alertSeverity?.[`${TABLE_OIDS.alertSeverity}.${index}`] || 0);
      return { severity, message: String(value || "").trim() };
    })
    .filter((item) => item.message);
  const detectedErrors = [
    ...decodeErrorState(data.scalars[SCALAR_OIDS.hrPrinterDetectedErrorState]),
    ...Object.values(data.tables.hrPrinterDetectedErrorState || {}).flatMap(decodeErrorState),
  ];
  const messages = [...new Set([...alerts.map((item) => item.message), ...detectedErrors])];
  const paperJams = messages.filter((message) => /jam/i.test(message)).length;
  return {
    paperJams,
    errorMessages: messages.filter((_, index) => index < 20),
    warnings: alerts
      .filter((item) => item.severity > 0)
      .map((item) => item.message)
      .slice(0, 20),
  };
}

function resolveStatus(data, maintenance) {
  const status = Number(
    data.scalars[SCALAR_OIDS.hrPrinterStatus] ||
      firstText(data.tables.hrPrinterStatus) ||
      0,
  );
  const messages = [
    ...(maintenance.errorMessages || []),
    ...(maintenance.warnings || []),
  ].join(" ").toLowerCase();
  if (/offline|service requested|door open|jam|no paper|no toner|output full/.test(messages)) {
    return "error";
  }
  if (/low paper|low toner|near full|maintenance/.test(messages)) {
    return "warning";
  }
  if (status === 5) return "warning";
  if (status === 4) return "online";
  if (status === 3) return "online";
  return "online";
}

function mapPrinter(host, data) {
  if (!data) return null;
  const model = resolveModel(data);
  const hostname = String(data.scalars[SCALAR_OIDS.sysName] || "").trim();
  if (NON_PRINTER_DEVICE_REGEX.test(`${hostname} ${model}`)) {
    return null;
  }
  const rawPrinterName = String(data.scalars[SCALAR_OIDS.printerName] || "").trim();
  const rawNameLooksHostLike = /^[A-Z0-9_-]{6,}$/i.test(rawPrinterName);
  const printerName = String(
    rawPrinterName && !NON_PRINTER_DEVICE_REGEX.test(rawPrinterName) && !rawNameLooksHostLike
      ? rawPrinterName
      : model || hostname || host,
  ).trim();
  const serialNumber = String(data.scalars[SCALAR_OIDS.serialNumber] || "").trim();
  const tonerLevels = resolveTonerLevels(data);
  const maintenance = resolveMaintenance(data);
  const status = resolveStatus(data, maintenance);

  const standardPageCount = maxNumber(data.tables.markerLifeCount);
  const vendor = resolveVendor(`${data.scalars[SCALAR_OIDS.sysDescr] || ""} ${model}`);

  // Initialize detailed counters with standard fallback
  let totalPages = standardPageCount;
  let monoPages = 0;
  let colorPages = 0;
  let duplexPages = 0;
  let copyPages = 0;
  let scanPages = 0;

  if (vendor === "Kyocera") {
    const kyoceraTotal = Number(data.scalars[SCALAR_OIDS.kyoceraTotalPages]);
    if (Number.isFinite(kyoceraTotal) && kyoceraTotal > 0) {
      totalPages = kyoceraTotal;
    }

    const printMono = Number(data.scalars[SCALAR_OIDS.kyoceraPrintMono]) || 0;
    const printColor = Number(data.scalars[SCALAR_OIDS.kyoceraPrintColor]) || 0;
    const copyMono = Number(data.scalars[SCALAR_OIDS.kyoceraCopyMono]) || 0;
    const copyColor = Number(data.scalars[SCALAR_OIDS.kyoceraCopyColor]) || 0;

    monoPages = printMono + copyMono;
    colorPages = printColor + copyColor;
    copyPages = copyMono + copyColor;

    const scan = Number(data.scalars[SCALAR_OIDS.kyoceraScanPages]);
    if (Number.isFinite(scan)) scanPages = scan;

    const duplex = Number(data.scalars[SCALAR_OIDS.kyoceraDuplex]);
    if (Number.isFinite(duplex)) duplexPages = duplex;
  } else if (vendor === "HP") {
    const hpMono = Number(data.scalars[SCALAR_OIDS.hpMonoPages]);
    const hpColor = Number(data.scalars[SCALAR_OIDS.hpColorPages]);
    const hpDuplex = Number(data.scalars[SCALAR_OIDS.hpDuplexPages]);
    const adfScan = Number(data.scalars[SCALAR_OIDS.hpAdfScan]) || 0;
    const flatbedScan = Number(data.scalars[SCALAR_OIDS.hpFlatbedScan]) || 0;

    if (Number.isFinite(hpMono)) monoPages = hpMono;
    if (Number.isFinite(hpColor)) colorPages = hpColor;
    if (Number.isFinite(hpDuplex)) duplexPages = hpDuplex;
    if (adfScan > 0 || flatbedScan > 0) scanPages = adfScan + flatbedScan;
  } else {
    // Generic B&W fallback
    monoPages = totalPages;
  }

  // Ensure logical alignment
  if (totalPages === 0 && (monoPages > 0 || colorPages > 0)) {
    totalPages = monoPages + colorPages;
  }
  if (monoPages === 0 && totalPages > 0 && colorPages === 0) {
    monoPages = totalPages;
  }

  return {
    ipAddress: host,
    hostname,
    model,
    serialNumber,
    printerName,
    vendor,
    status,
    counters: {
      totalPages,
      monoPages,
      colorPages,
      duplexPages,
      copyPages,
      scanPages,
    },
    tonerLevels,
    maintenance,
  };
}

async function probePrinter(host, options = {}) {
  const startedAt = Date.now();
  const hostTimeoutMs = resolveHostTimeout(options);
  logPrinterSync("printer.probe.start", {
    host,
    skipWebDetails: Boolean(options.skipWebDetails),
    hostTimeoutMs,
  });
  const data = await withTimeout(
    getSnmpData(host, options),
    hostTimeoutMs,
    null,
    () => logPrinterSync("printer.probe.host_timeout", { host, hostTimeoutMs }),
  );
  const printer = mapPrinter(host, data);
  if (!printer) {
    logPrinterSync("printer.probe.no_printer", {
      host,
      durationMs: Date.now() - startedAt,
    });
    return null;
  }
  if (options.skipWebDetails) {
    logPrinterSync("printer.probe.done", {
      host,
      printerName: printer.printerName,
      model: printer.model,
      durationMs: Date.now() - startedAt,
      webDetails: false,
    });
    return printer;
  }
  try {
    const webDetails = await collectPrinterWebDetails(host);
    const merged = mergeExtendedDetails(printer, webDetails);
    logPrinterSync("printer.probe.done", {
      host,
      printerName: merged.printerName,
      model: merged.model,
      durationMs: Date.now() - startedAt,
      webDetails: Boolean(webDetails),
    });
    return merged;
  } catch (_) {
    logPrinterSync("printer.probe.web_failed", {
      host,
      durationMs: Date.now() - startedAt,
    });
    return printer;
  }
}

function withTimeout(promise, timeoutMs, fallbackValue, onTimeout = null) {
  let timer = null;
  const timeoutPromise = new Promise((resolve) => {
    timer = setTimeout(() => {
      if (onTimeout) onTimeout();
      resolve(fallbackValue);
    }, timeoutMs);
    timer.unref?.();
  });
  return Promise.race([promise, timeoutPromise]).finally(() => {
    if (timer) clearTimeout(timer);
  });
}

async function discoverPrinters(networkRange, options = {}) {
  if (!snmp) {
    throw new Error("SNMP package is not available. Run npm install in backend and restart the server.");
  }
  const hosts = expandNetworkRange(networkRange);
  logPrinterSync("discovery.hosts.expanded", {
    networkRange,
    hostCount: hosts.length,
    skipWebDetails: Boolean(options.skipWebDetails),
  });
  if (hosts.length === 0) {
    throw new Error(
      "Invalid printer network range. Use CIDR like 192.168.10.0/24, a gateway like 192.168.10.1, a single printer IP, or a range like 192.168.10.20-80.",
    );
  }
  const discovered = [];
  const concurrency = Number(process.env.PRINTER_DISCOVERY_CONCURRENCY || 24);
  const workerCount = Number.isFinite(concurrency) && concurrency > 0 ? concurrency : 24;
  logPrinterSync("discovery.start", {
    networkRange,
    hostCount: hosts.length,
    workerCount,
  });
  let cursor = 0;

  async function worker() {
    while (cursor < hosts.length) {
      const host = hosts[cursor];
      cursor += 1;
      try {
        const printer = await probePrinter(host, options);
        if (printer) discovered.push(printer);
      } catch (error) {
        logPrinterSync("printer.probe.error", {
          host,
          message: error?.message || String(error),
        });
      }
    }
  }

  await Promise.all(Array.from({ length: Math.min(workerCount, hosts.length) }, worker));
  logPrinterSync("discovery.done", {
    networkRange,
    hostCount: hosts.length,
    discoveredCount: discovered.length,
  });
  return discovered;
}

module.exports = {
  discoverPrinters,
  probePrinter,
  expandNetworkRange,
};
