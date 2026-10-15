/// Tests for:
///   5. Chat cache clearAll on logout (mobile – file-based path_provider cache).
///   6. Cached messages with status=pending converted to failed on load.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:mobile_app/features/chat/data/chat_local_cache.dart';
import 'package:mobile_app/features/chat/models/chat_models.dart';
import 'package:mobile_app/features/chat/presentation/chat_overview_controller.dart';
import 'package:mobile_app/features/chat/data/chat_repository.dart';
import 'package:mobile_app/features/chat/data/chat_socket_service.dart';
import 'package:mobile_app/shared/providers/providers.dart';
import 'package:mobile_app/features/auth/presentation/auth_controller.dart';
import 'package:mobile_app/features/auth/data/auth_repository.dart';
import 'package:mobile_app/shared/models/app_user.dart';
import 'dart:async';

// ─── path_provider mock ─────────────────────────────────────────────────────

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory _dir;
  _FakePathProvider(this._dir);

  @override
  Future<String?> getApplicationSupportPath() async => _dir.path;

  @override
  Future<String?> getTemporaryPath() async => _dir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir.path;
}

// ─── Helpers ────────────────────────────────────────────────────────────────

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

ChatMessage _makeMsg({
  required String id,
  String? status,
  String? clientMessageId,
}) {
  final now = DateTime(2026, 9, 28, 10);
  return ChatMessage(
    id: id,
    conversationId: 'conv_1',
    senderId: 'user_1',
    sender: null,
    content: 'test',
    messageType: 'text',
    fileUrl: null,
    fileName: null,
    fileSize: null,
    mimeType: null,
    replyToMessageId: null,
    isDeleted: false,
    metadata: {
      if (status != null) 'status': status,
      if (clientMessageId != null) 'clientMessageId': clientMessageId,
    },
    createdAt: now,
    updatedAt: now,
    seenBy: const [],
    deliveredTo: const [],
  );
}

// ─── Fakes ──────────────────────────────────────────────────────────────────

class FakeChatRepository implements ChatRepository {
  final ChatLocalCache _cache;
  final List<ChatMessage> initialMessages;

  FakeChatRepository({
    required ChatLocalCache cache,
    this.initialMessages = const [],
  }) : _cache = cache;

  @override
  ChatLocalCache get cache => _cache;

  @override
  Future<ChatMessagesPage?> getCachedMessages(String conversationId) =>
      _cache.loadMessages(conversationId);

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
    throw UnimplementedError();
  }

  @override
  Future<void> removeMessage(String messageId) async {}

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

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('mobile_chat_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir);
  });

  tearDown(() async {
    // On Windows, file handles may still be held briefly after container dispose.
    // Best-effort cleanup; leftover tmp dirs are auto-removed by the OS.
    try {
      if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  // ── 5. clearAll ──────────────────────────────────────────────────────────

  group('ChatLocalCache.clearAll (point 5)', () {
    test('clearAll removes all JSON files from chat_cache directory', () async {
      final cache = ChatLocalCache();

      await cache.saveConversations([]);
      await cache.saveMessages(
        'conv_abc',
        ChatMessagesPage(messages: [_makeMsg(id: 'm1')], nextCursor: null, hasMore: false, limit: 40),
      );
      await cache.saveMessages(
        'conv_xyz',
        ChatMessagesPage(messages: [_makeMsg(id: 'm2')], nextCursor: null, hasMore: false, limit: 40),
      );

      expect(await cache.loadConversations(), isNotNull);
      expect(await cache.loadMessages('conv_abc'), isNotNull);
      expect(await cache.loadMessages('conv_xyz'), isNotNull);

      await cache.clearAll();

      expect(await cache.loadConversations(), isNull);
      expect(await cache.loadMessages('conv_abc'), isNull);
      expect(await cache.loadMessages('conv_xyz'), isNull);
    });

    test('clearAll on empty dir does not throw', () async {
      final cache = ChatLocalCache();
      await expectLater(cache.clearAll(), completes);
    });

    test('clearAll via provider removes cache data', () async {
      final cache = ChatLocalCache();
      await cache.saveMessages(
        'conv_seed',
        ChatMessagesPage(messages: [_makeMsg(id: 'seed_msg')], nextCursor: null, hasMore: false, limit: 40),
      );
      expect(await cache.loadMessages('conv_seed'), isNotNull);

      final fakeRepo = FakeChatRepository(cache: cache);
      final fakeSocket = FakeChatSocketService();
      final testUser = _createTestUser();

      final container = ProviderContainer(
        overrides: [
          chatLocalCacheProvider.overrideWithValue(cache),
          chatRepositoryProvider.overrideWithValue(fakeRepo),
          chatSocketServiceProvider.overrideWithValue(fakeSocket),
          chatSocketConnectionProvider.overrideWith((ref) => Future<void>.value()),
          authControllerProvider.overrideWith(FakeAuthController.new),
          currentUserProvider.overrideWithValue(testUser),
          authTokenProvider.overrideWith((ref) => Future.value('dummy_token')),
        ],
      );
      addTearDown(container.dispose);

      await container.read(chatLocalCacheProvider).clearAll();
      expect(await cache.loadMessages('conv_seed'), isNull);
    });
  });

  // ── 6. pending → failed on cache load ────────────────────────────────────

  group('_markPendingAsFailed (point 6)', () {
    test('pending messages from cache become failed in controller state', () async {
      final cache = ChatLocalCache();

      final pendingMsg = _makeMsg(id: 'temp_p', status: 'pending', clientMessageId: 'c1');
      final normalMsg  = _makeMsg(id: 'server_s');

      await cache.saveMessages(
        'conv_p6',
        ChatMessagesPage(messages: [pendingMsg, normalMsg], nextCursor: null, hasMore: false, limit: 40),
      );

      final fakeRepo   = FakeChatRepository(cache: cache, initialMessages: [normalMsg]);
      final fakeSocket = FakeChatSocketService();
      final testUser   = _createTestUser();

      final container = ProviderContainer(
        overrides: [
          chatLocalCacheProvider.overrideWithValue(cache),
          chatRepositoryProvider.overrideWithValue(fakeRepo),
          chatSocketServiceProvider.overrideWithValue(fakeSocket),
          chatSocketConnectionProvider.overrideWith((ref) => Future<void>.value()),
          authControllerProvider.overrideWith(FakeAuthController.new),
          currentUserProvider.overrideWithValue(testUser),
          authTokenProvider.overrideWith((ref) => Future.value('dummy_token')),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        conversationMessagesControllerProvider('conv_p6'),
        (_, __) {},
      );
      addTearDown(sub.close);

      final state = await container.read(
        conversationMessagesControllerProvider('conv_p6').future,
      );

      final wasP = state.messages.where((m) => m.id == 'temp_p').toList();
      expect(wasP.length, 1);
      expect(wasP.first.metadata?['status'], 'failed');

      final srvMsg = state.messages.where((m) => m.id == 'server_s').toList();
      expect(srvMsg.length, 1);
      expect(srvMsg.first.metadata?['status'], isNull);
    });

    test('already-failed messages stay failed', () async {
      final cache = ChatLocalCache();
      final failedMsg = _makeMsg(id: 'temp_f', status: 'failed', clientMessageId: 'c2');

      await cache.saveMessages(
        'conv_f6',
        ChatMessagesPage(messages: [failedMsg], nextCursor: null, hasMore: false, limit: 40),
      );

      final fakeRepo   = FakeChatRepository(cache: cache);
      final fakeSocket = FakeChatSocketService();
      final testUser   = _createTestUser();

      final container = ProviderContainer(
        overrides: [
          chatLocalCacheProvider.overrideWithValue(cache),
          chatRepositoryProvider.overrideWithValue(fakeRepo),
          chatSocketServiceProvider.overrideWithValue(fakeSocket),
          chatSocketConnectionProvider.overrideWith((ref) => Future<void>.value()),
          authControllerProvider.overrideWith(FakeAuthController.new),
          currentUserProvider.overrideWithValue(testUser),
          authTokenProvider.overrideWith((ref) => Future.value('dummy_token')),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        conversationMessagesControllerProvider('conv_f6'),
        (_, __) {},
      );
      addTearDown(sub.close);

      final state = await container.read(
        conversationMessagesControllerProvider('conv_f6').future,
      );
      expect(state.messages.first.metadata?['status'], 'failed');
    });

    test('regular server messages (no status key) remain untouched', () async {
      final cache = ChatLocalCache();
      final sentMsg = _makeMsg(id: 'server_sent');

      await cache.saveMessages(
        'conv_s6',
        ChatMessagesPage(messages: [sentMsg], nextCursor: null, hasMore: false, limit: 40),
      );

      final fakeRepo   = FakeChatRepository(cache: cache, initialMessages: [sentMsg]);
      final fakeSocket = FakeChatSocketService();
      final testUser   = _createTestUser();

      final container = ProviderContainer(
        overrides: [
          chatLocalCacheProvider.overrideWithValue(cache),
          chatRepositoryProvider.overrideWithValue(fakeRepo),
          chatSocketServiceProvider.overrideWithValue(fakeSocket),
          chatSocketConnectionProvider.overrideWith((ref) => Future<void>.value()),
          authControllerProvider.overrideWith(FakeAuthController.new),
          currentUserProvider.overrideWithValue(testUser),
          authTokenProvider.overrideWith((ref) => Future.value('dummy_token')),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        conversationMessagesControllerProvider('conv_s6'),
        (_, __) {},
      );
      addTearDown(sub.close);

      final state = await container.read(
        conversationMessagesControllerProvider('conv_s6').future,
      );
      expect(state.messages.first.metadata?['status'], isNull);
    });
  });
}
