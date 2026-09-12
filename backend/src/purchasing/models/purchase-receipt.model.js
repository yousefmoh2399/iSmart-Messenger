const mongoose = require("mongoose");

const purchaseReceiptItemSchema = new mongoose.Schema({
  purchaseRequestItemId: { type: mongoose.Schema.Types.ObjectId, required: true },
  receivedQuantity: { type: Number, required: true, min: 1 },
  acceptedQuantity: { type: Number, required: true, min: 0 },
  rejectedQuantity: { type: Number, default: 0, min: 0 },
  serialNumbers: { type: [String], default: [] },
  notes: { type: String, default: "", trim: true },
});

const purchaseReceiptSchema = new mongoose.Schema(
  {
    purchaseRequestId: { type: mongoose.Schema.Types.ObjectId, ref: "PurchaseRequest", required: true },
    receiptNo: { type: String, required: true, unique: true, index: true },
    invoiceNo: { type: String, default: null, trim: true },
    vendorId: { type: mongoose.Schema.Types.ObjectId, ref: "Vendor", default: null },
    receivedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    receivedAt: { type: Date, default: Date.now },
    storeLocationId: { type: mongoose.Schema.Types.ObjectId, default: null },
    notes: { type: String, default: "", trim: true },
    attachmentId: { type: mongoose.Schema.Types.ObjectId, ref: "ItAttachment", default: null },
    items: { type: [purchaseReceiptItemSchema], required: true },
  },
  { timestamps: true }
);

module.exports = mongoose.model("PurchaseReceipt", purchaseReceiptSchema);
