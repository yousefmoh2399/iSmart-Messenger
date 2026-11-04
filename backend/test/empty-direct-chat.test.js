const assert = require("node:assert/strict");
const test = require("node:test");

test("empty direct conversation logic: skips for recipient, allows for initiator", () => {
  const emptyDirectConv = {
    type: "direct",
    createdBy: "6724a0000000000000000001", // User A
    lastMessage: {
      id: null,
      content: "",
      senderId: null,
      createdAt: null,
    },
  };

  const hasMessages = Boolean(
    emptyDirectConv.lastMessage &&
    (emptyDirectConv.lastMessage.id || emptyDirectConv.lastMessage.createdAt)
  );
  assert.equal(hasMessages, false, "empty direct conversation should have hasMessages = false");

  // For User B (recipient):
  const userBId = "6724b0000000000000000002";
  const isCreatorB = String(emptyDirectConv.createdBy) === userBId;
  const shouldSkipForB = !hasMessages && !isCreatorB;
  assert.equal(shouldSkipForB, true, "User B (recipient) must skip empty direct conversation");

  // For User A (initiator):
  const userAId = "6724a0000000000000000001";
  const isCreatorA = String(emptyDirectConv.createdBy) === userAId;
  const shouldSkipForA = !hasMessages && !isCreatorA;
  assert.equal(shouldSkipForA, false, "User A (initiator) must NOT skip so they can open chat and type");
});

test("non-empty direct conversation logic: retains direct conversations for both users once message sent", () => {
  const activeDirectConv = {
    type: "direct",
    createdBy: "6724a0000000000000000001",
    lastMessage: {
      id: "6724b0000000000000000001",
      content: "Hello",
      senderId: "6724a0000000000000000001",
      createdAt: new Date(),
    },
  };

  const hasMessages = Boolean(
    activeDirectConv.lastMessage &&
    (activeDirectConv.lastMessage.id || activeDirectConv.lastMessage.createdAt)
  );

  assert.equal(hasMessages, true, "active direct conversation should have hasMessages = true");

  const userBId = "6724b0000000000000000002";
  const isCreatorB = String(activeDirectConv.createdBy) === userBId;
  const shouldSkipForB = !hasMessages && !isCreatorB;
  assert.equal(shouldSkipForB, false, "User B sees active direct conversation");
});

test("group/department/broadcast conversations are not skipped even if no messages", () => {
  const groupConv = {
    type: "group",
    lastMessage: {
      id: null,
      content: "",
      createdAt: null,
    },
  };

  const shouldSkip = groupConv.type === "direct" && !Boolean(
    groupConv.lastMessage &&
    (groupConv.lastMessage.id || groupConv.lastMessage.createdAt)
  );

  assert.equal(shouldSkip, false, "groups should not be skipped even without messages");
});
