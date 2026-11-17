const mongoose = require("mongoose");

const userStickersSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      unique: true,
      index: true,
    },
    stickers: [
      {
        id: { type: String, required: true },
        name: { type: String, required: true },
        bytes: { type: String, required: true }, // base64 encoded bytes
        category: { type: String, default: "عام" },
        favorite: { type: Boolean, default: false },
        lastUsedAt: { type: Number, default: null },
      },
    ],
    packs: [
      {
        id: { type: String, required: true },
        name: { type: String, required: true },
        coverStickerId: { type: String, default: null },
        stickerIds: [{ type: String }],
      },
    ],
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model("UserStickers", userStickersSchema);
