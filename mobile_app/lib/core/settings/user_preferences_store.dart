import 'package:shared_preferences/shared_preferences.dart';

import 'user_preferences.dart';

class UserPreferencesStore {
  static const _enterSendsMessageKey = 'prefs_enter_sends_message';
  static const _autoSaveAfterScanKey = 'prefs_auto_save_after_scan';
  static const _scanSaveDirPathKey = 'prefs_scan_save_directory_path';
  static const _localStorageDirPathKey = 'prefs_local_storage_directory_path';
  static const _preferredPrinterNameKey = 'prefs_preferred_printer_name';
  static const _notificationToneIdKey = 'prefs_notification_tone_id';
  static const _notificationDisplayModeKey = 'prefs_notification_display_mode';

  // Advanced & WhatsApp Grouping Notification Keys
  static const _notificationsEnabledKey = 'prefs_notifications_enabled';
  static const _messageNotificationsEnabledKey = 'prefs_msg_notifications_enabled';
  static const _messageVibrateKey = 'prefs_msg_vibrate';
  static const _messagePreviewKey = 'prefs_msg_preview';
  static const _groupNotificationsEnabledKey = 'prefs_group_notifications_enabled';
  static const _groupToneIdKey = 'prefs_group_tone_id';
  static const _groupVibrateKey = 'prefs_group_vibrate';
  static const _groupPreviewKey = 'prefs_group_preview';
  static const _groupNotificationsByChatKey = 'prefs_group_notifications_by_chat';
  static const _inAppBannersKey = 'prefs_in_app_banners';
  static const _reactionNotificationsKey = 'prefs_reaction_notifications';
  static const _autoClearOnOpenKey = 'prefs_auto_clear_on_open';

  Future<UserPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    return UserPreferences(
      enterSendsMessage: preferences.getBool(_enterSendsMessageKey) ?? false,
      autoSaveAfterScan: preferences.getBool(_autoSaveAfterScanKey) ?? false,
      scanSaveDirectoryPath: _normalizeOptionalString(
        preferences.getString(_scanSaveDirPathKey),
      ),
      localStorageDirectoryPath: _normalizeOptionalString(
        preferences.getString(_localStorageDirPathKey),
      ),
      preferredPrinterName: _normalizeOptionalString(
        preferences.getString(_preferredPrinterNameKey),
      ),
      notificationToneId:
          preferences.getString(_notificationToneIdKey) ??
          NotificationTone.defaultTone.id,
      notificationDisplayModeId:
          preferences.getString(_notificationDisplayModeKey) ??
          NotificationDisplayMode.defaultMode.id,
      notificationsEnabled: preferences.getBool(_notificationsEnabledKey) ?? true,
      messageNotificationsEnabled:
          preferences.getBool(_messageNotificationsEnabledKey) ?? true,
      messageVibrate: preferences.getBool(_messageVibrateKey) ?? true,
      messagePreview: preferences.getBool(_messagePreviewKey) ?? true,
      groupNotificationsEnabled:
          preferences.getBool(_groupNotificationsEnabledKey) ?? true,
      groupToneId:
          preferences.getString(_groupToneIdKey) ??
          NotificationTone.defaultTone.id,
      groupVibrate: preferences.getBool(_groupVibrateKey) ?? true,
      groupPreview: preferences.getBool(_groupPreviewKey) ?? true,
      groupNotificationsByChat:
          preferences.getBool(_groupNotificationsByChatKey) ?? true,
      inAppBanners: preferences.getBool(_inAppBannersKey) ?? true,
      reactionNotifications:
          preferences.getBool(_reactionNotificationsKey) ?? true,
      autoClearOnOpen: preferences.getBool(_autoClearOnOpenKey) ?? true,
    );
  }

  Future<void> save(UserPreferences value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enterSendsMessageKey, value.enterSendsMessage);
    await preferences.setBool(_autoSaveAfterScanKey, value.autoSaveAfterScan);

    final scanPath = _normalizeOptionalString(value.scanSaveDirectoryPath);
    if (scanPath == null) {
      await preferences.remove(_scanSaveDirPathKey);
    } else {
      await preferences.setString(_scanSaveDirPathKey, scanPath);
    }

    final storagePath = _normalizeOptionalString(
      value.localStorageDirectoryPath,
    );
    if (storagePath == null) {
      await preferences.remove(_localStorageDirPathKey);
    } else {
      await preferences.setString(_localStorageDirPathKey, storagePath);
    }

    final preferredPrinter = _normalizeOptionalString(
      value.preferredPrinterName,
    );
    if (preferredPrinter == null) {
      await preferences.remove(_preferredPrinterNameKey);
    } else {
      await preferences.setString(_preferredPrinterNameKey, preferredPrinter);
    }

    await preferences.setString(
      _notificationToneIdKey,
      value.notificationToneId,
    );
    await preferences.setString(
      _notificationDisplayModeKey,
      value.notificationDisplayModeId,
    );

    // Save notification preferences
    await preferences.setBool(_notificationsEnabledKey, value.notificationsEnabled);
    await preferences.setBool(
      _messageNotificationsEnabledKey,
      value.messageNotificationsEnabled,
    );
    await preferences.setBool(_messageVibrateKey, value.messageVibrate);
    await preferences.setBool(_messagePreviewKey, value.messagePreview);
    await preferences.setBool(
      _groupNotificationsEnabledKey,
      value.groupNotificationsEnabled,
    );
    await preferences.setString(_groupToneIdKey, value.groupToneId);
    await preferences.setBool(_groupVibrateKey, value.groupVibrate);
    await preferences.setBool(_groupPreviewKey, value.groupPreview);
    await preferences.setBool(
      _groupNotificationsByChatKey,
      value.groupNotificationsByChat,
    );
    await preferences.setBool(_inAppBannersKey, value.inAppBanners);
    await preferences.setBool(
      _reactionNotificationsKey,
      value.reactionNotifications,
    );
    await preferences.setBool(_autoClearOnOpenKey, value.autoClearOnOpen);
  }

  String? _normalizeOptionalString(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
