const mongoose = require("mongoose");

const pushDeviceSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    token: {
      type: String,
      required: true,
      trim: true,
      unique: true,
      index: true,
    },
    platform: {
      type: String,
      enum: ["android", "ios", "unknown"],
      default: "unknown",
      index: true,
    },
    deviceId: {
      type: String,
      default: null,
      trim: true,
      index: true,
    },
    deviceName: {
      type: String,
      default: null,
      trim: true,
    },
    appVersion: {
      type: String,
      default: null,
      trim: true,
    },
    notificationToneId: {
      type: String,
      enum: ["default", "chime", "alert", "silent"],
      default: "default",
      trim: true,
      index: true,
    },
    isActive: {
      type: Boolean,
      default: true,
      index: true,
    },
    lastSeenAt: {
      type: Date,
      default: Date.now,
    },
  },
  {
    timestamps: true,
  }
);

pushDeviceSchema.index({ userId: 1, deviceId: 1 });

module.exports = mongoose.model("PushDevice", pushDeviceSchema);
