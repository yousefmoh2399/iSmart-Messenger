const mongoose = require("mongoose");

const systemErrorLogSchema = new mongoose.Schema(
  {
    actorId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
      index: true,
    },
    method: {
      type: String,
      trim: true,
      maxlength: 16,
    },
    path: {
      type: String,
      trim: true,
      maxlength: 500,
      required: true,
    },
    statusCode: {
      type: Number,
      required: true,
      min: 100,
      max: 599,
      index: true,
    },
    errorName: {
      type: String,
      trim: true,
      maxlength: 120,
      default: "Error",
    },
    message: {
      type: String,
      trim: true,
      maxlength: 5000,
      required: true,
    },
    stack: {
      type: String,
      trim: true,
      default: null,
    },
    meta: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
    },
  },
  {
    timestamps: { createdAt: true, updatedAt: false },
    versionKey: false,
  }
);

systemErrorLogSchema.index({ createdAt: -1 });

module.exports = mongoose.model("SystemErrorLog", systemErrorLogSchema);
