const mongoose = require("mongoose");

const dailySnapshotSchema = new mongoose.Schema(
  {
    printerId: { type: mongoose.Schema.Types.ObjectId, ref: "Printer", required: true, index: true },
    branchId: { type: mongoose.Schema.Types.ObjectId, ref: "PrinterBranch", required: true, index: true },
    snapshotAt: { type: Date, required: true, default: Date.now, index: true },
    counters: { type: Object, default: {} },
    lifetimeCounters: { type: Object, default: {} },
    tonerLevels: { type: Object, default: {} },
    maintenance: { type: Object, default: {} },
    extendedDetails: { type: Object, default: {} },
    status: { type: String, default: "offline" },
  },
  { timestamps: true },
);

// Compound indexes for efficient consumption queries:
//   calculateMonthlyConsumption queries { printerId, snapshotAt: {$gte, $lt} }
//   baseline query: { printerId, snapshotAt: {$lt} } sorted by snapshotAt desc
dailySnapshotSchema.index({ printerId: 1, snapshotAt: 1 });
dailySnapshotSchema.index({ branchId: 1, snapshotAt: 1 });

// E3: TTL index — automatically purge snapshots older than 2 years (730 days).
// With 5 syncs/day x 50 printers = ~7,500 new records/day; without TTL the
// collection grows unboundedly. MongoDB runs the TTL reaper every ~60 seconds.
dailySnapshotSchema.index({ snapshotAt: 1 }, { expireAfterSeconds: 730 * 24 * 60 * 60 });

module.exports = mongoose.model("DailySnapshot", dailySnapshotSchema);
