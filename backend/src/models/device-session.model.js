const mongoose = require("mongoose");

const deviceSessionSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    socketId: {
      type: String,
      required: false,
      index: true,
    },
    ipAddress: {
      type: String,
      default: null,
    },
    clientType: {
      type: String,
      default: "unknown",
      index: true,
    },
    deviceInfo: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
    },
    isOnline: {
      type: Boolean,
      default: true,
      index: true,
    },
    lastSeenAt: {
      type: Date,
      default: Date.now,
    },
    startedAt: {
      type: Date,
      default: Date.now,
      index: true,
    },
  },
  {
    timestamps: true,
  }
);

deviceSessionSchema.index({ userId: 1, ipAddress: 1, clientType: 1 });
deviceSessionSchema.index({ userId: 1, "deviceInfo.hostname": 1 });
deviceSessionSchema.index({ isOnline: 1, lastSeenAt: -1 });

module.exports = mongoose.model("DeviceSession", deviceSessionSchema);
