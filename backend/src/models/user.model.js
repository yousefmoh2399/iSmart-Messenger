const mongoose = require("mongoose");

const userSchema = new mongoose.Schema(
  {
    username: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      lowercase: true,
      minlength: 3,
      maxlength: 50,
    },
    passwordHash: {
      type: String,
      required: true,
    },
    fullName: {
      type: String,
      required: true,
      trim: true,
      maxlength: 120,
    },
    role: {
      type: String,
      required: true,
      default: "user",
      enum: ["user", "manager", "admin"],
    },
    permissionOverrides: {
      type: Map,
      of: Boolean,
      default: {},
    },
    departmentId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Department",
      default: null,
      index: true,
    },
    departmentIds: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: "Department",
      },
    ],
    branchId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Branch",
      default: null,
      index: true,
    },
    branchCode: {
      type: String,
      default: "main",
      trim: true,
      uppercase: true,
      maxlength: 30,
      index: true,
    },
    isOnline: {
      type: Boolean,
      default: false,
      index: true,
    },
    presenceStatus: {
      type: String,
      enum: ["online", "idle", "meeting", "lunch", "offline"],
      default: "offline",
      index: true,
    },
    isActive: {
      type: Boolean,
      default: true,
      index: true,
    },
    avatarUrl: {
      type: String,
      default: null,
      trim: true,
    },
    lastSeen: {
      type: Date,
      default: null,
    },
    lastActiveAt: {
      type: Date,
      default: null,
    },
    /**
     * Legacy single-session refresh nonce (kept for migration).
     * New installs should use refreshSessions below.
     */
    refreshTokenNonce: {
      type: String,
      default: null,
      select: false,
    },
    /**
     * Multi-device refresh sessions. Each deviceUid keeps its own rotating nonce.
     * This prevents one device login from invalidating another device session.
     */
    refreshSessions: {
      type: [
        new mongoose.Schema(
          {
            deviceUid: { type: String, required: true },
            nonce: { type: String, required: true },
            createdAt: { type: Date, default: Date.now },
            lastUsedAt: { type: Date, default: Date.now },
          },
          { _id: false },
        ),
      ],
      default: [],
      select: false,
    },
    tokenVersion: {
      type: Number,
      default: 1,
      index: true,
    },
    chatPreferences: {
      type: new mongoose.Schema(
        {
          themeId: { type: String, default: "system" },
          wallpaperId: { type: String, default: "default" },
          customTheme: {
            type: new mongoose.Schema(
              {
                accentColorHex: { type: String, default: "#3390EC" },
                outgoingBubbleColorHexes: {
                  type: [String],
                  default: () => ["#5BA9FF", "#2F8CFF"],
                },
                incomingBubbleColorHex: {
                  type: String,
                  default: "#182533",
                },
                wallpaperColorHexes: {
                  type: [String],
                  default: () => ["#0E1621", "#111B26", "#17212B"],
                },
              },
              { _id: false },
            ),
            default: () => ({
              accentColorHex: "#3390EC",
              outgoingBubbleColorHexes: ["#5BA9FF", "#2F8CFF"],
              incomingBubbleColorHex: "#182533",
              wallpaperColorHexes: ["#0E1621", "#111B26", "#17212B"],
            }),
          },
        },
        { _id: false },
      ),
      default: () => ({
        themeId: "system",
        wallpaperId: "default",
        customTheme: {
          accentColorHex: "#3390EC",
          outgoingBubbleColorHexes: ["#5BA9FF", "#2F8CFF"],
          incomingBubbleColorHex: "#182533",
          wallpaperColorHexes: ["#0E1621", "#111B26", "#17212B"],
        },
      }),
    },
  },
  {
    timestamps: true,
  },
);

module.exports = mongoose.model("User", userSchema);
