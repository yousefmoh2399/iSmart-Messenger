const mongoose = require("mongoose");

const documentSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    fileName: {
      type: String,
      required: true,
      trim: true,
      maxlength: 255,
    },
    originalName: {
      type: String,
      required: true,
      trim: true,
      maxlength: 255,
    },
    storedName: {
      type: String,
      required: true,
      trim: true,
    },
    filePath: {
      type: String,
      required: true,
    },
    mimeType: {
      type: String,
      required: true,
      default: "application/pdf",
    },
    pageCount: {
      type: Number,
      required: true,
      min: 1,
    },
    fileSize: {
      type: Number,
      required: true,
      min: 1,
    },
    localSyncStatus: {
      type: String,
      enum: ["none", "pending", "synced"],
      default: "none",
      index: true,
    },
    localSyncedAt: {
      type: Date,
      default: null,
    },
    localSyncRequestedAt: {
      type: Date,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model("Document", documentSchema);
