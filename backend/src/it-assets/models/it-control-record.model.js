const mongoose = require("mongoose");

const signatureSchema = new mongoose.Schema(
  {
    role: { type: String, required: true, trim: true },
    userId: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    userName: { type: String, required: true, trim: true },
    ipAddress: { type: String, default: "", trim: true },
    signedAt: { type: Date, default: Date.now },
  },
  { _id: true },
);

const itControlRecordSchema = new mongoose.Schema(
  {
    recordType: {
      type: String,
      required: true,
      enum: [
        "inventory_session",
        "discrepancy",
        "correction",
        "period_closure",
        "vendor",
        "purchase_request",
        "damaged_inspection",
        "scrap_request",
        "workflow_rule",
        "notification",
      ],
      index: true,
    },
    recordNumber: { type: String, required: true, unique: true, trim: true, index: true },
    title: { type: String, required: true, trim: true },
    status: { type: String, required: true, default: "open", trim: true, index: true },
    assetId: { type: mongoose.Schema.Types.ObjectId, ref: "ItAsset", default: null, index: true },
    sparePartId: { type: mongoose.Schema.Types.ObjectId, ref: "ItSparePart", default: null, index: true },
    operationId: { type: mongoose.Schema.Types.ObjectId, ref: "ItOperation", default: null, index: true },
    parentRecordId: { type: mongoose.Schema.Types.ObjectId, ref: "ItControlRecord", default: null, index: true },
    branchName: { type: String, default: "", trim: true, index: true },
    location: { type: String, default: "", trim: true },
    assignedTo: { type: String, default: "", trim: true },
    reason: { type: String, default: "", trim: true },
    notes: { type: String, default: "", trim: true },
    data: { type: mongoose.Schema.Types.Mixed, default: {} },
    signatures: { type: [signatureSchema], default: [] },
    locked: { type: Boolean, default: false, index: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    createdByName: { type: String, required: true, trim: true },
    approvedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    approvedAt: { type: Date, default: null },
    closedAt: { type: Date, default: null },
  },
  { timestamps: true },
);

module.exports = mongoose.model("ItControlRecord", itControlRecordSchema);
