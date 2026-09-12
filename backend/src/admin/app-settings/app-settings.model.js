const mongoose = require("mongoose");

const serverTargetSchema = new mongoose.Schema(
  {
    title: {
      type: String,
      required: true,
      trim: true,
      maxlength: 120,
    },
    baseUrl: {
      type: String,
      required: true,
      trim: true,
      maxlength: 500,
    },
    ports: {
      type: [Number],
      default: [],
    },
  },
  {
    _id: false,
  },
);

const appSettingsSchema = new mongoose.Schema(
  {
    singletonKey: {
      type: String,
      required: true,
      unique: true,
      default: "default",
      index: true,
    },
    desktopBaseUrl: {
      type: String,
      default: null,
      trim: true,
    },
    mobileBaseUrl: {
      type: String,
      default: null,
      trim: true,
    },
    snipeitUrl: {
      type: String,
      default: null,
      trim: true,
    },
    serverTargets: {
      type: [serverTargetSchema],
      default: [],
    },
    showServersShortcut: {
      type: Boolean,
      default: true,
    },
    updatedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },
  },
  {
    timestamps: true,
  },
);

module.exports = mongoose.model("AppSettings", appSettingsSchema);
