const mongoose = require("mongoose");

const updateJobSchema = new mongoose.Schema(
  {
    releaseId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "UpdateRelease",
      required: true,
      index: true,
    },
    releaseVersion: {
      type: String,
      required: true,
      trim: true,
      maxlength: 120,
    },
    platform: {
      type: String,
      enum: ["desktop_windows", "mobile_android"],
      default: "desktop_windows",
      trim: true,
      lowercase: true,
      maxlength: 40,
      index: true,
    },
    targetType: {
      type: String,
      enum: ["all", "branch", "devices"],
      required: true,
      index: true,
    },
    targetBranches: {
      type: [String],
      default: [],
    },
    targetDeviceIds: {
      type: [{ type: mongoose.Schema.Types.ObjectId, ref: "UpdateDevice" }],
      default: [],
    },
    status: {
      type: String,
      enum: [
        "queued",
        "running",
        "completed",
        "partial_failed",
        "failed",
        "cancelled",
      ],
      default: "queued",
      index: true,
    },
    stats: {
      total: { type: Number, default: 0 },
      pending: { type: Number, default: 0 },
      acknowledged: { type: Number, default: 0 },
      downloading: { type: Number, default: 0 },
      installing: { type: Number, default: 0 },
      completed: { type: Number, default: 0 },
      failed: { type: Number, default: 0 },
      cancelled: { type: Number, default: 0 },
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    scheduledAt: {
      type: Date,
      default: Date.now,
    },
    startedAt: {
      type: Date,
      default: null,
    },
    finishedAt: {
      type: Date,
      default: null,
    },
    note: {
      type: String,
      default: "",
      trim: true,
      maxlength: 2000,
    },
  },
  {
    timestamps: true,
  }
);

updateJobSchema.index({ createdAt: -1 });

module.exports = mongoose.model("UpdateJob", updateJobSchema);
