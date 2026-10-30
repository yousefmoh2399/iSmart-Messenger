import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/features/chat/models/chat_models.dart';

void main() {
  group('Desktop ChatLastMessage Status & Receipts Tests', () {
    const currentUserId = 'desktop_user_1';
    const peerUserId = 'desktop_user_2';

    test('ChatLastMessage fromJson parses seenBy, deliveredTo and status', () {
      final json = {
        'id': 'msg_desk_01',
        'content': 'مرحبا من سطح المكتب',
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

      expect(lastMessage.id, 'msg_desk_01');
      expect(lastMessage.content, 'مرحبا من سطح المكتب');
      expect(lastMessage.senderId, currentUserId);
      expect(lastMessage.status, 'read');
      expect(lastMessage.seenBy.length, 1);
      expect(lastMessage.deliveredTo.length, 1);
      expect(lastMessage.isSeenByAny(currentUserId), isTrue);
      expect(lastMessage.isDeliveredToAny(currentUserId), isTrue);
    });

    test('isSeenByAny and isDeliveredToAny check correct receipts', () {
      final sentMsg = ChatLastMessage(
        id: 'msg_desk_02',
        content: 'مرسلة',
        senderId: currentUserId,
        senderName: 'أنا',
        messageType: 'text',
        seenBy: const [],
        deliveredTo: const [],
        status: 'sent',
        createdAt: DateTime.now(),
      );

      expect(sentMsg.isSeenByAny(currentUserId), isFalse);
      expect(sentMsg.isDeliveredToAny(currentUserId), isFalse);

      final deliveredMsg = sentMsg.copyWith(
        status: 'delivered',
        deliveredTo: [ChatReceipt(userId: peerUserId, at: DateTime.now())],
      );

      expect(deliveredMsg.isSeenByAny(currentUserId), isFalse);
      expect(deliveredMsg.isDeliveredToAny(currentUserId), isTrue);
    });

    test('ChatLastMessage fromJson parses sender map fallback and trimmed receipt matching', () {
      final json = {
        'id': 'msg_desk_03',
        'content': 'مرحبا',
        'sender': {'_id': ' desktop_user_1 ', 'fullName': 'يوسف'},
        'messageType': 'text',
        'seenBy': [
          {'userId': ' desktop_user_2 ', 'at': '2026-10-28T12:00:00.000Z'},
        ],
        'deliveredTo': [
          {'userId': ' desktop_user_2 ', 'at': '2026-10-28T11:59:00.000Z'},
        ],
        'status': 'sent',
      };

      final parsed = ChatLastMessage.fromJson(json);
      expect(parsed.senderId, ' desktop_user_1 ');
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
