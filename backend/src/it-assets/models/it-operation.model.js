const mongoose = require("mongoose");

const itOperationSchema = new mongoose.Schema(
  {
    documentNumber: { type: String, required: true, unique: true, trim: true, index: true },
    operationType: {
      type: String,
      required: true,
      enum: [
        "movement", "maintenance", "transfer", "replacement", "damaged", "inventory",
        "custody", "employee_clearance", "branch_handover", "temporary_assignment", "scrap",
        "purchase_received_as_asset", "purchase_received_to_stock", "purchase_return"
      ],
      index: true,
    },
    title: { type: String, required: true, trim: true },
    assetId: { type: mongoose.Schema.Types.ObjectId, ref: "ItAsset", default: null, index: true },
    sparePartId: { type: mongoose.Schema.Types.ObjectId, ref: "ItSparePart", default: null, index: true },
    quantity: { type: Number, default: 0, min: 0 },
    fromLocation: { type: String, default: "", trim: true },
    toLocation: { type: String, default: "", trim: true },
    assignedTo: { type: String, default: "", trim: true },
    status: {
      type: String,
      required: true,
      enum: ["draft", "pending_audit", "approved", "in_progress", "completed", "rejected", "cancelled"],
      default: "pending_audit",
      index: true,
    },
    details: { type: String, default: "", trim: true },
    rootCause: { type: String, default: "", trim: true, index: true },
    priority: { type: String, default: "medium", trim: true },
    dueAt: { type: Date, default: null, index: true },
    expectedReturnDate: { type: Date, default: null, index: true },
    cost: { type: Number, default: 0, min: 0 },
    metadata: { type: mongoose.Schema.Types.Mixed, default: {} },
    signedAt: { type: Date, default: null },
    signedByName: { type: String, default: "", trim: true },
    solution: { type: String, default: "", trim: true },
    auditNote: { type: String, default: "", trim: true },
    auditReference: { type: String, default: "", trim: true },
    acknowledgedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    acknowledgedAt: { type: Date, default: null },
    completedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    completedAt: { type: Date, default: null },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    createdByName: { type: String, required: true, trim: true },
  },
  { timestamps: true },
);

module.exports = mongoose.model("ItOperation", itOperationSchema);
