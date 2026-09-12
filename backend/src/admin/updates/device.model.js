const mongoose = require("mongoose");

const updateStateSchema = new mongoose.Schema(
  {
    status: {
      type: String,
      enum: [
        "idle",
        "pending",
        "acknowledged",
        "downloading",
        "installing",
        "completed",
        "failed",
        "cancelled",
      ],
      default: "idle",
    },
    currentTaskId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "UpdateTask",
      default: null,
    },
    targetVersion: {
      type: String,
      default: null,
      trim: true,
      maxlength: 120,
    },
    progress: {
      type: Number,
      default: 0,
      min: 0,
      max: 100,
    },
    lastError: {
      type: String,
      default: null,
      trim: true,
      maxlength: 1000,
    },
    updatedAt: {
      type: Date,
      default: null,
    },
  },
  { _id: false }
);

const updateDeviceSchema = new mongoose.Schema(
  {
    deviceUid: {
      type: String,
      required: true,
      unique: true,
      index: true,
      trim: true,
      maxlength: 160,
    },
    deviceName: {
      type: String,
      default: null,
      trim: true,
      maxlength: 160,
    },
    hostName: {
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
    channel: {
      type: String,
      default: "stable",
      trim: true,
      lowercase: true,
      maxlength: 40,
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
    appVersion: {
      type: String,
      default: null,
      trim: true,
      maxlength: 80,
      index: true,
    },
    osName: {
      type: String,
      default: null,
      trim: true,
      maxlength: 80,
    },
    osVersion: {
      type: String,
      default: null,
      trim: true,
      maxlength: 120,
    },
    architecture: {
      type: String,
      default: null,
      trim: true,
      maxlength: 80,
    },
    localIp: {
      type: String,
      default: null,
      trim: true,
      maxlength: 120,
    },
    connectionStatus: {
      type: String,
      enum: ["online", "idle", "meeting", "lunch", "offline"],
      default: "online",
      index: true,
    },
    lastKnownUserId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
      index: true,
    },
    lastKnownUsername: {
      type: String,
      default: null,
      trim: true,
      maxlength: 80,
    },
    lastKnownFullName: {
      type: String,
      default: null,
      trim: true,
      maxlength: 160,
    },
    capabilities: {
      autoUpdate: {
        type: Boolean,
        default: true,
      },
      silentInstall: {
        type: Boolean,
        default: true,
      },
    },
    isActive: {
      type: Boolean,
      default: true,
      index: true,
    },
    lastHeartbeatAt: {
      type: Date,
      default: null,
      index: true,
    },
    lastSeenAt: {
      type: Date,
      default: null,
      index: true,
    },
    updateState: {
      type: updateStateSchema,
      default: () => ({}),
    },
  },
  {
    timestamps: true,
  }
);

updateDeviceSchema.index({ branchCode: 1, platform: 1, appVersion: 1 });
updateDeviceSchema.index({ isActive: 1, lastHeartbeatAt: -1 });

module.exports = mongoose.model("UpdateDevice", updateDeviceSchema);
