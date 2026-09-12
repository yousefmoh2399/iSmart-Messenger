const mongoose = require("mongoose");

const releaseSchema = new mongoose.Schema(
  {
    version: {
      type: String,
      required: true,
      trim: true,
      maxlength: 120,
    },
    buildNumber: {
      type: String,
      default: null,
      trim: true,
      maxlength: 80,
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
    notes: {
      type: String,
      default: "",
      trim: true,
      maxlength: 6000,
    },
    mandatory: {
      type: Boolean,
      default: false,
    },
    isEnabled: {
      type: Boolean,
      default: true,
      index: true,
    },
    installerKind: {
      type: String,
      enum: ["msi", "exe", "zip", "apk", "unknown"],
      default: "unknown",
    },
    packageType: {
      type: String,
      enum: ["full", "delta"],
      default: "full",
    },
    packageLayout: {
      type: String,
      enum: ["bundle_zip", "installer", "apk"],
      default: "bundle_zip",
    },
    entryExecutable: {
      type: String,
      default: "iSmartMessenger.exe",
      trim: true,
      maxlength: 260,
    },
    minSupportedVersion: {
      type: String,
      default: null,
      trim: true,
      maxlength: 120,
    },
    targetArchitecture: {
      type: String,
      default: "x64",
      trim: true,
      lowercase: true,
      maxlength: 40,
    },
    minWindowsBuild: {
      type: String,
      default: null,
      trim: true,
      maxlength: 80,
    },
    rolloutPercentage: {
      type: Number,
      default: 100,
      min: 1,
      max: 100,
    },
    silentInstallArgs: {
      type: String,
      default: "",
      trim: true,
      maxlength: 1200,
    },
    checksumSha256: {
      type: String,
      default: null,
      trim: true,
      lowercase: true,
      maxlength: 128,
    },
    externalDownloadUrl: {
      type: String,
      default: null,
      trim: true,
      maxlength: 2000,
    },
    fileName: {
      type: String,
      default: null,
      trim: true,
      maxlength: 260,
    },
    filePath: {
      type: String,
      default: null,
      trim: true,
      maxlength: 2000,
    },
    fileSize: {
      type: Number,
      default: 0,
      min: 0,
    },
    mimeType: {
      type: String,
      default: null,
      trim: true,
      maxlength: 200,
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    publishedAt: {
      type: Date,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

releaseSchema.index({ version: 1, channel: 1, platform: 1 }, { unique: true });

module.exports = mongoose.model("UpdateRelease", releaseSchema);

