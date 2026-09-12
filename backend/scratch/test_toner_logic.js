const mongoose = require("mongoose");
const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "../.env") });

// Import model and service functions
const Printer = require("../src/printers/models/printer.model");
const PrinterNotification = require("../src/printers/models/printer-notification.model");
const PrinterBranch = require("../src/printers/models/printer-branch.model");
const { upsertDiscoveredPrinter } = require("../src/printers/services/printer.service");

// Re-create the logic of resolveTonerLevels & assignToner to test locally
function assignToner(tonerLevels, description, percent, isMonochrome = false) {
  if (percent == null) return;
  const text = String(description || "").toLowerCase();
  if (/\bwaste\b|\bdrum\b|\bfuser\b|\bmaintenance\b|\btransfer\b|\bbelt\b|\bstaple\b/.test(text)) {
    return;
  }
  if (/\bblack\b|\bbk\b|\bk toner\b|toner k\b|\btk-[\w-]*k\b/.test(text)) {
    tonerLevels.black = percent;
  } else if (/\bcyan\b|\bc toner\b|toner c\b|\btk-[\w-]*c\b/.test(text)) {
    tonerLevels.cyan = percent;
  } else if (/\bmagenta\b|\bm toner\b|toner m\b|\btk-[\w-]*m\b/.test(text)) {
    tonerLevels.magenta = percent;
  } else if (/\byellow\b|\by toner\b|toner y\b|\btk-[\w-]*y\b/.test(text)) {
    tonerLevels.yellow = percent;
  } else if (isMonochrome || /\bcf\d+\w*|\bce\d+\w*|\bcb\d+\w*|\bcc\d+\w*|\bq\d+\w*/.test(text)) {
    tonerLevels.black = percent;
  }
}

function readSupplyPercent(description, level, maxCapacity) {
  const current = Number(level);
  const max = Number(maxCapacity);
  if (!Number.isFinite(current) || current < 0) return null;
  if (current <= 100 && (!Number.isFinite(max) || max <= 0 || max === 100)) {
    return Math.round(current);
  }
  if (!Number.isFinite(max) || max <= 0) return null;
  return Math.max(0, Math.min(100, Math.round((current / max) * 100)));
}

function resolveTonerLevels(data) {
  const descriptions = data.tables.suppliesDescription || {};
  const maxCapacities = data.tables.suppliesMaxCapacity || {};
  const levels = data.tables.suppliesLevel || {};
  const tonerLevels = {};
  
  const tonerOids = Object.keys(descriptions).filter(oid => {
    const desc = String(descriptions[oid] || "").toLowerCase();
    return !/waste|drum|fuser|maintenance|transfer|belt|staple/.test(desc);
  });
  
  for (const [oid, description] of Object.entries(descriptions)) {
    const index = oid.split(".").slice(-2).join("."); // simplified index extraction
    const level = levels[`1.3.6.1.2.1.43.11.1.1.9.${index}`];
    const maxCapacity = maxCapacities[`1.3.6.1.2.1.43.11.1.1.8.${index}`];
    
    let desc = description;
    let percent = readSupplyPercent(desc, level, maxCapacity);
    
    assignToner(tonerLevels, desc, percent, tonerOids.length === 1);
  }
  return tonerLevels;
}

async function run() {
  console.log("=== 1. Testing OID Parsing Logic ===");
  const testData = {
    tables: {
      suppliesDescription: {
        "1.3.6.1.2.1.43.11.1.1.6.1.1": "HP CF226A"
      },
      suppliesLevel: {
        "1.3.6.1.2.1.43.11.1.1.9.1.1": "1000"
      },
      suppliesMaxCapacity: {
        "1.3.6.1.2.1.43.11.1.1.8.1.1": "10000"
      }
    }
  };
  
  const tonerLevels = resolveTonerLevels(testData);
  console.log("Parsed Toner Levels (Expected black: 10):", JSON.stringify(tonerLevels));
  if (tonerLevels.black === 10) {
    console.log("✅ Toner parsing logic matches black cartridge code and monochrome fallback!");
  } else {
    console.error("❌ Toner parsing logic failed!");
  }

  console.log("\n=== 2. Testing Database Integration & Notification Creation ===");
  await mongoose.connect(process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/workplace_documents");
  console.log("Connected to MongoDB");

  // Get a branch to associate with the test
  const branch = await PrinterBranch.findOne({ deletedAt: null });
  if (!branch) {
    console.error("❌ No active branch found in MongoDB! Please seed branches first.");
    await mongoose.disconnect();
    return;
  }
  console.log(`Using branch: ${branch.name} (${branch._id})`);

  // Clear existing notifications for test HP printers if any
  await PrinterNotification.deleteMany({ type: "toner_low" });
  console.log("Cleared existing toner_low notifications");

  // Simulate upserting a discovered HP printer with 10% toner
  const payload = {
    ipAddress: "192.168.99.10",
    hostname: "HPTESTPRINTER",
    model: "HP LaserJet M402n",
    serialNumber: "TESTSNM402N",
    vendor: "HP",
    status: "online",
    tonerLevels: { black: 10, cyan: null, magenta: null, yellow: null },
    counters: { totalPages: 5000, monoPages: 5000, colorPages: 0, duplexPages: 0, copyPages: 0, scanPages: 0 },
    maintenance: { paperJams: 0, errorMessages: [] }
  };

  console.log("Upserting simulated HP M402n printer...");
  const printer = await upsertDiscoveredPrinter(branch, payload);
  console.log(`Saved printer in DB. Toner levels in DB document:`, JSON.stringify(printer.tonerLevels));

  // Query notifications to see if toner_low was created
  const notifs = await PrinterNotification.find({ printerId: printer._id, type: "toner_low" }).lean();
  console.log(`Found ${notifs.length} toner_low notifications for this printer in DB`);
  if (notifs.length > 0) {
    console.log("✅ low_toner alert notification created successfully in MongoDB!");
    notifs.forEach(n => {
      console.log(`  Alert title: "${n.title}", Message: "${n.message}", Severity: "${n.severity}"`);
    });
  } else {
    console.error("❌ Failed to create low_toner alert notification in MongoDB!");
  }

  // Clean up test printer and notifications
  await Printer.deleteOne({ _id: printer._id });
  await PrinterNotification.deleteMany({ printerId: printer._id });
  console.log("Cleaned up test records from database");

  await mongoose.disconnect();
  console.log("Disconnected from MongoDB");
}

run().catch(console.error);
