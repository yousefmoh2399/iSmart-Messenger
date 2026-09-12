import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalMediaStorageService {
  const LocalMediaStorageService();

  static const appFolderName = 'iSmart Messenger';
  static const storageFolderName = 'Storage';

  Future<Directory> resolveRootDirectory({String? preferredPath}) async {
    final customPath = preferredPath?.trim();
    if (customPath != null && customPath.isNotEmpty) {
      final directory = Directory(customPath);
      await directory.create(recursive: true);
      return directory;
    }

    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA']?.trim();
      if (localAppData != null && localAppData.isNotEmpty) {
        final directory = Directory(
          p.join(localAppData, appFolderName, storageFolderName),
        );
        await directory.create(recursive: true);
        return directory;
      }
    }

    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, storageFolderName));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> chatDirectory({String? preferredPath}) =>
      _childDirectory('Chat', preferredPath: preferredPath);

  Future<Directory> sentChatArchiveDirectory({String? preferredPath}) async {
    final chat = await chatDirectory(preferredPath: preferredPath);
    final directory = Directory(p.join(chat.path, 'sent'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> documentsDirectory({String? preferredPath}) =>
      _childDirectory('Documents', preferredPath: preferredPath);

  Future<Directory> scansDirectory({String? preferredPath}) =>
      _childDirectory('Scans', preferredPath: preferredPath);

  Future<Directory> incomingDirectory({String? preferredPath}) =>
      _childDirectory('Incoming', preferredPath: preferredPath);

  Future<void> initializeStorageTree({String? preferredPath}) async {
    await Future.wait([
      chatDirectory(preferredPath: preferredPath),
      sentChatArchiveDirectory(preferredPath: preferredPath),
      documentsDirectory(preferredPath: preferredPath),
      scansDirectory(preferredPath: preferredPath),
      incomingDirectory(preferredPath: preferredPath),
    ]);
  }

  Future<String> writeUniqueFile({
    required Directory directory,
    required String fileName,
    required Uint8List bytes,
    String? prefix,
  }) async {
    await directory.create(recursive: true);
    final safeName = sanitizeFileName(fileName);
    final baseName = p.basenameWithoutExtension(safeName);
    final extension = p.extension(safeName);
    final stem = prefix == null || prefix.trim().isEmpty
        ? baseName
        : '${sanitizeFileName(prefix)}_$baseName';
    var candidate = p.join(directory.path, '$stem$extension');
    var counter = 1;
    while (await File(candidate).exists()) {
      candidate = p.join(directory.path, '$stem ($counter)$extension');
      counter += 1;
    }
    await File(candidate).writeAsBytes(bytes, flush: true);
    return candidate;
  }

  String sanitizeFileName(String input) {
    final baseName = p.basename(input.trim());
    final cleaned = baseName
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'file' : cleaned;
  }

  Future<String> calculateFileSha256(String filePath) async {
    final digest = await sha256.bind(File(filePath).openRead()).first;
    return digest.toString();
  }

  Future<String> archiveSentChatFile({
    required String messageId,
    required String sha256Hex,
    required String fileName,
    String? sourcePath,
    Uint8List? bytes,
    String? preferredPath,
  }) async {
    final directory = await sentChatArchiveDirectory(
      preferredPath: preferredPath,
    );
    final safeMessageId = sanitizeFileName(messageId);
    final safeHash = sha256Hex.toLowerCase().replaceAll(
      RegExp(r'[^a-f0-9]'),
      '',
    );
    final extension = p.extension(sanitizeFileName(fileName));
    final targetPath = p.join(
      directory.path,
      '${safeMessageId}_$safeHash${extension.isEmpty ? '.bin' : extension}',
    );
    if (await File(targetPath).exists()) {
      return targetPath;
    }
    if (bytes != null) {
      await File(targetPath).writeAsBytes(bytes, flush: true);
      return targetPath;
    }
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      throw ArgumentError('sourcePath or bytes is required.');
    }
    await File(sourcePath).copy(targetPath);
    return targetPath;
  }

  Future<File?> findSentChatArchive({
    required String messageId,
    required String sha256Hex,
    String? preferredPath,
  }) async {
    final directory = await sentChatArchiveDirectory(
      preferredPath: preferredPath,
    );
    final safeMessageId = sanitizeFileName(messageId);
    final safeHash = sha256Hex.toLowerCase().replaceAll(
      RegExp(r'[^a-f0-9]'),
      '',
    );
    if (!await directory.exists()) return null;
    await for (final entry in directory.list()) {
      if (entry is! File) continue;
      final name = p.basename(entry.path).toLowerCase();
      if (name.startsWith('${safeMessageId.toLowerCase()}_') &&
          name.contains(safeHash) &&
          await entry.exists()) {
        return entry;
      }
    }
    return null;
  }

  Future<Directory> _childDirectory(
    String name, {
    required String? preferredPath,
  }) async {
    final root = await resolveRootDirectory(preferredPath: preferredPath);
    final directory = Directory(p.join(root.path, name));
    await directory.create(recursive: true);
    return directory;
  }
}
