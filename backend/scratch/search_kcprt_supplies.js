const fs = require("fs");

const logPath = "C:\\Users\\Yousef\\.gemini\\antigravity\\brain\\1d15f0e6-2883-4702-bbb2-1a18ab27741e\\.system_generated\\tasks\\task-312.log";

if (!fs.existsSync(logPath)) {
  console.log("Log file not found!");
  process.exit(0);
}

const content = fs.readFileSync(logPath, "utf8");
const lines = content.split("\n");

console.log("Searching log for 1.3.6.1.4.1.1347.43.11...");
let count = 0;
lines.forEach(line => {
  if (line.includes("1.3.6.1.4.1.1347.43.11")) {
    console.log(line.trim());
    count++;
  }
});

console.log(`Found ${count} lines.`);
