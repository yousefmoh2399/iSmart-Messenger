const fs = require("fs");

const logPath = "C:\\Users\\Yousef\\.gemini\\antigravity\\brain\\1d15f0e6-2883-4702-bbb2-1a18ab27741e\\.system_generated\\tasks\\task-312.log";

if (!fs.existsSync(logPath)) {
  console.log("Log file not found!");
  process.exit(0);
}

const content = fs.readFileSync(logPath, "utf8");
const lines = content.split("\n");

const oids = {};
lines.forEach(line => {
  const match = line.match(/(1\.3\.6\.1\.4\.1\.1347\.\S+)\s*=\s*(\S+)/);
  if (match) {
    oids[match[1]] = match[2];
  }
});

console.log("Searching for final-digit 4-index OID groups...");

const patterns = {};
for (const oid of Object.keys(oids)) {
  const parts = oid.split(".");
  const last = parts[parts.length - 1];
  
  if (["1", "2", "3", "4"].includes(last)) {
    const base = parts.slice(0, -1).join(".");
    if (!patterns[base]) patterns[base] = new Set();
    patterns[base].add(last);
  }
}

for (const [base, indices] of Object.entries(patterns)) {
  if (indices.has("1") && indices.has("2") && indices.has("3") && indices.has("4") && indices.size === 4) {
    console.log(`\nCandidate Base OID: ${base}.{1..4}`);
    for (let i = 1; i <= 4; i++) {
      const fullOid = `${base}.${i}`;
      console.log(`  ${fullOid} = ${oids[fullOid]}`);
    }
  }
}
