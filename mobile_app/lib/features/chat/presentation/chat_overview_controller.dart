import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/providers/providers.dart';
import '../data/chat_repository.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import '../utils/chat_reaction_emoji_stats.dart';

class ChatOverviewController extends AsyncNotifier<ChatOverviewData> {
  void resetState() { state = const AsyncLoading(); }

  StreamSubscription<ChatSocketEvent>? _eventsSubscription;
  ChatRepository? _chatRepository;
  ChatSocketService? _chatSocketService;
  String _currentUserId = '';
  bool _disposed = false;
  int _usersPage = 1;
  bool _hasMoreUsers = false;
  bool _loadingMoreUsers = false;
  Future<void>? _refreshFuture;

  ChatRepository _repository() =>
      _chatRepository ?? ref.read(chatRepositoryProvider);

  Future<T> _guardAuth<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      if (error is ApiException && error.isUnauthorized) {
        Future<void>.microtask(
          () => ref.read(authControllerProvider.notifier).logout(),
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<ChatOverviewData> build() async {
    ref.watch(serverRecoveryRevisionProvider);
    await ref.watch(chatSocketConnectionProvider.future);
    _chatRepository = ref.read(chatRepositoryProvider);
    _chatSocketService = ref.read(chatSocketServiceProvider);
    _currentUserId = ref.read(authControllerProvider).valueOrNull?.id ?? '';
    _disposed = false;
    _listenToSocket();
    ref.onDispose(() {
      _disposed = true;
      _eventsSubscription?.cancel();
    });
    return _loadOverview();
  }

  Future<ChatOverviewData> _loadOverview() async {
    final repository = _repository();
    final conversations = await _guardAuth(repository.fetchConversations);
    final usersPage = await _guardAuth(repository.fetchUsersPage);
    _usersPage = usersPage.page;
    _hasMoreUsers = usersPage.hasMore;
    final departments = await _guardAuth(repository.fetchDepartments);
    final branches = await _guardAuth(repository.fetchBranches);

    Future<List<T>> safeList<T>(Future<List<T>> Function() loader) async {
      try {
        return await _guardAuth(loader);
      } catch (error) {
        if (error is ApiException && error.isUnauthorized) {
          rethrow;
        }
        return <T>[];
      }
    }

    final manageableConversations = await safeList(
      repository.fetchManageableConversations,
    );
    final roles = await safeList(repository.fetchRoles);

    return ChatOverviewData(
      conversations: conversations,
      manageableConversations: manageableConversations,
      users: usersPage.users,
      departments: departments,
      branches: branches,
      roles: roles,
    );
  }

  Future<void> loadMoreUsers() async {
    final current = state.valueOrNull;
    if (current == null || !_hasMoreUsers || _loadingMoreUsers) {
      return;
    }
    _loadingMoreUsers = true;
    try {
      final page = await _guardAuth(
        () => _repository().fetchUsersPage(page: _usersPage + 1),
      );
      _usersPage = page.page;
      _hasMoreUsers = page.hasMore;
      final byId = <String, ChatDirectoryUser>{
        for (final user in current.users) user.id: user,
        for (final user in page.users) user.id: user,
      };
      state = AsyncData(
        _copyOverview(source: current, users: byId.values.toList()),
      );
    } finally {
      _loadingMoreUsers = false;
    }
  }

  void _listenToSocket() {
    _eventsSubscription?.cancel();
    final socketService = _chatSocketService;
    if (socketService == null) {
      return;
    }

    _eventsSubscription = socketService.events.listen((event) {
      if (event.type == 'receive_message') {
        _applyIncomingMessage(ChatMessage.fromJson(event.payload));
        return;
      }

      if (event.type == 'socket_connected') {
        if (state.isLoading && state.valueOrNull == null) {
          return;
        }
        Future<void>.microtask(() async {
          if (_disposed) {
            return;
          }
          await refresh();
        });
        return;
      }

      if (event.type == 'message_seen') {
        _applySeenUpdate(
          conversationId: event.payload['conversationId']?.toString(),
          userId: event.payload['userId']?.toString(),
        );
        return;
      }

      if (event.type == 'message_deleted') {
        _applyMessageDeleted(event.payload['conversationId']?.toString());
        return;
      }

      if (event.type == 'message_updated') {
        _applyMessageUpdated(ChatMessage.fromJson(event.payload));
        return;
      }

      if (event.type == 'conversation_updated' && event.payload['id'] != null) {
        _applyConversationUpdate(ChatConversation.fromJson(event.payload));
        return;
      }

      if (event.type == 'conversation_deleted') {
        _applyConversationDeleted(event.payload['conversationId']?.toString());
        return;
      }

      if (event.type == 'conversation_state_changed') {
        _applyConversationStateUpdate(
          conversationId: event.payload['conversationId']?.toString(),
          isActive: event.payload['isActive'] == true,
        );
        return;
      }

      if (event.type == 'unread_count_updated') {
        _applyUnreadCountUpdate(
          conversationId: event.payload['conversationId']?.toString(),
          unreadCount: event.payload['unreadCount'] as int? ?? 0,
        );
        return;
      }

      if (event.type == 'user_profile_updated') {
        _applyUserProfileUpdate(event.payload);
        return;
      }

      if (event.type == 'presence_updated' ||
          event.type == 'user_online' ||
          event.type == 'user_offline') {
        _applyPresenceUpdate(event);
      }
    });
  }

  ChatOverviewData _copyOverview({
    required ChatOverviewData source,
    List<ChatConversation>? conversations,
    List<ChatConversation>? manageableConversations,
    List<ChatDirectoryUser>? users,
  }) {
    return ChatOverviewData(
      conversations: conversations ?? source.conversations,
      manageableConversations:
          manageableConversations ?? source.manageableConversations,
      users: users ?? source.users,
      departments: source.departments,
      branches: source.branches,
      roles: source.roles,
    );
  }

  ChatDirectoryUser _copyProfileUser(
    ChatDirectoryUser source,
    ChatDirectoryUser updated,
  ) {
    return ChatDirectoryUser(
      id: source.id,
      username: updated.username.isNotEmpty
          ? updated.username
          : source.username,
      fullName: updated.fullName.isNotEmpty
          ? updated.fullName
          : source.fullName,
      role: updated.role.isNotEmpty ? updated.role : source.role,
      departmentId: updated.departmentId,
      branchId: updated.branchId,
      branchCode: updated.branchCode,
      isOnline: source.isOnline,
      presenceStatus: source.presenceStatus,
      isActive: updated.isActive,
      avatarUrl: updated.avatarUrl,
      lastSeen: source.lastSeen,
      lastActiveAt: source.lastActiveAt,
    );
  }

  void _applyUserProfileUpdate(Map<String, dynamic> payload) {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    final rawUser = payload['user'];
    if (rawUser is! Map) {
      return;
    }
    final updatedUser = ChatDirectoryUser.fromJson(
      Map<String, dynamic>.from(rawUser),
    );

    List<ChatDirectoryUser> updateUsersInDirectory(
      List<ChatDirectoryUser> users,
    ) {
      final exists = users.any((user) => user.id == updatedUser.id);
      if (!exists) {
        return [...users, updatedUser];
      }
      return users
          .map(
            (user) => user.id == updatedUser.id
                ? _copyProfileUser(user, updatedUser)
                : user,
          )
          .toList();
    }

    List<ChatDirectoryUser> updateUsersInConversation(
      List<ChatDirectoryUser> users,
    ) {
      return users
          .map(
            (user) => user.id == updatedUser.id
                ? _copyProfileUser(user, updatedUser)
                : user,
          )
          .toList();
    }

    List<ChatConversation> updateConversations(
      List<ChatConversation> conversations,
    ) {
      return conversations
          .map(
            (conversation) => conversation.copyWith(
              members: updateUsersInConversation(conversation.members),
              admins: updateUsersInConversation(conversation.admins),
            ),
          )
          .toList();
    }

    state = AsyncData(
      ChatOverviewData(
        conversations: updateConversations(current.conversations),
        manageableConversations: updateConversations(
          current.manageableConversations,
        ),
        users: updateUsersInDirectory(current.users),
        departments: current.departments,
        branches: current.branches,
        roles: current.roles,
      ),
    );
  }

  ChatLastMessage _buildLastMessage(ChatMessage message) {
    return ChatLastMessage(
      content: message.content.isNotEmpty
          ? message.content
          : (message.fileName ?? 'مرفق'),
      senderId: message.sender?.id ?? message.senderId,
      senderName: message.sender?.displayName ?? '',
      messageType: message.messageType,
      createdAt: message.createdAt,
    );
  }

  List<ChatConversation> _sortConversations(List<ChatConversation> source) {
    // Deduplicate by ID, keeping the latest one
    final Map<String, ChatConversation> uniqueConversations = {};
    for (final c in source) {
      if (!uniqueConversations.containsKey(c.id)) {
        uniqueConversations[c.id] = c;
      } else {
        final existing = uniqueConversations[c.id]!;
        final newTime = _conversationActivityAt(c);
        final existingTime = _conversationActivityAt(existing);
        if (newTime.isAfter(existingTime)) {
          uniqueConversations[c.id] = c;
        }
      }
    }
    final deduplicatedSource = uniqueConversations.values.toList();

    final active = deduplicatedSource
        .where((conversation) => !conversation.isArchived)
        .toList();
    final archived = deduplicatedSource
        .where((conversation) => conversation.isArchived)
        .toList();

    int byPinnedThenRecent(ChatConversation a, ChatConversation b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return _conversationActivityAt(b).compareTo(_conversationActivityAt(a));
    }

    active.sort(byPinnedThenRecent);
    archived.sort(byPinnedThenRecent);
    return [...active, ...archived];
  }

  DateTime _conversationActivityAt(ChatConversation conversation) {
    return conversation.lastMessage?.createdAt ?? conversation.updatedAt;
  }

  ChatDirectoryUser _copyPresenceUser(
    ChatDirectoryUser source, {
    required bool isOnline,
    required String presenceStatus,
    DateTime? lastSeen,
    DateTime? lastActiveAt,
  }) {
    return ChatDirectoryUser(
      id: source.id,
      username: source.username,
      fullName: source.fullName,
      role: source.role,
      departmentId: source.departmentId,
      branchId: source.branchId,
      branchCode: source.branchCode,
      isOnline: isOnline,
      presenceStatus: presenceStatus,
      isActive: source.isActive,
      avatarUrl: source.avatarUrl,
      lastSeen: lastSeen ?? source.lastSeen,
      lastActiveAt: lastActiveAt ?? source.lastActiveAt,
    );
  }

  void _applyPresenceUpdate(ChatSocketEvent event) {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    final userId = event.payload['userId']?.toString();
    if (userId == null || userId.isEmpty) {
      return;
    }

    final isOnline =
        event.payload['isOnline'] as bool? ?? event.type == 'user_online';
    final presenceStatus =
        event.payload['presenceStatus']?.toString() ??
        (isOnline ? 'online' : 'offline');
    final lastSeen = event.payload['lastSeen'] is String
        ? DateTime.tryParse(event.payload['lastSeen'] as String)
        : null;
    final lastActiveAt = event.payload['lastActiveAt'] is String
        ? DateTime.tryParse(event.payload['lastActiveAt'] as String)
        : null;

    state = AsyncData(
      ChatOverviewData(
        conversations: current.conversations
            .map(
              (conversation) => conversation.copyWith(
                members: conversation.members
                    .map(
                      (member) => member.id == userId
                          ? _copyPresenceUser(
                              member,
                              isOnline: isOnline,
                              presenceStatus: presenceStatus,
                              lastSeen: lastSeen,
                              lastActiveAt: lastActiveAt,
                            )
                          : member,
                    )
                    .toList(),
              ),
            )
            .toList(),
        manageableConversations: current.manageableConversations
            .map(
              (conversation) => conversation.copyWith(
                members: conversation.members
                    .map(
                      (member) => member.id == userId
                          ? _copyPresenceUser(
                              member,
                              isOnline: isOnline,
                              presenceStatus: presenceStatus,
                              lastSeen: lastSeen,
                              lastActiveAt: lastActiveAt,
                            )
                          : member,
                    )
                    .toList(),
              ),
            )
            .toList(),
        users: current.users
            .map(
              (user) => user.id == userId
                  ? _copyPresenceUser(
                      user,
                      isOnline: isOnline,
                      presenceStatus: presenceStatus,
                      lastSeen: lastSeen,
                      lastActiveAt: lastActiveAt,
                    )
                  : user,
            )
            .toList(),
        departments: current.departments,
        branches: current.branches,
        roles: current.roles,
      ),
    );
  }

  void _applyIncomingMessage(ChatMessage message) {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    final index = current.conversations.indexWhere(
      (conversation) => conversation.id == message.conversationId,
    );

    if (index == -1) {
      Future<void>.microtask(() async {
        try {
          final repository = _repository();
          final conversation = await repository.fetchConversation(
            message.conversationId,
          );
          final latest = state.valueOrNull;
          if (latest == null ||
              latest.conversations.any(
                (entry) => entry.id == conversation.id,
              )) {
            return;
          }

          final inserted = conversation.copyWith(
            lastMessage: _buildLastMessage(message),
            unreadCount: message.sender?.id == _currentUserId ? 0 : 1,
            updatedAt: message.createdAt,
          );

          state = AsyncData(
            _copyOverview(
              source: latest,
              conversations: _sortConversations([
                inserted,
                ...latest.conversations,
              ]),
            ),
          );
        } catch (_) {}
      });
      return;
    }

    final activeConversationId = ref.read(activeConversationIdProvider);
    final isAppVisible = ref.read(chatAppVisibilityProvider);
    final isActiveConversation =
        activeConversationId == message.conversationId && isAppVisible;
    final updated = [...current.conversations];
    final existing = updated[index];
    updated[index] = existing.copyWith(
      lastMessage: _buildLastMessage(message),
      unreadCount: message.sender?.id == _currentUserId || isActiveConversation
          ? 0
          : existing.unreadCount + 1,
      updatedAt: message.createdAt,
    );

    state = AsyncData(
      _copyOverview(
        source: current,
        conversations: _sortConversations(updated),
      ),
    );

    if (isActiveConversation && message.sender?.id != _currentUserId) {
      Future<void>.microtask(() async {
        if (_disposed) {
          return;
        }
        _chatSocketService?.markSeen(message.conversationId);
        try {
          await _repository().markConversationSeen(message.conversationId);
        } catch (_) {}
      });
    }
  }

  void _applyMessageUpdated(ChatMessage message) {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    final updated = current.conversations.map((conversation) {
      if (conversation.id != message.conversationId) {
        return conversation;
      }

      final lastMessage = conversation.lastMessage;
      if (lastMessage == null || lastMessage.senderId != message.sender?.id) {
        return conversation;
      }

      final sameTimestamp =
          lastMessage.createdAt == null ||
          lastMessage.createdAt!.isAtSameMomentAs(message.createdAt);

      if (!sameTimestamp) {
        return conversation;
      }

      return conversation.copyWith(lastMessage: _buildLastMessage(message));
    }).toList();

    state = AsyncData(_copyOverview(source: current, conversations: updated));
  }

  void _applyMessageDeleted(String? conversationId) {
    if (conversationId == null) {
      return;
    }
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    final updated = current.conversations.map((conversation) {
      if (conversation.id != conversationId ||
          conversation.lastMessage == null) {
        return conversation;
      }
      return conversation.copyWith(
        lastMessage: ChatLastMessage(
          content: 'تم حذف رسالة',
          senderId: conversation.lastMessage!.senderId,
          senderName: conversation.lastMessage!.senderName,
          messageType: 'system',
          createdAt: conversation.lastMessage!.createdAt,
        ),
      );
    }).toList();

    state = AsyncData(_copyOverview(source: current, conversations: updated));
  }

  void _applySeenUpdate({
    required String? conversationId,
    required String? userId,
  }) {
    final current = state.valueOrNull;
    if (current == null || conversationId == null || userId == null) {
      return;
    }

    if (userId != _currentUserId) {
      return;
    }

    final updated = current.conversations
        .map(
          (conversation) => conversation.id == conversationId
              ? conversation.copyWith(unreadCount: 0)
              : conversation,
        )
        .toList();

    state = AsyncData(_copyOverview(source: current, conversations: updated));
  }

  void _applyConversationUpdate(ChatConversation conversation) {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    final updated = [...current.conversations];
    final index = updated.indexWhere((entry) => entry.id == conversation.id);
    if (index == -1) {
      updated.insert(0, conversation);
    } else {
      updated[index] = conversation.copyWith(
        unreadCount: updated[index].unreadCount,
      );
    }

    final manageable = [...current.manageableConversations];
    final manageableIndex = manageable.indexWhere(
      (entry) => entry.id == conversation.id,
    );
    if (manageableIndex != -1) {
      manageable[manageableIndex] = conversation.copyWith(
        unreadCount: manageable[manageableIndex].unreadCount,
      );
    }

    state = AsyncData(
      _copyOverview(
        source: current,
        conversations: _sortConversations(updated),
        manageableConversations: _sortConversations(manageable),
      ),
    );
  }

  void _applyUnreadCountUpdate({
    required String? conversationId,
    required int unreadCount,
  }) {
    final current = state.valueOrNull;
    if (current == null || conversationId == null) {
      return;
    }

    state = AsyncData(
      _copyOverview(
        source: current,
        conversations: current.conversations
            .map(
              (conversation) => conversation.id == conversationId
                  ? conversation.copyWith(unreadCount: unreadCount)
                  : conversation,
            )
            .toList(),
      ),
    );
  }

  void _applyConversationDeleted(String? conversationId) {
    final current = state.valueOrNull;
    if (current == null || conversationId == null || conversationId.isEmpty) {
      return;
    }

    state = AsyncData(
      _copyOverview(
        source: current,
        conversations: current.conversations
            .where((conversation) => conversation.id != conversationId)
            .toList(),
        manageableConversations: current.manageableConversations
            .where((conversation) => conversation.id != conversationId)
            .toList(),
      ),
    );
  }

  void _applyConversationStateUpdate({
    required String? conversationId,
    required bool isActive,
  }) {
    final current = state.valueOrNull;
    if (current == null || conversationId == null || conversationId.isEmpty) {
      return;
    }

    state = AsyncData(
      _copyOverview(
        source: current,
        conversations: current.conversations
            .map(
              (conversation) => conversation.id == conversationId
                  ? conversation.copyWith(isActive: isActive)
                  : conversation,
            )
            .toList(),
        manageableConversations: current.manageableConversations
            .map(
              (conversation) => conversation.id == conversationId
                  ? conversation.copyWith(isActive: isActive)
                  : conversation,
            )
            .toList(),
      ),
    );
  }

  Future<void> refresh({bool showLoader = false}) async {
    final activeRefresh = _refreshFuture;
    if (activeRefresh != null && !showLoader) {
      return activeRefresh;
    }
    final future = _refreshInternal(showLoader: showLoader);
    _refreshFuture = future;
    try {
      await future;
    } finally {
      if (identical(_refreshFuture, future)) {
        _refreshFuture = null;
      }
    }
  }

  Future<void> _refreshInternal({required bool showLoader}) async {
    if (_disposed) {
      return;
    }
    final previous = state.valueOrNull;
    if (showLoader || previous == null) {
      state = const AsyncLoading();
    }
    final next = await AsyncValue.guard(() => _guardAuth(_loadOverview));
    if (_disposed) {
      return;
    }
    if (next.hasError && previous != null) {
      state = AsyncData(previous);
      return;
    }
    state = next;
  }

  Future<ChatConversation> createDirectConversation(String userId) async {
    final repository = _repository();
    final conversation = await repository.createDirectConversation(userId);
    unawaited(refresh());
    return conversation;
  }

  Future<ChatConversation> createConversation({
    required String type,
    required String name,
    String description = '',
    List<String> memberIds = const [],
    List<String> adminIds = const [],
    String? departmentId,
  }) async {
    final repository = _repository();
    final conversation = await repository.createConversation(
      type: type,
      name: name,
      description: description,
      memberIds: memberIds,
      adminIds: adminIds,
      departmentId: departmentId,
    );
    unawaited(refresh());
    return conversation;
  }

  Future<ChatConversation> updateConversationPreferences({
    required String conversationId,
    bool? isMuted,
    bool? isArchived,
    bool? isPinned,
    bool? isFavorite,
  }) async {
    final repository = _repository();
    final conversation = await repository.updateConversationPreferences(
      conversationId: conversationId,
      isMuted: isMuted,
      isArchived: isArchived,
      isPinned: isPinned,
      isFavorite: isFavorite,
    );
    _applyConversationUpdate(conversation);
    return conversation;
  }

  Future<ChatConversation> setGroupPinnedMessage({
    required String conversationId,
    required String content,
    String? messageId,
  }) async {
    final conversation = await _repository().setGroupPinnedMessage(
      conversationId: conversationId,
      content: content,
      messageId: messageId,
    );
    _applyConversationUpdate(conversation);
    return conversation;
  }

  Future<ChatConversation> clearGroupPinnedMessage({
    required String conversationId,
  }) async {
    final conversation = await _repository().clearGroupPinnedMessage(
      conversationId: conversationId,
    );
    _applyConversationUpdate(conversation);
    return conversation;
  }

  Future<void> leaveConversation(String conversationId) async {
    await _guardAuth(() => _repository().leaveConversation(conversationId));
    await refresh();
  }

  Future<void> deleteConversation(
    String conversationId, {
    bool deleteForEveryone = false,
  }) async {
    try {
      final conversation = await _guardAuth(
        () => _repository().deleteConversation(
          conversationId,
          deleteForEveryone: deleteForEveryone,
        ),
      );
      if (conversation != null) {
        _applyConversationUpdate(conversation);
        return;
      }
      await refresh();
    } catch (error) {
      final isNotFound =
          error is ApiException &&
          error.statusCode == 404 &&
          !deleteForEveryone;
      if (isNotFound) {
        await refresh();
        return;
      }
      rethrow;
    }
  }

  Future<List<ChatAuditLog>> fetchAuditLogs({
    String? departmentId,
    int limit = 100,
  }) {
    final repository = _repository();
    return repository.fetchAuditLogs(departmentId: departmentId, limit: limit);
  }

  Future<List<ChatSystemError>> fetchSystemErrors({
    int limit = 100,
    int? statusCode,
  }) {
    final repository = _repository();
    return repository.fetchSystemErrors(limit: limit, statusCode: statusCode);
  }

  Future<void> createDepartment({
    required String name,
    required String code,
    String description = '',
  }) async {
    final repository = _repository();
    await repository.createDepartment(
      name: name,
      code: code,
      description: description,
    );
    await refresh();
  }

  Future<void> updateDepartment({
    required String departmentId,
    required String name,
    required String code,
    String description = '',
    List<String> managers = const [],
  }) async {
    final repository = _repository();
    await repository.updateDepartment(
      departmentId: departmentId,
      name: name,
      code: code,
      description: description,
      managers: managers,
    );
    await refresh();
  }

  Future<void> deleteDepartment(String departmentId) async {
    final repository = _repository();
    await repository.deleteDepartment(departmentId);
    await refresh();
  }

  Future<void> createBranch({
    required String name,
    required String code,
    String description = '',
  }) async {
    final repository = _repository();
    await repository.createBranch(
      name: name,
      code: code,
      description: description,
    );
    await refresh();
  }

  Future<void> updateBranch({
    required String branchId,
    required String name,
    required String code,
    String description = '',
  }) async {
    final repository = _repository();
    await repository.updateBranch(
      branchId: branchId,
      name: name,
      code: code,
      description: description,
    );
    await refresh();
  }

  Future<void> deleteBranch(String branchId) async {
    final repository = _repository();
    await repository.deleteBranch(branchId);
    await refresh();
  }

  Future<void> updateRole({
    required String roleId,
    required ChatPermissionSet permissions,
  }) async {
    final repository = _repository();
    await repository.updateRolePermissions(
      roleId: roleId,
      permissions: permissions,
    );
    await refresh();
  }

  Future<void> updateManagedConversation({
    required String conversationId,
    String? name,
    String? description,
    List<String>? memberIds,
    List<String>? adminIds,
    bool? isArchived,
    bool? isActive,
  }) async {
    final repository = _repository();
    await repository.updateManagedConversation(
      conversationId: conversationId,
      name: name,
      description: description,
      memberIds: memberIds,
      adminIds: adminIds,
      isArchived: isArchived,
      isActive: isActive,
    );
    await refresh();
  }

  Future<void> deleteManagedConversation(String conversationId) async {
    final repository = _repository();
    await repository.deleteManagedConversation(conversationId);
    await refresh();
  }

  Future<ChatConversation> addGroupMembers({
    required String conversationId,
    required List<String> userIds,
  }) async {
    final conversation = await _repository().addGroupMembers(
      conversationId: conversationId,
      userIds: userIds,
    );
    _applyConversationUpdate(conversation);
    return conversation;
  }

  Future<ChatConversation> removeGroupMember({
    required String conversationId,
    required String userId,
  }) async {
    final conversation = await _repository().removeGroupMember(
      conversationId: conversationId,
      userId: userId,
    );
    _applyConversationUpdate(conversation);
    return conversation;
  }

  Future<ChatConversation> promoteGroupAdmin({
    required String conversationId,
    required String userId,
  }) async {
    final conversation = await _repository().promoteGroupAdmin(
      conversationId: conversationId,
      userId: userId,
    );
    _applyConversationUpdate(conversation);
    return conversation;
  }

  Future<ChatConversation> demoteGroupAdmin({
    required String conversationId,
    required String userId,
  }) async {
    final conversation = await _repository().demoteGroupAdmin(
      conversationId: conversationId,
      userId: userId,
    );
    _applyConversationUpdate(conversation);
    return conversation;
  }

  Future<ChatConversation> blockGroupMember({
    required String conversationId,
    required String userId,
  }) async {
    final conversation = await _repository().blockGroupMember(
      conversationId: conversationId,
      userId: userId,
    );
    _applyConversationUpdate(conversation);
    return conversation;
  }

  Future<ChatConversation> unblockGroupMember({
    required String conversationId,
    required String userId,
  }) async {
    final conversation = await _repository().unblockGroupMember(
      conversationId: conversationId,
      userId: userId,
    );
    _applyConversationUpdate(conversation);
    return conversation;
  }
}

class ConversationMessagesController
    extends AutoDisposeFamilyAsyncNotifier<ConversationMessagesState, String> {
  StreamSubscription<ChatSocketEvent>? _eventsSubscription;
  ChatSocketService? _socketService;
  ChatRepository? _chatRepository;
  bool _isRefreshing = false;
  bool _disposed = false;
  ChatRepository _repository() =>
      _chatRepository ?? ref.read(chatRepositoryProvider);

  Future<T> _guardAuth<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      if (error is ApiException && error.isUnauthorized) {
        Future<void>.microtask(
          () => ref.read(authControllerProvider.notifier).logout(),
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<ConversationMessagesState> build(String arg) async {
    ref.watch(serverRecoveryRevisionProvider);
    await ref.watch(chatSocketConnectionProvider.future);
    _socketService = ref.read(chatSocketServiceProvider);
    _chatRepository = ref.read(chatRepositoryProvider);
    _disposed = false;
    _socketService?.joinConversation(arg);
    _listenToSocket(arg);
    ref.onDispose(() {
      _disposed = true;
      _eventsSubscription?.cancel();
      _socketService?.leaveConversation(arg);
    });

    final page = await _repository().fetchMessages(arg);
    return ConversationMessagesState.initial(page);
  }

  void _listenToSocket(String conversationId) {
    _eventsSubscription?.cancel();
    final socketService = _socketService;
    if (socketService == null) {
      return;
    }

    _eventsSubscription = socketService.events.listen((event) {
      final current = state.valueOrNull;
      if (current == null) {
        return;
      }

      if (event.type == 'receive_message') {
        final message = ChatMessage.fromJson(event.payload);
        if (message.conversationId == conversationId) {
          state = AsyncData(
            current.copyWith(
              messages: _upsertMessage(current.messages, message),
            ),
          );
        }
        return;
      }

      if (event.type == 'message_updated') {
        final message = ChatMessage.fromJson(event.payload);
        if (message.conversationId == conversationId) {
          state = AsyncData(
            current.copyWith(
              messages: _upsertMessage(current.messages, message),
            ),
          );
        }
        return;
      }

      if (event.type == 'message_deleted' &&
          event.payload['conversationId']?.toString() == conversationId) {
        final messageId = event.payload['messageId']?.toString();
        if (messageId != null) {
          state = AsyncData(
            current.copyWith(
              messages: _markMessageDeleted(current.messages, messageId),
            ),
          );
        }
        return;
      }

      if (event.type == 'socket_connected') {
        if (state.isLoading && state.valueOrNull == null) {
          return;
        }
        Future<void>.microtask(() async {
          if (_disposed) {
            return;
          }
          await refresh();
        });
        return;
      }

      if (event.type == 'message_seen' &&
          event.payload['conversationId']?.toString() == conversationId) {
        final messageIds =
            (event.payload['messageIds'] as List<dynamic>? ?? const [])
                .map((entry) => entry.toString())
                .toSet();
        final userId = event.payload['userId']?.toString();
        if (userId == null) {
          return;
        }

        var matchedAny = false;
        final updatedMessages = current.messages.map((message) {
          if (!messageIds.contains(message.id)) {
            return message;
          }
          matchedAny = true;
          final alreadySeen = message.seenBy.any(
            (entry) => entry.userId == userId,
          );
          if (alreadySeen) {
            return message;
          }
          return message.copyWith(
            seenBy: [
              ...message.seenBy,
              ChatReceipt(userId: userId, at: DateTime.now()),
            ],
          );
        }).toList();

        state = AsyncData(current.copyWith(messages: updatedMessages));

        if (!matchedAny) {
          Future<void>.microtask(() async {
            if (_disposed) {
              return;
            }
            await refresh();
          });
        }
        return;
      }

      if (event.type == 'message_delivered' &&
          event.payload['conversationId']?.toString() == conversationId) {
        final userId = event.payload['userId']?.toString();
        final affectedIds = <String>{
          if (event.payload['messageId'] != null)
            event.payload['messageId'].toString(),
          ...(event.payload['messageIds'] as List<dynamic>? ?? const []).map(
            (entry) => entry.toString(),
          ),
        };
        if (affectedIds.isEmpty || userId == null) {
          return;
        }

        state = AsyncData(
          current.copyWith(
            messages: current.messages
                .map(
                  (message) =>
                      affectedIds.contains(message.id) &&
                          !message.deliveredTo.any(
                            (entry) => entry.userId == userId,
                          )
                      ? message.copyWith(
                          deliveredTo: [
                            ...message.deliveredTo,
                            ChatReceipt(userId: userId, at: DateTime.now()),
                          ],
                        )
                      : message,
                )
                .toList(),
          ),
        );
      }
    });
  }

  List<ChatMessage> _upsertMessage(
    List<ChatMessage> source,
    ChatMessage message,
  ) {
    final index = source.indexWhere((entry) => entry.id == message.id);
    final items = [...source];
    if (index == -1) {
      items.add(message);
    } else {
      items[index] = message;
    }
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  List<ChatMessage> _markMessageDeleted(
    List<ChatMessage> source,
    String messageId,
  ) {
    return source
        .map(
          (message) => message.id == messageId
              ? message.copyWith(
                  content: '',
                  fileUrl: '',
                  fileName: null,
                  isDeleted: true,
                  metadata: {...?message.metadata, 'deletedLocally': true},
                  updatedAt: DateTime.now(),
                )
              : message,
        )
        .toList();
  }

  ChatMessage _toggleReactionLocally(
    ChatMessage message, {
    required String emoji,
    required String userId,
  }) {
    final metadata = Map<String, dynamic>.from(message.metadata ?? const {});
    final rawReactions = metadata['reactions'];
    final reactions = rawReactions is Map
        ? Map<String, dynamic>.from(rawReactions)
        : <String, dynamic>{};
    final existing = (reactions[emoji] as List<dynamic>? ?? const [])
        .map((entry) => entry.toString())
        .toSet();

    if (existing.contains(userId)) {
      existing.remove(userId);
    } else {
      existing.add(userId);
    }

    if (existing.isEmpty) {
      reactions.remove(emoji);
    } else {
      reactions[emoji] = existing.toList();
    }

    metadata['reactions'] = reactions;
    return message.copyWith(metadata: metadata, updatedAt: DateTime.now());
  }

  ChatMessage _toggleFavoriteLocally(
    ChatMessage message, {
    required String userId,
  }) {
    final metadata = Map<String, dynamic>.from(message.metadata ?? const {});
    final existing = (metadata['favoriteBy'] as List<dynamic>? ?? const [])
        .map((entry) => entry.toString())
        .toSet();
    if (existing.contains(userId)) {
      existing.remove(userId);
    } else {
      existing.add(userId);
    }
    metadata['favoriteBy'] = existing.toList();
    return message.copyWith(metadata: metadata, updatedAt: DateTime.now());
  }

  Future<void> refresh() async {
    if (_isRefreshing || _disposed) {
      return;
    }
    if (state.isLoading && state.valueOrNull == null) {
      return;
    }
    _isRefreshing = true;
    try {
      final page = await _guardAuth(() => _repository().fetchMessages(arg));
      if (_disposed) {
        return;
      }
      state = AsyncData(ConversationMessagesState.initial(page));
    } catch (error, stackTrace) {
      if (_disposed) {
        return;
      }
      state = AsyncError(error, stackTrace);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) {
      return;
    }

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await _guardAuth(
        () => _repository().fetchMessages(arg, cursor: current.nextCursor),
      );
      final merged = [...page.messages, ...current.messages];
      merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      state = AsyncData(
        current.copyWith(
          messages: merged,
          nextCursor: page.nextCursor,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> hydrateMessages(List<ChatMessage> messages) async {
    if (messages.isEmpty) {
      return;
    }

    final current =
        state.valueOrNull ??
        const ConversationMessagesState(
          messages: [],
          nextCursor: null,
          hasMore: false,
          isLoadingMore: false,
        );

    var merged = current.messages;
    for (final message in messages) {
      merged = _upsertMessage(merged, message);
    }

    state = AsyncData(current.copyWith(messages: merged));
  }

  Future<void> sendText(
    String content, {
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
    bool isSilent = false,
    DateTime? scheduledFor,
  }) async {
    return sendMessage(
      content: content,
      replyToMessageId: replyToMessageId,
      metadata: metadata,
      messageType: 'text',
      isSilent: isSilent,
      scheduledFor: scheduledFor,
    );
  }

  Future<void> sendMessage({
    required String content,
    String? messageType,
    String? fileUrl,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
    bool isSilent = false,
    DateTime? scheduledFor,
  }) async {
    _socketService?.markActivity();
    final result = await _guardAuth(
      () => _repository().sendTextMessage(
        conversationId: arg,
        content: content,
        replyToMessageId: replyToMessageId,
        metadata: metadata,
        messageType: messageType,
        fileUrl: fileUrl,
        isSilent: isSilent,
        isScheduled: scheduledFor != null,
        scheduledFor: scheduledFor,
      ),
    );
    
    if (scheduledFor != null) {
      // Do not add scheduled messages to the main chat list
      return;
    }

    final current =
        state.valueOrNull ??
        const ConversationMessagesState(
          messages: [],
          nextCursor: null,
          hasMore: false,
          isLoadingMore: false,
        );
    state = AsyncData(
      current.copyWith(
        messages: _upsertMessage(current.messages, result.message),
      ),
    );
  }

  Future<void> sendFile(
    String filePath, {
    String? replyToMessageId,
    String? customFileName,
    Map<String, dynamic>? metadata,
    void Function(int sent, int total)? onProgress,
  }) async {
    _socketService?.markActivity();
    final result = await _guardAuth(
      () => _repository().sendFileMessage(
        conversationId: arg,
        filePath: filePath,
        replyToMessageId: replyToMessageId,
        customFileName: customFileName,
        metadata: metadata,
        onProgress: onProgress,
      ),
    );
    final current =
        state.valueOrNull ??
        const ConversationMessagesState(
          messages: [],
          nextCursor: null,
          hasMore: false,
          isLoadingMore: false,
        );
    state = AsyncData(
      current.copyWith(
        messages: _upsertMessage(current.messages, result.message),
      ),
    );
  }

  Future<void> editMessage({
    required String messageId,
    required String content,
  }) async {
    final updated = await _guardAuth(
      () => _repository().editMessage(messageId: messageId, content: content),
    );
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(messages: _upsertMessage(current.messages, updated)),
    );
  }

  Future<void> deleteMessage(String messageId) async {
    await _guardAuth(() => _repository().removeMessage(messageId));
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        messages: _markMessageDeleted(current.messages, messageId),
      ),
    );
  }

  Future<void> toggleReaction({
    required String messageId,
    required String emoji,
  }) async {
    final current = state.valueOrNull;
    final uid = ref.read(authControllerProvider).valueOrNull?.id.trim();
    ChatMessage? previousMessage;

    if (current != null && uid != null && uid.isNotEmpty) {
      for (final message in current.messages) {
        if (message.id == messageId) {
          previousMessage = message;
          break;
        }
      }
      if (previousMessage != null) {
        state = AsyncData(
          current.copyWith(
            messages: _upsertMessage(
              current.messages,
              _toggleReactionLocally(
                previousMessage,
                emoji: emoji,
                userId: uid,
              ),
            ),
          ),
        );
      }
    }

    try {
      final updated = await _guardAuth(
        () => _repository().toggleReaction(messageId: messageId, emoji: emoji),
      );
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(messages: _upsertMessage(latest.messages, updated)),
        );
      }
      if (uid != null &&
          uid.isNotEmpty &&
          chatMessageHasUserReactionEmoji(updated, emoji, uid)) {
        unawaited(ChatReactionEmojiStats.recordUnicodeIfAnimated(emoji));
      }
    } catch (error) {
      final latest = state.valueOrNull;
      if (latest != null && previousMessage != null) {
        state = AsyncData(
          latest.copyWith(
            messages: _upsertMessage(latest.messages, previousMessage),
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> toggleFavoriteMessage({required String messageId}) async {
    final current = state.valueOrNull;
    final uid = ref.read(authControllerProvider).valueOrNull?.id.trim();
    ChatMessage? previousMessage;

    if (current != null && uid != null && uid.isNotEmpty) {
      for (final message in current.messages) {
        if (message.id == messageId) {
          previousMessage = message;
          break;
        }
      }
      if (previousMessage != null) {
        state = AsyncData(
          current.copyWith(
            messages: _upsertMessage(
              current.messages,
              _toggleFavoriteLocally(previousMessage, userId: uid),
            ),
          ),
        );
      }
    }

    try {
      final updated = await _guardAuth(
        () => _repository().toggleFavoriteMessage(messageId: messageId),
      );
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(messages: _upsertMessage(latest.messages, updated)),
        );
      }
    } catch (error) {
      final latest = state.valueOrNull;
      if (latest != null && previousMessage != null) {
        state = AsyncData(
          latest.copyWith(
            messages: _upsertMessage(latest.messages, previousMessage),
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> votePoll(String messageId, List<String> optionIds) async {
    try {
      final updatedMessage = await ref
          .read(chatRepositoryProvider)
          .votePoll(messageId, optionIds);
      final st = state.valueOrNull;
      if (st != null) {
        state = AsyncData(
          st.copyWith(messages: _upsertMessage(st.messages, updatedMessage)),
        );
      }
    } catch (e, stack) {
      state = AsyncError(e, stack);
    }
  }

  Future<void> exportPoll(String messageId) async {
    try {
      final file = await ref.read(chatRepositoryProvider).downloadPollExport(messageId);
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw Exception('Could not open file: ${result.message}');
      }
    } catch (e, stack) {
      state = AsyncError(e, stack);
    }
  }

  Future<ChatSearchResult> searchMessages(String query, {String? cursor}) {
    return _guardAuth(
      () => _repository().searchMessages(
        query: query,
        conversationId: arg,
        cursor: cursor,
      ),
    );
  }

  Future<void> markSeen() async {
    if (_disposed) {
      return;
    }
    _socketService?.markSeen(arg);
    try {
      await _repository().markConversationSeen(arg);
    } catch (_) {}
  }

  void sendTyping() => _socketService?.sendTyping(arg);

  void stopTyping() => _socketService?.stopTyping(arg);
}





