import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/chat/models/chat_models.dart';

void main() {
  group('Saved Messages & Self-Notes Tests', () {
    const currentUserId = 'user_me_123';
    const meUser = ChatDirectoryUser(
      id: currentUserId,
      username: 'yousef',
      fullName: 'يوسف محمد',
      role: 'admin',
      jobTitle: 'مهندس برمجيات',
      departmentId: 'dept1',
      branchId: 'branch1',
      branchCode: 'cairo',
      isOnline: true,
      presenceStatus: 'online',
      avatarUrl: null,
      isActive: true,
      lastSeen: null,
      lastActiveAt: null,
    );

    const colleague = ChatDirectoryUser(
      id: 'user_other_456',
      username: 'ahmed',
      fullName: 'أحمد علي',
      role: 'employee',
      jobTitle: 'محاسب',
      departmentId: 'dept2',
      branchId: 'branch2',
      branchCode: 'alex',
      isOnline: false,
      presenceStatus: 'offline',
      avatarUrl: null,
      isActive: true,
      lastSeen: null,
      lastActiveAt: null,
    );

    test('isSelfChat returns true when direct chat contains only current user', () {
      final selfConv = ChatConversation(
        id: 'self_conv_1',
        type: 'direct',
        name: '',
        description: '',
        departmentId: null,
        createdBy: currentUserId,
        members: const [meUser],
        admins: const [],
        broadcastPublisherIds: const [],
        blockedMemberIds: const [],
        pinnedMessage: null,
        lastMessage: null,
        unreadCount: 0,
        isArchived: false,
        isMuted: false,
        isPinned: false,
        isFavorite: false,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(selfConv.isSelfChat(currentUserId), isTrue);
      expect(selfConv.displayTitle(currentUserId), equals('الرسائل المحفوظة'));
    });

    test('isSelfChat returns false when conversation includes other members', () {
      final directConv = ChatConversation(
        id: 'direct_conv_1',
        type: 'direct',
        name: '',
        description: '',
        departmentId: null,
        createdBy: currentUserId,
        members: const [meUser, colleague],
        admins: const [],
        broadcastPublisherIds: const [],
        blockedMemberIds: const [],
        pinnedMessage: null,
        lastMessage: null,
        unreadCount: 0,
        isArchived: false,
        isMuted: false,
        isPinned: false,
        isFavorite: false,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(directConv.isSelfChat(currentUserId), isFalse);
      expect(directConv.displayTitle(currentUserId), equals('أحمد علي'));
    });

    test('displayTitle respects custom name if explicitly provided', () {
      final customNamedConv = ChatConversation(
        id: 'self_conv_2',
        type: 'direct',
        name: 'ملاحظاتي الخاصة',
        description: '',
        departmentId: null,
        createdBy: currentUserId,
        members: const [meUser],
        admins: const [],
        broadcastPublisherIds: const [],
        blockedMemberIds: const [],
        pinnedMessage: null,
        lastMessage: null,
        unreadCount: 0,
        isArchived: false,
        isMuted: false,
        isPinned: false,
        isFavorite: false,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(customNamedConv.isSelfChat(currentUserId), isTrue);
      expect(customNamedConv.displayTitle(currentUserId), equals('ملاحظاتي الخاصة'));
    });

    test('Group conversation cannot be classified as self chat', () {
      final groupConv = ChatConversation(
        id: 'group_conv_1',
        type: 'group',
        name: 'جروب المشروع',
        description: '',
        departmentId: null,
        createdBy: currentUserId,
        members: const [meUser],
        admins: const [],
        broadcastPublisherIds: const [],
        blockedMemberIds: const [],
        pinnedMessage: null,
        lastMessage: null,
        unreadCount: 0,
        isArchived: false,
        isMuted: false,
        isPinned: false,
        isFavorite: false,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(groupConv.isSelfChat(currentUserId), isFalse);
      expect(groupConv.displayTitle(currentUserId), equals('جروب المشروع'));
    });
  });
}
