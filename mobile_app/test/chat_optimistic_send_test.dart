import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/chat/models/chat_models.dart';
import 'package:mobile_app/features/chat/presentation/chat_overview_controller.dart';

ChatMessage _makeMsg({
  required String id,
  required DateTime createdAt,
  required String content,
  String? clientMessageId,
  String? status,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conv_1',
    senderId: 'user_me',
    sender: null,
    content: content,
    messageType: 'text',
    fileUrl: null,
    fileName: null,
    fileSize: null,
    mimeType: null,
    replyToMessageId: null,
    isDeleted: false,
    metadata: {
      if (clientMessageId != null) 'clientMessageId': clientMessageId,
      if (status != null) 'status': status,
    },
    createdAt: createdAt,
    updatedAt: createdAt,
    seenBy: const [],
    deliveredTo: const [],
  );
}

void main() {
  group('Optimistic Send & Deduplication End-to-End', () {
    test('1. Success: optimistic pending message is replaced by server message at index 0', () {
      final t0 = DateTime(2026, 9, 28, 10, 0, 0);
      final existingMsg = _makeMsg(id: 'm0', createdAt: t0, content: 'Initial message');

      List<ChatMessage> state = [existingMsg];

      // Step A: User triggers send -> Optimistic message is inserted immediately
      final clientMsgId = 'c_success_1';
      final tempCreatedAt = DateTime(2026, 9, 28, 10, 5, 0);
      final optimisticMsg = _makeMsg(
        id: 'temp_$clientMsgId',
        createdAt: tempCreatedAt,
        content: 'Hello optimistic',
        clientMessageId: clientMsgId,
        status: 'pending',
      );

      state = sortAndDedupeChatMessages([...state, optimisticMsg]);

      // Check optimistic state
      expect(state.length, 2);
      expect(state[0].id, 'temp_$clientMsgId');
      expect(state[0].metadata?['status'], 'pending');
      expect(state[0].metadata?['clientMessageId'], clientMsgId);
      expect(state[1].id, 'm0');

      // Step B: Server responds with confirmed message (different ID and server createdAt)
      final serverCreatedAt = DateTime(2026, 9, 28, 10, 5, 2);
      final serverConfirmedMsg = _makeMsg(
        id: '66f8e792c0194b150937a4b1',
        createdAt: serverCreatedAt,
        content: 'Hello optimistic',
        clientMessageId: clientMsgId,
      );

      state = sortAndDedupeChatMessages([...state, serverConfirmedMsg]);

      // Exactly 1 message for this clientMessageId, at index 0, with server id
      expect(state.length, 2);
      expect(state[0].id, '66f8e792c0194b150937a4b1');
      expect(state[0].metadata?['clientMessageId'], clientMsgId);
      expect(state[0].metadata?['status'], isNull);
      expect(state[1].id, 'm0');
      expect(state.any((m) => m.id == 'temp_$clientMsgId'), isFalse);
    });

    test('2. Failure then Retry: failed message stays in state, retry replaces it cleanly with 1 message', () {
      final t0 = DateTime(2026, 9, 28, 10, 0, 0);
      final existingMsg = _makeMsg(id: 'm0', createdAt: t0, content: 'Initial message');

      List<ChatMessage> state = [existingMsg];

      // Step A: Send message
      final clientMsgId = 'c_fail_retry_1';
      final tempCreatedAt = DateTime(2026, 9, 28, 10, 6, 0);
      final optimisticMsg = _makeMsg(
        id: 'temp_$clientMsgId',
        createdAt: tempCreatedAt,
        content: 'Hello failure',
        clientMessageId: clientMsgId,
        status: 'pending',
      );

      state = sortAndDedupeChatMessages([...state, optimisticMsg]);
      expect(state[0].metadata?['status'], 'pending');

      // Step B: Network fails -> message status marked as 'failed' in state
      final failedMsg = optimisticMsg.copyWith(
        metadata: {
          'clientMessageId': clientMsgId,
          'status': 'failed',
          'error': 'Network connection timed out',
        },
      );

      state = sortAndDedupeChatMessages([...state, failedMsg]);
      expect(state.length, 2);
      expect(state[0].id, 'temp_$clientMsgId');
      expect(state[0].metadata?['status'], 'failed');
      expect(state[0].metadata?['error'], 'Network connection timed out');

      // Step C: User hits retry -> re-enters pending state with the same clientMessageId
      final retryPendingMsg = failedMsg.copyWith(
        metadata: {
          'clientMessageId': clientMsgId,
          'status': 'pending',
        },
      );

      state = sortAndDedupeChatMessages([...state, retryPendingMsg]);
      expect(state.length, 2);
      expect(state[0].id, 'temp_$clientMsgId');
      expect(state[0].metadata?['status'], 'pending');

      // Step D: Server responds successfully to retry
      final serverConfirmedMsg = _makeMsg(
        id: '66f8e792c0194b150937a4b2',
        createdAt: DateTime(2026, 9, 28, 10, 6, 5),
        content: 'Hello failure',
        clientMessageId: clientMsgId,
      );

      state = sortAndDedupeChatMessages([...state, serverConfirmedMsg]);

      // Exactly 1 message remains at index 0, confirmed
      expect(state.length, 2);
      expect(state[0].id, '66f8e792c0194b150937a4b2');
      expect(state[0].metadata?['clientMessageId'], clientMsgId);
      expect(state[0].metadata?['status'], isNull);
      expect(state.any((m) => m.id == 'temp_$clientMsgId'), isFalse);
    });

    test('3. Rapid successive sending (5 messages): all appear optimistic and resolve without duplicates in correct order', () {
      final t0 = DateTime(2026, 9, 28, 10, 0, 0);
      final existingMsg = _makeMsg(id: 'm0', createdAt: t0, content: 'Initial message');

      List<ChatMessage> state = [existingMsg];

      // Send 5 messages in rapid succession
      for (int i = 1; i <= 5; i++) {
        final optMsg = _makeMsg(
          id: 'temp_c_rapid_$i',
          createdAt: DateTime(2026, 9, 28, 10, 10, i),
          content: 'Rapid message $i',
          clientMessageId: 'c_rapid_$i',
          status: 'pending',
        );
        state = sortAndDedupeChatMessages([...state, optMsg]);
      }

      // Check all 5 are in state, in descending order (newest index 0 = msg 5)
      expect(state.length, 6);
      expect(state[0].id, 'temp_c_rapid_5');
      expect(state[1].id, 'temp_c_rapid_4');
      expect(state[2].id, 'temp_c_rapid_3');
      expect(state[3].id, 'temp_c_rapid_2');
      expect(state[4].id, 'temp_c_rapid_1');
      expect(state[5].id, 'm0');

      // Server / socket responses arrive (simulating out-of-order arrival: 3, 1, 5, 2, 4)
      final arrivalOrder = [3, 1, 5, 2, 4];
      for (final i in arrivalOrder) {
        final serverMsg = _makeMsg(
          id: 'server_id_rapid_$i',
          createdAt: DateTime(2026, 9, 28, 10, 10, i),
          content: 'Rapid message $i',
          clientMessageId: 'c_rapid_$i',
        );
        state = sortAndDedupeChatMessages([...state, serverMsg]);
      }

      // Exactly 6 messages total, exactly 1 message per clientMessageId
      expect(state.length, 6);
      expect(state.map((m) => m.id).toList(), [
        'server_id_rapid_5',
        'server_id_rapid_4',
        'server_id_rapid_3',
        'server_id_rapid_2',
        'server_id_rapid_1',
        'm0',
      ]);

      // Ensure no temp message remains
      expect(state.any((m) => m.id.startsWith('temp_')), isFalse);
    });

    testWidgets('4. Widget Test: ListView reverse:true preserves stable keys and renders states correctly', (tester) async {
      final t0 = DateTime(2026, 9, 28, 10, 0, 0);
      final existingMsg = _makeMsg(id: 'm0', createdAt: t0, content: 'Initial message');

      final messagesNotifier = ValueNotifier<List<ChatMessage>>([existingMsg]);

      // Helper widget mimicking ConversationScreen ListView.builder with reverse: true and stable Key
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<List<ChatMessage>>(
              valueListenable: messagesNotifier,
              builder: (context, messages, _) {
                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final stableKey = message.metadata?['clientMessageId']?.toString() ?? message.id;
                    final status = message.metadata?['status']?.toString();

                    return Container(
                      key: ValueKey(stableKey),
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Text(message.content),
                          if (status == 'pending')
                            const Icon(Icons.access_time_rounded, key: ValueKey('icon_pending')),
                          if (status == 'failed')
                            const Icon(Icons.error_outline_rounded, key: ValueKey('icon_failed')),
                          if (status == null)
                            const Icon(Icons.done_all_rounded, key: ValueKey('icon_sent')),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );

      // Initially only existing message
      expect(find.text('Initial message'), findsOneWidget);
      expect(find.byKey(const ValueKey('icon_sent')), findsOneWidget);

      // Step 1: Add optimistic message
      final clientMsgId = 'c_widget_1';
      final optimisticMsg = _makeMsg(
        id: 'temp_$clientMsgId',
        createdAt: DateTime(2026, 9, 28, 10, 5, 0),
        content: 'Widget test message',
        clientMessageId: clientMsgId,
        status: 'pending',
      );

      messagesNotifier.value = sortAndDedupeChatMessages([
        ...messagesNotifier.value,
        optimisticMsg,
      ]);
      await tester.pump();

      // Pending icon shown, 1 optimistic widget with stable key ValueKey('c_widget_1')
      expect(find.byKey(ValueKey(clientMsgId)), findsOneWidget);
      expect(find.byKey(const ValueKey('icon_pending')), findsOneWidget);

      // Step 2: Server responds -> Key remains ValueKey('c_widget_1') preventing recreation
      final serverMsg = _makeMsg(
        id: 'server_mongo_66f8e792',
        createdAt: DateTime(2026, 9, 28, 10, 5, 1),
        content: 'Widget test message',
        clientMessageId: clientMsgId,
      );

      messagesNotifier.value = sortAndDedupeChatMessages([
        ...messagesNotifier.value,
        serverMsg,
      ]);
      await tester.pump();

      // Key remains stable: exactly 1 widget for clientMsgId, icon switched to sent
      expect(find.byKey(ValueKey(clientMsgId)), findsOneWidget);
      expect(find.byKey(const ValueKey('icon_sent')), findsNWidgets(2)); // m0 + serverMsg
      expect(find.byKey(const ValueKey('icon_pending')), findsNothing);
    });
  });
}
