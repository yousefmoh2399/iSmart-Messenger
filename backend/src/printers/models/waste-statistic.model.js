const mongoose = require("mongoose");

const wasteStatisticSchema = new mongoose.Schema(
  {
    printerId: { type: mongoose.Schema.Types.ObjectId, ref: "Printer", required: true, index: true },
    branchId: { type: mongoose.Schema.Types.ObjectId, ref: "PrinterBranch", required: true, index: true },
    calculatedAt: { type: Date, default: Date.now, index: true },
    paperJams: { type: Number, default: 0 },
    failedJobs: { type: Number, default: 0 },
    interruptedJobs: { type: Number, default: 0 },
    printerErrors: { type: Number, default: 0 },
    estimatedWastePages: { type: Number, default: 0 },
    config: { type: Object, default: {} },
  },
  { timestamps: true },
);

// Compound indexes for efficient report queries:
//   exportCustomReport queries { branchId, calculatedAt: {$gte, $lt} }
//   per-printer waste queries { printerId, calculatedAt: {$gte, $lt} }
wasteStatisticSchema.index({ branchId: 1, calculatedAt: 1 });
wasteStatisticSchema.index({ printerId: 1, calculatedAt: 1 });

// E4: TTL index — automatically purge waste records older than 2 years (730 days).
// Prevents unbounded collection growth with no data-retention policy.
wasteStatisticSchema.index({ calculatedAt: 1 }, { expireAfterSeconds: 730 * 24 * 60 * 60 });

module.exports = mongoose.model("WasteStatistic", wasteStatisticSchema);
