import 'package:desktop_app/features/chat/models/chat_models.dart';
import 'package:desktop_app/features/chat/presentation/chat_overview_controller.dart';
import 'package:desktop_app/features/chat/utils/chat_album_utils.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _createTestMessage({
  required String id,
  required DateTime createdAt,
  String content = 'Test message',
  String messageType = 'text',
  String? mediaGroupId,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conv_123',
    senderId: 'user_1',
    sender: null,
    content: content,
    messageType: messageType,
    fileUrl: messageType == 'image' ? 'http://example.com/$id.png' : null,
    fileName: messageType == 'image' ? '$id.png' : null,
    fileSize: messageType == 'image' ? 1024 : null,
    mimeType: messageType == 'image' ? 'image/png' : null,
    replyToMessageId: null,
    isDeleted: false,
    metadata: mediaGroupId != null ? {'mediaGroupId': mediaGroupId} : null,
    createdAt: createdAt,
    updatedAt: createdAt,
    seenBy: const [],
    deliveredTo: const [],
  );
}

void main() {
  group('Chat Reverse Order & Message Sorting', () {
    test('sortAndDedupeChatMessages sorts messages descending (newest at index 0)', () {
      final t1 = DateTime(2026, 9, 28, 10, 0, 0);
      final t2 = DateTime(2026, 9, 28, 10, 5, 0);
      final t3 = DateTime(2026, 9, 28, 10, 10, 0);

      final msg1 = _createTestMessage(id: 'm1', createdAt: t1);
      final msg2 = _createTestMessage(id: 'm2', createdAt: t2);
      final msg3 = _createTestMessage(id: 'm3', createdAt: t3);

      final result = sortAndDedupeChatMessages([msg1, msg3, msg2]);

      expect(result.length, 3);
      expect(result[0].id, 'm3'); // newest
      expect(result[1].id, 'm2');
      expect(result[2].id, 'm1'); // oldest
    });

    test('sortAndDedupeChatMessages removes duplicate message IDs', () {
      final t1 = DateTime(2026, 9, 28, 10, 0, 0);
      final t2 = DateTime(2026, 9, 28, 10, 5, 0);

      final msg1 = _createTestMessage(id: 'm1', createdAt: t1, content: 'Initial');
      final msg1Updated = _createTestMessage(id: 'm1', createdAt: t1, content: 'Updated');
      final msg2 = _createTestMessage(id: 'm2', createdAt: t2);

      final result = sortAndDedupeChatMessages([msg1, msg2, msg1Updated]);

      expect(result.length, 2);
      expect(result[0].id, 'm2');
      expect(result[1].id, 'm1');
      expect(result[1].content, 'Updated');
    });

    test('Pagination / loadMore merges older page without duplicates and preserves descending order', () {
      final t1 = DateTime(2026, 9, 28, 9, 0, 0);
      final t2 = DateTime(2026, 9, 28, 9, 30, 0);
      final t3 = DateTime(2026, 9, 28, 10, 0, 0);
      final t4 = DateTime(2026, 9, 28, 10, 30, 0);

      final currentMessages = [
        _createTestMessage(id: 'm4', createdAt: t4),
        _createTestMessage(id: 'm3', createdAt: t3),
      ];

      final olderPage = [
        _createTestMessage(id: 'm3', createdAt: t3), // overlapping message
        _createTestMessage(id: 'm2', createdAt: t2),
        _createTestMessage(id: 'm1', createdAt: t1),
      ];

      final merged = sortAndDedupeChatMessages([
        ...olderPage,
        ...currentMessages,
      ]);

      expect(merged.length, 4);
      expect(merged.map((m) => m.id).toList(), ['m4', 'm3', 'm2', 'm1']);
    });

    test('optimistic message is replaced by server message with same clientMessageId at index 0 without duplicates', () {
      final t0 = DateTime(2026, 9, 28, 10, 0, 0);
      final existingMsg = _createTestMessage(id: 'm1', createdAt: t0);

      // 1. Optimistic message created with temp id, status pending, and clientMessageId
      final optimisticMsg = _createTestMessage(
        id: 'temp_c_12345',
        createdAt: DateTime(2026, 9, 28, 10, 5, 0),
      ).copyWith(
        metadata: {
          'clientMessageId': 'c_12345',
          'status': 'pending',
        },
      );

      // Add optimistic message to chat state
      var stateList = sortAndDedupeChatMessages([existingMsg, optimisticMsg]);
      expect(stateList.length, 2);
      expect(stateList[0].id, 'temp_c_12345'); // At index 0 (newest)
      expect(stateList[0].metadata?['status'], 'pending');

      // 2. Server responds with different id (e.g. MongoDB ObjectId) and different server createdAt
      final serverMsg = _createTestMessage(
        id: '66f8e792c0194b150937a4b1',
        createdAt: DateTime(2026, 9, 28, 10, 5, 1),
      ).copyWith(
        metadata: {
          'clientMessageId': 'c_12345',
        },
      );

      // State is updated with server message
      stateList = sortAndDedupeChatMessages([...stateList, serverMsg]);

      // 3. Exactly 1 message in state at index 0, replaced without duplicates
      expect(stateList.length, 2);
      expect(stateList[0].id, '66f8e792c0194b150937a4b1');
      expect(stateList[0].metadata?['clientMessageId'], 'c_12345');
      expect(stateList[0].metadata?['status'], isNull);
      expect(stateList[1].id, 'm1');
      expect(stateList.any((m) => m.id == 'temp_c_12345'), isFalse);
    });
  });

  group('Media Album Utilities', () {
    test('collapseMediaAlbums collapses grouped images into single entry', () {
      final t1 = DateTime(2026, 9, 28, 10, 0, 0);
      final t2 = DateTime(2026, 9, 28, 10, 0, 1);
      final t3 = DateTime(2026, 9, 28, 10, 0, 2);
      final t4 = DateTime(2026, 9, 28, 10, 5, 0);

      // In descending list: newest first
      final textMsg = _createTestMessage(id: 'm4', createdAt: t4, messageType: 'text');
      final img3 = _createTestMessage(id: 'img3', createdAt: t3, messageType: 'image', mediaGroupId: 'album_1');
      final img2 = _createTestMessage(id: 'img2', createdAt: t2, messageType: 'image', mediaGroupId: 'album_1');
      final img1 = _createTestMessage(id: 'img1', createdAt: t1, messageType: 'image', mediaGroupId: 'album_1');

      final descendingList = [textMsg, img3, img2, img1];
      final collapsed = collapseMediaAlbums(descendingList);

      // Should keep textMsg and only the first encountered album message (img3)
      expect(collapsed.length, 2);
      expect(collapsed[0].id, 'm4');
      expect(collapsed[1].id, 'img3');
    });

    test('albumFor returns album photos sorted chronologically (oldest to newest)', () {
      final t1 = DateTime(2026, 9, 28, 10, 0, 0);
      final t2 = DateTime(2026, 9, 28, 10, 0, 1);
      final t3 = DateTime(2026, 9, 28, 10, 0, 2);

      final img1 = _createTestMessage(id: 'img1', createdAt: t1, messageType: 'image', mediaGroupId: 'album_1');
      final img2 = _createTestMessage(id: 'img2', createdAt: t2, messageType: 'image', mediaGroupId: 'album_1');
      final img3 = _createTestMessage(id: 'img3', createdAt: t3, messageType: 'image', mediaGroupId: 'album_1');

      // The chat list is descending
      final chatList = [img3, img2, img1];

      final albumPhotos = albumFor(img3, chatList);

      expect(albumPhotos.length, 3);
      expect(albumPhotos[0].id, 'img1'); // chronologically first (oldest)
      expect(albumPhotos[1].id, 'img2');
      expect(albumPhotos[2].id, 'img3'); // chronologically last (newest)
    });

    test('albumFor returns single item for non-album image', () {
      final t1 = DateTime(2026, 9, 28, 10, 0, 0);
      final soloImg = _createTestMessage(id: 'solo', createdAt: t1, messageType: 'image');

      final result = albumFor(soloImg, [soloImg]);
      expect(result.length, 1);
      expect(result.first.id, 'solo');
    });
  });
}
