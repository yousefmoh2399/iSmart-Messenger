import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/features/chat/models/chat_models.dart';

void main() {
  group('Chat Department & Branch Resolution Tests', () {
    final itDept = DepartmentSummary(
      id: '69f056e654d597515919f723',
      name: 'IT Dept',
      code: '100.1',
      description: 'IT Support',
      managers: const [],
      membersCount: 10,
      defaultConversationId: null,
    );

    final accDept = DepartmentSummary(
      id: '69f057ac54d597515919fe77',
      name: 'ACC Branches',
      code: '.20',
      description: 'ACC-Branches',
      managers: const [],
      membersCount: 49,
      defaultConversationId: null,
    );

    final mainBranch = BranchSummary(
      id: '69f19cf6cd34718a202550a8',
      name: 'المركز الرئيسي',
      code: '100',
      description: 'المركز الرئيسي',
      membersCount: 61,
    );

    final abuKabirBranch = BranchSummary(
      id: '69f05c1a54d59751591a1e40',
      name: 'أبو كبير',
      code: '32',
      description: 'أبو كبير',
      membersCount: 6,
    );

    final departments = [itDept, accDept];
    final branches = [mainBranch, abuKabirBranch];

    final departmentByIdAndCode = <String, DepartmentSummary>{
      for (final department in departments) ...{
        department.id: department,
        department.id.trim(): department,
        if (department.code.trim().isNotEmpty) ...{
          department.code: department,
          department.code.trim(): department,
          department.code.trim().toLowerCase(): department,
          department.code.trim().toUpperCase(): department,
        },
        if (department.name.trim().isNotEmpty) ...{
          department.name.trim(): department,
          department.name.trim().toLowerCase(): department,
        },
      },
    };

    final branchByIdAndCode = <String, BranchSummary>{
      for (final branch in branches) ...{
        branch.id: branch,
        branch.id.trim(): branch,
        if (branch.code.trim().isNotEmpty) ...{
          branch.code: branch,
          branch.code.trim(): branch,
          branch.code.trim().toUpperCase(): branch,
          branch.code.trim().toLowerCase(): branch,
        },
        if (branch.name.trim().isNotEmpty) ...{
          branch.name.trim(): branch,
          branch.name.trim().toLowerCase(): branch,
        },
      },
    };

    BranchSummary? resolveBranch(ChatDirectoryUser user) {
      if (user.branchId != null && user.branchId!.trim().isNotEmpty) {
        final key = user.branchId!.trim();
        final match = branchByIdAndCode[key] ??
            branchByIdAndCode[key.toUpperCase()] ??
            branchByIdAndCode[key.toLowerCase()];
        if (match != null) return match;
      }
      if (user.branchCode.trim().isNotEmpty) {
        final key = user.branchCode.trim();
        final match = branchByIdAndCode[key] ??
            branchByIdAndCode[key.toUpperCase()] ??
            branchByIdAndCode[key.toLowerCase()];
        if (match != null) return match;
      }
      return null;
    }

    List<DepartmentSummary> resolveDepartments(ChatDirectoryUser user) {
      final matched = <DepartmentSummary>{};
      for (final id in user.allDepartmentIds) {
        if (id.trim().isEmpty) continue;
        final key = id.trim();
        final match = departmentByIdAndCode[key] ??
            departmentByIdAndCode[key.toLowerCase()] ??
            departmentByIdAndCode[key.toUpperCase()];
        if (match != null) matched.add(match);
      }
      if (matched.isEmpty &&
          user.departmentId != null &&
          user.departmentId!.trim().isNotEmpty) {
        final key = user.departmentId!.trim();
        final match = departmentByIdAndCode[key] ??
            departmentByIdAndCode[key.toLowerCase()] ??
            departmentByIdAndCode[key.toUpperCase()];
        if (match != null) matched.add(match);
      }
      return matched.toList();
    }

    test('User with branchCode "100" but null branchId properly resolves to المركز الرئيسي', () {
      const user = ChatDirectoryUser(
        id: 'u_hq_1',
        username: 'yousef',
        fullName: 'Yousef Mohamed-HQ',
        role: 'manager',
        departmentId: '69f056e654d597515919f723',
        departmentIds: ['69f056e654d597515919f723'],
        branchId: null,
        branchCode: '100',
        isOnline: true,
        presenceStatus: 'online',
        isActive: true,
        avatarUrl: null,
        lastSeen: null,
        lastActiveAt: null,
      );

      final branch = resolveBranch(user);
      expect(branch, isNotNull);
      expect(branch!.name, 'المركز الرئيسي');
      expect(branch.code, '100');

      final depts = resolveDepartments(user);
      expect(depts, isNotEmpty);
      expect(depts.first.name, 'IT Dept');
    });

    test('User with branchId matches directly, branchCode works as fallback', () {
      const user = ChatDirectoryUser(
        id: 'u_branch_1',
        username: 'acc32',
        fullName: 'ACC - أبو كبير',
        role: 'user',
        departmentId: '69f057ac54d597515919fe77',
        departmentIds: ['69f057ac54d597515919fe77'],
        branchId: '69f05c1a54d59751591a1e40',
        branchCode: '32',
        isOnline: false,
        presenceStatus: 'offline',
        isActive: true,
        avatarUrl: null,
        lastSeen: null,
        lastActiveAt: null,
      );

      final branch = resolveBranch(user);
      expect(branch, isNotNull);
      expect(branch!.name, 'أبو كبير');
      expect(branch.code, '32');

      final depts = resolveDepartments(user);
      expect(depts, isNotEmpty);
      expect(depts.first.name, 'ACC Branches');
    });

    test('User with department code instead of id matches department successfully', () {
      const user = ChatDirectoryUser(
        id: 'u_code_1',
        username: 'coder',
        fullName: 'Coder',
        role: 'user',
        departmentId: '100.1',
        departmentIds: ['100.1'],
        branchId: null,
        branchCode: '100',
        isOnline: false,
        presenceStatus: 'offline',
        isActive: true,
        avatarUrl: null,
        lastSeen: null,
        lastActiveAt: null,
      );

      final depts = resolveDepartments(user);
      expect(depts, isNotEmpty);
      expect(depts.first.name, 'IT Dept');
    });

    test('All tab ordering: recent direct conversation appears at top above older department rooms', () {
      DateTime conversationActivityAt(ChatConversation c) {
        return c.lastMessage?.createdAt ?? c.updatedAt;
      }

      int compareConversations(ChatConversation a, ChatConversation b) {
        if (a.isPinned != b.isPinned) {
          return a.isPinned ? -1 : 1;
        }
        return conversationActivityAt(b).compareTo(conversationActivityAt(a));
      }

      final now = DateTime.now();

      ChatLastMessage makeMessage(String id, DateTime dt) {
        return ChatLastMessage(
          id: id,
          content: 'msg',
          senderId: 'u1',
          senderName: 'User',
          messageType: 'text',
          createdAt: dt,
        );
      }

      final olderDepartmentRoom = ChatConversation(
        id: 'room_1',
        type: 'department',
        name: 'غرفة الدعم الفني',
        description: '',
        departmentId: 'dept_1',
        createdBy: 'u1',
        members: const [],
        admins: const [],
        broadcastPublisherIds: const [],
        blockedMemberIds: const [],
        pinnedMessage: null,
        unreadCount: 0,
        isArchived: false,
        isMuted: false,
        isPinned: false,
        isFavorite: false,
        isActive: true,
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(hours: 3)),
        lastMessage: makeMessage('msg_old', now.subtract(const Duration(hours: 3))),
      );

      final recentDirectChat = ChatConversation(
        id: 'direct_1',
        type: 'direct',
        name: 'محادثة محمد',
        description: '',
        departmentId: null,
        createdBy: 'u2',
        members: const [],
        admins: const [],
        broadcastPublisherIds: const [],
        blockedMemberIds: const [],
        pinnedMessage: null,
        unreadCount: 1,
        isArchived: false,
        isMuted: false,
        isPinned: false,
        isFavorite: false,
        isActive: true,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(minutes: 1)),
        lastMessage: makeMessage('msg_new', now.subtract(const Duration(minutes: 1))),
      );

      final list = <ChatConversation>[olderDepartmentRoom, recentDirectChat]..sort(compareConversations);

      // The recent direct chat MUST be index 0 (at the very top)
      expect(list.first.id, 'direct_1');
      expect(list.first.type, 'direct');
      expect(list.last.id, 'room_1');
      expect(list.last.type, 'department');
    });
  });
}
