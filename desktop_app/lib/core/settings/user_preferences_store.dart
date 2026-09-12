import 'package:shared_preferences/shared_preferences.dart';

import 'user_preferences.dart';

class UserPreferencesStore {
  static const _enterSendsMessageKey = 'prefs_enter_sends_message';
  static const _autoSaveAfterScanKey = 'prefs_auto_save_after_scan';
  static const _scanSaveDirPathKey = 'prefs_scan_save_directory_path';
  static const _localStorageDirPathKey = 'prefs_local_storage_directory_path';
  static const _preferredPrinterNameKey = 'prefs_preferred_printer_name';
  static const _notificationToneIdKey = 'prefs_notification_tone_id';

  Future<UserPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    return UserPreferences(
      enterSendsMessage: preferences.getBool(_enterSendsMessageKey) ?? true,
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
  }

  String? _normalizeOptionalString(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
