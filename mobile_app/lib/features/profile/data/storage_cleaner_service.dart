import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StorageCategory {
  appCache,
  media,
  audio,
  documents,
}

class StorageBreakdown {
  const StorageBreakdown({
    this.appCacheBytes = 0,
    this.mediaBytes = 0,
    this.audioBytes = 0,
    this.documentsBytes = 0,
  });

  final int appCacheBytes;
  final int mediaBytes;
  final int audioBytes;
  final int documentsBytes;

  int get totalBytes =>
      appCacheBytes + mediaBytes + audioBytes + documentsBytes;

  String get formattedTotal => formatBytes(totalBytes);
  String get formattedAppCache => formatBytes(appCacheBytes);
  String get formattedMedia => formatBytes(mediaBytes);
  String get formattedAudio => formatBytes(audioBytes);
  String get formattedDocuments => formatBytes(documentsBytes);

  static String formatBytes(int bytes, [int decimals = 1]) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor().clamp(0, suffixes.length - 1);
    final size = bytes / pow(1024, i);
    return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
  }
}

final storageCleanerServiceProvider = Provider<StorageCleanerService>((ref) {
  return StorageCleanerService();
});

class StorageCleanerService {
  static const _prefRetentionDaysKey = 'storage_retention_days';
  static const _prefCleanOnLogoutKey = 'storage_clean_on_logout';

  static const _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
    '.ico',
  };

  static const _audioExtensions = {
    '.m4a',
    '.aac',
    '.mp3',
    '.wav',
    '.ogg',
    '.opus',
    '.flac',
  };

  static const _docExtensions = {
    '.pdf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.txt',
    '.csv',
    '.zip',
    '.rar',
  };

  /// Calculates storage breakdown safely without accessing SQLite databases or message logs.
  Future<StorageBreakdown> calculateBreakdown() async {
    int appCache = 0;
    int media = 0;
    int audio = 0;
    int documents = 0;

    try {
      // 1. Temporary Directory
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        await for (final entity in tempDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              final size = await entity.length();
              final ext = p.extension(entity.path).toLowerCase();
              if (_imageExtensions.contains(ext)) {
                media += size;
              } else if (_audioExtensions.contains(ext)) {
                audio += size;
              } else if (_docExtensions.contains(ext)) {
                documents += size;
              } else {
                appCache += size;
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[StorageCleaner] error scanning tempDir: $e');
    }

    try {
      // 2. Memory image cache estimate
      final memCacheSize = PaintingBinding.instance.imageCache.currentSizeBytes;
      appCache += memCacheSize;
    } catch (_) {}

    return StorageBreakdown(
      appCacheBytes: appCache,
      mediaBytes: media,
      audioBytes: audio,
      documentsBytes: documents,
    );
  }

  /// Cleans all temporary caches without modifying conversation database.
  Future<void> clearAll() async {
    await clearCategory(StorageCategory.appCache);
    await clearCategory(StorageCategory.media);
    await clearCategory(StorageCategory.audio);
    await clearCategory(StorageCategory.documents);
  }

  /// Cleans a specific storage category.
  Future<void> clearCategory(StorageCategory category) async {
    try {
      if (category == StorageCategory.appCache) {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      }

      final tempDir = await getTemporaryDirectory();
      if (!tempDir.existsSync()) return;

      await for (final entity in tempDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          bool shouldDelete = false;

          switch (category) {
            case StorageCategory.appCache:
              if (!_imageExtensions.contains(ext) &&
                  !_audioExtensions.contains(ext) &&
                  !_docExtensions.contains(ext)) {
                shouldDelete = true;
              }
              break;
            case StorageCategory.media:
              if (_imageExtensions.contains(ext)) {
                shouldDelete = true;
              }
              break;
            case StorageCategory.audio:
              if (_audioExtensions.contains(ext)) {
                shouldDelete = true;
              }
              break;
            case StorageCategory.documents:
              if (_docExtensions.contains(ext)) {
                shouldDelete = true;
              }
              break;
          }

          if (shouldDelete) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[StorageCleaner] error clearing $category: $e');
    }
  }

  // ── Retention & Auto Clean Preferences ───────────────────────────────────

  Future<int> getRetentionDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefRetentionDaysKey) ?? 30;
  }

  Future<void> setRetentionDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefRetentionDaysKey, days);
  }

  Future<bool> getCleanOnLogout() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefCleanOnLogoutKey) ?? false;
  }

  Future<void> setCleanOnLogout(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefCleanOnLogoutKey, value);
  }
}
