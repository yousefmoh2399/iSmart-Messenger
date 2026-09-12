const fs = require("fs");

const logPath = "C:\\Users\\Yousef\\.gemini\\antigravity\\brain\\1d15f0e6-2883-4702-bbb2-1a18ab27741e\\.system_generated\\tasks\\task-312.log";

if (!fs.existsSync(logPath)) {
  console.log("Log file not found!");
  process.exit(0);
}

const content = fs.readFileSync(logPath, "utf8");
const lines = content.split("\n");

console.log("Searching log for toner keywords...");

const matches = [];
const keywords = [/toner/i, /black/i, /cyan/i, /magenta/i, /yellow/i, /tk-/i];

lines.forEach((line, index) => {
  for (const regex of keywords) {
    if (regex.test(line)) {
      matches.push({ index, line: line.trim() });
      break;
    }
  }
});

console.log(`Found ${matches.length} matching lines:`);
matches.slice(0, 100).forEach(m => console.log(`Line ${m.index}: ${m.line}`));
if (matches.length > 100) {
  console.log(`... and ${matches.length - 100} more`);
}
