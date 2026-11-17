const test = require("node:test");
const assert = require("node:assert/strict");
const {
  serializeConversation,
  sanitizeBroadcastConversations,
  createMessage,
} = require("../src/chat/services/chat.service");
const Conversation = require("../src/chat/models/conversation.model");
const Message = require("../src/chat/models/message.model");
const ConversationMemberState = require("../src/chat/models/conversation-member-state.model");

test("serializeConversation: strips tainted regular members from broadcastPublisherIds", async () => {
  const origFindOne = ConversationMemberState.findOne;
  ConversationMemberState.findOne = () => ({
    select: () => ({
      lean: async () => ({
        unreadCount: 0,
        isArchived: false,
        isMuted: false,
        mutedUntil: null,
        isPinned: false,
        isFavorite: false,
      }),
    }),
  });

  try {
    const creatorId = "650000000000000000000001";
    const adminId = "650000000000000000000002";
    const regularMember1 = "650000000000000000000003";
    const regularMember2 = "650000000000000000000004";

    // Tainted broadcast where all 4 members were put in broadcastPublisherIds
    const mockTaintedConv = {
      _id: "650000000000000000000099",
      type: "broadcast",
      name: "Tainted Channel",
      createdBy: creatorId,
      admins: [adminId],
      members: [creatorId, adminId, regularMember1, regularMember2],
      broadcastPublisherIds: [creatorId, adminId, regularMember1, regularMember2],
    };

    const serialized = await serializeConversation(mockTaintedConv, creatorId);

    // Regular members must NOT be in broadcastPublisherIds
    assert.equal(serialized.broadcastPublisherIds.includes(regularMember1), false);
    assert.equal(serialized.broadcastPublisherIds.includes(regularMember2), false);

    // Creator and admin MUST be in broadcastPublisherIds
    assert.equal(serialized.broadcastPublisherIds.includes(creatorId), true);
    assert.equal(serialized.broadcastPublisherIds.includes(adminId), true);
  } finally {
    ConversationMemberState.findOne = origFindOne;
  }
});

test("serializeConversation: preserves legitimate broadcast publishers", async () => {
  const origFindOne = ConversationMemberState.findOne;
  ConversationMemberState.findOne = () => ({
    select: () => ({
      lean: async () => ({
        unreadCount: 0,
        isArchived: false,
        isMuted: false,
        mutedUntil: null,
        isPinned: false,
        isFavorite: false,
      }),
    }),
  });

  try {
    const creatorId = "650000000000000000000001";
    const adminId = "650000000000000000000002";
    const explicitPublisher = "650000000000000000000003";
    const regularMember = "650000000000000000000004";

    const mockCleanConv = {
      _id: "650000000000000000000088",
      type: "broadcast",
      name: "Clean Channel",
      createdBy: creatorId,
      admins: [adminId],
      members: [creatorId, adminId, explicitPublisher, regularMember],
      broadcastPublisherIds: [creatorId, adminId, explicitPublisher],
    };

    const serialized = await serializeConversation(mockCleanConv, creatorId);

    assert.equal(serialized.broadcastPublisherIds.includes(creatorId), true);
    assert.equal(serialized.broadcastPublisherIds.includes(adminId), true);
    assert.equal(serialized.broadcastPublisherIds.includes(explicitPublisher), true);
    assert.equal(serialized.broadcastPublisherIds.includes(regularMember), false);
  } finally {
    ConversationMemberState.findOne = origFindOne;
  }
});

test("sanitizeBroadcastConversations is exported as an async function", () => {
  assert.equal(typeof sanitizeBroadcastConversations, "function");
});

test("sanitizeBroadcastConversations: repairs tainted broadcast channels in database", async () => {
  const creatorId = "650000000000000000000001";
  const adminId = "650000000000000000000002";
  const member1 = "650000000000000000000003";
  const member2 = "650000000000000000000004";

  let saved = false;
  const mockConv = {
    _id: "650000000000000000000077",
    type: "broadcast",
    createdBy: creatorId,
    admins: [adminId],
    members: [creatorId, adminId, member1, member2],
    broadcastPublisherIds: [creatorId, adminId, member1, member2], // tainted!
    save: async function () {
      saved = true;
    },
  };

  const origFind = Conversation.find;
  Conversation.find = () => ({
    exec: async () => [mockConv],
  });

  try {
    await sanitizeBroadcastConversations();

    assert.equal(saved, true);
    assert.equal(mockConv.broadcastPublisherIds.includes(member1), false);
    assert.equal(mockConv.broadcastPublisherIds.includes(member2), false);
    assert.equal(mockConv.broadcastPublisherIds.includes(creatorId), true);
    assert.equal(mockConv.broadcastPublisherIds.includes(adminId), true);
  } finally {
    Conversation.find = origFind;
  }
});

test("createMessage: rejects non-publishers in broadcast with 403", async () => {
  const origFindOne = Conversation.findOne;
  const creatorId = "650000000000000000000001";
  const regularUserId = "650000000000000000000005";

  const mockConv = {
    _id: "650000000000000000000066",
    type: "broadcast",
    createdBy: creatorId,
    admins: [{ _id: creatorId }],
    members: [{ _id: creatorId }, { _id: regularUserId }],
    broadcastPublisherIds: [creatorId],
    blockedMembers: [],
    isActive: true,
    deletedAt: null,
  };

  const mockQuery = {
    populate: () => mockQuery,
    exec: async () => mockConv,
  };

  Conversation.findOne = () => mockQuery;

  const regularUser = {
    id: regularUserId,
    _id: regularUserId,
    role: "employee",
    permissions: ["canChat"],
  };

  try {
    await assert.rejects(
      async () => {
        await createMessage(regularUser, {
          conversationId: "650000000000000000000066",
          content: "Spam message from regular user",
        });
      },
      (err) => {
        assert.equal(err.statusCode, 403);
        assert.match(err.message, /قناة بث/);
        return true;
      }
    );
  } finally {
    Conversation.findOne = origFindOne;
  }
});
