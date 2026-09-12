const mongoose = require("mongoose");

const ticketSchema = new mongoose.Schema(
  {
    ticketNumber: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      maxlength: 40,
      index: true,
    },
    ticketType: {
      type: String,
      enum: ["ticket", "complaint", "suggestion"],
      default: "ticket",
      index: true,
    },
    targetDepartmentId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Department",
      default: null,
      index: true,
    },
    title: {
      type: String,
      required: true,
      trim: true,
      maxlength: 220,
    },
    description: {
      type: String,
      required: true,
      trim: true,
      maxlength: 6000,
    },
    status: {
      type: String,
      enum: [
        "open",
        "assigned",
        "in_progress",
        "waiting_branch",
        "resolved",
        "closed",
      ],
      default: "open",
      index: true,
    },
    priority: {
      type: String,
      enum: ["low", "normal", "high", "critical"],
      default: "normal",
      index: true,
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    branchDepartmentId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Department",
      default: null,
      index: true,
    },
    assignedTo: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
      index: true,
    },
    lastUpdateAt: {
      type: Date,
      default: Date.now,
      index: true,
    },
    lastPublicMessage: {
      type: String,
      default: "",
      trim: true,
      maxlength: 600,
    },
    resolvedAt: {
      type: Date,
      default: null,
    },
    closedAt: {
      type: Date,
      default: null,
    },
    dueDate: {
      type: Date,
      default: null,
      index: true,
    },
    deletedAt: {
      type: Date,
      default: null,
      index: true,
    },
    rating: {
      type: Number,
      min: 1,
      max: 5,
      default: null,
    },
    feedback: {
      type: String,
      default: "",
      trim: true,
      maxlength: 1000,
    },
  },
  {
    timestamps: true,
  }
);

ticketSchema.index({ createdBy: 1, updatedAt: -1 });
ticketSchema.index({ assignedTo: 1, updatedAt: -1 });
ticketSchema.index({ status: 1, priority: 1, updatedAt: -1 });

module.exports = mongoose.model("Ticket", ticketSchema);

