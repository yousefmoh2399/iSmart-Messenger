import 'dart:convert';

import 'package:animated_emoji/animated_emoji.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_models.dart';

const _kPrefsKey = 'chat_reaction_emoji_usage_v1';

/// تتبع إيموجي التفاعلات الأكثر استخدامًا (محليًا عبر [SharedPreferences]).
class ChatReactionEmojiStats {
  ChatReactionEmojiStats._();

  static Future<Map<String, int>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kPrefsKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save(Map<String, int> map) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrefsKey, jsonEncode(map));
  }

  static Future<void> bumpForAnimatedName(String emojiName) async {
    final cur = await load();
    cur[emojiName] = (cur[emojiName] ?? 0) + 1;
    await _save(cur);
  }

  static Future<void> recordUnicodeIfAnimated(String unicodeEmoji) async {
    final data = AnimatedEmojis.fromEmojiString(unicodeEmoji);
    if (data == null) {
      return;
    }
    await bumpForAnimatedName(data.name);
  }
}

bool chatMessageHasUserReactionEmoji(
  ChatMessage message,
  String emoji,
  String userId,
) {
  final meta = message.metadata;
  if (meta == null) {
    return false;
  }
  final r = meta['reactions'];
  if (r is! Map) {
    return false;
  }
  final list = r[emoji];
  if (list is! List) {
    return false;
  }
  return list.map((e) => e.toString()).contains(userId);
}
