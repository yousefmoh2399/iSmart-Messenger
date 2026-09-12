const mongoose = require("mongoose");

const itAttachmentSchema = new mongoose.Schema(
  {
    entityType: { type: String, required: true, trim: true, index: true },
    entityId: { type: mongoose.Schema.Types.ObjectId, required: true, index: true },
    originalName: { type: String, required: true, trim: true },
    storedPath: { type: String, required: true, trim: true },
    mimeType: { type: String, required: true, trim: true },
    size: { type: Number, required: true, min: 0 },
    uploadedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    uploadedByName: { type: String, required: true, trim: true },
  },
  { timestamps: { createdAt: true, updatedAt: false } },
);

module.exports = mongoose.model("ItAttachment", itAttachmentSchema);
