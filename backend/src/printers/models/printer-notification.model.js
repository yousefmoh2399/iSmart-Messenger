const mongoose = require("mongoose");

const printerNotificationSchema = new mongoose.Schema(
  {
    type: {
      type: String,
      enum: ["offline", "toner_low", "excessive_waste", "sync_failure", "counter_reset", "printer_replaced", "counter_anomaly"],
      required: true,
      index: true,
    },
    severity: { type: String, enum: ["info", "warning", "critical"], default: "warning" },
    title: { type: String, required: true, trim: true },
    message: { type: String, required: true, trim: true },
    branchId: { type: mongoose.Schema.Types.ObjectId, ref: "PrinterBranch", default: null, index: true },
    printerId: { type: mongoose.Schema.Types.ObjectId, ref: "Printer", default: null, index: true },
    readAt: { type: Date, default: null },
  },
  { timestamps: true },
);

module.exports = mongoose.model("PrinterNotification", printerNotificationSchema);
