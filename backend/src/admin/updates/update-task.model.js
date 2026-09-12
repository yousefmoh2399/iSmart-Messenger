const mongoose = require("mongoose");

const logEntrySchema = new mongoose.Schema(
  {
    status: {
      type: String,
      required: true,
      trim: true,
      maxlength: 40,
    },
    message: {
      type: String,
      default: null,
      trim: true,
      maxlength: 1000,
    },
    progress: {
      type: Number,
      default: null,
      min: 0,
      max: 100,
    },
    at: {
      type: Date,
      default: Date.now,
    },
  },
  { _id: false }
);

const updateTaskSchema = new mongoose.Schema(
  {
    jobId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "UpdateJob",
      required: true,
      index: true,
    },
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
    deviceId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "UpdateDevice",
      required: true,
      index: true,
    },
    deviceUid: {
      type: String,
      required: true,
      trim: true,
      maxlength: 160,
      index: true,
    },
    deviceName: {
      type: String,
      default: null,
      trim: true,
      maxlength: 160,
    },
    branchCode: {
      type: String,
      default: "main",
      trim: true,
      lowercase: true,
      maxlength: 80,
      index: true,
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
    status: {
      type: String,
      enum: [
        "pending",
        "acknowledged",
        "downloading",
        "installing",
        "completed",
        "failed",
        "cancelled",
      ],
      default: "pending",
      index: true,
    },
    progress: {
      type: Number,
      default: 0,
      min: 0,
      max: 100,
    },
    message: {
      type: String,
      default: null,
      trim: true,
      maxlength: 1000,
    },
    attempts: {
      type: Number,
      default: 0,
      min: 0,
    },
    lastError: {
      type: String,
      default: null,
      trim: true,
      maxlength: 1500,
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    requestedAt: {
      type: Date,
      default: Date.now,
    },
    acknowledgedAt: {
      type: Date,
      default: null,
    },
    completedAt: {
      type: Date,
      default: null,
    },
    logs: {
      type: [logEntrySchema],
      default: [],
    },
  },
  {
    timestamps: true,
  }
);

updateTaskSchema.index({ deviceId: 1, platform: 1, status: 1, createdAt: 1 });
updateTaskSchema.index({ jobId: 1, status: 1 });

module.exports = mongoose.model("UpdateTask", updateTaskSchema);
