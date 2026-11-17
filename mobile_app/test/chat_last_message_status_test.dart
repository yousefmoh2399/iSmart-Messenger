import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/chat/models/chat_models.dart';

void main() {
  group('ChatLastMessage Status & Receipts Tests', () {
    const currentUserId = 'user_me_123';
    const peerUserId = 'user_peer_456';

    test('ChatLastMessage fromJson correctly parses seenBy, deliveredTo and status', () {
      final json = {
        'id': 'msg_001',
        'content': 'مرحبا بك',
        'senderId': currentUserId,
        'senderName': 'أنا',
        'messageType': 'text',
        'seenBy': [
          {'userId': peerUserId, 'at': '2026-10-28T12:00:00.000Z'},
        ],
        'deliveredTo': [
          {'userId': peerUserId, 'at': '2026-10-28T11:59:00.000Z'},
        ],
        'status': 'read',
        'createdAt': '2026-10-28T11:58:00.000Z',
      };

      final lastMessage = ChatLastMessage.fromJson(json);

      expect(lastMessage.id, 'msg_001');
      expect(lastMessage.content, 'مرحبا بك');
      expect(lastMessage.senderId, currentUserId);
      expect(lastMessage.status, 'read');
      expect(lastMessage.seenBy.length, 1);
      expect(lastMessage.seenBy.first.userId, peerUserId);
      expect(lastMessage.deliveredTo.length, 1);
      expect(lastMessage.isSeenByAny(currentUserId), isTrue);
      expect(lastMessage.isDeliveredToAny(currentUserId), isTrue);
    });

    test('isSeenByAny and isDeliveredToAny handle sent state (no receipts)', () {
      final lastMessage = ChatLastMessage(
        id: 'msg_002',
        content: 'رسالة قيد الإرسال',
        senderId: currentUserId,
        senderName: 'أنا',
        messageType: 'text',
        seenBy: const [],
        deliveredTo: const [],
        status: 'sent',
        createdAt: DateTime.now(),
      );

      expect(lastMessage.isSeenByAny(currentUserId), isFalse);
      expect(lastMessage.isDeliveredToAny(currentUserId), isFalse);
    });

    test('isDeliveredToAny returns true when recipient delivered but not seen', () {
      final lastMessage = ChatLastMessage(
        id: 'msg_003',
        content: 'رسالة وصلت',
        senderId: currentUserId,
        senderName: 'أنا',
        messageType: 'text',
        seenBy: const [],
        deliveredTo: [
          ChatReceipt(userId: peerUserId, at: DateTime.now()),
        ],
        status: 'delivered',
        createdAt: DateTime.now(),
      );

      expect(lastMessage.isSeenByAny(currentUserId), isFalse);
      expect(lastMessage.isDeliveredToAny(currentUserId), isTrue);
    });

    test('copyWith updates status, seenBy, deliveredTo immutably', () {
      final original = ChatLastMessage(
        id: 'msg_004',
        content: 'تجربة التحديث',
        senderId: currentUserId,
        senderName: 'أنا',
        messageType: 'text',
        seenBy: const [],
        deliveredTo: const [],
        status: 'sent',
        createdAt: DateTime.now(),
      );

      final updated = original.copyWith(
        status: 'read',
        seenBy: [ChatReceipt(userId: peerUserId, at: DateTime.now())],
      );

      expect(original.status, 'sent');
      expect(original.seenBy, isEmpty);
      expect(updated.status, 'read');
      expect(updated.seenBy.length, 1);
      expect(updated.isSeenByAny(currentUserId), isTrue);
    });

    test('ChatLastMessage fromJson parses sender map fallback and trimmed receipt matching', () {
      final json = {
        'id': 'msg_005',
        'content': 'مرحبا',
        'sender': {'_id': ' user_me_123 ', 'fullName': 'يوسف'},
        'messageType': 'text',
        'seenBy': [
          {'userId': ' user_peer_456 ', 'at': '2026-10-28T12:00:00.000Z'},
        ],
        'deliveredTo': [
          {'userId': ' user_peer_456 ', 'at': '2026-10-28T11:59:00.000Z'},
        ],
        'status': 'sent',
      };

      final parsed = ChatLastMessage.fromJson(json);
      expect(parsed.senderId, ' user_me_123 ');
      expect(parsed.senderName, 'يوسف');
      expect(parsed.isSeenByAny(currentUserId), isTrue);
      expect(parsed.isDeliveredToAny(currentUserId), isTrue);
    });

    test('Self-chat conversation correctly resolves isSelfChat', () {
      final selfChat = ChatConversation(
        id: 'conv_self',
        type: 'direct',
        name: '',
        description: '',
        avatarUrl: null,
        departmentId: null,
        createdBy: currentUserId,
        members: [
          ChatDirectoryUser(
            id: currentUserId,
            username: 'me',
            fullName: 'أنا',
            role: 'user',
            departmentId: null,
            branchId: null,
            branchCode: '',
            isOnline: true,
            presenceStatus: 'online',
            isActive: true,
            avatarUrl: null,
            lastSeen: null,
            lastActiveAt: null,
          ),
        ],
        admins: [],
        broadcastPublisherIds: [],
        blockedMemberIds: [],
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

      expect(selfChat.isSelfChat(currentUserId), isTrue);
      expect(selfChat.displayTitle(currentUserId), 'الرسائل المحفوظة');
    });
  });
}
