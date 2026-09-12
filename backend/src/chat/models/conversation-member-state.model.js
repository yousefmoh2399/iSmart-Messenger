const mongoose = require("mongoose");

const conversationMemberStateSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    conversationId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Conversation",
      required: true,
      index: true,
    },
    unreadCount: {
      type: Number,
      default: 0,
      min: 0,
    },
    lastReadMessageId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Message",
      default: null,
    },
    lastReadAt: {
      type: Date,
      default: null,
    },
    isMuted: {
      type: Boolean,
      default: false,
    },
    isArchived: {
      type: Boolean,
      default: false,
    },
    isPinned: {
      type: Boolean,
      default: false,
    },
    isFavorite: {
      type: Boolean,
      default: false,
    },
    clearHistoryAt: {
      type: Date,
      default: null,
    },
    joinedAt: {
      type: Date,
      default: Date.now,
    },
  },
  {
    timestamps: true,
  }
);

conversationMemberStateSchema.index(
  { userId: 1, conversationId: 1 },
  { unique: true }
);

module.exports = mongoose.model(
  "ConversationMemberState",
  conversationMemberStateSchema
);
