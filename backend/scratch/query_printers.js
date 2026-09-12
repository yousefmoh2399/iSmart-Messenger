const mongoose = require("mongoose");
const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "../.env") });

require("../src/printers/models/daily-snapshot.model");

async function run() {
  const uri = process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/workplace_documents";
  await mongoose.connect(uri);

  const DailySnapshot = mongoose.model("DailySnapshot");

  // Find snapshots in June (month 6) for missing printers (we know their IDs start with 6a27)
  const juneSnapshotsForMissing = await DailySnapshot.find({
    printerId: { $regex: /^6a27/ },
    snapshotAt: {
      $gte: new Date(2026, 5, 1),
      $lt: new Date(2026, 6, 1)
    }
  }).limit(5).lean();

  console.log(`June snapshots for missing printers (count):`, juneSnapshotsForMissing.length);
  for (const s of juneSnapshotsForMissing) {
    console.log(`- Snapshot ID: ${s._id}, Printer ID: ${s.printerId}, Date: ${s.snapshotAt.toISOString()}, totalPages: ${s.lifetimeCounters?.totalPages || s.counters?.totalPages}`);
  }

  await mongoose.disconnect();
}

run().catch(console.error);
