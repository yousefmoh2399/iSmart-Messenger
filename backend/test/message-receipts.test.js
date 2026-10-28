const test = require("node:test");
const assert = require("node:assert/strict");

const {
  getMessageReadReceipts,
  serializeMessage,
} = require("../src/chat/services/chat.service");

test("serializeMessage excludes the sender from seenBy and deliveredTo", () => {
  const senderId = "66f000000000000000000001";
  const recipientId = "66f000000000000000000002";

  const message = {
    _id: "66f000000000000000000010",
    conversationId: "66f000000000000000000099",
    senderId,
    content: "مرحبا",
    messageType: "text",
    createdAt: new Date(),
    updatedAt: new Date(),
    seenBy: [
      { userId: senderId, at: new Date() },
      { userId: recipientId, at: new Date() },
    ],
    deliveredTo: [
      { userId: senderId, at: new Date() },
      { userId: recipientId, at: new Date() },
    ],
  };

  const serialized = serializeMessage(message);

  assert.equal(serialized.seenBy.length, 1);
  assert.equal(serialized.seenBy[0].userId, recipientId);

  assert.equal(serialized.deliveredTo.length, 1);
  assert.equal(serialized.deliveredTo[0].userId, recipientId);
});
