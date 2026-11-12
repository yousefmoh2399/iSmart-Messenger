import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_app/core/network/api_client.dart';
import 'package:desktop_app/features/auth/data/session_store.dart';
import 'package:desktop_app/features/auth/presentation/auth_controller.dart';
import 'package:desktop_app/features/chat/data/chat_local_cache.dart';
import 'package:desktop_app/features/chat/data/chat_repository.dart';
import 'package:desktop_app/features/chat/data/chat_socket_service.dart';
import 'package:desktop_app/features/chat/models/chat_models.dart';
import 'package:desktop_app/shared/models/app_user.dart';
import 'package:desktop_app/shared/providers/providers.dart';
import 'package:desktop_app/shared/services/desktop_update_agent.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppUser _buildTestUser() {
  return AppUser(
    id: 'user_self',
    username: 'selfuser',
    fullName: 'Self User',
    role: 'user',
    departmentId: 'dept_1',
    branchId: 'branch_1',
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

ChatDirectoryUser _buildDirectoryUser(
  String id, {
  bool isOnline = false,
  String presenceStatus = 'offline',
}) {
  return ChatDirectoryUser(
    id: id,
    username: id,
    fullName: 'User $id',
    role: 'user',
    departmentId: 'dept_1',
    branchId: 'branch_1',
    branchCode: 'main',
    isOnline: isOnline,
    presenceStatus: presenceStatus,
    isActive: true,
    avatarUrl: null,
    lastSeen: null,
    lastActiveAt: null,
  );
}

ChatConversation _buildConversation(
  String id, {
  List<ChatDirectoryUser> members = const [],
}) {
  final now = DateTime(2026, 11, 11, 9, 0);
  return ChatConversation(
    id: id,
    type: 'direct',
    name: 'Conv $id',
    description: '',
    avatarUrl: null,
    departmentId: 'dept_1',
    createdBy: 'user_self',
    members: members,
    admins: const [],
    broadcastPublisherIds: const [],
    blockedMemberIds: const [],
    blockedMembers: const [],
    pinnedMessage: null,
    lastMessage: null,
    unreadCount: 0,
    isArchived: false,
    isMuted: false,
    mutedUntil: null,
    isPinned: false,
    isFavorite: false,
    isActive: true,
    isMember: true,
    membershipStatus: 'active',
    canSend: true,
    isBlocked: false,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeAuthController extends Notifier<AuthState> implements AuthController {
  @override
  AuthState build() {
    return AuthState(
      status: AuthStatus.authenticated,
      session: const StoredAuthSession(
        accessToken: 'dummy_token',
        refreshToken: 'dummy_refresh',
        userId: 'user_self',
        generation: 1,
      ),
      user: _buildTestUser(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChatSocketService implements ChatSocketService {
  final _controller = StreamController<ChatSocketEvent>.broadcast();
  int connectCount = 0;
  int disconnectCount = 0;
  final List<String> updatedTokens = <String>[];
  bool fakeConnected = true;

  void emit(ChatSocketEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  @override
  bool get isConnected => fakeConnected;

  @override
  Future<void> connect({
    required String baseUrl,
    required String token,
    String clientType = 'desktop',
    dynamic socketOverride,
  }) async {
    connectCount++;
    fakeConnected = true;
  }

  @override
  void disconnect({bool clearJoined = true}) {
    disconnectCount++;
    fakeConnected = false;
  }

  @override
  void updateAuthToken(String token) {
    updatedTokens.add(token);
  }

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
  void dispose() {
    _controller.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStormChatRepository implements ChatRepository {
  _FakeStormChatRepository({
    this.conversations = const [],
    this.users = const [],
    this.cachedMessagesCompleter,
  });

  final List<ChatConversation> conversations;
  final List<ChatDirectoryUser> users;
  final Completer<ChatMessagesPage?>? cachedMessagesCompleter;
  final Map<String, int> fetchMessagesCounts = {};
  int fetchConversationsCount = 0;

  @override
  final ChatLocalCache cache = ChatLocalCache();

  @override
  Future<List<ChatConversation>> fetchConversations() async {
    fetchConversationsCount++;
    return conversations;
  }

  @override
  Future<List<ChatConversation>> fetchManageableConversations() async =>
      const [];

  @override
  Future<List<DepartmentSummary>> fetchDepartments() async => const [
        DepartmentSummary(
          id: 'dept_1',
          name: 'IT',
          code: 'IT',
          description: '',
          managers: [],
          membersCount: 1,
          defaultConversationId: null,
        ),
      ];

  @override
  Future<List<BranchSummary>> fetchBranches() async => const [
        BranchSummary(
          id: 'branch_1',
          name: 'Main',
          code: 'main',
          description: '',
          membersCount: 1,
        ),
      ];

  @override
  Future<List<ChatRole>> fetchRoles() async => const [];

  @override
  Future<ChatDirectoryUsersPage> fetchUsersPage({
    String? search,
    String? departmentId,
    String? branchId,
    int? page,
    int? limit,
  }) async {
    return ChatDirectoryUsersPage(
      users: users,
      page: page ?? 1,
      limit: limit ?? 500,
      hasMore: false,
    );
  }

  @override
  Future<ChatMessagesPage?> getCachedMessages(String conversationId) async =>
      cachedMessagesCompleter != null
          ? cachedMessagesCompleter!.future
          : null;

  @override
  Future<ChatMessagesPage> fetchMessages(
    String conversationId, {
    String? cursor,
    int limit = 40,
    bool isScheduled = false,
  }) async {
    fetchMessagesCounts[conversationId] =
        (fetchMessagesCounts[conversationId] ?? 0) + 1;
    return const ChatMessagesPage(
      messages: [],
      nextCursor: null,
      hasMore: false,
      limit: 40,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingHttpClientAdapter implements HttpClientAdapter {
  _CountingHttpClientAdapter({required this.statusCode});

  int statusCode;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    return ResponseBody.fromString(
      '{"error":"simulated_$statusCode"}',
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('VPN & Morning Reconnect Storm Prevention', () {
    test(
      'ChatOverviewController batches rapid presence updates into a single AsyncData emission',
      () async {
        final peerA = _buildDirectoryUser('u_a');
        final peerB = _buildDirectoryUser('u_b');
        final fakeRepo = _FakeStormChatRepository(
          users: [peerA, peerB],
          conversations: [
            _buildConversation('c_ab', members: [peerA, peerB]),
          ],
        );
        final fakeSocket = _FakeChatSocketService();
        addTearDown(fakeSocket.dispose);

        final container = ProviderContainer(
          overrides: [
            chatRepositoryProvider.overrideWithValue(fakeRepo),
            chatSocketServiceProvider.overrideWithValue(fakeSocket),
            chatSocketConnectionProvider.overrideWith(
              (ref) => Future<void>.value(),
            ),
            authControllerProvider.overrideWith(_FakeAuthController.new),
            currentUserProvider.overrideWithValue(_buildTestUser()),
            authTokenProvider.overrideWith((ref) => Future.value('dummy_token')),
          ],
        );
        addTearDown(container.dispose);

        await container.read(chatOverviewControllerProvider.future);
        // Allow background loadAllUsers() microtask to finish before counting
        // presence batch emissions.
        await Future<void>.delayed(const Duration(milliseconds: 30));

        var dataEmissions = 0;
        final sub = container.listen(chatOverviewControllerProvider, (
          prev,
          next,
        ) {
          if (next is AsyncData<ChatOverviewData>) {
            dataEmissions++;
          }
        });
        addTearDown(sub.close);

        // Emit a burst of 12 presence events across both users inside <250ms.
        for (var i = 0; i < 6; i++) {
          fakeSocket.emit(
            const ChatSocketEvent(
              type: 'user_online',
              payload: {
                'userId': 'u_a',
                'isOnline': true,
                'presenceStatus': 'online',
              },
            ),
          );
          fakeSocket.emit(
            ChatSocketEvent(
              type: 'presence_updated',
              payload: {
                'userId': 'u_b',
                'isOnline': i.isEven,
                'presenceStatus': i.isEven ? 'idle' : 'offline',
              },
            ),
          );
        }

        // Before the 250ms window flushes, zero rebuild emissions occurred.
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(dataEmissions, 0);

        // Wait past the 250ms batching window.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(dataEmissions, 1);

        final overview = container
            .read(chatOverviewControllerProvider)
            .requireValue;
        final updatedA = overview.users.firstWhere((u) => u.id == 'u_a');
        final updatedB = overview.users.firstWhere((u) => u.id == 'u_b');
        expect(updatedA.isOnline, isTrue);
        expect(updatedA.presenceStatus, 'online');
        // Final event for u_b had i = 5 (odd) -> offline.
        expect(updatedB.isOnline, isFalse);
        expect(updatedB.presenceStatus, 'offline');

        // Conversation member snapshots are updated in lockstep.
        final convMemberA = overview.conversations.first.members.firstWhere(
          (m) => m.id == 'u_a',
        );
        expect(convMemberA.isOnline, isTrue);
      },
    );

    test(
      'ConversationMessagesController refreshes on socket_connected only for active conversation and lazily on switch',
      () async {
        final fakeRepo = _FakeStormChatRepository();
        final fakeSocket = _FakeChatSocketService();
        addTearDown(fakeSocket.dispose);

        final container = ProviderContainer(
          overrides: [
            chatRepositoryProvider.overrideWithValue(fakeRepo),
            chatSocketServiceProvider.overrideWithValue(fakeSocket),
            chatSocketConnectionProvider.overrideWith(
              (ref) => Future<void>.value(),
            ),
            authControllerProvider.overrideWith(_FakeAuthController.new),
            currentUserProvider.overrideWithValue(_buildTestUser()),
            authTokenProvider.overrideWith((ref) => Future.value('dummy_token')),
          ],
        );
        addTearDown(container.dispose);

        container.read(activeConversationIdProvider.notifier).state =
            'conv_active';

        final subActive = container.listen(
          conversationMessagesControllerProvider('conv_active'),
          (_, __) {},
        );
        final subInactive = container.listen(
          conversationMessagesControllerProvider('conv_inactive'),
          (_, __) {},
        );
        addTearDown(subActive.close);
        addTearDown(subInactive.close);

        await container.read(
          conversationMessagesControllerProvider('conv_active').future,
        );
        await container.read(
          conversationMessagesControllerProvider('conv_inactive').future,
        );

        expect(fakeRepo.fetchMessagesCounts['conv_active'], 1);
        expect(fakeRepo.fetchMessagesCounts['conv_inactive'], 1);

        // Simulate VPN socket reconnect while conv_active is focused.
        fakeSocket.emit(
          const ChatSocketEvent(type: 'socket_connected', payload: {}),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(fakeRepo.fetchMessagesCounts['conv_active'], 2);
        expect(
          fakeRepo.fetchMessagesCounts['conv_inactive'],
          1,
          reason: 'Inactive keepAlive conversations must not fetch on reconnect',
        );

        // Switching focus to conv_inactive triggers lazy catch-up refresh.
        container.read(activeConversationIdProvider.notifier).state =
            'conv_inactive';
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(fakeRepo.fetchMessagesCounts['conv_inactive'], 2);
      },
    );

    test(
      'appSettingsSocketSyncProvider throttles socket_connected bursts (>=5m) while applying app_settings_updated immediately',
      () async {
        final fakeSocket = _FakeChatSocketService();
        addTearDown(fakeSocket.dispose);

        final container = ProviderContainer(
          overrides: [
            chatSocketServiceProvider.overrideWithValue(fakeSocket),
          ],
        );
        addTearDown(container.dispose);

        container.read(appSettingsSocketSyncProvider);
        expect(container.read(appSettingsRevisionProvider), 0);

        // Burst of 5 reconnects within milliseconds -> only 1 bump.
        for (var i = 0; i < 5; i++) {
          fakeSocket.emit(
            const ChatSocketEvent(type: 'socket_connected', payload: {}),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(container.read(appSettingsRevisionProvider), 1);

        // Explicit settings push still updates immediately.
        fakeSocket.emit(
          const ChatSocketEvent(type: 'app_settings_updated', payload: {}),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(container.read(appSettingsRevisionProvider), 2);

        // Immediate reconnect after settings push remains throttled.
        fakeSocket.emit(
          const ChatSocketEvent(type: 'socket_connected', payload: {}),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(container.read(appSettingsRevisionProvider), 2);
      },
    );

    test(
      'DesktopUpdateAgent.computeAutoUpdateStagger spreads devices within 3..45 seconds',
      () {
        final uniqueBuckets = <int>{};
        for (var i = 0; i < 200; i++) {
          final uid = 'pc-branch-${i.toString().padLeft(3, '0')}-host';
          final delay = DesktopUpdateAgent.computeAutoUpdateStagger(
            uid,
            jitterSecondsOverride: 0,
          );
          expect(delay.inSeconds, inInclusiveRange(3, 45));
          uniqueBuckets.add(delay.inSeconds);
        }
        expect(uniqueBuckets.length, greaterThanOrEqualTo(10));

        // Clamping holds even with extreme overrides.
        expect(
          DesktopUpdateAgent.computeAutoUpdateStagger(
            'device-a',
            jitterSecondsOverride: 99,
          ).inSeconds,
          45,
        );
        expect(
          DesktopUpdateAgent.computeAutoUpdateStagger(
            'device-a',
            jitterSecondsOverride: -100,
          ).inSeconds,
          3,
        );
      },
    );

    test(
      'ApiClient skips auto-retry on 503 backpressure and caps GET 502 retries to 1',
      () async {
        final client503 = ApiClient(baseUrl: 'http://127.0.0.1:5000');
        final adapter503 = _CountingHttpClientAdapter(statusCode: 503);
        client503.dio.httpClientAdapter = adapter503;

        await expectLater(
          client503.dio.get<void>(
            '/api/chat/conversations',
            options: Options(extra: {'skipErrorLog': true}),
          ),
          throwsA(isA<DioException>()),
        );
        expect(
          adapter503.requestCount,
          1,
          reason: 'HTTP 503 must fail fast without amplifying backpressure',
        );

        final client502 = ApiClient(baseUrl: 'http://127.0.0.1:5000');
        final adapter502 = _CountingHttpClientAdapter(statusCode: 502);
        client502.dio.httpClientAdapter = adapter502;

        await expectLater(
          client502.dio.get<void>(
            '/api/chat/conversations',
            options: Options(extra: {'skipErrorLog': true}),
          ),
          throwsA(isA<DioException>()),
        );
        expect(
          adapter502.requestCount,
          2,
          reason: 'Transient 502 on GET retries at most once (initial + 1 retry)',
        );
      },
    );

    test(
      'Silent authCredentialsRevisionProvider bump does not rebuild ChatOverview or kept-alive conversations',
      () async {
        final fakeRepo = _FakeStormChatRepository(
          conversations: [
            _buildConversation('conv_1'),
            _buildConversation('conv_2'),
          ],
        );
        final fakeSocket = _FakeChatSocketService();
        addTearDown(fakeSocket.dispose);

        final container = ProviderContainer(
          overrides: [
            chatRepositoryProvider.overrideWithValue(fakeRepo),
            chatSocketServiceProvider.overrideWithValue(fakeSocket),
            chatSocketConnectionProvider.overrideWith(
              (ref) => Future<void>.value(),
            ),
            authControllerProvider.overrideWith(_FakeAuthController.new),
            currentUserProvider.overrideWithValue(_buildTestUser()),
            authTokenProvider.overrideWith((ref) async {
              final rev = ref.watch(authCredentialsRevisionProvider);
              return 'token_rev_$rev';
            }),
          ],
        );
        addTearDown(container.dispose);

        await container.read(chatOverviewControllerProvider.future);
        await container.read(
          conversationMessagesControllerProvider('conv_1').future,
        );
        await container.read(
          conversationMessagesControllerProvider('conv_2').future,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(fakeRepo.fetchConversationsCount, 1);
        expect(fakeRepo.fetchMessagesCounts['conv_1'], 1);
        expect(fakeRepo.fetchMessagesCounts['conv_2'], 1);

        // Simulate two silent token refreshes.
        container.read(authCredentialsRevisionProvider.notifier).state++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        container.read(authCredentialsRevisionProvider.notifier).state++;
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          fakeRepo.fetchConversationsCount,
          1,
          reason: 'Overview must not reload on silent token rotation',
        );
        expect(fakeRepo.fetchMessagesCounts['conv_1'], 1);
        expect(fakeRepo.fetchMessagesCounts['conv_2'], 1);
      },
    );

    test(
      'Real chatSocketConnectionProvider updates token without disconnecting live socket on silent JWT refresh',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'desktop_api_base_url_v2': 'http://127.0.0.2:15100',
          'desktop_api_base_url_override_v1': true,
        });
        final fakeSocket = _FakeChatSocketService();
        addTearDown(fakeSocket.dispose);

        final container = ProviderContainer(
          overrides: [
            chatSocketServiceProvider.overrideWithValue(fakeSocket),
            appSettingsSocketSyncProvider.overrideWith((ref) {}),
            authControllerProvider.overrideWith(_FakeAuthController.new),
            currentUserProvider.overrideWithValue(_buildTestUser()),
            authTokenProvider.overrideWith((ref) async {
              final rev = ref.watch(authCredentialsRevisionProvider);
              return 'jwt_generation_$rev';
            }),
          ],
        );
        addTearDown(container.dispose);

        await container.read(chatSocketConnectionProvider.future);
        expect(fakeSocket.connectCount, 1);
        expect(fakeSocket.disconnectCount, 0);

        // Rotate silent JWT token twice while socket stays healthy.
        container.read(authCredentialsRevisionProvider.notifier).state++;
        await Future<void>.delayed(const Duration(milliseconds: 25));
        container.read(authCredentialsRevisionProvider.notifier).state++;
        await Future<void>.delayed(const Duration(milliseconds: 25));

        expect(
          fakeSocket.connectCount,
          1,
          reason: 'Live socket must NOT disconnect/reconnect on silent JWT rotation',
        );
        expect(fakeSocket.disconnectCount, 0);
        expect(
          fakeSocket.updatedTokens,
          ['jwt_generation_1', 'jwt_generation_2'],
        );
      },
    );

    test(
      'ConversationMessagesController skips redundant skipIfFresh refresh right after initial fetch',
      () async {
        final fakeRepo = _FakeStormChatRepository(
          conversations: [_buildConversation('conv_dup')],
        );
        final fakeSocket = _FakeChatSocketService();
        addTearDown(fakeSocket.dispose);

        final container = ProviderContainer(
          overrides: [
            chatRepositoryProvider.overrideWithValue(fakeRepo),
            chatSocketServiceProvider.overrideWithValue(fakeSocket),
            chatSocketConnectionProvider.overrideWith(
              (ref) => Future<void>.value(),
            ),
            authControllerProvider.overrideWith(_FakeAuthController.new),
            currentUserProvider.overrideWithValue(_buildTestUser()),
            authTokenProvider.overrideWith((ref) async => 'tok_1'),
          ],
        );
        addTearDown(container.dispose);

        await container.read(
          conversationMessagesControllerProvider('conv_dup').future,
        );
        expect(fakeRepo.fetchMessagesCounts['conv_dup'], 1);

        // ChatScreen postFrameCallback calls refresh(skipIfFresh: true)
        await container
            .read(conversationMessagesControllerProvider('conv_dup').notifier)
            .refresh(skipIfFresh: true);
        expect(fakeRepo.fetchMessagesCounts['conv_dup'], 1);

        // Explicit forced refresh still executes cleanly
        await container
            .read(conversationMessagesControllerProvider('conv_dup').notifier)
            .refresh();
        expect(fakeRepo.fetchMessagesCounts['conv_dup'], 2);
      },
    );

    test(
      'ConversationMessagesController skips refresh(skipIfFresh: true) called during async build prologue',
      () async {
        final cacheGate = Completer<ChatMessagesPage?>();
        final fakeRepo = _FakeStormChatRepository(
          conversations: [_buildConversation('conv_async')],
          cachedMessagesCompleter: cacheGate,
        );
        final fakeSocket = _FakeChatSocketService();
        addTearDown(fakeSocket.dispose);

        final container = ProviderContainer(
          overrides: [
            chatRepositoryProvider.overrideWithValue(fakeRepo),
            chatSocketServiceProvider.overrideWithValue(fakeSocket),
            chatSocketConnectionProvider.overrideWith(
              (ref) => Future<void>.value(),
            ),
            authControllerProvider.overrideWith(_FakeAuthController.new),
            currentUserProvider.overrideWithValue(_buildTestUser()),
            authTokenProvider.overrideWith((ref) async => 'tok_1'),
          ],
        );
        addTearDown(container.dispose);

        // Start initial build; it pauses at getCachedMessages('conv_async').
        final buildFuture = container.read(
          conversationMessagesControllerProvider('conv_async').future,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Simulate ChatScreen.initState addPostFrameCallback firing while build awaits cache.
        await container
            .read(conversationMessagesControllerProvider('conv_async').notifier)
            .refresh(skipIfFresh: true);
        expect(fakeRepo.fetchMessagesCounts['conv_async'] ?? 0, 0);

        cacheGate.complete(null);
        await buildFuture;

        expect(
          fakeRepo.fetchMessagesCounts['conv_async'],
          1,
          reason:
              'Initial build prologue must shield against duplicate Frame-1 skipIfFresh refresh',
        );
      },
    );
  });
}
