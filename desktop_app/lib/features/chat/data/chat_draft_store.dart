import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatDraftStore {
  const ChatDraftStore();

  static const _key = 'chat_text_drafts_v1';

  Future<Map<String, String>> _read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<String?> load(String conversationId) async {
    return (await _read())[conversationId];
  }

  Future<void> save(String conversationId, String text) async {
    final drafts = await _read();
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) {
      drafts.remove(conversationId);
    } else {
      drafts[conversationId] = trimmed;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(drafts));
  }

  Future<void> clear(String conversationId) => save(conversationId, '');
}
