const test = require("node:test");
const assert = require("node:assert/strict");
const { serializeConversation } = require("../src/chat/services/chat.service");
const ConversationMemberState = require("../src/chat/models/conversation-member-state.model");

test("serializeConversation handles smart mute duration correctly", async () => {
  const origFindOne = ConversationMemberState.findOne;

  // Test 1: Muted with future expiration
  const futureDate = new Date(Date.now() + 8 * 3600 * 1000);
  ConversationMemberState.findOne = () => ({
    select: () => ({
      lean: async () => ({
        unreadCount: 0,
        isArchived: false,
        isMuted: true,
        mutedUntil: futureDate,
        isPinned: false,
        isFavorite: false,
      }),
    }),
  });

  const mockConv = {
    _id: "650000000000000000000001",
    type: "direct",
    name: "Test Conv",
    members: [],
    admins: [],
  };

  let serialized = await serializeConversation(mockConv, "user1");
  assert.equal(serialized.isMuted, true);
  assert.equal(serialized.mutedUntil, futureDate.toISOString());

  // Test 2: Muted with expired expiration
  const pastDate = new Date(Date.now() - 3600 * 1000);
  ConversationMemberState.findOne = () => ({
    select: () => ({
      lean: async () => ({
        unreadCount: 0,
        isArchived: false,
        isMuted: true,
        mutedUntil: pastDate,
        isPinned: false,
        isFavorite: false,
      }),
    }),
  });

  serialized = await serializeConversation(mockConv, "user1");
  assert.equal(serialized.isMuted, false);
  assert.equal(serialized.mutedUntil, null);

  // Test 3: Muted indefinitely (mutedUntil = null)
  ConversationMemberState.findOne = () => ({
    select: () => ({
      lean: async () => ({
        unreadCount: 0,
        isArchived: false,
        isMuted: true,
        mutedUntil: null,
        isPinned: false,
        isFavorite: false,
      }),
    }),
  });

  serialized = await serializeConversation(mockConv, "user1");
  assert.equal(serialized.isMuted, true);
  assert.equal(serialized.mutedUntil, null);

  // Restore
  ConversationMemberState.findOne = origFindOne;
});
