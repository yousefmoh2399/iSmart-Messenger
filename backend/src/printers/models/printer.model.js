const mongoose = require("mongoose");

const countersSchema = new mongoose.Schema(
  {
    totalPages: { type: Number, default: 0 },
    monoPages: { type: Number, default: 0 },
    colorPages: { type: Number, default: 0 },
    duplexPages: { type: Number, default: 0 },
    copyPages: { type: Number, default: 0 },
    scanPages: { type: Number, default: 0 },
  },
  { _id: false, suppressReservedKeysWarning: true },
);

const tonerSchema = new mongoose.Schema(
  {
    black: { type: Number, default: null },
    cyan: { type: Number, default: null },
    magenta: { type: Number, default: null },
    yellow: { type: Number, default: null },
  },
  { _id: false },
);

const maintenanceSchema = new mongoose.Schema(
  {
    paperJams: { type: Number, default: 0 },
    errorMessages: { type: [String], default: [] },
    warnings: { type: [String], default: [] },
  },
  { _id: false },
);

const printerSchema = new mongoose.Schema(
  {
    branchId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "PrinterBranch",
      required: true,
      index: true,
    },
    ipAddress: { type: String, required: true, trim: true, index: true },
    hostname: { type: String, default: "", trim: true },
    model: { type: String, default: "", trim: true },
    serialNumber: { type: String, default: "", trim: true },
    printerName: { type: String, default: "", trim: true },
    macAddress: { type: String, default: "", trim: true },
    deviceFingerprint: { type: String, default: "", trim: true, index: true },
    identityConfidence: {
      type: String,
      enum: ["strong", "medium", "weak"],
      default: "weak",
      index: true,
    },
    vendor: { type: String, default: "SNMP", trim: true },
    status: {
      type: String,
      enum: ["online", "offline", "warning", "error"],
      default: "offline",
      index: true,
    },
    lastSyncAt: { type: Date, default: null },
    counters: { type: countersSchema, default: () => ({}) },
    previousCounters: { type: countersSchema, default: () => ({}) },
    lifetimeCounters: { type: countersSchema, default: () => ({}) },
    tonerLevels: { type: tonerSchema, default: () => ({}) },
    maintenance: { type: maintenanceSchema, default: () => ({}) },
    extendedDetails: { type: Object, default: {} },
    replacedAt: { type: Date, default: null, index: true },
    replacedByPrinterId: { type: mongoose.Schema.Types.ObjectId, ref: "Printer", default: null },
    replacementReason: { type: String, default: "" },
    lastAnomalyAt: { type: Date, default: null },
    anomalyFlags: { type: [String], default: [] },
    deletedAt: { type: Date, default: null, index: true },
  },
  { timestamps: true },
);

printerSchema.index(
  { serialNumber: 1 },
  {
    unique: true,
    partialFilterExpression: { serialNumber: { $type: "string", $gt: "" } },
  },
);
printerSchema.index(
  { branchId: 1, ipAddress: 1 },
  {
    unique: true,
    partialFilterExpression: { deletedAt: null },
  },
);

module.exports = mongoose.model("Printer", printerSchema);
