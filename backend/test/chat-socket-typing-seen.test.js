const test = require("node:test");
const assert = require("node:assert/strict");

const {
  getUnreadCountsForUser,
  getConversationState,
} = require("../src/chat/services/chat-member-state.service");
const {
  serializeConversation,
} = require("../src/chat/services/chat.service");
const ConversationMemberState = require("../src/chat/models/conversation-member-state.model");

test("chat-member-state.service exports getConversationState correctly", async () => {
  assert.equal(typeof getConversationState, "function");
  assert.equal(typeof getUnreadCountsForUser, "function");
});

test("chat.socket imports getConversationState without ReferenceError", async () => {
  const chatSocket = require("../src/chat/sockets/chat.socket");
  assert.ok(chatSocket);
  assert.equal(typeof chatSocket.initializeChatSocketServer, "function");
});

test("serializeConversation: department conversation allows department member even if not in members array", async () => {
  const origFindOne = ConversationMemberState.findOne;
  ConversationMemberState.findOne = () => ({
    select: () => ({
      lean: async () => null,
    }),
  });

  try {
    const deptConv = {
      _id: "650000000000000000000101",
      type: "department",
      name: "IT Department",
      departmentId: "650000000000000000000010",
      members: [],
      admins: [],
      blockedMembers: [],
      isActive: true,
    };

    const userInDept = "650000000000000000000005";
    const serialized = await serializeConversation(deptConv, userInDept);

    assert.equal(serialized.isMember, true);
    assert.equal(serialized.canSend, true);
    assert.equal(serialized.membershipStatus, "active");
  } finally {
    ConversationMemberState.findOne = origFindOne;
  }
});

test("serializeConversation: broadcast channel allows publisher even if not in regular members array", async () => {
  const origFindOne = ConversationMemberState.findOne;
  ConversationMemberState.findOne = () => ({
    select: () => ({
      lean: async () => null,
    }),
  });

  try {
    const publisherId = "650000000000000000000007";
    const bcastConv = {
      _id: "650000000000000000000202",
      type: "broadcast",
      name: "Company Announcements",
      members: ["650000000000000000000099"], // regular subscriber
      admins: [],
      broadcastPublisherIds: [publisherId],
      blockedMembers: [],
      isActive: true,
    };

    const serialized = await serializeConversation(bcastConv, publisherId);

    assert.equal(serialized.isMember, true);
    assert.equal(serialized.canSend, true);
    assert.equal(serialized.membershipStatus, "active");
  } finally {
    ConversationMemberState.findOne = origFindOne;
  }
});
