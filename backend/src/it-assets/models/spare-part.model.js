const mongoose = require("mongoose");

const sparePartSchema = new mongoose.Schema(
  {
    partCode: { type: String, required: true, unique: true, trim: true, uppercase: true, index: true },
    name: { type: String, required: true, trim: true, index: true },
    category: { type: String, required: true, trim: true },
    brand: { type: String, default: "", trim: true },
    model: { type: String, default: "", trim: true },
    unit: { type: String, default: "قطعة", trim: true },
    quantityAvailable: { type: Number, default: 0, min: 0 },
    quantityReserved: { type: Number, default: 0, min: 0 },
    damagedQuantity: { type: Number, default: 0, min: 0 },
    minimumQuantity: { type: Number, default: 0, min: 0 },
    criticalQuantity: { type: Number, default: 0, min: 0 },
    preferredQuantity: { type: Number, default: 0, min: 0 },
    location: { type: String, default: "المخزن الرئيسي", trim: true },
    hasSerialNumbers: { type: Boolean, default: false },
    notes: { type: String, default: "", trim: true },
    isArchived: { type: Boolean, default: false, index: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    updatedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
  },
  { timestamps: true },
);

module.exports = mongoose.model("ItSparePart", sparePartSchema);
