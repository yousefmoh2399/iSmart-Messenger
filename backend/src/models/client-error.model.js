const mongoose = require("mongoose");

const clientErrorSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
      index: true,
    },
    sessionId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "DeviceSession",
      default: null,
    },
    clientType: {
      type: String,
      default: "unknown",
      index: true,
    },
    source: {
      type: String,
      default: "app",
      index: true,
    },
    errorMessage: {
      type: String,
      required: true,
    },
    errorContext: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
    },
    stackTrace: {
      type: String,
      default: null,
    },
    resolved: {
      type: Boolean,
      default: false,
      index: true,
    },
    createdAt: {
      type: Date,
      default: Date.now,
      index: true,
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model("ClientError", clientErrorSchema);
