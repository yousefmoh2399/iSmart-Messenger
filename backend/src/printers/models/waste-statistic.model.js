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

module.exports = mongoose.model("WasteStatistic", wasteStatisticSchema);
