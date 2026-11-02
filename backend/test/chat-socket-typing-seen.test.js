const test = require("node:test");
const assert = require("node:assert/strict");

const {
  getUnreadCountsForUser,
  getConversationState,
} = require("../src/chat/services/chat-member-state.service");

test("chat-member-state.service exports getConversationState correctly", async () => {
  assert.equal(typeof getConversationState, "function");
  assert.equal(typeof getUnreadCountsForUser, "function");
});

test("chat.socket imports getConversationState without ReferenceError", async () => {
  // Verifies that loading the socket module does not throw any import or syntax error
  const chatSocket = require("../src/chat/sockets/chat.socket");
  assert.ok(chatSocket);
  assert.equal(typeof chatSocket.initializeChatSocketServer, "function");
});
