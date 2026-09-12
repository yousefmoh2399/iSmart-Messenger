const mongoose = require("mongoose");

const counterResetEventSchema = new mongoose.Schema(
  {
    printerId: { type: mongoose.Schema.Types.ObjectId, ref: "Printer", required: true, index: true },
    branchId: { type: mongoose.Schema.Types.ObjectId, ref: "PrinterBranch", required: true, index: true },
    counterName: { type: String, required: true },
    previousValue: { type: Number, required: true },
    currentValue: { type: Number, required: true },
    lifetimeBefore: { type: Number, required: true },
    lifetimeAfter: { type: Number, required: true },
    detectedAt: { type: Date, default: Date.now, index: true },
  },
  { timestamps: true },
);

module.exports = mongoose.model("CounterResetEvent", counterResetEventSchema);
