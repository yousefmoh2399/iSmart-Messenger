const mongoose = require("mongoose");

const syncLogSchema = new mongoose.Schema(
  {
    scope: { type: String, enum: ["printer", "branch", "full"], required: true, index: true },
    branchId: { type: mongoose.Schema.Types.ObjectId, ref: "PrinterBranch", default: null, index: true },
    printerId: { type: mongoose.Schema.Types.ObjectId, ref: "Printer", default: null, index: true },
    startedAt: { type: Date, required: true, default: Date.now },
    endedAt: { type: Date, default: null },
    status: { type: String, enum: ["running", "success", "failed", "partial"], default: "running", index: true },
    devicesSynced: { type: Number, default: 0 },
    errors: { type: [String], default: [] },
    triggeredBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
  },
  { timestamps: true, suppressReservedKeysWarning: true },
);

module.exports = mongoose.model("SyncLog", syncLogSchema);
