const mongoose = require("mongoose");

const lastMessageSchema = new mongoose.Schema(
  {
    content: { type: String, default: "" },
    senderId: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    senderName: { type: String, default: "" },
    messageType: {
      type: String,
      enum: ["text", "file", "image", "pdf", "audio", "system", "poll", "gif", "checklist"],
      default: "text",
    },
    createdAt: { type: Date, default: null },
  },
  { _id: false }
);

const pinnedMessageSchema = new mongoose.Schema(
  {
    messageId: { type: mongoose.Schema.Types.ObjectId, ref: "Message", default: null },
    content: { type: String, default: "", maxlength: 2000 },
    setBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    setByName: { type: String, default: "" },
    createdAt: { type: Date, default: null },
    updatedAt: { type: Date, default: null },
  },
  { _id: false }
);

const conversationSchema = new mongoose.Schema(
  {
    type: {
      type: String,
      required: true,
      enum: ["direct", "group", "department", "broadcast"],
      index: true,
    },
    name: {
      type: String,
      default: "",
      trim: true,
      maxlength: 200,
    },
    description: {
      type: String,
      default: "",
      trim: true,
      maxlength: 500,
    },
    departmentId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Department",
      default: null,
      index: true,
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },
    members: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
        index: true,
      },
    ],
    admins: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
      },
    ],
    broadcastPublisherIds: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
      },
    ],
    blockedMembers: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
      },
    ],
    lastMessage: {
      type: lastMessageSchema,
      default: () => ({}),
    },
    pinnedMessage: {
      type: pinnedMessageSchema,
      default: null,
    },
    directKey: {
      type: String,
      default: null,
      sparse: true,
      unique: true,
      trim: true,
    },
    isArchived: {
      type: Boolean,
      default: false,
    },
    isActive: {
      type: Boolean,
      default: true,
    },
    deletedAt: {
      type: Date,
      default: null,
      index: true,
    },
  },
  {
    timestamps: true,
  }
);

conversationSchema.index({ type: 1, departmentId: 1 });
conversationSchema.index({ members: 1, updatedAt: -1 });
conversationSchema.index({ type: 1, directKey: 1 }, { unique: true, sparse: true });

module.exports = mongoose.model("Conversation", conversationSchema);
