const assert = require("node:assert/strict");
const test = require("node:test");

const {
  getUserStickers,
  syncUserStickers,
  addOrUpdateUserSticker,
  deleteUserSticker,
} = require("../src/chat/services/user-stickers.service");

test("user-stickers.service exports required functions", () => {
  assert.equal(typeof getUserStickers, "function");
  assert.equal(typeof syncUserStickers, "function");
  assert.equal(typeof addOrUpdateUserSticker, "function");
  assert.equal(typeof deleteUserSticker, "function");
});
