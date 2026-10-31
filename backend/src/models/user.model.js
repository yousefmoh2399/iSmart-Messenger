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
    jobTitle: {
      type: String,
      default: "",
      trim: true,
      maxlength: 150,
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
            previousNonce: { type: String, default: null },
            previousNonceExpiresAt: { type: Date, default: null },
            deviceName: { type: String, default: null },
            platform: { type: String, default: null },
            appVersion: { type: String, default: null },
            ipAddress: { type: String, default: null },
            userAgent: { type: String, default: null },
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
          doodles: { type: Boolean, default: true },
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
    maxAttachmentSizeMB: {
      type: Number,
      default: 20,
    },
    quickReplies: {
      type: [
        new mongoose.Schema(
          {
            id: { type: String, required: true },
            shortcut: { type: String, required: true },
            title: { type: String, required: true },
            content: { type: String, required: true },
            category: { type: String, default: "عام" },
          },
          { _id: false },
        ),
      ],
      default: [],
    },
    messageReminders: {
      type: [
        new mongoose.Schema(
          {
            id: { type: String, required: true },
            userId: { type: String, default: "" },
            conversationId: { type: String, required: true },
            conversationTitle: { type: String, default: "" },
            messageId: { type: String, required: true },
            senderName: { type: String, default: "" },
            messagePreview: { type: String, default: "" },
            remindAt: { type: Date, required: true, index: true },
            createdAt: { type: Date, default: Date.now },
            note: { type: String, default: "" },
            isNotified: { type: Boolean, default: false },
          },
          { _id: false },
        ),
      ],
      default: [],
    },
    workspaceDocs: {
      type: [mongoose.Schema.Types.Mixed],
      default: [],
    },
  },
  {
    timestamps: true,
  },
);

module.exports = mongoose.model("User", userSchema);
