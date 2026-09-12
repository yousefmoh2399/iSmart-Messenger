const mongoose = require("mongoose");

const ticketSettingsSchema = new mongoose.Schema(
  {
    singletonKey: {
      type: String,
      required: true,
      unique: true,
      default: "default",
      trim: true,
      maxlength: 20,
    },
    supportAgentIds: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
      },
    ],
    reportExporters: [
      {
        userId: {
          type: mongoose.Schema.Types.ObjectId,
          ref: "User",
          required: true,
        },
        ticketTypes: [
          {
            type: String,
            enum: ["ticket", "complaint", "suggestion"],
            required: true,
          },
        ],
      },
    ],
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model("TicketSettings", ticketSettingsSchema);
