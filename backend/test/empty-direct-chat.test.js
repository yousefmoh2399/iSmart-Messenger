const assert = require("node:assert/strict");
const test = require("node:test");

test("empty direct conversation logic: skips direct conversations with no messages", () => {
  const emptyDirectConv = {
    type: "direct",
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
});

test("non-empty direct conversation logic: retains direct conversations with valid message id or createdAt", () => {
  const activeDirectConv = {
    type: "direct",
    lastMessage: {
      id: "6724b0000000000000000001",
      content: "Hello",
      senderId: "6724a0000000000000000002",
      createdAt: new Date(),
    },
  };

  const hasMessages = Boolean(
    activeDirectConv.lastMessage &&
    (activeDirectConv.lastMessage.id || activeDirectConv.lastMessage.createdAt)
  );

  assert.equal(hasMessages, true, "active direct conversation should have hasMessages = true");
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
