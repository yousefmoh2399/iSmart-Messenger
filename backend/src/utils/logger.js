const os = require("os");

const INSTANCE_ID = String(
  process.env.INSTANCE_ID || os.hostname() || "backend-01"
).trim();

const SENSITIVE_KEY_PATTERN =
  /password|secret|token|authorization|cookie|mongodb_uri|redis_url/i;

function sanitizeMeta(value, depth = 0) {
  if (depth > 4 || value === null || value === undefined) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((item) => sanitizeMeta(item, depth + 1));
  }
  if (typeof value === "object") {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      if (SENSITIVE_KEY_PATTERN.test(k)) {
        out[k] = "[REDACTED]";
      } else {
        out[k] = sanitizeMeta(v, depth + 1);
      }
    }
    return out;
  }
  return value;
}

function safeJson(value) {
  try {
    return JSON.stringify(value);
  } catch (_) {
    return JSON.stringify({ message: "unserializable" });
  }
}

function log(level, message, meta = {}) {
  const safeMeta = sanitizeMeta(meta);
  const payload = {
    ts: new Date().toISOString(),
    level,
    instanceId: INSTANCE_ID,
    message,
    ...(safeMeta && typeof safeMeta === "object" ? safeMeta : {}),
  };
  const line = safeJson(payload);
  // eslint-disable-next-line no-console
  console.log(line);
}

module.exports = {
  info: (message, meta) => log("info", message, meta),
  warn: (message, meta) => log("warn", message, meta),
  error: (message, meta) => log("error", message, meta),
  getInstanceId: () => INSTANCE_ID,
};

