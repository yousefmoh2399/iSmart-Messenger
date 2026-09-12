const fs = require("fs");
const path = require("path");

const htmlPath = path.join(__dirname, "start_wlm.html");

if (!fs.existsSync(htmlPath)) {
  console.log("File not found!");
  process.exit(0);
}

const html = fs.readFileSync(htmlPath, "utf8");
const lines = html.split("\n");

console.log("Lines containing lastHTML or toner or status page info:");
lines.forEach(line => {
  const trimmed = line.trim();
  if (trimmed.includes("lastHTML") || trimmed.includes("sample_toner") || trimmed.includes("toner") || trimmed.includes(".htm") && trimmed.includes("=")) {
    console.log(trimmed);
  }
});
