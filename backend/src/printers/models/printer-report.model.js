const mongoose = require("mongoose");

const printerReportSchema = new mongoose.Schema(
  {
    type: { type: String, enum: ["branch", "global", "printer"], required: true, index: true },
    format: { type: String, enum: ["pdf", "xlsx"], required: true },
    branchId: { type: mongoose.Schema.Types.ObjectId, ref: "PrinterBranch", default: null },
    generatedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    generatedAt: { type: Date, default: Date.now },
    fileName: { type: String, required: true },
  },
  { timestamps: true },
);

module.exports = mongoose.model("PrinterReport", printerReportSchema);
