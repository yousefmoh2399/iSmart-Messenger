import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatDraftStore {
  const ChatDraftStore();

  static const _key = 'chat_text_drafts_v1';
  static const _saveDebounceDelay = Duration(milliseconds: 350);

  static Map<String, String>? _memoryDrafts;
  static Timer? _debounceTimer;
  static Future<void>? _inFlightFlush;

  Future<Map<String, String>> _read() async {
    if (_memoryDrafts != null) {
      return _memoryDrafts!;
    }
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) {
      _memoryDrafts = <String, String>{};
      return _memoryDrafts!;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _memoryDrafts = <String, String>{};
        return _memoryDrafts!;
      }
      _memoryDrafts = decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
      return _memoryDrafts!;
    } catch (_) {
      _memoryDrafts = <String, String>{};
      return _memoryDrafts!;
    }
  }

  Future<String?> load(String conversationId) async {
    return (await _read())[conversationId];
  }

  Future<void> save(String conversationId, String text) async {
    final drafts = await _read();
    final trimmed = text.trimRight();
    final changed = trimmed.isEmpty
        ? drafts.remove(conversationId) != null
        : drafts[conversationId] != trimmed;
    if (!changed) {
      return;
    }
    if (trimmed.isNotEmpty) {
      drafts[conversationId] = trimmed;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_saveDebounceDelay, () {
      _debounceTimer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_memoryDrafts == null) {
      return;
    }
    if (_inFlightFlush != null) {
      await _inFlightFlush;
    }
    final snapshot = Map<String, String>.from(_memoryDrafts!);
    final op = () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_key, jsonEncode(snapshot));
    }();
    _inFlightFlush = op;
    try {
      await op;
    } finally {
      if (identical(_inFlightFlush, op)) {
        _inFlightFlush = null;
      }
    }
  }

  Future<void> clear(String conversationId) async {
    final drafts = await _read();
    final removed = drafts.remove(conversationId) != null;
    if (removed) {
      await flush();
    }
  }
}
