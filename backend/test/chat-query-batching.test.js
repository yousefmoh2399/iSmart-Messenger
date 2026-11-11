const test = require("node:test");
const assert = require("node:assert/strict");

const Role = require("../src/chat/models/role.model");
const roleService = require("../src/chat/services/role.service");
const Conversation = require("../src/chat/models/conversation.model");
const ConversationMemberState = require("../src/chat/models/conversation-member-state.model");
const Message = require("../src/chat/models/message.model");
const User = require("../src/models/user.model");
const userService = require("../src/services/user.service");
const chatService = require("../src/chat/services/chat.service");

test("role.service caches role permissions across repeated lookups and invalidates cleanly", async () => {
  const origFindOne = Role.findOne;
  let findOneCount = 0;

  Role.findOne = (query) => {
    findOneCount += 1;
    return {
      lean: async () => ({
        roleName: query.roleName,
        permissions: { canManageBranches: true },
      }),
    };
  };

  try {
    roleService.invalidateRoleCache();

    const first = await roleService.getPermissionsForRole("user");
    const second = await roleService.getPermissionsForRole("user");
    const [p1, p2] = await Promise.all([
      roleService.getPermissionsForRole("manager"),
      roleService.getPermissionsForRole("manager"),
    ]);

    assert.equal(first.canManageBranches, true);
    assert.equal(second.canManageBranches, true);
    assert.equal(p1.canManageBranches, true);
    assert.equal(p2.canManageBranches, true);
    assert.equal(
      findOneCount,
      2,
      "Expected 1 query for 'user' and 1 coalesced query for 'manager'",
    );

    roleService.invalidateRoleCache("user");
    await roleService.getPermissionsForRole("user");
    assert.equal(findOneCount, 3, "Invalidation should refresh cache cleanly");
  } finally {
    roleService.invalidateRoleCache();
    Role.findOne = origFindOne;
  }
});

test("getEffectivePermissionsMapForUsers preloads roles in one Role.find batch and merges overrides", async () => {
  const origFind = Role.find;
  let batchFindCount = 0;
  let requestedRoles = [];

  Role.find = (query) => {
    batchFindCount += 1;
    requestedRoles = query?.roleName?.$in || [];
    return {
      lean: async () => [
        { roleName: "user", permissions: { canUploadFiles: true } },
        { roleName: "custom_qa", permissions: { canViewSystemMonitor: true } },
      ],
    };
  };

  try {
    roleService.invalidateRoleCache();
    const map = await roleService.getEffectivePermissionsMapForUsers([
      {
        _id: "66f100000000000000000001",
        role: "user",
        permissionOverrides: { canSendBroadcast: true },
      },
      {
        _id: "66f100000000000000000002",
        role: "custom_qa",
      },
    ]);

    assert.equal(batchFindCount, 1);
    assert.deepEqual(requestedRoles.sort(), ["custom_qa", "user"]);
    assert.equal(
      map.get("66f100000000000000000001").canSendBroadcast,
      true,
    );
    assert.equal(
      map.get("66f100000000000000000002").canViewSystemMonitor,
      true,
    );
  } finally {
    roleService.invalidateRoleCache();
    Role.find = origFind;
  }
});

test("user.service.listUsers resolves permissions for all users in a single batch", async () => {
  const origUserFind = User.find;
  const origCountDocuments = User.countDocuments;
  const origRoleFind = Role.find;
  const origRoleFindOne = Role.findOne;

  let roleFindCount = 0;
  let roleFindOneCount = 0;

  const mockUsers = Array.from({ length: 15 }, (_, idx) => ({
    _id: `66f2000000000000000000${String(idx + 10).padStart(2, "0")}`,
    username: `user_${idx}`,
    fullName: `User ${idx}`,
    role: idx % 2 === 0 ? "user" : "manager",
    isActive: true,
    createdAt: new Date(),
    updatedAt: new Date(),
  }));

  User.find = () => ({
    sort: () => ({
      skip: () => ({
        limit: () => ({
          lean: async () => mockUsers,
        }),
      }),
    }),
  });
  User.countDocuments = async () => mockUsers.length;
  Role.find = () => {
    roleFindCount += 1;
    return {
      lean: async () => [
        { roleName: "user", permissions: {} },
        { roleName: "manager", permissions: { canCreateRooms: true } },
      ],
    };
  };
  Role.findOne = () => {
    roleFindOneCount += 1;
    return { lean: async () => null };
  };

  try {
    roleService.invalidateRoleCache();
    const res = await userService.listUsers({ role: "admin" }, { page: 1, limit: 50 });
    assert.equal(res.users.length, 15);
    assert.equal(roleFindCount, 1);
    assert.equal(roleFindOneCount, 0);
  } finally {
    roleService.invalidateRoleCache();
    User.find = origUserFind;
    User.countDocuments = origCountDocuments;
    Role.find = origRoleFind;
    Role.findOne = origRoleFindOne;
  }
});

test("listConversationsForUser eliminates per-conversation ConversationMemberState.findOne N+1 queries", async () => {
  const origStateFind = ConversationMemberState.find;
  const origStateFindOne = ConversationMemberState.findOne;
  const origConvFind = Conversation.find;

  let stateFindCount = 0;
  let stateFindOneCount = 0;
  const userId = "66f300000000000000000001";
  const convId1 = "66f300000000000000000011";
  const convId2 = "66f300000000000000000012";

  ConversationMemberState.find = () => {
    stateFindCount += 1;
    return {
      select: () => ({
        lean: async () => [
          {
            conversationId: convId1,
            unreadCount: 3,
            isMuted: false,
            isPinned: true,
            isFavorite: false,
            isArchived: false,
            membershipStatus: "active",
            isDeleted: false,
          },
          {
            conversationId: convId2,
            unreadCount: 0,
            membershipStatus: "active",
            isDeleted: true,
          },
        ],
      }),
    };
  };

  ConversationMemberState.findOne = () => {
    stateFindOneCount += 1;
    return {
      select: () => ({ lean: async () => null }),
      lean: async () => null,
    };
  };

  const convDocs = [
    {
      _id: convId1,
      type: "group",
      name: "Room 1",
      createdBy: userId,
      admins: [userId],
      members: [userId],
      blockedMembers: [],
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date(),
    },
    {
      _id: convId2,
      type: "group",
      name: "Deleted Room 2",
      createdBy: userId,
      admins: [userId],
      members: [userId],
      blockedMembers: [],
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date(),
    },
  ];

  Conversation.find = () => {
    const chain = {
      sort: () => chain,
      populate: () => chain,
      lean: async () => convDocs,
    };
    return chain;
  };

  try {
    const list = await chatService.listConversationsForUser({
      id: userId,
      role: "user",
    });

    assert.equal(stateFindCount, 1, "Expected exactly 1 batched ConversationMemberState.find call");
    assert.equal(stateFindOneCount, 0, "Expected 0 per-conversation findOne queries");
    assert.equal(list.length, 1);
    assert.equal(list[0].id, convId1);
    assert.equal(list[0].unreadCount, 3);
    assert.equal(list[0].isPinned, true);
  } finally {
    ConversationMemberState.find = origStateFind;
    ConversationMemberState.findOne = origStateFindOne;
    Conversation.find = origConvFind;
  }
});

test("markConversationSeen and markConversationDelivered use bulk Message.updateMany instead of sequential saves", async () => {
  const origConvFindOne = Conversation.findOne;
  const origMsgFind = Message.find;
  const origMsgUpdateMany = Message.updateMany;
  const origMsgFindOne = Message.findOne;
  const origConvUpdateOne = Conversation.updateOne;
  const origStateUpdateOne = ConversationMemberState.updateOne;

  const userId = "66f400000000000000000001";
  const senderId = "66f400000000000000000002";
  const convId = "66f400000000000000000099";

  const mockConv = {
    _id: convId,
    type: "group",
    members: [{ _id: userId }, { _id: senderId }],
    admins: [],
    blockedMembers: [],
    isActive: true,
    deletedAt: null,
  };
  const convChain = {
    populate: () => convChain,
    exec: async () => mockConv,
  };
  Conversation.findOne = () => convChain;

  let updateManyCalls = [];
  Message.updateMany = async (filter, update) => {
    updateManyCalls.push({ filter, update });
    return { modifiedCount: 2 };
  };

  Message.find = () => ({
    select: () => ({
      sort: () => ({
        lean: async () => [
          { _id: "66f400000000000000000101" },
          { _id: "66f400000000000000000102" },
        ],
      }),
      lean: async () => [
        { _id: "66f400000000000000000101" },
        { _id: "66f400000000000000000102" },
      ],
    }),
  });

  const msgFindOneChain = {
    sort: () => msgFindOneChain,
    populate: () => msgFindOneChain,
    exec: async () => null,
  };
  Message.findOne = () => msgFindOneChain;
  Conversation.updateOne = async () => ({ modifiedCount: 1 });
  ConversationMemberState.updateOne = async () => ({ modifiedCount: 1 });

  try {
    const seenIds = await chatService.markConversationSeen(
      { id: userId, role: "user" },
      convId,
    );
    const deliveredIds = await chatService.markConversationDelivered(
      { id: userId, role: "user" },
      convId,
    );

    assert.deepEqual(seenIds, [
      "66f400000000000000000101",
      "66f400000000000000000102",
    ]);
    assert.deepEqual(deliveredIds, [
      "66f400000000000000000101",
      "66f400000000000000000102",
    ]);
    assert.equal(updateManyCalls.length, 2, "Expected 1 updateMany for seen + 1 updateMany for delivered");
    assert.equal(updateManyCalls[0].filter._id.$in.length, 2);
    assert.equal(updateManyCalls[1].filter._id.$in.length, 2);
  } finally {
    Conversation.findOne = origConvFindOne;
    Message.find = origMsgFind;
    Message.updateMany = origMsgUpdateMany;
    Message.findOne = origMsgFindOne;
    Conversation.updateOne = origConvUpdateOne;
    ConversationMemberState.updateOne = origStateUpdateOne;
  }
});

test("listBranches and listDepartments aggregate user counts in a single batch query", async () => {
  const Branch = require("../src/chat/models/branch.model");
  const Department = require("../src/chat/models/department.model");
  const branchService = require("../src/chat/services/branch.service");
  const departmentService = require("../src/chat/services/department.service");

  const origBranchFind = Branch.find;
  const origDeptFind = Department.find;
  const origUserAggregate = User.aggregate;
  const origUserCountDocuments = User.countDocuments;

  let aggregateCount = 0;
  let countDocsCalls = 0;

  Branch.find = () => ({
    sort: () => ({
      lean: async () => [
        { _id: "66f500000000000000000001", name: "HQ", code: "HQ" },
        { _id: "66f500000000000000000002", name: "Alex", code: "ALX" },
      ],
    }),
  });
  Department.find = () => ({
    sort: () => ({
      lean: async () => [
        { _id: "66f600000000000000000001", name: "IT", code: "IT" },
        { _id: "66f600000000000000000002", name: "Sales", code: "SLS" },
      ],
    }),
  });
  User.aggregate = async (pipeline) => {
    aggregateCount += 1;
    const isBranch = Boolean(pipeline?.[0]?.$match?.branchId);
    if (isBranch) {
      return [{ _id: "66f500000000000000000001", count: 14 }];
    }
    return [{ _id: "66f600000000000000000002", count: 9 }];
  };
  User.countDocuments = async () => {
    countDocsCalls += 1;
    return 0;
  };

  try {
    const [branches, departments] = await Promise.all([
      branchService.listBranches(),
      departmentService.listDepartments(),
    ]);

    assert.equal(aggregateCount, 2);
    assert.equal(countDocsCalls, 0);
    assert.equal(branches[0].membersCount, 14);
    assert.equal(branches[1].membersCount, 0);
    assert.equal(departments[0].membersCount, 0);
    assert.equal(departments[1].membersCount, 9);
  } finally {
    Branch.find = origBranchFind;
    Department.find = origDeptFind;
    User.aggregate = origUserAggregate;
    User.countDocuments = origUserCountDocuments;
  }
});
