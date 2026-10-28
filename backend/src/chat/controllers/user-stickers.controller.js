const asyncHandler = require("../../middleware/async-handler.middleware");
const { sendChatResponse } = require("../utils/chat-response");
const {
  getUserStickers,
  syncUserStickers,
  addOrUpdateUserSticker,
  deleteUserSticker,
} = require("../services/user-stickers.service");

const getMyStickers = asyncHandler(async (req, res) => {
  const result = await getUserStickers(req.user.id);
  sendChatResponse(res, result);
});

const putMyStickers = asyncHandler(async (req, res) => {
  const result = await syncUserStickers(req.user.id, req.body || {});
  const io = req.app.get("io");
  if (io) {
    io.to(`user:${req.user.id}`).emit("stickers_updated", result);
  }
  sendChatResponse(res, result);
});

const postMySticker = asyncHandler(async (req, res) => {
  const result = await addOrUpdateUserSticker(req.user.id, req.body || {});
  const io = req.app.get("io");
  if (io) {
    io.to(`user:${req.user.id}`).emit("stickers_updated", {
      stickers: result.stickers,
      packs: result.packs,
    });
  }
  sendChatResponse(res, result.sticker);
});

const deleteMySticker = asyncHandler(async (req, res) => {
  const result = await deleteUserSticker(req.user.id, req.params.id);
  const io = req.app.get("io");
  if (io) {
    io.to(`user:${req.user.id}`).emit("stickers_updated", result);
  }
  sendChatResponse(res, result);
});

module.exports = {
  getMyStickers,
  putMyStickers,
  postMySticker,
  deleteMySticker,
};
