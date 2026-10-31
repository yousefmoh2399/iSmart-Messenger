import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:desktop_app/features/chat/models/chat_models.dart';
import 'package:desktop_app/features/chat/data/chat_local_cache.dart';
import 'package:desktop_app/features/chat/data/chat_repository.dart';
import 'package:desktop_app/features/chat/data/chat_socket_service.dart';
import 'package:desktop_app/shared/providers/providers.dart';
import 'package:desktop_app/features/auth/presentation/auth_controller.dart';
import 'package:desktop_app/shared/models/app_user.dart';
import 'package:desktop_app/features/auth/data/session_store.dart';

AppUser _createTestUser() {
  return AppUser(
    id: 'user_1',
    username: 'testuser',
    fullName: 'Test User',
    role: 'user',
    departmentId: null,
    branchId: null,
    branchCode: 'main',
    isOnline: true,
    presenceStatus: 'online',
    isActive: true,
    avatarUrl: null,
    lastSeen: null,
    lastActiveAt: null,
    maxAttachmentSizeMB: 20,
    permissions: const {},
    chatPreferences: ChatPreferences.defaults,
  );
}

class FakeChatRepository implements ChatRepository {
  bool shouldFail = false;
  int sendCallCount = 0;
  int removeCallCount = 0;
  final Duration delay;
  final List<ChatMessage> initialMessages;

  FakeChatRepository({
    this.delay = Duration.zero,
    this.initialMessages = const [],
  });

  @override
  final ChatLocalCache cache = ChatLocalCache();

  @override
  Future<ChatMessagesPage?> getCachedMessages(String conversationId) async {
    return ChatMessagesPage(
      messages: initialMessages,
      nextCursor: null,
      hasMore: false,
      limit: 40,
    );
  }

  @override
  Future<ChatMessagesPage> fetchMessages(
    String conversationId, {
    String? cursor,
    int limit = 40,
    bool isScheduled = false,
  }) async {
    return ChatMessagesPage(
      messages: initialMessages,
      nextCursor: null,
      hasMore: false,
      limit: 40,
    );
  }

  @override
  Future<ChatPostResult> sendTextMessage({
    required String conversationId,
    required String content,
    String? clientMessageId,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
    String? messageType,
    String? fileUrl,
    bool isSilent = false,
    bool isScheduled = false,
    DateTime? scheduledFor,
  }) async {
    sendCallCount++;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (shouldFail) {
      throw Exception('Simulated network error');
    }
    final serverMsg = ChatMessage(
      id: 'srv_${clientMessageId ?? sendCallCount}',
      conversationId: conversationId,
      senderId: 'user_1',
      sender: null,
      content: content,
      messageType: messageType ?? 'text',
      fileUrl: fileUrl,
      fileName: null,
      fileSize: null,
      mimeType: null,
      replyToMessageId: replyToMessageId,
      isDeleted: false,
      metadata: {
        ...?metadata,
        if (clientMessageId != null) 'clientMessageId': clientMessageId,
      },
      createdAt: DateTime.now().add(Duration(milliseconds: sendCallCount)),
      updatedAt: DateTime.now().add(Duration(milliseconds: sendCallCount)),
      seenBy: const [],
      deliveredTo: const [],
    );
    return ChatPostResult(
      message: serverMsg,
      conversation: ChatConversation.fromJson({
        'id': conversationId,
        'type': 'direct',
        'name': 'Direct Chat',
      }),
    );
  }

  @override
  Future<void> removeMessage(String messageId) async {
    removeCallCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeChatSocketService implements ChatSocketService {
  final _controller = StreamController<ChatSocketEvent>.broadcast();

  @override
  Stream<ChatSocketEvent> get events => _controller.stream;

  @override
  void joinConversation(String conversationId) {}

  @override
  void leaveConversation(String conversationId) {}

  @override
  void markActivity() {}

  @override
  void markSeen(String conversationId) {}

  @override
  void sendTyping(String conversationId) {}

  @override
  void stopTyping(String conversationId) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthController extends Notifier<AuthState> implements AuthController {
  @override
  AuthState build() {
    return AuthState(
      status: AuthStatus.authenticated,
      session: const StoredAuthSession(
        accessToken: 'dummy_token',
        refreshToken: 'dummy_refresh',
        userId: 'user_1',
        generation: 1,
      ),
      user: _createTestUser(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ConversationMessagesController.sendMessage Tests', () {
    test('1. Success: optimistic insert -> network completes -> exactly 1 confirmed message', () async {
      final fakeRepo = FakeChatRepository();
      final fakeSocket = FakeChatSocketService();
      final testUser = _createTestUser();

      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(fakeRepo),
          chatSocketServiceProvider.overrideWithValue(fakeSocket),
          chatSocketConnectionProvider.overrideWith((ref) => Future<void>.value()),
          authControllerProvider.overrideWith(FakeAuthController.new),
          currentUserProvider.overrideWithValue(testUser),
          authTokenProvider.overrideWith((ref) => Future.value('dummy_token')),
        ],
      );
      addTearDown(container.dispose);

      const convId = 'conv_test_1';
      final sub = container.listen(conversationMessagesControllerProvider(convId), (_, __) {});
      addTearDown(sub.close);
      final controller = container.read(conversationMessagesControllerProvider(convId).notifier);
      await container.read(conversationMessagesControllerProvider(convId).future);

      const clientMsgId = 'c_success_100';
      await controller.sendMessage(
        content: 'Hello World',
        clientMessageId: clientMsgId,
      );

      final state = container.read(conversationMessagesControllerProvider(convId)).value!;
      
      // Verify exactly 1 message exists for this clientMessageId
      final matchingMessages = state.messages
          .where((m) => m.metadata?['clientMessageId'] == clientMsgId)
          .toList();
      expect(matchingMessages.length, 1);
      
      final msg = matchingMessages.first;
      expect(msg.id, 'srv_$clientMsgId');
      expect(msg.content, 'Hello World');
      expect(msg.metadata?['status'], isNull); // Confirmed on server
      expect(state.messages.length, 1);
      expect(state.messages.first.id, 'srv_$clientMsgId');
    });

    test('2. Failure then Retry: message fails -> status failed -> retry succeeds -> exactly 1 message', () async {
      final fakeRepo = FakeChatRepository();
      final fakeSocket = FakeChatSocketService();
      final testUser = _createTestUser();

      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(fakeRepo),
          chatSocketServiceProvider.overrideWithValue(fakeSocket),
          chatSocketConnectionProvider.overrideWith((ref) => Future<void>.value()),
          authControllerProvider.overrideWith(FakeAuthController.new),
          currentUserProvider.overrideWithValue(testUser),
          authTokenProvider.overrideWith((ref) => Future.value('dummy_token')),
        ],
      );
      addTearDown(container.dispose);

      const convId = 'conv_test_2';
      final sub = container.listen(conversationMessagesControllerProvider(convId), (_, __) {});
      addTearDown(sub.close);
      final controller = container.read(conversationMessagesControllerProvider(convId).notifier);
      await container.read(conversationMessagesControllerProvider(convId).future);

      const clientMsgId = 'c_fail_retry_200';

      // Step A: Trigger send with simulated network failure
      fakeRepo.shouldFail = true;
      try {
        await controller.sendMessage(
          content: 'Will fail first',
          clientMessageId: clientMsgId,
        );
      } catch (_) {
        // Expected network failure
      }

      var state = container.read(conversationMessagesControllerProvider(convId)).value!;
      expect(state.messages.length, 1);
      expect(state.messages.first.id, 'temp_$clientMsgId');
      expect(state.messages.first.metadata?['status'], 'failed');
      expect(state.messages.first.metadata?['clientMessageId'], clientMsgId);

      // Step B: Retry sending the same message when network is restored
      fakeRepo.shouldFail = false;
      await controller.sendMessage(
        content: state.messages.first.content,
        clientMessageId: clientMsgId,
        metadata: state.messages.first.metadata,
      );

      state = container.read(conversationMessagesControllerProvider(convId)).value!;
      
      // Verify exactly 1 message exists for this clientMessageId, and it is confirmed
      final matching = state.messages
          .where((m) => m.metadata?['clientMessageId'] == clientMsgId)
          .toList();
      expect(matching.length, 1);
      expect(matching.first.id, 'srv_$clientMsgId');
      expect(matching.first.metadata?['status'], isNull);
      expect(state.messages.any((m) => m.id == 'temp_$clientMsgId'), isFalse);
    });

    test('3. Rapid successive sending: 5 messages sent concurrently -> exactly 1 per clientMessageId in descending order', () async {
      // Simulate realistic async network latency (15ms per request)
      final fakeRepo = FakeChatRepository(delay: const Duration(milliseconds: 15));
      final fakeSocket = FakeChatSocketService();
      final testUser = _createTestUser();

      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(fakeRepo),
          chatSocketServiceProvider.overrideWithValue(fakeSocket),
          chatSocketConnectionProvider.overrideWith((ref) => Future<void>.value()),
          authControllerProvider.overrideWith(FakeAuthController.new),
          currentUserProvider.overrideWithValue(testUser),
          authTokenProvider.overrideWith((ref) => Future.value('dummy_token')),
        ],
      );
      addTearDown(container.dispose);

      const convId = 'conv_test_3';
      final sub = container.listen(conversationMessagesControllerProvider(convId), (_, __) {});
      addTearDown(sub.close);
      final controller = container.read(conversationMessagesControllerProvider(convId).notifier);
      await container.read(conversationMessagesControllerProvider(convId).future);

      final clientIds = List.generate(5, (i) => 'rapid_client_msg_${i + 1}');

      // Send 5 messages in rapid succession (concurrently in flight)
      final sendFutures = <Future<void>>[];
      for (int i = 0; i < 5; i++) {
        sendFutures.add(
          controller.sendMessage(
            content: 'Message #${i + 1}',
            clientMessageId: clientIds[i],
          ),
        );
      }

      await Future.wait(sendFutures);

      final state = container.read(conversationMessagesControllerProvider(convId)).value!;

      // 1. Total message count must be exactly 5
      expect(state.messages.length, 5);

      // 2. Exactly 1 message per clientMessageId
      for (final cid in clientIds) {
        final matches = state.messages
            .where((m) => m.metadata?['clientMessageId'] == cid)
            .toList();
        expect(matches.length, 1, reason: 'Expected exactly 1 message for clientMessageId: $cid');
        expect(matches.first.id, 'srv_$cid');
        expect(matches.first.metadata?['status'], isNull);
      }

      // 3. Descending order (newest first, index 0 is newest)
      for (int i = 0; i < state.messages.length - 1; i++) {
        final current = state.messages[i];
        final next = state.messages[i + 1];
        expect(
          current.createdAt.isAfter(next.createdAt) || current.createdAt.isAtSameMomentAs(next.createdAt),
          isTrue,
          reason: 'Messages must be sorted in descending order',
        );
      }
    });

    test('4. Delete failed message: removes message locally without calling server removeMessage', () async {
      final fakeRepo = FakeChatRepository();
      final fakeSocket = FakeChatSocketService();
      final testUser = _createTestUser();

      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(fakeRepo),
          chatSocketServiceProvider.overrideWithValue(fakeSocket),
          chatSocketConnectionProvider.overrideWith((ref) => Future<void>.value()),
          authControllerProvider.overrideWith(FakeAuthController.new),
          currentUserProvider.overrideWithValue(testUser),
          authTokenProvider.overrideWith((ref) => Future.value('dummy_token')),
        ],
      );
      addTearDown(container.dispose);

      const convId = 'conv_test_4';
      final sub = container.listen(conversationMessagesControllerProvider(convId), (_, __) {});
      addTearDown(sub.close);
      final controller = container.read(conversationMessagesControllerProvider(convId).notifier);
      await container.read(conversationMessagesControllerProvider(convId).future);

      const clientMsgId = 'c_failed_to_delete';

      fakeRepo.shouldFail = true;
      try {
        await controller.sendMessage(
          content: 'Failed to delete',
          clientMessageId: clientMsgId,
        );
      } catch (_) {}

      var state = container.read(conversationMessagesControllerProvider(convId)).value!;
      expect(state.messages.length, 1);
      final failedMsgId = state.messages.first.id;

      // Delete the failed message
      await controller.deleteMessage(failedMsgId);

      state = container.read(conversationMessagesControllerProvider(convId)).value!;
      expect(state.messages.isEmpty, isTrue);
      // Ensure backend removeMessage was NOT called for local failed message
      expect(fakeRepo.removeCallCount, 0);
    });
  });
}
