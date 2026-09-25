import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_models.dart';

class ChatLocalCache {
  ChatLocalCache();

  Future<void> saveRawJson(String key, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('chat_cache_$key', jsonEncode(data));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> loadRawJson(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('chat_cache_$key');
      if (jsonStr == null) return null;
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveConversations(List<ChatConversation> conversations) async {}
  Future<List<ChatConversation>?> loadConversations() async => null;
  Future<void> saveMessages(String conversationId, ChatMessagesPage page) async {}
  Future<ChatMessagesPage?> loadMessages(String conversationId) async => null;
}
