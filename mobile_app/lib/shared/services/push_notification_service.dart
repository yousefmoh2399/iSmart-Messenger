import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../features/auth/data/auth_repository.dart';
import 'local_notification_service.dart';
import 'permission_request_coordinator.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    final data = message.data;
    final type = data['type']?.toString();
    final conversationId = data['conversationId']?.toString().trim();

    final plugin = FlutterLocalNotificationsPlugin();

    if (type == 'dismiss_chat' &&
        conversationId != null &&
        conversationId.isNotEmpty) {
      const int summaryIdOffset = 1000000;
      final summaryId =
          (conversationId.hashCode.abs() % 800000) + summaryIdOffset;
      await plugin.cancel(summaryId);
      final androidPlugin = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.cancel(summaryId, tag: 'chat_$conversationId');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final session = prefs.getString('auth_session_v1') ??
        prefs.getString('auth_session');
    final token = prefs.getString('auth_token');
    final isLoggedOut = (session == null || session.isEmpty) &&
        (token == null || token.isEmpty);
    if (isLoggedOut) {
      await plugin.cancelAll();
      return;
    }
  } catch (_) {}
}

class PushNotificationService {
  PushNotificationService(
    this._apiClient,
    this._authRepository,
    this._localNotificationService,
  );

  static const _deviceIdKey = 'push_device_id';

  final ApiClient _apiClient;
  final AuthRepository _authRepository;
  final LocalNotificationService _localNotificationService;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedMessageSubscription;
  final StreamController<Map<String, dynamic>> _openedController =
      StreamController<Map<String, dynamic>>.broadcast();
  bool _initialized = false;
  bool _firebaseReady = false;
  Map<String, dynamic>? _pendingOpenedPayload;

  Stream<Map<String, dynamic>> get openedNotifications =>
      _openedController.stream;

  static Future<void> registerBackgroundHandler() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (_) {
      _firebaseReady = false;
      _initialized = true;
      return;
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    await PermissionRequestCoordinator.run(
      () => messaging.requestPermission(alert: true, badge: true, sound: true),
    );
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen((
      message,
    ) async {
      final payload = _messagePayload(message);
      final type = payload['type']?.toString();
      final conversationId = payload['conversationId']?.toString().trim();

      if (type == 'dismiss_chat' &&
          conversationId != null &&
          conversationId.isNotEmpty) {
        await _localNotificationService.cancelConversationNotifications(conversationId);
        return;
      }

      final authToken = await _authRepository.getToken();
      if (authToken == null || authToken.isEmpty) {
        return;
      }

      final title =
          message.notification?.title ??
          payload['title']?.toString() ??
          'رسالة جديدة';
      final body =
          message.notification?.body ??
          payload['body']?.toString() ??
          'لديك رسالة جديدة';
      await _localNotificationService.showIncomingMessage(
        title: title,
        body: body,
        payload: payload,
      );
    });

    _openedMessageSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      _emitOpenedPayload(_messagePayload(message));
    });

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _emitOpenedPayload(_messagePayload(initialMessage));
    }

    _tokenRefreshSubscription = messaging.onTokenRefresh.listen((token) {
      unawaited(_registerToken(token));
    });

    _initialized = true;
  }

  Future<void> registerForAuthenticatedUser() async {
    await initialize();
    if (!_firebaseReady) {
      return;
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.trim().isEmpty) {
      return;
    }
    await _registerToken(token);
  }

  Future<String?> getCurrentToken() async {
    try {
      if (!_firebaseReady) await initialize();
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> unregisterCurrentDevice() async {
    await initialize();
    if (!_firebaseReady) {
      return;
    }
    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    final authToken = await _authRepository.getToken();
    final deviceId = await _loadOrCreateDeviceId();

    if (authToken != null && authToken.isNotEmpty) {
      try {
        await _apiClient.dio.delete<Map<String, dynamic>>(
          '/api/users/me/push-devices',
          data: {
            if (token != null && token.isNotEmpty) 'token': token,
            'deviceId': deviceId,
          },
          options: Options(headers: {'Authorization': 'Bearer $authToken'}),
        );
      } catch (_) {}
    }

    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    await _openedMessageSubscription?.cancel();
    await _openedController.close();
  }

  Map<String, dynamic>? takePendingOpenedPayload() {
    final payload = _pendingOpenedPayload;
    _pendingOpenedPayload = null;
    return payload;
  }

  Future<void> _registerToken(String token) async {
    final authToken = await _authRepository.getToken();
    if (authToken == null || authToken.isEmpty) {
      return;
    }
    final notificationToneId = await _localNotificationService
        .getCurrentNotificationToneId();

    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/users/me/push-devices',
        data: {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'deviceId': await _loadOrCreateDeviceId(),
          'deviceName': Platform.operatingSystem,
          'notificationToneId': notificationToneId,
        },
        options: Options(headers: {'Authorization': 'Bearer $authToken'}),
      );
    } catch (_) {}
  }

  Future<String> _loadOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final created = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    await prefs.setString(_deviceIdKey, created);
    return created;
  }

  Map<String, dynamic> _messagePayload(RemoteMessage message) {
    final payload = Map<String, dynamic>.from(message.data);
    final title = message.notification?.title?.trim();
    final body = message.notification?.body?.trim();
    if (title != null && title.isNotEmpty) {
      payload.putIfAbsent('title', () => title);
    }
    if (body != null && body.isNotEmpty) {
      payload.putIfAbsent('body', () => body);
    }
    return payload;
  }

  void _emitOpenedPayload(Map<String, dynamic> payload) {
    if (payload.isEmpty) {
      return;
    }
    _pendingOpenedPayload = payload;
    _openedController.add(payload);
  }
}
