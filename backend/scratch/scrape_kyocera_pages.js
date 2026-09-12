const http = require("http");
const https = require("https");

function fetchUrl(url) {
  return new Promise((resolve) => {
    const isHttps = url.startsWith("https:");
    const client = isHttps ? https : http;
    const options = isHttps ? { rejectUnauthorized: false, timeout: 3000 } : { timeout: 3000 };
    client.get(url, options, (res) => {
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => {
        resolve({
          statusCode: res.statusCode,
          headers: res.headers,
          body: Buffer.concat(chunks).toString("utf8")
        });
      });
    }).on("error", (err) => resolve({ error: err.message }));
  });
}

async function run() {
  console.log("Fetching https://192.168.10.11/...");
  const res1 = await fetchUrl("https://192.168.10.11/");
  console.log("Result 1:", res1);

  if (res1.body && res1.body.includes("location.href")) {
    const match = res1.body.match(/location\.href\s*=\s*['"]([^'"]+)['"]/);
    if (match) {
      const redirectUrl = new URL(match[1], "https://192.168.10.11/").toString();
      console.log("Found JS redirect to:", redirectUrl);
      const res2 = await fetchUrl(redirectUrl);
      console.log("Result 2:", res2);
    }
  }
}

run();
