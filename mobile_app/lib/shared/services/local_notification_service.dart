import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings/user_preferences.dart';
import 'permission_request_coordinator.dart';

@pragma('vm:entry-point')
Future<void> onDidReceiveBackgroundNotificationResponse(
  NotificationResponse response,
) async {
  final input = response.input?.trim();
  if (response.actionId != 'reply_action' || input == null || input.isEmpty) {
    return;
  }
  final payloadStr = response.payload;
  if (payloadStr == null || payloadStr.isEmpty) return;
  Map<String, dynamic> payload = {};
  try {
    final decoded = jsonDecode(payloadStr);
    if (decoded is Map) {
      payload = Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    return;
  }
  final conversationId = payload['conversationId']?.toString();
  if (conversationId == null || conversationId.isEmpty) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final sessionStr = prefs.getString('auth_session');
    if (sessionStr == null || sessionStr.isEmpty) return;
    final sessionJson = jsonDecode(sessionStr) as Map<String, dynamic>;
    final token = sessionJson['accessToken']?.toString();
    if (token == null || token.isEmpty) return;

    var baseUrl = prefs.getString('api_base_url');
    if (baseUrl == null || baseUrl.isEmpty) {
      baseUrl = prefs.getString('admin_default_base_url');
    }
    if (baseUrl == null || baseUrl.isEmpty) {
      baseUrl = 'http://192.168.1.100:3000';
    }
    baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

    final uri = Uri.parse('$baseUrl/api/chat/messages');
    final client = HttpClient();
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.headers.set('Authorization', 'Bearer $token');
    request.write(jsonEncode({
      'conversationId': conversationId,
      'content': input,
      'messageType': 'text',
    }));
    final res = await request.close();
    await res.drain();
    client.close();
  } catch (_) {}
}

class LocalNotificationService {
  LocalNotificationService({required this.appName});

  static const _notificationToneIdKey = 'prefs_notification_tone_id';
  static const _legacyNotificationToneIdKey = 'notificationToneId';
  static const _androidLocalChannelId = 'chat_messages_local_v2';
  static const _androidDefaultChannelId = 'chat_messages_default_v1';
  static const _androidChimeChannelId = 'chat_messages_chime_v1';
  static const _androidAlertChannelId = 'chat_messages_alert_v1';
  static const _androidSilentChannelId = 'chat_messages_silent_v1';

  final String appName;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _tapController =
      StreamController<Map<String, dynamic>>.broadcast();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _initialized = false;
  int _nextId = 1;
  Map<String, dynamic>? _pendingLaunchPayload;

  Stream<Map<String, dynamic>> get tapEvents => _tapController.stream;

  Map<String, dynamic>? takePendingLaunchPayload() {
    final payload = _pendingLaunchPayload;
    _pendingLaunchPayload = null;
    return payload;
  }

  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    const windows = WindowsInitializationSettings(
      appName: 'Workplace Chat',
      appUserModelId: 'workplace.chat.mobile',
      guid: '5f5a15fb-4364-4385-97fc-70c7ce5e6e61',
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      windows: windows,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          onDidReceiveBackgroundNotificationResponse,
    );
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      await PermissionRequestCoordinator.run(
        androidPlugin.requestNotificationsPermission,
      );
    }
    await _createAndroidNotificationChannels(androidPlugin);
    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails != null &&
          launchDetails.didNotificationLaunchApp &&
          launchDetails.notificationResponse != null) {
        _handleNotificationResponse(launchDetails.notificationResponse!);
      }
    } catch (_) {}
    _initialized = true;
  }

  Future<void> showIncomingMessage({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    await initialize();
    await _playNotificationTone();

    final isChat = payload == null ||
        payload.isEmpty ||
        payload['type'] == 'chat' ||
        payload['conversationId'] != null;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidLocalChannelId,
        'رسائل الشات داخل التطبيق',
        channelDescription: 'إشعارات الرسائل الداخلية',
        importance: Importance.high,
        priority: Priority.high,
        playSound: false,
        actions: isChat
            ? const <AndroidNotificationAction>[
                AndroidNotificationAction(
                  'reply_action',
                  'رد',
                  inputs: <AndroidNotificationActionInput>[
                    AndroidNotificationActionInput(
                      label: 'اكتب ردك هنا...',
                    ),
                  ],
                  allowGeneratedReplies: true,
                ),
              ]
            : null,
      ),
      iOS: const DarwinNotificationDetails(presentSound: false),
      windows: WindowsNotificationDetails(
        audio: WindowsNotificationAudio.silent(),
      ),
    );

    final notificationId = _nextId++;
    await _plugin.show(
      notificationId,
      title.isEmpty ? appName : title,
      body.isEmpty ? 'لديك رسالة جديدة' : body,
      details,
      payload: payload == null || payload.isEmpty
          ? null
          : jsonEncode({
              ...payload,
              'notificationId': notificationId,
            }),
    );
  }

  Future<void> _playNotificationTone() async {
    try {
      final tone = await _loadSelectedTone();
      if (tone.isSilent || tone.assetPath == null) {
        return;
      }
      await _audioPlayer.stop();
      await _audioPlayer.setAsset(tone.assetPath!);
      await _audioPlayer.play();
    } catch (_) {
      // Ignore audio playback failures and still show the notification.
    }
  }

  Future<void> previewNotificationTone(String? toneId) async {
    final tone = NotificationTone.fromId(toneId);
    if (tone.isSilent || tone.assetPath == null) {
      await _audioPlayer.stop();
      return;
    }
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setAsset(tone.assetPath!);
      await _audioPlayer.play();
    } catch (_) {}
  }

  Future<NotificationTone> _loadSelectedTone() async {
    final prefs = await SharedPreferences.getInstance();
    final toneId =
        prefs.getString(_notificationToneIdKey) ??
        prefs.getString(_legacyNotificationToneIdKey);
    if (toneId != null && prefs.containsKey(_legacyNotificationToneIdKey)) {
      await prefs.setString(_notificationToneIdKey, toneId);
      await prefs.remove(_legacyNotificationToneIdKey);
    }
    return NotificationTone.fromId(toneId);
  }

  Future<String> getCurrentNotificationToneId() async {
    final tone = await _loadSelectedTone();
    return tone.id;
  }

  static String androidFcmChannelIdForToneId(String? toneId) {
    return switch (NotificationTone.fromId(toneId).id) {
      'chime' => _androidChimeChannelId,
      'alert' => _androidAlertChannelId,
      'silent' => _androidSilentChannelId,
      _ => _androidDefaultChannelId,
    };
  }

  Future<void> _createAndroidNotificationChannels(
    AndroidFlutterLocalNotificationsPlugin? androidPlugin,
  ) async {
    if (androidPlugin == null) {
      return;
    }

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidLocalChannelId,
        'رسائل الشات داخل التطبيق',
        description: 'إشعارات الرسائل عند فتح التطبيق',
        importance: Importance.high,
        playSound: false,
      ),
    );
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidDefaultChannelId,
        'رسائل الشات',
        description: 'إشعارات الرسائل الداخلية بالنغمة الافتراضية',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('default_tone'),
      ),
    );
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidChimeChannelId,
        'رسائل الشات - رنين',
        description: 'إشعارات الرسائل الداخلية بنغمة الرنين',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('chime_tone'),
      ),
    );
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidAlertChannelId,
        'رسائل الشات - تنبيه',
        description: 'إشعارات الرسائل الداخلية بنغمة التنبيه',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('alert_tone'),
      ),
    );
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidSilentChannelId,
        'رسائل الشات - صامت',
        description: 'إشعارات الرسائل الداخلية بدون صوت',
        importance: Importance.high,
        playSound: false,
      ),
    );
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = Map<String, dynamic>.from(_decodePayload(response.payload));
    if (response.actionId != null) {
      payload['actionId'] = response.actionId;
    }
    if (response.input != null && response.input!.trim().isNotEmpty) {
      payload['replyText'] = response.input!.trim();
    }
    if (response.id != null) {
      payload['notificationId'] = response.id;
    }
    if (payload.isNotEmpty) {
      _pendingLaunchPayload = payload;
      _tapController.add(payload);
    }
  }

  Map<String, dynamic> _decodePayload(String? rawPayload) {
    final trimmed = rawPayload?.trim() ?? '';
    if (trimmed.isEmpty) {
      return const <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return const <String, dynamic>{};
  }

  Future<void> dispose() async {
    await _tapController.close();
    await _audioPlayer.dispose();
  }
}
