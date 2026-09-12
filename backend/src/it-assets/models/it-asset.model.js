const mongoose = require("mongoose");

const timelineSchema = new mongoose.Schema(
  {
    action: { type: String, required: true, trim: true },
    details: { type: String, default: "", trim: true },
    documentNumber: { type: String, default: null, trim: true },
    performedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    performedByName: { type: String, required: true, trim: true },
    createdAt: { type: Date, default: Date.now },
  },
  { _id: true },
);

const itAssetSchema = new mongoose.Schema(
  {
    assetCode: { type: String, required: true, unique: true, trim: true, uppercase: true, index: true },
    category: { type: String, required: true, trim: true, index: true },
    assetType: { type: String, required: true, trim: true },
    brand: { type: String, default: "", trim: true },
    model: { type: String, default: "", trim: true },
    serialNumber: { type: String, default: undefined, trim: true, uppercase: true },
    status: { type: String, required: true, default: "available", trim: true, index: true },
    condition: { type: String, required: true, default: "good", trim: true },
    branchName: { type: String, default: "", trim: true, index: true },
    location: { type: String, default: "المخزن الرئيسي", trim: true },
    assignedTo: { type: String, default: "", trim: true, index: true },
    purchaseDate: { type: Date, default: null },
    warrantyEndDate: { type: Date, default: null },
    vendor: { type: String, default: "", trim: true },
    invoiceNumber: { type: String, default: "", trim: true },
    notes: { type: String, default: "", trim: true },
    isArchived: { type: Boolean, default: false, index: true },
    timeline: { type: [timelineSchema], default: [] },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    updatedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
  },
  { timestamps: true },
);

itAssetSchema.index(
  { serialNumber: 1 },
  {
    unique: true,
    partialFilterExpression: {
      serialNumber: { $type: "string", $ne: "" },
    },
  },
);

module.exports = mongoose.model("ItAsset", itAssetSchema);
