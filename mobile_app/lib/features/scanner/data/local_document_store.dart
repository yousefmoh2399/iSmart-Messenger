import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_session.dart';
import '../../../shared/services/local_media_storage_service.dart';

class LocalDocumentStore {
  static const _pendingUploadsKey = 'pending_uploads';
  static const _scanDraftKey = 'scan_draft';

  Future<void> initialize() async {
    await getPendingDirectory();
    await getDraftsDirectory();
    await getDownloadsDirectory();
  }

  Future<Directory> _appDirectory() =>
      path_provider.getApplicationDocumentsDirectory();

  Future<Directory> getPendingDirectory() async {
    final directory = Directory(
      path.join((await _appDirectory()).path, 'pending'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> getDraftsDirectory() async {
    final directory = Directory(
      path.join((await _appDirectory()).path, 'drafts'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> getDownloadsDirectory() async {
    return const LocalMediaStorageService().scansDirectory();
  }

  Future<List<PendingUpload>> loadPendingUploads() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_pendingUploadsKey);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    final uploads = decoded
        .cast<Map<String, dynamic>>()
        .map(PendingUpload.fromJson)
        .toList();

    var updated = false;
    final validUploads = <PendingUpload>[];
    for (final upload in uploads) {
      final repaired = await _repairPendingUploadPath(upload);
      if (repaired.filePath != upload.filePath ||
          repaired.fileSize != upload.fileSize) {
        updated = true;
      }
      if (File(repaired.filePath).existsSync()) {
        validUploads.add(repaired);
      } else {
        updated = true;
      }
    }

    if (updated) {
      await _savePendingUploads(validUploads);
    }

    return validUploads;
  }

  Future<void> _savePendingUploads(List<PendingUpload> uploads) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _pendingUploadsKey,
      jsonEncode(uploads.map((upload) => upload.toJson()).toList()),
    );
  }

  Future<PendingUpload> createPendingUpload({
    required String fileName,
    required Uint8List pdfBytes,
    required int pageCount,
    String? saveDirectoryPath,
  }) async {
    final id = const Uuid().v4();
    final sanitizedName = sanitizePdfName(fileName);
    final file = await _writePendingUploadFile(
      id: id,
      sanitizedName: sanitizedName,
      pdfBytes: pdfBytes,
      preferredDirectoryPath: saveDirectoryPath,
    );

    final upload = PendingUpload(
      id: id,
      fileName: sanitizedName,
      filePath: file.path,
      pageCount: pageCount,
      fileSize: await file.length(),
      createdAt: DateTime.now(),
    );

    final items = await loadPendingUploads();
    await _savePendingUploads([upload, ...items]);
    return upload;
  }

  Future<File> _writePendingUploadFile({
    required String id,
    required String sanitizedName,
    required Uint8List pdfBytes,
    required String? preferredDirectoryPath,
  }) async {
    final pendingDirectory = await getPendingDirectory();
    await pendingDirectory.create(recursive: true);
    final pendingFile = File(
      path.join(pendingDirectory.path, '${id}_$sanitizedName'),
    );
    await pendingFile.writeAsBytes(pdfBytes, flush: true);

    // التحقق الصريح من سلامة بايتات الـ PDF
    final headerBytes = await pendingFile.openRead(0, 5).first;
    final headerString = String.fromCharCodes(headerBytes);
    if (headerString != '%PDF-') {
      await pendingFile.delete();
      throw Exception('الملف الناتج تالف وليس بصيغة PDF صحيحة.');
    }

    final candidateDirectories = <Directory>[];
    if (preferredDirectoryPath != null &&
        preferredDirectoryPath.trim().isNotEmpty) {
      candidateDirectories.add(
        Directory(path.join(preferredDirectoryPath.trim(), 'Scans')),
      );
    }
    candidateDirectories.add(await getDownloadsDirectory());
    for (final directory in candidateDirectories) {
      try {
        await directory.create(recursive: true);
        final file = File(path.join(directory.path, '${id}_$sanitizedName'));
        await file.writeAsBytes(pdfBytes, flush: true);
        break;
      } catch (_) {
        // Best-effort export only. Uploads rely on the internal pending file.
      }
    }

    return pendingFile;
    /*
    throw Exception(
      'تعذر حفظ الملف في المسار المطلوب أو في مجلد التطبيق الآمن. ${lastError ?? ''}'
          .trim(),
    );
*/
  }

  Future<void> removePendingUpload(String id) async {
    final items = await loadPendingUploads();
    final target = items.where((upload) => upload.id == id).toList();
    for (final upload in target) {
      final file = File(upload.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _savePendingUploads(
      items.where((upload) => upload.id != id).toList(),
    );
  }

  Future<PendingUpload> _repairPendingUploadPath(PendingUpload upload) async {
    final currentFile = File(upload.filePath);
    if (await currentFile.exists()) {
      return upload;
    }

    final pendingDirectory = await getPendingDirectory();
    final repairedPath = path.join(
      pendingDirectory.path,
      path.basename(upload.filePath),
    );
    final repairedFile = File(repairedPath);
    if (!await repairedFile.exists()) {
      return upload;
    }

    return PendingUpload(
      id: upload.id,
      fileName: upload.fileName,
      filePath: repairedPath,
      pageCount: upload.pageCount,
      fileSize: await repairedFile.length(),
      createdAt: upload.createdAt,
    );
  }

  Future<void> saveDraft(ScanSession session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_scanDraftKey, jsonEncode(session.toJson()));
  }

  Future<ScanSession?> loadDraft() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_scanDraftKey);
    if (raw == null || raw.isEmpty) return null;

    final session = ScanSession.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    final validPages = session.pages
        .where((page) => File(page.imagePath).existsSync())
        .toList();
    if (validPages.isEmpty) {
      await clearDraft();
      return null;
    }
    return session.copyWith(pages: validPages);
  }

  Future<void> clearDraft() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_scanDraftKey);
  }

  Future<String> savePageBytes({
    required String sessionId,
    required String pageId,
    required Uint8List bytes,
  }) async {
    final draftsDirectory = await getDraftsDirectory();
    final sessionDirectory = Directory(
      path.join(draftsDirectory.path, sessionId),
    );
    await sessionDirectory.create(recursive: true);
    final filePath = path.join(sessionDirectory.path, '$pageId.jpg');
    await File(filePath).writeAsBytes(bytes);
    return filePath;
  }

  Future<String> importRawScanFile({
    required String sessionId,
    required String sourcePath,
  }) async {
    final draftsDirectory = await getDraftsDirectory();
    final sessionDirectory = Directory(
      path.join(draftsDirectory.path, sessionId),
    );
    await sessionDirectory.create(recursive: true);

    final extension = path.extension(sourcePath).trim().isEmpty
        ? '.jpg'
        : path.extension(sourcePath);
    final filePath = path.join(
      sessionDirectory.path,
      'raw_${const Uuid().v4()}$extension',
    );
    final copiedFile = await File(sourcePath).copy(filePath);
    return copiedFile.path;
  }

  Future<void> clearSessionFiles(String sessionId) async {
    final draftsDirectory = await getDraftsDirectory();
    final sessionDirectory = Directory(
      path.join(draftsDirectory.path, sessionId),
    );
    if (await sessionDirectory.exists()) {
      await sessionDirectory.delete(recursive: true);
    }
  }

  Future<void> deletePageFile(String imagePath) async {
    final file = File(imagePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
