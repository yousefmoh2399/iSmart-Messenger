import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class WindowsStorageMigration {
  WindowsStorageMigration._();

  static const String _companyName = 'Yousef Mohamed';
  static const String _productName = 'iSmart Messenger';
  static const String _sharedPreferencesFileName = 'shared_preferences.json';
  static const Set<String> _importantPreferenceKeys = <String>{
    'desktop_auth_token',
    'desktop_refresh_token',
    'desktop_remembered_username',
    'desktop_remember_username_enabled',
    'desktop_api_base_url_v2',
    'desktop_api_base_url_override_v1',
    'desktop_api_base_url_admin_default_v1',
    'theme_mode',
    'prefs_enter_sends_message',
    'prefs_auto_save_after_scan',
    'prefs_scan_save_directory_path',
    'prefs_preferred_printer_name',
    'prefs_notification_tone_id',
  };

  static Future<void> migrateIfNeeded() async {
    if (kIsWeb) {
      return;
    }
    if (!Platform.isWindows) {
      return;
    }

    final roamingAppData = Platform.environment['APPDATA']?.trim();
    if (roamingAppData == null || roamingAppData.isEmpty) {
      return;
    }

    final currentSupportDir = Directory(
      path.join(roamingAppData, _companyName, _productName),
    );
    final currentPrefsFile = File(
      path.join(currentSupportDir.path, _sharedPreferencesFileName),
    );
    final currentPrefs = await _readPreferences(currentPrefsFile);
    if (_hasMeaningfulPreferences(currentPrefs)) {
      return;
    }

    _LegacyPreferencesCandidate? bestCandidate;
    for (final candidatePath in _buildCandidateDirectories(
      roamingAppData,
      currentSupportDir.path,
    )) {
      final prefsFile = File(
        path.join(candidatePath, _sharedPreferencesFileName),
      );
      final prefs = await _readPreferences(prefsFile);
      if (!_hasMeaningfulPreferences(prefs)) {
        continue;
      }
      final candidate = _LegacyPreferencesCandidate(
        preferences: prefs,
        score: _scorePreferences(prefs),
      );
      if (bestCandidate == null || candidate.score > bestCandidate.score) {
        bestCandidate = candidate;
      }
    }

    if (bestCandidate == null) {
      return;
    }

    await Directory(currentSupportDir.path).create(recursive: true);
    final mergedPreferences = <String, dynamic>{
      ...bestCandidate.preferences,
      ...currentPrefs,
    };
    await currentPrefsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(mergedPreferences),
      flush: true,
    );
  }

  static Iterable<String> _buildCandidateDirectories(
    String roamingAppData,
    String currentSupportPath,
  ) sync* {
    final normalizedCurrent = path.normalize(currentSupportPath).toLowerCase();
    final seen = <String>{};

    final companies = <String?>['com.example', 'Yousef Mohamed', null];
    final products = <String>[
      'iSmart Messenger',
      'iSmartMessenger',
      'desktop_app',
    ];

    for (final company in companies) {
      for (final product in products) {
        final candidate = company == null
            ? path.join(roamingAppData, product)
            : path.join(roamingAppData, company, product);
        final normalizedCandidate = path.normalize(candidate).toLowerCase();
        if (normalizedCandidate == normalizedCurrent ||
            !seen.add(normalizedCandidate)) {
          continue;
        }
        yield candidate;
      }
    }
  }

  static Future<Map<String, dynamic>> _readPreferences(File file) async {
    if (!file.existsSync()) {
      return const <String, dynamic>{};
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return const <String, dynamic>{};
  }

  static bool _hasMeaningfulPreferences(Map<String, dynamic> values) {
    if (values.isEmpty) {
      return false;
    }
    for (final key in _importantPreferenceKeys) {
      final value = values[key];
      if (_isMeaningfulValue(value)) {
        return true;
      }
    }
    return false;
  }

  static bool _isMeaningfulValue(dynamic value) {
    if (value == null) {
      return false;
    }
    if (value is String) {
      return value.trim().isNotEmpty;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is List) {
      return value.isNotEmpty;
    }
    if (value is Map) {
      return value.isNotEmpty;
    }
    return true;
  }

  static int _scorePreferences(Map<String, dynamic> values) {
    var score = values.length;
    if (_isMeaningfulValue(values['desktop_auth_token'])) {
      score += 100;
    }
    if (_isMeaningfulValue(values['desktop_refresh_token'])) {
      score += 80;
    }
    if (_isMeaningfulValue(values['desktop_remembered_username'])) {
      score += 30;
    }
    if (_isMeaningfulValue(values['prefs_scan_save_directory_path'])) {
      score += 20;
    }
    if (_isMeaningfulValue(values['prefs_preferred_printer_name'])) {
      score += 20;
    }
    if (_isMeaningfulValue(values['theme_mode'])) {
      score += 10;
    }
    return score;
  }
}

class _LegacyPreferencesCandidate {
  const _LegacyPreferencesCandidate({
    required this.preferences,
    required this.score,
  });

  final Map<String, dynamic> preferences;
  final int score;
}
