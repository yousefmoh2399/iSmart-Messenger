const fs = require("fs");
const path = require("path");

const logPath = "C:\\Users\\Yousef\\.gemini\\antigravity\\brain\\1d15f0e6-2883-4702-bbb2-1a18ab27741e\\.system_generated\\tasks\\task-312.log";

if (!fs.existsSync(logPath)) {
  console.log("Log file not found!");
  process.exit(0);
}

const logContent = fs.readFileSync(logPath, "utf8");
const lines = logContent.split("\n");

console.log("Searching walk log for possible toner percentage values (0-100)...");

const candidates = [];
lines.forEach(line => {
  const match = line.match(/(1\.3\.6\.1\.4\.1\.1347\.\S+)\s*=\s*(\d+)/);
  if (match) {
    const oid = match[1];
    const val = parseInt(match[2], 10);
    // Toner percentages are usually between 0 and 100
    // Let's print OIDs where value is between 5 and 100
    if (val >= 0 && val <= 100) {
      candidates.push({ oid, val });
    }
  }
});

// Sort by OID
candidates.sort((a, b) => a.oid.localeCompare(b.oid));

console.log(`Found ${candidates.length} OIDs with values 0-100:`);
candidates.forEach(c => {
  // We can filter out things that look like common status values (like 1, 2, 3, 4, 12, 18, 24)
  // Let's print all of them so we can analyze
  console.log(`${c.oid} = ${c.val}`);
});
