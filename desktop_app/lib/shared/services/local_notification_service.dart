import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings/user_preferences.dart';
import 'web_platform_bridge.dart' as web_bridge;

class LocalNotificationService {
  LocalNotificationService({required this.appName});

  static const MethodChannel _windowChannel = MethodChannel('dbacd_hub/window');
  static const _notificationToneIdKey = 'prefs_notification_tone_id';
  static const _legacyNotificationToneIdKey = 'notificationToneId';
  static const _androidChannelId = 'chat_messages_v2';

  final String appName;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _disabled = false;
  int _nextId = 1;

  Future<void> initialize() async {
    if (_initialized || _disabled) {
      return;
    }
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const windows = WindowsInitializationSettings(
      appName: 'iSmart Messenger',
      appUserModelId: 'workplace.chat.desktop',
      guid: '4cb6f7c4-78be-48b7-b316-68578d5988af',
    );
    const settings = InitializationSettings(android: android, windows: windows);

    try {
      await _plugin.initialize(settings);
      _initialized = true;
    } catch (_) {
      _disabled = true;
    }
  }

  Future<void> showIncomingMessage({
    required String title,
    required String body,
    bool requestAttention = true,
  }) async {
    await initialize();
    if (kIsWeb) {
      final tone = await _loadSelectedTone();
      final soundAssetPath = tone.isSilent ? null : tone.assetPath;
      if (!web_bridge.isElectron() && soundAssetPath != null) {
        await _playNotificationTone();
      }
      await web_bridge.showBrowserNotification(
        title: title.isEmpty ? appName : title,
        body: body.isEmpty ? 'لديك رسالة جديدة' : body,
        silent: true,
        soundAssetPath: soundAssetPath,
      );
      return;
    }
    if (requestAttention) {
      await _requestWindowAttention();
    }
    if (_disabled) {
      return;
    }

    await _playNotificationTone();

    final details = await _buildNotificationDetails();

    try {
      await _plugin.show(
        _nextId++,
        title.isEmpty ? appName : title,
        body.isEmpty ? 'لديك رسالة جديدة' : body,
        details,
      );
    } catch (_) {
      _disabled = true;
    }
  }

  Future<NotificationDetails> _buildNotificationDetails() async {
    return NotificationDetails(
      android: const AndroidNotificationDetails(
        _androidChannelId,
        'رسائل الشات',
        channelDescription: 'إشعارات الرسائل الداخلية',
        importance: Importance.high,
        priority: Priority.high,
        playSound: false,
      ),
      windows: WindowsNotificationDetails(
        audio: WindowsNotificationAudio.silent(),
      ),
      linux: const LinuxNotificationDetails(suppressSound: true),
    );
  }

  Future<bool> _playNotificationTone() async {
    try {
      final tone = await _loadSelectedTone();
      debugPrint(
        '[local-notif] selected tone: ${tone.id} asset:${tone.assetPath} silent:${tone.isSilent}',
      );
      if (tone.isSilent || tone.assetPath == null) {
        debugPrint(
          '[local-notif] tone is silent or has no asset, skipping playback',
        );
        return false;
      }
      if (kIsWeb) {
        try {
          await web_bridge.playBrowserAudioAsset(tone.assetPath!);
          debugPrint(
            '[local-notif] web audio playback requested for ${tone.assetPath}',
          );
          return true;
        } catch (e, st) {
          debugPrint('[local-notif] web audio playback error: $e');
          debugPrintStack(stackTrace: st);
          return false;
        }
      }
      if (Platform.isWindows || Platform.isLinux) {
        await _playDesktopTone(tone);
        return true;
      }
      final playablePath = await _preparePlayableToneFile(tone);
      if (playablePath == null) {
        return false;
      }
      await _playWithPlatformCommand(playablePath);
      return true;
    } catch (_) {
      // Ignore audio playback failures and still show the notification.
    }
    return false;
  }

  Future<void> previewNotificationTone(String? toneId) async {
    final tone = NotificationTone.fromId(toneId);
    if (tone.isSilent || tone.assetPath == null) {
      return;
    }
    try {
      if (kIsWeb) {
        await web_bridge.playBrowserAudioAsset(tone.assetPath!);
        return;
      }
      if (Platform.isWindows || Platform.isLinux) {
        await _playDesktopTone(tone);
        return;
      }
      final playablePath = await _preparePlayableToneFile(tone);
      if (playablePath == null) {
        return;
      }
      await _playWithPlatformCommand(playablePath);
    } catch (_) {}
  }

  Future<void> dispose() async {}

  Future<bool> shouldSuppressActiveConversationNotification() async {
    if (kIsWeb) {
      if (web_bridge.isElectron()) {
        return web_bridge.isElectronWindowForegroundVisible();
      }
      return web_bridge.isPageVisible();
    }
    final state = await _getWindowState();
    if (state == null) {
      return false;
    }

    final isVisible = state['isVisible'] == true;
    final isMinimized = state['isMinimized'] == true;
    return isVisible && !isMinimized;
  }

  Future<void> _requestWindowAttention() async {
    try {
      await _windowChannel.invokeMethod<void>('requestAttention', {
        'playSound': false,
      });
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

  Future<Map<Object?, Object?>?> _getWindowState() async {
    try {
      final result = await _windowChannel.invokeMethod<dynamic>(
        'getWindowState',
      );
      if (result is Map<Object?, Object?>) {
        return result;
      }
    } catch (_) {}
    return null;
  }
}

Future<void> _playDesktopTone(NotificationTone tone) async {
  final playablePath = await _preparePlayableToneFile(tone);
  if (playablePath == null) {
    return;
  }
  await _playWithPlatformCommand(playablePath);
}

Future<String?> _resolveLinuxAudioCommand() async {
  for (final candidate in const ['/usr/bin/paplay', '/usr/bin/aplay']) {
    if (await File(candidate).exists()) {
      return candidate;
    }
  }
  return null;
}

Future<void> _playWithPlatformCommand(String filePath) async {
  if (Platform.isWindows) {
    final escapedPath = filePath.replaceAll("'", "''");
    final process = await Process.start('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r"$player = New-Object System.Media.SoundPlayer('" +
          escapedPath +
          r"'); $player.PlaySync();",
    ]);
    unawaited(process.exitCode.catchError((_) => -1));
    return;
  }

  if (Platform.isLinux) {
    final command = await _resolveLinuxAudioCommand();
    if (command == null) {
      if (kDebugMode) {
        debugPrint('Linux notification tone fallback unavailable.');
      }
      return;
    }
    final process = await Process.start(command, [filePath]);
    unawaited(process.exitCode.catchError((_) => -1));
  }
}

Future<String?> _preparePlayableToneFile(NotificationTone tone) async {
  final assetPath = tone.assetPath;
  if (assetPath == null || assetPath.isEmpty) {
    return null;
  }

  try {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final hash = sha1.convert(bytes).toString().substring(0, 12);
    final originalName = assetPath.split('/').last;
    final dotIndex = originalName.lastIndexOf('.');
    final baseName = dotIndex == -1
        ? originalName
        : originalName.substring(0, dotIndex);
    final extension = dotIndex == -1
        ? 'wav'
        : originalName.substring(dotIndex + 1);
    final filePath =
        '${Directory.systemTemp.path}/dbacd_notification_${baseName}_$hash.$extension';
    final file = File(filePath);
    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  } catch (_) {
    return null;
  }
}
