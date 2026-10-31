const assert = require("node:assert/strict");
const test = require("node:test");

const {
  deleteConversationForUser,
  clearConversationHistoryForUser,
} = require("../src/chat/services/chat-member-state.service");
const {
  deleteConversation,
} = require("../src/chat/services/chat.service");

test("chat-member-state.service exports deleteConversationForUser and clearConversationHistoryForUser", () => {
  assert.equal(typeof deleteConversationForUser, "function");
  assert.equal(typeof clearConversationHistoryForUser, "function");
});

test("chat.service exports deleteConversation function", () => {
  assert.equal(typeof deleteConversation, "function");
});
