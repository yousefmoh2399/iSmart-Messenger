import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Centralized utility for safe directory resolution across desktop and mobile.
/// Guarantees graceful fallback to [Directory.systemTemp] if [path_provider]
/// platform channels throw [MissingPluginException] or any [PlatformException].
class AppPathUtils {
  AppPathUtils._();

  /// Safely returns the temporary directory.
  /// Falls back to [Directory.systemTemp] on native platforms.
  static Future<Directory> getSafeTemporaryDirectory() async {
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      try {
        return Directory.systemTemp;
      } catch (_) {
        return Directory.current;
      }
    }
  }

  /// Synchronous system temporary directory fallback.
  static Directory get systemTempDirectory {
    try {
      return Directory.systemTemp;
    } catch (_) {
      return Directory.current;
    }
  }

  /// Safely returns the application support directory.
  static Future<Directory> getSafeApplicationSupportDirectory() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      if (!kIsWeb && Platform.isWindows) {
        final localAppData = Platform.environment['LOCALAPPDATA']?.trim();
        if (localAppData != null && localAppData.isNotEmpty) {
          final dir = Directory(p.join(localAppData, 'iSmartMessenger'));
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          return dir;
        }
      }
      return getSafeTemporaryDirectory();
    }
  }

  /// Safely returns the application documents directory.
  static Future<Directory> getSafeApplicationDocumentsDirectory() async {
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      if (!kIsWeb && Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE']?.trim();
        if (userProfile != null && userProfile.isNotEmpty) {
          final dir = Directory(p.join(userProfile, 'Documents', 'iSmartMessenger'));
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          return dir;
        }
      }
      return getSafeTemporaryDirectory();
    }
  }
}
