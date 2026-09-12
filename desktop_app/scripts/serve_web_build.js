const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");

const host = process.env.WEB_HOST || "0.0.0.0";
const port = Number(process.env.WEB_PORT || process.argv[2] || 15570);
const root = path.resolve(__dirname, "..", "build", "web");

const mimeTypes = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".wasm": "application/wasm",
  ".otf": "font/otf",
  ".ttf": "font/ttf",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
};

function localNetworkUrls() {
  const urls = [`http://localhost:${port}`];
  for (const entries of Object.values(os.networkInterfaces())) {
    for (const entry of entries || []) {
      if (entry.family === "IPv4" && !entry.internal) {
        urls.push(`http://${entry.address}:${port}`);
      }
    }
  }
  return [...new Set(urls)];
}

function resolveRequestPath(url) {
  const parsed = new URL(url, `http://127.0.0.1:${port}`);
  const cleanPath = decodeURIComponent(parsed.pathname).replace(/^\/+/, "");
  const requested = path.resolve(root, cleanPath || "index.html");
  if (!requested.startsWith(root)) {
    return null;
  }
  return requested;
}

const server = http.createServer((request, response) => {
  if (request.method !== "GET" && request.method !== "HEAD") {
    response.writeHead(405);
    response.end("Method not allowed");
    return;
  }

  let filePath = resolveRequestPath(request.url || "/");
  if (!filePath) {
    response.writeHead(403);
    response.end("Forbidden");
    return;
  }

  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    filePath = path.join(root, "index.html");
  }

  fs.readFile(filePath, (error, data) => {
    if (error) {
      response.writeHead(404);
      response.end("Not found");
      return;
    }
    const ext = path.extname(filePath).toLowerCase();
    response.writeHead(200, {
      "Content-Type": mimeTypes[ext] || "application/octet-stream",
      "Cache-Control": ext === ".html" ? "no-store" : "public, max-age=3600",
    });
    if (request.method === "HEAD") {
      response.end();
      return;
    }
    response.end(data);
  });
});

server.listen(port, host, () => {
  console.log("Web app is running:");
  for (const url of localNetworkUrls()) {
    console.log(`  ${url}`);
  }
  console.log("Use the network IP URL from mobile/branch devices.");
});
