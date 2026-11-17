import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_models.dart';

class ChatLocalCache {
  ChatLocalCache();

  static const String _keyPrefix = 'chat_cache_';

  Future<void> saveRawJson(String key, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_keyPrefix$key', jsonEncode(data));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> loadRawJson(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('$_keyPrefix$key');
      if (jsonStr == null) return null;
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Removes a single key from the cache.
  Future<void> deleteRawJson(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyPrefix$key');
    } catch (_) {}
  }

  /// Removes every key that starts with [_keyPrefix] from SharedPreferences.
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keysToRemove =
          prefs.getKeys().where((k) => k.startsWith(_keyPrefix)).toList();
      for (final k in keysToRemove) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  Future<void> saveConversations(List<ChatConversation> conversations) async {
    await saveRawJson('conversations', {
      'conversations': conversations
          .map((conversation) => conversation.toJson())
          .toList(),
    });
  }

  Future<List<ChatConversation>?> loadConversations() async {
    final cached = await loadRawJson('conversations');
    final raw = cached?['conversations'];
    if (raw is! List) return null;
    return raw
        .whereType<Map>()
        .map(
          (entry) =>
              ChatConversation.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList();
  }

  Future<void> saveUsers(List<ChatDirectoryUser> users) async {
    await saveRawJson('users_directory', {
      'users': users.map((user) => user.toJson()).toList(),
    });
  }

  Future<List<ChatDirectoryUser>?> loadUsers() async {
    final cached = await loadRawJson('users_directory');
    final raw = cached?['users'];
    if (raw is! List) return null;
    return raw
        .whereType<Map>()
        .map(
          (entry) =>
              ChatDirectoryUser.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList();
  }

  Future<void> saveDepartments(List<DepartmentSummary> departments) async {
    await saveRawJson('departments', {
      'departments': departments.map((d) => d.toJson()).toList(),
    });
  }

  Future<List<DepartmentSummary>?> loadDepartments() async {
    final cached = await loadRawJson('departments');
    final raw = cached?['departments'];
    if (raw is! List) return null;
    return raw
        .whereType<Map>()
        .map(
          (entry) =>
              DepartmentSummary.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList();
  }

  Future<void> saveBranches(List<BranchSummary> branches) async {
    await saveRawJson('branches', {
      'branches': branches.map((b) => b.toJson()).toList(),
    });
  }

  Future<List<BranchSummary>?> loadBranches() async {
    final cached = await loadRawJson('branches');
    final raw = cached?['branches'];
    if (raw is! List) return null;
    return raw
        .whereType<Map>()
        .map(
          (entry) =>
              BranchSummary.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList();
  }

  Future<void> saveMessages(
    String conversationId,
    ChatMessagesPage page,
  ) async {
    await saveRawJson('messages_$conversationId', {
      'messages': page.messages.map((message) => message.toJson()).toList(),
      'meta': {
        'nextCursor': page.nextCursor,
        'hasMore': page.hasMore,
        'limit': page.limit,
      },
    });
  }

  Future<ChatMessagesPage?> loadMessages(String conversationId) async {
    final cached = await loadRawJson('messages_$conversationId');
    final raw = cached?['messages'];
    if (raw is! List) return null;
    final meta = cached?['meta'] is Map
        ? Map<String, dynamic>.from(cached!['meta'] as Map)
        : const <String, dynamic>{};
    return ChatMessagesPage(
      messages: raw
          .whereType<Map>()
          .map(
            (entry) => ChatMessage.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(),
      nextCursor: meta['nextCursor'] as String?,
      hasMore: meta['hasMore'] == true,
      limit: (meta['limit'] as num?)?.toInt() ?? 40,
    );
  }

  Future<void> clearConversationMessages(String conversationId) async {
    await deleteRawJson('messages_$conversationId');
  }

  Future<void> removeConversation(String conversationId) async {
    await clearConversationMessages(conversationId);
    final conversations = await loadConversations();
    if (conversations != null) {
      final updated =
          conversations.where((c) => c.id != conversationId).toList();
      await saveConversations(updated);
    }
  }

  Future<void> saveOutboxItems(List<Map<String, dynamic>> items) async {
    await saveRawJson('outbox_queue', {'items': items});
  }

  Future<List<Map<String, dynamic>>?> loadOutboxItems() async {
    final cached = await loadRawJson('outbox_queue');
    final raw = cached?['items'];
    if (raw is! List) return null;
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }
}
