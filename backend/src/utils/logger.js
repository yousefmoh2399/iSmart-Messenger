function safeJson(value) {
  try {
    return JSON.stringify(value);
  } catch (_) {
    return JSON.stringify({ message: "unserializable" });
  }
}

function log(level, message, meta = {}) {
  const payload = {
    ts: new Date().toISOString(),
    level,
    message,
    ...meta,
  };
  const line = safeJson(payload);
  // eslint-disable-next-line no-console
  console.log(line);
}

module.exports = {
  info: (message, meta) => log("info", message, meta),
  warn: (message, meta) => log("warn", message, meta),
  error: (message, meta) => log("error", message, meta),
};

