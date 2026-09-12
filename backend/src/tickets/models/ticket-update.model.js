const mongoose = require("mongoose");

const ticketUpdateSchema = new mongoose.Schema(
  {
    ticketId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Ticket",
      required: true,
      index: true,
    },
    kind: {
      type: String,
      enum: ["created", "comment", "status", "assignment", "note"],
      required: true,
      index: true,
    },
    message: {
      type: String,
      default: "",
      trim: true,
      maxlength: 6000,
    },
    visibility: {
      type: String,
      enum: ["public", "internal"],
      default: "public",
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    createdByName: {
      type: String,
      default: "",
      trim: true,
      maxlength: 120,
    },
    createdByRole: {
      type: String,
      default: "user",
      trim: true,
      maxlength: 30,
    },
    fromStatus: {
      type: String,
      default: null,
      trim: true,
      maxlength: 30,
    },
    toStatus: {
      type: String,
      default: null,
      trim: true,
      maxlength: 30,
    },
    fromAssigneeId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },
    toAssigneeId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },
    toAssigneeName: {
      type: String,
      default: "",
      trim: true,
      maxlength: 120,
    },
    metadata: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

ticketUpdateSchema.index({ ticketId: 1, createdAt: -1 });

module.exports = mongoose.model("TicketUpdate", ticketUpdateSchema);

