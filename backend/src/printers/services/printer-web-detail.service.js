const http = require("http");
const https = require("https");
const { execFile } = require("child_process");
const { TextDecoder } = require("util");
const { getBundledExecutable } = require("../../utils/executable.util");

const COMMON_PATHS = [
  "/",
  "/hp/device/this.LCDispatcher",
  "/hp/device/info_deviceStatus.html",
  "/hp/device/info_configuration.html",
  "/hp/device/info_suppliesStatus.html",
  "/hp/device/info_usage.html",
  "/hp/device/info_eventLog.html",
  "/hp/device/info_jobLog.html",
  "/hp/device/InternalPages/Index?id=UsagePage",
  "/hp/device/InternalPages/Index?id=SuppliesStatus",
  "/hp/device/InternalPages/Index?id=EventLog",
  "/start/start.htm",
  "/startwlm/Start_Wlm.htm",
  "/status.htm",
  "/basic/status.htm",
  "/dvcinfo/dvcinfo.htm",
  "/eng/status/usage.htm",
  "/job/JobStatus.htm",
];

const TONER_KEYWORDS = {
  black: ["black", "bk", "toner k", "tk-", "k"],
  cyan: ["cyan", "toner c", "c"],
  magenta: ["magenta", "toner m", "m"],
  yellow: ["yellow", "toner y", "y"],
};

const CRAWL_KEYWORDS =
  /status|supply|suppl|toner|usage|counter|report|event|job|history|maint|device|consum|paper|ccrx|log/i;

function requestText(url, timeout = Number(process.env.PRINTER_EWS_TIMEOUT_MS || 3000), redirects = 0) {
  return new Promise((resolve) => {
    const client = url.startsWith("https:") ? https : http;
    const options = url.startsWith("https:")
      ? {
          timeout,
          rejectUnauthorized: false,
          minVersion: "TLSv1",
          headers: {
            "User-Agent": "iSmart-Printer-Monitor/1.0",
            Accept: "text/html,application/xhtml+xml,application/xml,text/xml,*/*",
          },
        }
      : {
          timeout,
          headers: {
            "User-Agent": "iSmart-Printer-Monitor/1.0",
            Accept: "text/html,application/xhtml+xml,application/xml,text/xml,*/*",
          },
        };
    const req = client.get(url, options, (res) => {
      const statusCode = res.statusCode || 0;
      if (statusCode >= 300 && statusCode < 400 && res.headers.location && redirects < 3) {
        res.resume();
        const nextUrl = new URL(res.headers.location, url).toString();
        resolve(requestText(nextUrl, timeout, redirects + 1));
        return;
      }
      if (statusCode >= 400) {
        res.resume();
        resolve(null);
        return;
      }
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", async () => {
        const text = decodeBuffer(Buffer.concat(chunks), res.headers["content-type"]);
        if (text) {
          resolve(text);
          return;
        }
        resolve(await requestTextWithCurl(url, timeout));
      });
    });
    req.on("timeout", () => {
      req.destroy();
      requestTextWithCurl(url, timeout).then(resolve).catch(() => resolve(null));
    });
    req.on("error", () => {
      requestTextWithCurl(url, timeout).then(resolve).catch(() => resolve(null));
    });
  });
}

function requestTextWithCurl(url, timeout) {
  return new Promise((resolve) => {
    const maxTimeSeconds = Math.max(2, Math.ceil(timeout / 1000));
    const command = getBundledExecutable("curl");
    execFile(
      command,
      [
        "-k",
        "-L",
        "--compressed",
        "--max-time",
        String(maxTimeSeconds),
        "-A",
        "iSmart-Printer-Monitor/1.0",
        "-H",
        "Accept: text/html,application/xhtml+xml,application/xml,text/xml,*/*",
        url,
      ],
      { encoding: "buffer", maxBuffer: 4 * 1024 * 1024 },
      (error, stdout) => {
        if (error || !stdout || stdout.length === 0) {
          resolve(null);
          return;
        }
        resolve(decodeBuffer(Buffer.from(stdout), ""));
      },
    );
  });
}

function decodeBuffer(buffer, contentType = "") {
  const charset = String(contentType).match(/charset=([^;]+)/i)?.[1]?.toLowerCase() || "";
  if (charset.includes("windows-1256") || charset.includes("cp1256")) {
    return new TextDecoder("windows-1256").decode(buffer);
  }
  if (charset.includes("latin")) return buffer.toString("latin1");
  return buffer.toString("utf8");
}

function decodeHtml(value) {
  return String(value || "")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)))
    .replace(/&#x([0-9a-f]+);/gi, (_, code) => String.fromCharCode(parseInt(code, 16)));
}

function stripTags(value) {
  return decodeHtml(value)
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(td|th|tr|p|div|li|h\d|option)>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\n\s+/g, "\n")
    .trim();
}

function normalizeText(value) {
  return stripTags(value)
    .replace(/[:：]+$/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function parseNumber(value) {
  const match = String(value == null ? "" : value).match(/-?\d[\d,.]*/);
  if (!match) return null;
  const normalized = match[0].includes(".") && !match[0].includes(",")
    ? match[0]
    : match[0].replace(/,/g, "");
  const number = Number(normalized);
  return Number.isFinite(number) ? number : null;
}

function parseTables(html) {
  const tables = [];
  const tableMatches = String(html || "").match(/<table[\s\S]*?<\/table>/gi) || [];
  for (const tableHtml of tableMatches) {
    const rows = [];
    const rowMatches = tableHtml.match(/<tr[\s\S]*?<\/tr>/gi) || [];
    for (const rowHtml of rowMatches) {
      const cells = [];
      const cellMatches = rowHtml.match(/<(td|th)[^>]*>[\s\S]*?<\/\1>/gi) || [];
      for (const cellHtml of cellMatches) {
        const cell = normalizeText(cellHtml);
        if (cell) cells.push(cell);
      }
      if (cells.length) rows.push(cells);
    }
    if (rows.length) tables.push(rows);
  }
  return tables;
}

function keyValueRows(tables) {
  const rows = [];
  for (const table of tables) {
    for (const row of table) {
      if (row.length === 2) {
        rows.push([row[0], row[1]]);
      } else if (row.length > 2) {
        for (let index = 0; index < row.length - 1; index += 2) {
          rows.push([row[index], row[index + 1]]);
        }
      }
    }
  }
  return rows.filter(([key, value]) => key && value && key !== value);
}

function xmlSections(xml, tagName) {
  const pattern = new RegExp(
    `<(?:[\\w-]+:)?${tagName}\\b[^>]*>([\\s\\S]*?)<\\/(?:[\\w-]+:)?${tagName}>`,
    "gi",
  );
  return [...String(xml || "").matchAll(pattern)].map((match) => match[1]);
}

function xmlSection(xml, tagName) {
  return xmlSections(xml, tagName)[0] || "";
}

function xmlValue(xml, tagName) {
  return normalizeText(xmlSection(xml, tagName));
}

function xmlValues(xml, tagName) {
  return xmlSections(xml, tagName).map(normalizeText).filter(Boolean);
}

function requestDevMgmtXml(ipAddress, fileName) {
  return requestText(`http://${ipAddress}/DevMgmt/${fileName}`);
}

function humanizeStatusToken(value) {
  return String(value || "")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/_/g, " ")
    .trim();
}

function buildStatusDescription(alertId, details) {
  return [humanizeStatusToken(alertId), ...details.filter(Boolean)].join(" - ");
}

function parseHpUsageMedia(usageXml) {
  return xmlSections(usageXml, "UsageByMedia")
    .map((block) => ({
      mediaSize: xmlValue(block, "MediaSizeName"),
      totalPages: parseNumber(xmlValue(block, "TotalImpressions")),
      units: parseNumber(xmlValue(block, "DuplexSheets")) ?? 0,
    }))
    .filter((entry) => entry.mediaSize || entry.totalPages);
}

function parseHpConsumables(consumableXml) {
  const supplies = xmlSections(consumableXml, "ConsumableInfo").map((block) => {
    const family = xmlValue(block, "ConsumableFamilyName");
    const colorCode = xmlValue(block, "ConsumableLabelCode");
    const state = xmlValue(xmlSection(block, "ConsumableLifeState"), "ConsumableState");
    const level = parseNumber(xmlValue(block, "ConsumablePercentageLevelRemaining"));
    return {
      color: colorCode || family,
      status: humanizeStatusToken(state),
      serialNumber: xmlValue(block, "SerialNumber"),
      type: xmlValue(block, "ConsumableTypeEnum"),
      firstInstallDate: xmlValue(xmlSection(block, "Installation"), "Date"),
      lastUseDate: xmlValue(block, "ConsumableLastUsedDate"),
      pagesPrinted: parseNumber(xmlValue(xmlSection(block, "PreviousCartridgeData"), "PageCountLetterAreaConvertedAtVeryLow")),
      remainingPages: level,
      application: xmlValue(block, "CartridgeDataCreator"),
      partNumber: xmlValue(block, "ProductNumber"),
      family,
    };
  });

  const tonerLevels = {};
  for (const item of supplies) {
    const text = `${item.color} ${item.family}`.toLowerCase();
    const level = parseNumber(item.remainingPages);
    if (level == null) continue;
    const code = String(item.color || "").trim().toUpperCase();
    if (code === "K") tonerLevels.black = level;
    else if (code === "C") tonerLevels.cyan = level;
    else if (code === "M") tonerLevels.magenta = level;
    else if (code === "Y") tonerLevels.yellow = level;
    else {
      if (TONER_KEYWORDS.black.some((keyword) => text.includes(keyword))) tonerLevels.black = level;
      if (TONER_KEYWORDS.cyan.some((keyword) => text.includes(keyword))) tonerLevels.cyan = level;
      if (TONER_KEYWORDS.magenta.some((keyword) => text.includes(keyword))) tonerLevels.magenta = level;
      if (TONER_KEYWORDS.yellow.some((keyword) => text.includes(keyword))) tonerLevels.yellow = level;
    }
  }

  return { supplies, tonerLevels };
}

function parseHpProductStatus(statusXml) {
  const statuses = xmlValues(statusXml, "StatusCategory");
  const alerts = xmlSections(statusXml, "Alert").map((block) => {
    const alertId = xmlValue(block, "ProductStatusAlertID");
    const details = [
      humanizeStatusToken(xmlValue(block, "AlertDetailsMarkerColor")),
      humanizeStatusToken(xmlValue(block, "AlertDetailsInputBin")),
      humanizeStatusToken(xmlValue(block, "AlertDetailsConsumableTypeEnum")),
    ];
    return {
      code: alertId,
      type: humanizeStatusToken(xmlValue(block, "Severity") || "Alert"),
      dateTime: "",
      cycles: "",
      count: parseNumber(xmlValue(block, "AlertPriority")),
      description: buildStatusDescription(alertId, details),
      firmware: "",
    };
  });

  const warnings = [];
  const errors = [];
  for (const token of statuses) {
    const normalized = humanizeStatusToken(token);
    if (/low|empty|power save/i.test(normalized)) warnings.push(normalized);
    else errors.push(normalized);
  }

  return {
    statuses,
    alerts,
    warnings: [...new Set(warnings)],
    errors: [...new Set(errors)],
  };
}

function parseHpEventLog(logXml) {
  return xmlSections(logXml, "Event").map((block) => ({
    code: xmlValue(block, "EventCode"),
    type: humanizeStatusToken(xmlValue(block, "Severity")),
    dateTime: xmlValue(block, "TimeStamp"),
    cycles: parseNumber(xmlValue(block, "TotalImpressions")),
    count: parseNumber(xmlValue(block, "EventOccurrences")),
    description: xmlValue(block, "EventCode"),
    firmware: xmlValue(xmlSection(block, "FirmwareVersion"), "Revision"),
  }));
}

async function collectHpLedmDetails(ipAddress) {
  const [configXml, serviceXml, usageXml, statusXml, logsXml, consumableXml] = await Promise.all([
    requestDevMgmtXml(ipAddress, "ProductConfigDyn.xml"),
    requestDevMgmtXml(ipAddress, "ProductServiceDyn.xml"),
    requestDevMgmtXml(ipAddress, "ProductUsageDyn.xml"),
    requestDevMgmtXml(ipAddress, "ProductStatusDyn.xml"),
    requestDevMgmtXml(ipAddress, "ProductLogsDyn.xml"),
    requestDevMgmtXml(ipAddress, "ConsumableConfigDyn.xml"),
  ]);

  if (!configXml || !usageXml || !/MakeAndModel|ProductInformation/i.test(configXml)) {
    return null;
  }

  const productInfoXml = xmlSection(configXml, "ProductInformation");
  const productSettingsXml = xmlSection(configXml, "ProductSettings");
  const memoryXml = xmlSection(configXml, "Memory");
  const printerSubunitXml = xmlSection(usageXml, "PrinterSubunit");
  const hpConsumables = consumableXml ? parseHpConsumables(consumableXml) : { supplies: [], tonerLevels: {} };
  const hpStatus = statusXml ? parseHpProductStatus(statusXml) : { alerts: [], warnings: [], errors: [] };

  return {
    source: "hp_ledm",
    collectedAt: new Date(),
    pages: [
      `http://${ipAddress}/DevMgmt/ProductConfigDyn.xml`,
      `http://${ipAddress}/DevMgmt/ProductUsageDyn.xml`,
      `http://${ipAddress}/DevMgmt/ConsumableConfigDyn.xml`,
      `http://${ipAddress}/DevMgmt/ProductStatusDyn.xml`,
      `http://${ipAddress}/DevMgmt/ProductLogsDyn.xml`,
    ],
    product: {
      productName: xmlValue(productInfoXml, "MakeAndModel"),
      productNumber: xmlValue(productInfoXml, "ProductNumber"),
      serialNumber: xmlValue(productInfoXml, "SerialNumber"),
      serviceId: xmlValue(productInfoXml, "ServiceID"),
      firmwareVersion: xmlValue(xmlSection(productInfoXml, "Version"), "Revision"),
      engineFirmware: xmlValue(xmlSection(serviceXml, "EngineFWVersion"), "Revision"),
      region: humanizeStatusToken(xmlValue(productSettingsXml, "CountryAndRegionName")),
      memoryTotalKb: parseNumber(xmlValue(memoryXml, "TotalMemory")),
      memoryAvailableKb: parseNumber(xmlValue(memoryXml, "AvailableMemory")),
    },
    usage: {
      engineTotalPages: parseNumber(xmlValue(printerSubunitXml, "TotalImpressions")),
      totalPrintedPages: parseNumber(xmlValue(printerSubunitXml, "MonochromeImpressions")),
      simplexPages: parseNumber(xmlValue(printerSubunitXml, "SimplexSheets")),
      duplexPages: parseNumber(xmlValue(printerSubunitXml, "DuplexSheets")),
      pcl5Pages: parseNumber(xmlValue(xmlSection(printerSubunitXml, "PCL5Impressions"), "TotalImpressions")),
      pcl6Pages: parseNumber(xmlValue(xmlSection(printerSubunitXml, "PCL6Impressions"), "TotalImpressions")),
      postScriptPages: parseNumber(xmlValue(xmlSection(printerSubunitXml, "PostScriptImpressions"), "TotalImpressions")),
      paperJams: parseNumber(xmlValue(printerSubunitXml, "JamEvents")),
      mispicks: parseNumber(xmlValue(printerSubunitXml, "MispickEvents")),
      a4EquivalentPages: parseNumber(xmlValue(xmlSection(printerSubunitXml, "A4EquivalentImpressions"), "TotalImpressions")),
      media: parseHpUsageMedia(printerSubunitXml),
    },
    supplies: hpConsumables.supplies,
    tonerLevels: hpConsumables.tonerLevels,
    events: [...hpStatus.alerts.slice(0, 20), ...parseHpEventLog(logsXml).slice(0, 60)],
    jobs: [],
    rawKeyValues: [
      { key: "Product Name", value: xmlValue(productInfoXml, "MakeAndModel") },
      { key: "Product Number", value: xmlValue(productInfoXml, "ProductNumber") },
      { key: "Serial Number", value: xmlValue(productInfoXml, "SerialNumber") },
      { key: "Firmware Version", value: xmlValue(xmlSection(productInfoXml, "Version"), "Revision") },
      { key: "Engine Firmware", value: xmlValue(xmlSection(serviceXml, "EngineFWVersion"), "Revision") },
    ],
    warnings: hpStatus.warnings,
    errors: hpStatus.errors,
  };
}

function hasPrinterContent(text) {
  return /printer|laserjet|officejet|kyocera|taskalfa|ecosys|command center rx|toner|cartridge|pages|طابعة|خرطوش|الحبر|الصفحات|انحشار/i.test(
    String(text || ""),
  );
}

function normalizeUrl(origin, href) {
  try {
    const url = new URL(href, origin);
    if (!/^https?:$/i.test(url.protocol)) return null;
    return url.toString();
  } catch (_) {
    return null;
  }
}

function extractRelevantLinks(html, origin) {
  const links = new Set();
  const matches = String(html || "").match(/href\s*=\s*["']([^"'#]+)["']/gi) || [];
  for (const match of matches) {
    const href = match.match(/href\s*=\s*["']([^"'#]+)["']/i)?.[1];
    if (!href) continue;
    const normalized = normalizeUrl(origin, href);
    if (!normalized || !CRAWL_KEYWORDS.test(normalized)) continue;
    links.add(normalized);
  }
  return [...links].slice(0, 12);
}

function extractTonerLevels(rows) {
  const tonerLevels = {};
  for (const [key, value] of rows) {
    const text = `${key} ${value}`.toLowerCase();
    const percentMatch = String(value || "").match(/(\d{1,3})\s*%/);
    if (!percentMatch) continue;
    const percent = Number(percentMatch[1]);
    if (!Number.isFinite(percent)) continue;
    if (TONER_KEYWORDS.black.some((keyword) => text.includes(keyword))) tonerLevels.black = percent;
    if (TONER_KEYWORDS.cyan.some((keyword) => text.includes(keyword))) tonerLevels.cyan = percent;
    if (TONER_KEYWORDS.magenta.some((keyword) => text.includes(keyword))) tonerLevels.magenta = percent;
    if (TONER_KEYWORDS.yellow.some((keyword) => text.includes(keyword))) tonerLevels.yellow = percent;
  }
  return tonerLevels;
}

function classifyTable(table) {
  const header = (table[0] || []).join(" ").toLowerCase();
  if (/event|firmware|description|cycles|code|الحدث|الوصف|الدورات|التكرارات/.test(header)) return "events";
  if (/job|user|status|date|الوظيفة|المستخدم|الحالة|التاريخ/.test(header)) return "jobs";
  if (/media|medium|size|units|pages|الوسط|حجم|الوحدات|الصفحات/.test(header)) return "media";
  if (/cartridge|supply|toner|color|خرطوش|مستلزمات|الحبر|اللون/.test(header)) return "supplies";
  return "unknown";
}

function mapCells(cells, keys) {
  const result = {};
  for (let index = 0; index < Math.min(cells.length, keys.length); index += 1) {
    result[keys[index]] = cells[index];
  }
  return result;
}

function extractStructuredTables(tables) {
  const supplies = [];
  const events = [];
  const jobs = [];
  const media = [];

  for (const table of tables) {
    if (table.length < 2) continue;
    const type = classifyTable(table);
    const rows = table.slice(1);
    if (type === "events") {
      events.push(...rows.map((cells) => mapCells(cells, ["code", "type", "dateTime", "cycles", "count", "description", "firmware"])));
    } else if (type === "jobs") {
      jobs.push(...rows.map((cells) => mapCells(cells, ["name", "user", "status", "dateTime", "details"])));
    } else if (type === "media") {
      media.push(...rows.map((cells) => mapCells(cells, ["mediaSize", "units", "totalPages"])));
    } else if (type === "supplies") {
      supplies.push(...rows.map((cells) => mapCells(cells, ["color", "status", "serialNumber", "type", "firstInstallDate", "lastUseDate", "pagesPrinted", "remainingPages"])));
    }
  }

  return {
    supplies: supplies.filter((item) => Object.values(item).some(Boolean)).slice(0, 40),
    events: events.filter((item) => Object.values(item).some(Boolean)).slice(0, 100),
    jobs: jobs.filter((item) => Object.values(item).some(Boolean)).slice(0, 100),
    media: media.filter((item) => Object.values(item).some(Boolean)).slice(0, 80),
  };
}

function parseGenericWebPages(pages) {
  const tables = pages.flatMap((page) => parseTables(page.html));
  const rows = keyValueRows(tables);
  const structured = extractStructuredTables(tables);
  return {
    source: "embedded_web_server",
    collectedAt: new Date(),
    pages: pages.map((page) => page.url),
    product: {},
    usage: { media: structured.media },
    supplies: structured.supplies,
    tonerLevels: extractTonerLevels(rows),
    events: structured.events,
    jobs: structured.jobs,
    rawKeyValues: rows.slice(0, 220).map(([key, value]) => ({ key, value })),
  };
}

function mergeExtendedDetails(snmpPayload, webDetails) {
  if (!webDetails) return snmpPayload;
  const product = webDetails.product || {};
  const usage = webDetails.usage || {};
  const stripNumericCodes = (items) =>
    (items || []).filter((item) => !/^\d+(?:\.\d+)?$/.test(String(item || "").trim()));
  const warnings = [
    ...stripNumericCodes(snmpPayload.maintenance?.warnings),
    ...(webDetails.warnings || []),
  ];
  const errors = [
    ...stripNumericCodes(snmpPayload.maintenance?.errorMessages),
    ...(webDetails.errors || []),
  ];

  const suppliesText = JSON.stringify(webDetails.supplies || "");
  const eventsText = JSON.stringify(webDetails.events || []);
  if (/very low|low|منخفض/i.test(suppliesText)) {
    warnings.push("الحبر منخفض أو منخفض جدًا.");
  }
  if (/jam|انحشار/i.test(eventsText)) {
    errors.push("تم رصد انحشار ورق في سجل الطابعة.");
  }

  const counters = { ...(snmpPayload.counters || {}) };
  const engineTotal = Number(usage.engineTotalPages || usage.totalPrintedPages || 0);
  if (Number.isFinite(engineTotal) && engineTotal > 0) counters.totalPages = engineTotal;
  const monoPages = Number(usage.totalPrintedPages || usage.pcl6Pages || 0);
  if (Number.isFinite(monoPages) && monoPages > 0) counters.monoPages = monoPages;
  const duplexPages = Number(usage.duplexPages || 0);
  if (Number.isFinite(duplexPages) && duplexPages > 0) counters.duplexPages = duplexPages;

  const maintenance = {
    ...(snmpPayload.maintenance || {}),
    paperJams: Number.isFinite(Number(usage.paperJams)) ? Number(usage.paperJams) : snmpPayload.maintenance?.paperJams || 0,
    warnings: [...new Set(warnings.filter(Boolean))].slice(0, 20),
    errorMessages: [...new Set(errors.filter(Boolean))].slice(0, 20),
  };

  const tonerLevels = {
    ...(snmpPayload.tonerLevels || {}),
    ...(webDetails.tonerLevels || {}),
  };

  const messages = `${maintenance.warnings.join(" ")} ${maintenance.errorMessages.join(" ")}`.toLowerCase();
  const status = /jam|door|offline|error|empty|service/.test(messages)
    ? "error"
    : /low|warning|attention|maintenance/.test(messages)
      ? "warning"
      : snmpPayload.status;

  return {
    ...snmpPayload,
    model: product.productName || snmpPayload.model,
    serialNumber: product.serialNumber || snmpPayload.serialNumber,
    printerName: product.productName || snmpPayload.printerName,
    counters,
    tonerLevels,
    maintenance,
    status,
    extendedDetails: webDetails,
  };
}

async function collectGenericWebDetails(ipAddress) {
  const pages = [];
  const visited = new Set();
  const maxPages = Number(process.env.PRINTER_EWS_MAX_PAGES || 10);

  for (const protocol of ["http", "https"]) {
    const queue = COMMON_PATHS.map((pagePath) => `${protocol}://${ipAddress}${pagePath}`);
    while (queue.length > 0 && pages.length < maxPages) {
      const url = queue.shift();
      if (!url || visited.has(url)) continue;
      visited.add(url);
      const html = await requestText(url);
      if (!html || !hasPrinterContent(html)) continue;
      pages.push({ url, html });
      for (const link of extractRelevantLinks(html, url)) {
        if (!visited.has(link)) queue.push(link);
      }
    }
    if (pages.length) break;
  }

  if (!pages.length) return null;
  return parseGenericWebPages(pages);
}

async function collectPrinterWebDetails(ipAddress) {
  const hpLedm = await collectHpLedmDetails(ipAddress);
  if (hpLedm) return hpLedm;
  return collectGenericWebDetails(ipAddress);
}

module.exports = {
  collectPrinterWebDetails,
  mergeExtendedDetails,
};
