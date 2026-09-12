const mongoose = require("mongoose");

const purchaseRequestItemSchema = new mongoose.Schema({
  itemType: {
    type: String,
    enum: ["Asset", "Spare Part", "Consumable", "Service", "Other"],
    required: true,
  },
  assetCategoryId: { type: mongoose.Schema.Types.ObjectId, ref: "AssetCategory", default: null },
  sparePartId: { type: mongoose.Schema.Types.ObjectId, ref: "ItSparePart", default: null },
  itemName: { type: String, required: true, trim: true },
  description: { type: String, default: "", trim: true },
  brand: { type: String, default: "", trim: true },
  model: { type: String, default: "", trim: true },
  requestedQuantity: { type: Number, required: true, min: 1 },
  approvedQuantity: { type: Number, default: null },
  receivedQuantity: { type: Number, default: 0, min: 0 },
  currentStock: { type: Number, default: null },
  minimumStock: { type: Number, default: null },
  reservedQuantity: { type: Number, default: null },
  availableQuantity: { type: Number, default: null },
  estimatedUnitPrice: { type: Number, default: 0, min: 0 },
  estimatedTotalPrice: { type: Number, default: 0, min: 0 },
  suggestedVendorId: { type: mongoose.Schema.Types.ObjectId, ref: "Vendor", default: null },
  reason: { type: String, default: "", trim: true },
  notes: { type: String, default: "", trim: true },
});

const signatureSchema = new mongoose.Schema({
  userId: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
  userName: { type: String, required: true, trim: true },
  role: { type: String, required: true, trim: true },
  action: { type: String, required: true, trim: true },
  ipAddress: { type: String, default: "" },
  userAgent: { type: String, default: "" },
  signedAt: { type: Date, default: Date.now },
});

const timelineSchema = new mongoose.Schema({
  action: { type: String, required: true, trim: true },
  details: { type: String, default: "", trim: true },
  performedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
  performedByName: { type: String, required: true, trim: true },
  createdAt: { type: Date, default: Date.now },
});

const purchaseRequestSchema = new mongoose.Schema(
  {
    purchaseRequestNo: { type: String, required: true, unique: true, index: true },
    requestType: {
      type: String,
      enum: [
        "Spare Parts",
        "New Assets",
        "Consumables",
        "Maintenance Requirement",
        "Replacement Requirement",
        "Stock Refill",
        "Branch Requirement",
        "Project Requirement",
        "Other"
      ],
      required: true,
    },
    sourceType: { type: String, default: null },
    sourceId: { type: mongoose.Schema.Types.ObjectId, default: null },
    requestedForType: {
      type: String,
      enum: ["Main IT Store", "Branch", "Employee", "Maintenance", "Project", "General Stock"],
      required: true,
    },
    requestedForBranchId: { type: mongoose.Schema.Types.ObjectId, ref: "PrinterBranch", default: null },
    requestedForLocationId: { type: mongoose.Schema.Types.ObjectId, default: null },
    requestedForEmployeeId: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    priority: {
      type: String,
      enum: ["Low", "Medium", "High", "Critical"],
      default: "Medium",
    },
    neededBefore: { type: Date, default: null },
    reason: { type: String, required: true, trim: true },
    notes: { type: String, default: "", trim: true },
    status: {
      type: String,
      enum: [
        "Draft",
        "Submitted",
        "Pending IT Manager Approval",
        "Pending Audit Review",
        "Pending Finance/Admin Approval",
        "Approved",
        "Sent To Purchasing",
        "Ordered",
        "Partially Received",
        "Fully Received",
        "Added To Store",
        "Closed",
        "Rejected",
        "Cancelled",
        "Returned For Edit",
      ],
      default: "Draft",
      index: true,
    },
    auditStatus: {
      type: String,
      enum: [
        "Not Required",
        "Pending Review",
        "Pending Acknowledgement",
        "Acknowledged",
        "Pending Approval",
        "Approved",
        "Rejected",
      ],
      default: "Pending Review",
    },
    auditReferenceNo: { type: String, default: null, trim: true },
    auditNotes: { type: String, default: "", trim: true },
    totalEstimatedAmount: { type: Number, default: 0, min: 0 },
    
    items: { type: [purchaseRequestItemSchema], required: true },
    signatures: { type: [signatureSchema], default: [] },
    timeline: { type: [timelineSchema], default: [] },
    attachments: { type: [mongoose.Schema.Types.ObjectId], ref: "ItAttachment", default: [] },

    requestedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    submittedAt: { type: Date, default: null },
    
    itManagerApprovedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    itManagerApprovedAt: { type: Date, default: null },
    
    auditReviewedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    auditReviewedAt: { type: Date, default: null },
    
    financeApprovedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    financeApprovedAt: { type: Date, default: null },
    
    sentToPurchasingBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    sentToPurchasingAt: { type: Date, default: null },
    
    orderedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    orderedAt: { type: Date, default: null },
    
    closedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    closedAt: { type: Date, default: null },
    
    rejectedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    rejectedAt: { type: Date, default: null },
    rejectionReason: { type: String, default: null, trim: true },
    
    cancelledBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    cancelledAt: { type: Date, default: null },
    cancellationReason: { type: String, default: null, trim: true },
  },
  { timestamps: true }
);

module.exports = mongoose.model("PurchaseRequest", purchaseRequestSchema);
