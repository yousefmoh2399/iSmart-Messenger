import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/chat_models.dart';

class ChatLocalCache {
  ChatLocalCache();

  static const String _prefix = 'chat_cache_';

  Future<File> _file(String key) async {
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/chat_cache');
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
    // Sanitise key so it's safe as a filename
    final safeName = key.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return File('${cacheDir.path}/$_prefix$safeName.json');
  }

  Future<void> saveRawJson(String key, Map<String, dynamic> data) async {
    try {
      final f = await _file(key);
      await f.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> loadRawJson(String key) async {
    try {
      final f = await _file(key);
      if (!f.existsSync()) return null;
      final raw = await f.readAsString();
      if (raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the backing file for [key]. Silently ignores errors.
  Future<void> deleteRawJson(String key) async {
    try {
      final f = await _file(key);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  /// Deletes every file inside the chat_cache directory.
  Future<void> clearAll() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${dir.path}/chat_cache');
      if (cacheDir.existsSync()) {
        await cacheDir.delete(recursive: true);
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
}

