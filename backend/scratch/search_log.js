const fs = require("fs");
const path = require("path");

const logPath = "C:\\Users\\Yousef\\.gemini\\antigravity\\brain\\1d15f0e6-2883-4702-bbb2-1a18ab27741e\\.system_generated\\tasks\\task-312.log";

if (!fs.existsSync(logPath)) {
  console.log("Log file not found at " + logPath);
  process.exit(0);
}

const content = fs.readFileSync(logPath, "utf8");
const lines = content.split("\n");

console.log(`Total lines in log: ${lines.length}`);

const kyoceraOids = [];
lines.forEach(line => {
  if (line.includes("1.3.6.1.4.1.1347")) {
    kyoceraOids.push(line.trim());
  }
});

console.log(`Found ${kyoceraOids.length} Kyocera OIDs:`);
// Print first 100
kyoceraOids.slice(0, 150).forEach(line => console.log(line));
if (kyoceraOids.length > 150) {
  console.log(`... and ${kyoceraOids.length - 150} more`);
}
