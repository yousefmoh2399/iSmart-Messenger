const mongoose = require("mongoose");

const announcementSchema = new mongoose.Schema(
  {
    title: {
      type: String,
      required: true,
      trim: true,
      maxlength: 140,
    },
    message: {
      type: String,
      required: true,
      trim: true,
      maxlength: 4000,
    },
    tone: {
      type: String,
      enum: ["info", "success", "warning", "critical"],
      default: "info",
    },
    isPinned: {
      type: Boolean,
      default: false,
    },
    isActive: {
      type: Boolean,
      default: true,
      index: true,
    },
    startsAt: {
      type: Date,
      default: null,
      index: true,
    },
    endsAt: {
      type: Date,
      default: null,
      index: true,
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
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

announcementSchema.index({
  deletedAt: 1,
  isActive: 1,
  isPinned: -1,
  updatedAt: -1,
});

module.exports = mongoose.model("Announcement", announcementSchema);
