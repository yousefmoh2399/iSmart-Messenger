const mongoose = require("mongoose");

const chatFolderSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    name: {
      type: String,
      required: true,
      trim: true,
    },
    icon: {
      type: String,
      default: null,
    },
    conversationIds: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ChatConversation",
      }
    ],
    order: {
      type: Number,
      default: 0,
    },
  },
  {
    timestamps: true,
  }
);

// We might want to query by userId and sort by order
chatFolderSchema.index({ userId: 1, order: 1 });

module.exports = mongoose.model("ChatFolder", chatFolderSchema);
