const mongoose = require("mongoose");

const ticketCounterSchema = new mongoose.Schema(
  {
    dateKey: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      maxlength: 8,
    },
    seq: {
      type: Number,
      required: true,
      default: 0,
      min: 0,
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model("TicketCounter", ticketCounterSchema);

