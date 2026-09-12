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

module.exports = mongoose.model("DailySnapshot", dailySnapshotSchema);
