import 'dart:async';

import 'package:flutter/services.dart';

class AndroidSharedContent {
  const AndroidSharedContent({
    required this.text,
    required this.paths,
    this.conversationId,
  });
  final String text;
  final List<String> paths;
  final String? conversationId;
  bool get isEmpty => text.trim().isEmpty && paths.isEmpty;

  static AndroidSharedContent? fromRaw(Object? raw) {
    if (raw is! Map) return null;
    final paths = (raw['paths'] as List? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    final value = AndroidSharedContent(
      text: raw['text']?.toString() ?? '',
      paths: paths,
      conversationId: raw['conversationId']?.toString().isEmpty ?? true
          ? null
          : raw['conversationId']?.toString(),
    );
    return value.isEmpty ? null : value;
  }
}

class AndroidShareReceiver {
  AndroidShareReceiver._();
  static const _channel = MethodChannel('app.share_receiver');
  static final _events = StreamController<AndroidSharedContent>.broadcast();
  static Stream<AndroidSharedContent> get events => _events.stream;

  static Future<AndroidSharedContent?> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedContent') {
        final content = AndroidSharedContent.fromRaw(call.arguments);
        if (content != null) _events.add(content);
      }
    });
    return AndroidSharedContent.fromRaw(
      await _channel.invokeMethod('getInitialSharedContent'),
    );
  }

  static Future<void> updateDirectShareTargets(
    List<Map<String, String>> targets,
  ) => _channel.invokeMethod('updateDirectShareTargets', {'targets': targets});
}
