const test = require("node:test");
const assert = require("node:assert/strict");
const {
  serializeConversation,
  createMessage,
  listMessagesForConversation,
} = require("../src/chat/services/chat.service");
const Conversation = require("../src/chat/models/conversation.model");
const Message = require("../src/chat/models/message.model");
const ConversationMemberState = require("../src/chat/models/conversation-member-state.model");

test("serializeConversation: reflects removed member state with isMember=false and canSend=false", async () => {
  const origFindOne = ConversationMemberState.findOne;
  const removedUserId = "650000000000000000000003";
  const removedAt = new Date("2026-10-01T12:00:00Z");

  ConversationMemberState.findOne = () => ({
    select: () => ({
      lean: async () => ({
        unreadCount: 0,
        isArchived: false,
        isMuted: false,
        mutedUntil: null,
        isPinned: false,
        isFavorite: false,
        membershipStatus: "removed",
        removedAt,
        clearHistoryAt: null,
      }),
    }),
  });

  const origMessageFindOne = Message.findOne;
  Message.findOne = () => ({
    sort: () => ({
      populate: () => ({
        lean: async () => ({
          _id: "650000000000000000000088",
          conversationId: "650000000000000000000099",
          content: "Old message before removal",
          senderId: { _id: "650000000000000000000001", fullName: "Admin User" },
          createdAt: new Date("2026-10-01T11:59:00Z"),
          messageType: "text",
        }),
      }),
    }),
  });

  try {
    const mockGroup = {
      _id: "650000000000000000000099",
      type: "group",
      name: "Team Group",
      createdBy: "650000000000000000000001",
      admins: ["650000000000000000000001"],
      members: ["650000000000000000000001", "650000000000000000000002"],
      blockedMembers: [],
      lastMessage: {
        id: "650000000000000000000090",
        content: "New message after user was removed",
        createdAt: "2026-10-01T15:00:00Z",
      },
    };

    const serialized = await serializeConversation(mockGroup, removedUserId);

    assert.equal(serialized.isMember, false);
    assert.equal(serialized.canSend, false);
    assert.equal(serialized.membershipStatus, "removed");
    assert.equal(serialized.isBlocked, false);
    assert.equal(serialized.lastMessage.content, "Old message before removal");
  } finally {
    ConversationMemberState.findOne = origFindOne;
    Message.findOne = origMessageFindOne;
  }
});

test("createMessage: rejects removed member from sending messages with 403", async () => {
  const origFindOne = Conversation.findOne;
  const removedUser = { id: "650000000000000000000003", role: "user" };
  const mockGroup = {
    _id: "650000000000000000000099",
    type: "group",
    name: "Team Group",
    createdBy: "650000000000000000000001",
    members: [{ _id: "650000000000000000000001" }, { _id: "650000000000000000000002" }],
    blockedMembers: [],
    isActive: true,
    deletedAt: null,
  };

  const mockQuery = {
    populate: () => mockQuery,
    exec: async () => mockGroup,
  };
  Conversation.findOne = () => mockQuery;

  const origStateFindOne = ConversationMemberState.findOne;
  ConversationMemberState.findOne = () => ({
    lean: async () => ({
      userId: removedUser.id,
      conversationId: mockGroup._id,
      membershipStatus: "removed",
      removedAt: new Date("2026-10-01T12:00:00Z"),
      isDeleted: false,
    }),
  });

  try {
    await assert.rejects(
      async () => {
        await createMessage(
          removedUser,
          { conversationId: mockGroup._id, content: "Hello while removed" },
          null
        );
      },
      (err) => {
        assert.equal(err.statusCode, 403);
        assert.match(err.message, /no longer a member/i);
        return true;
      }
    );
  } finally {
    Conversation.findOne = origFindOne;
    ConversationMemberState.findOne = origStateFindOne;
  }
});

test("createMessage: rejects blocked member from sending messages with 403", async () => {
  const origFindOne = Conversation.findOne;
  const blockedUser = { id: "650000000000000000000004", role: "user" };
  const mockGroup = {
    _id: "650000000000000000000099",
    type: "group",
    name: "Team Group",
    createdBy: "650000000000000000000001",
    members: [{ _id: "650000000000000000000001" }, { _id: blockedUser.id }],
    blockedMembers: [{ _id: blockedUser.id }],
    isActive: true,
    deletedAt: null,
  };

  const mockQuery = {
    populate: () => mockQuery,
    exec: async () => mockGroup,
  };
  Conversation.findOne = () => mockQuery;

  const origStateFindOne = ConversationMemberState.findOne;
  ConversationMemberState.findOne = () => ({
    lean: async () => ({
      userId: blockedUser.id,
      conversationId: mockGroup._id,
      membershipStatus: "blocked",
      blockedAt: new Date("2026-10-01T12:00:00Z"),
      isDeleted: false,
    }),
  });

  try {
    await assert.rejects(
      async () => {
        await createMessage(
          blockedUser,
          { conversationId: mockGroup._id, content: "Trying to message while blocked" },
          null
        );
      },
      (err) => {
        assert.equal(err.statusCode, 403);
        assert.match(err.message, /blocked/i);
        return true;
      }
    );
  } finally {
    Conversation.findOne = origFindOne;
    ConversationMemberState.findOne = origStateFindOne;
  }
});

test("listMessagesForConversation: filters messages created after cutoffDate for removed user", async () => {
  const origFindOne = Conversation.findOne;
  const removedUser = { id: "650000000000000000000003", role: "user" };
  const removedAt = new Date("2026-10-01T12:00:00Z");

  const mockGroup = {
    _id: "650000000000000000000099",
    type: "group",
    name: "Team Group",
    createdBy: "650000000000000000000001",
    members: [{ _id: "650000000000000000000001" }],
    blockedMembers: [],
    isActive: true,
    deletedAt: null,
  };

  const mockQuery = {
    populate: () => mockQuery,
    exec: async () => mockGroup,
  };
  Conversation.findOne = () => mockQuery;

  const origStateFindOne = ConversationMemberState.findOne;
  ConversationMemberState.findOne = () => ({
    lean: async () => ({
      userId: removedUser.id,
      conversationId: mockGroup._id,
      membershipStatus: "removed",
      removedAt,
      isDeleted: false,
    }),
  });

  let capturedQuery = null;
  const origMessageFind = Message.find;
  Message.find = (query) => {
    capturedQuery = query;
    return {
      sort: () => ({
        limit: () => ({
          populate: () => ({
            exec: async () => [],
          }),
        }),
      }),
    };
  };

  try {
    await listMessagesForConversation(removedUser, mockGroup._id);
    assert.ok(capturedQuery);
    assert.ok(capturedQuery.createdAt);
    assert.deepEqual(capturedQuery.createdAt.$lte, removedAt);
  } finally {
    Conversation.findOne = origFindOne;
    ConversationMemberState.findOne = origStateFindOne;
    Message.find = origMessageFind;
  }
});

test("incrementUnreadCounts increments unreadCount for legacy records missing membershipStatus and upserts missing members", async () => {
  const { incrementUnreadCounts } = require("../src/chat/services/chat-member-state.service");
  const origFind = ConversationMemberState.find;
  const origUpdateMany = ConversationMemberState.updateMany;
  const origBulkWrite = ConversationMemberState.bulkWrite;

  const convId = "650000000000000000000099";
  const legacyActiveId = "650000000000000000000010"; // Has doc, but membershipStatus is undefined
  const removedId = "650000000000000000000020";      // Has doc, membershipStatus: "removed"
  const brandNewId = "650000000000000000000030";     // No doc at all

  ConversationMemberState.find = () => ({
    select: () => ({
      lean: async () => [
        { userId: legacyActiveId, membershipStatus: undefined, isDeleted: false },
        { userId: removedId, membershipStatus: "removed", isDeleted: false },
      ],
    }),
  });

  let capturedBulkWriteOps = null;
  ConversationMemberState.bulkWrite = async (ops) => {
    capturedBulkWriteOps = ops;
  };

  let capturedUpdateManyFilter = null;
  let capturedUpdateManyUpdate = null;
  ConversationMemberState.updateMany = async (filter, update) => {
    capturedUpdateManyFilter = filter;
    capturedUpdateManyUpdate = update;
  };

  try {
    await incrementUnreadCounts(convId, [legacyActiveId, removedId, brandNewId], null);

    // 1. brandNewId was missing and should be upserted with unreadCount: 1 and membershipStatus: "active"
    assert.ok(capturedBulkWriteOps);
    assert.equal(capturedBulkWriteOps.length, 1);
    assert.equal(capturedBulkWriteOps[0].updateOne.filter.userId, brandNewId);
    assert.equal(capturedBulkWriteOps[0].updateOne.update.$inc.unreadCount, 1);
    assert.equal(capturedBulkWriteOps[0].updateOne.update.$set.membershipStatus, "active");

    // 2. legacyActiveId had no membershipStatus, so it's NOT removed, and must be in eligible list for $inc
    assert.ok(capturedUpdateManyFilter);
    assert.deepEqual(capturedUpdateManyFilter.userId.$in, [legacyActiveId]);
    assert.equal(capturedUpdateManyUpdate.$inc.unreadCount, 1);
    assert.equal(capturedUpdateManyUpdate.$set.membershipStatus, "active");
  } finally {
    ConversationMemberState.find = origFind;
    ConversationMemberState.updateMany = origUpdateMany;
    ConversationMemberState.bulkWrite = origBulkWrite;
  }
});
