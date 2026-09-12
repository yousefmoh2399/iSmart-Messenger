const mongoose = require("mongoose");

const printerBranchSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true, maxlength: 120 },
    code: {
      type: String,
      required: true,
      trim: true,
      uppercase: true,
      maxlength: 30,
      unique: true,
      index: true,
    },
    networkRange: { type: String, required: true, trim: true, maxlength: 80 },
    location: { type: String, default: "", trim: true, maxlength: 180 },
    status: {
      type: String,
      enum: ["active", "inactive"],
      default: "active",
      index: true,
    },
    lastSyncAt: { type: Date, default: null },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    deletedAt: { type: Date, default: null, index: true },
  },
  { timestamps: true },
);

module.exports = mongoose.model("PrinterBranch", printerBranchSchema);
