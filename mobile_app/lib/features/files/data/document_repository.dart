import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/settings/user_preferences.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/remote_document.dart';
import '../../../shared/services/local_media_storage_service.dart';

class RemoteDocumentsPage {
  const RemoteDocumentsPage({
    required this.documents,
    required this.page,
    required this.limit,
    required this.hasMore,
  });

  final List<RemoteDocument> documents;
  final int page;
  final int limit;
  final bool hasMore;
}

class DocumentRepository {
  DocumentRepository({
    required ApiClient apiClient,
    required LocalMediaStorageService localStorage,
    required UserPreferences preferences,
  }) : _apiClient = apiClient,
       _localStorage = localStorage,
       _preferences = preferences;

  final ApiClient _apiClient;
  final LocalMediaStorageService _localStorage;
  final UserPreferences _preferences;

  static const _localDocsKey = 'local_synced_documents_list';

  Duration _uploadTimeoutForBytes(int bytes) {
    const minSeconds = 120;
    const maxSeconds = 480;
    final sizeInMb = bytes / (1024 * 1024);
    final scaledSeconds = minSeconds + (sizeInMb * 10).ceil();
    final seconds = scaledSeconds.clamp(minSeconds, maxSeconds);
    return Duration(seconds: seconds);
  }

  String _sanitizeFileName(String fileName) {
    final baseName = path.basename(fileName.trim());
    final cleaned = baseName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    final normalized = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    var safeName = normalized.isEmpty ? 'document' : normalized;
    final extension = path.extension(baseName);
    if (extension.isNotEmpty && !safeName.endsWith(extension)) {
      safeName = '$safeName$extension';
    }
    return safeName;
  }

  Future<List<RemoteDocument>> _getLocalDocs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localDocsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(RemoteDocument.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveLocalDocs(List<RemoteDocument> docs) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(docs.map((d) => d.toJson()).toList());
    await prefs.setString(_localDocsKey, encoded);
  }

  Future<RemoteDocumentsPage> fetchDocumentsPage({
    bool includeAll = false,
    int page = 1,
    int limit = 40,
  }) async {
    final localDocs = await _getLocalDocs();
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/documents',
        queryParameters: {
          if (includeAll) 'scope': 'all',
          'page': page,
          'limit': limit,
        },
      );

      final remoteList =
          (response.data?['documents'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>()
              .map(RemoteDocument.fromJson)
              .toList();

      final mergedMap = <String, RemoteDocument>{};
      for (final doc in localDocs) {
        mergedMap[doc.id] = doc;
      }
      for (final doc in remoteList) {
        mergedMap[doc.id] = doc;
      }

      final mergedList = mergedMap.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      await _saveLocalDocs(mergedList);

      final pagination = response.data?['pagination'];
      return RemoteDocumentsPage(
        documents: remoteList,
        page: pagination is Map ? (pagination['page'] as int? ?? page) : page,
        limit: pagination is Map
            ? (pagination['limit'] as int? ?? limit)
            : limit,
        hasMore: pagination is Map ? pagination['hasMore'] == true : false,
      );
    } catch (error) {
      final fallback = localDocs.skip((page - 1) * limit).take(limit).toList();
      return RemoteDocumentsPage(
        documents: fallback,
        page: page,
        limit: limit,
        hasMore: page * limit < localDocs.length,
      );
    }
  }

  Future<List<RemoteDocument>> fetchDocuments({
    bool includeAll = false,
    int page = 1,
    int limit = 40,
  }) async {
    final result = await fetchDocumentsPage(
      includeAll: includeAll,
      page: page,
      limit: limit,
    );
    return result.documents;
  }

  Future<RemoteDocument> uploadPendingDocument(
    PendingUpload pendingUpload, {
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      final file = await _resolvePendingUploadFile(pendingUpload);
      final timeout = _uploadTimeoutForBytes(pendingUpload.fileSize);
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/documents/upload',
        data: FormData.fromMap({
          'file': await MultipartFile.fromFile(
            file.path,
            filename: pendingUpload.fileName,
          ),
          'fileName': pendingUpload.fileName,
          'pageCount': pendingUpload.pageCount,
          'fileSize': pendingUpload.fileSize,
        }),
        options: Options(
          connectTimeout: timeout,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
        onSendProgress: onProgress,
      );

      final document = RemoteDocument.fromJson(
        response.data?['document'] as Map<String, dynamic>,
      );
      await _copyPendingUploadToLocalDocument(pendingUpload, document);

      final localDocs = await _getLocalDocs();
      localDocs.insert(0, document);
      await _saveLocalDocs(localDocs);

      return document;
    } catch (error) {
      throw _apiClient.mapError(error);
    }
  }

  Future<File> _resolvePendingUploadFile(PendingUpload pendingUpload) async {
    final file = File(pendingUpload.filePath);
    if (await file.exists()) {
      return file;
    }

    throw const ApiException(
      'ملف الرفع المحلي غير موجود. احذف هذا العنصر وامسح المستند مرة أخرى بعد التحديث.',
    );
  }

  Future<RemoteDocument> renameDocument(
    String documentId,
    String fileName,
  ) async {
    try {
      final response = await _apiClient.dio.put<Map<String, dynamic>>(
        '/api/documents/$documentId/rename',
        data: {'fileName': fileName},
      );
      final updatedDoc = RemoteDocument.fromJson(
        response.data?['document'] as Map<String, dynamic>,
      );

      final localDocs = await _getLocalDocs();
      final index = localDocs.indexWhere((d) => d.id == documentId);
      if (index >= 0) {
        localDocs[index] = updatedDoc;
        await _saveLocalDocs(localDocs);
      }

      return updatedDoc;
    } catch (error) {
      throw _apiClient.mapError(error);
    }
  }

  Future<void> deleteDocument(String documentId) async {
    try {
      await _apiClient.dio.delete<void>('/api/documents/$documentId');
    } catch (error) {
      // Even if API fails (e.g. already deleted), we should delete locally
    }

    final localDocs = await _getLocalDocs();
    final doc = localDocs.firstWhere(
      (d) => d.id == documentId,
      orElse: () => throw const ApiException('الملف غير موجود'),
    );
    final file = await _localDocumentFile(doc);
    if (await file.exists()) {
      await file.delete();
    }

    localDocs.removeWhere((d) => d.id == documentId);
    await _saveLocalDocs(localDocs);
  }

  final Map<String, _ActiveDownload> _activeDownloads = {};

  Future<String> downloadDocument(
    RemoteDocument document, {
    void Function(int received, int total)? onProgress,
  }) async {
    final docId = document.id;
    final localFile = await _localDocumentFile(document);
    if (await localFile.exists()) {
      return localFile.path;
    }

    _ActiveDownload? active = _activeDownloads[docId];
    if (active == null) {
      final controller = StreamController<double>.broadcast();
      final downloadsDir = await _localStorage.documentsDirectory(
        preferredPath: _preferences.localStorageDirectoryPath,
      );
      final outputPath = path.join(
        downloadsDir.path,
        _localDocumentFileName(document),
      );
      final tempOutputPath = '$outputPath.part';

      final progressDispatcher = (int received, int total) {
        if (!controller.isClosed) {
          final progress = total <= 0
              ? 0.0
              : (received / total).clamp(0.0, 1.0);
          controller.add(progress);
        }
      };

      final Future<String> future = () async {
        try {
          final tempFile = File(tempOutputPath);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
          await _apiClient.dio.download(
            '/api/documents/${document.id}/download',
            tempOutputPath,
            onReceiveProgress: progressDispatcher,
          );
          final downloaded = File(tempOutputPath);
          if (!await downloaded.exists() || await downloaded.length() == 0) {
            throw const ApiException('Downloaded document is empty.');
          }
          await downloaded.rename(outputPath);
          return outputPath;
        } catch (error) {
          try {
            final tempFile = File(tempOutputPath);
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          } catch (_) {}
          throw _apiClient.mapError(error);
        }
      }();

      active = _ActiveDownload(result: future, progressController: controller);
      _activeDownloads[docId] = active;

      unawaited(
        future.whenComplete(() async {
          final currentActive = _activeDownloads[docId];
          if (identical(currentActive?.result, future)) {
            _activeDownloads.remove(docId);
            if (!controller.isClosed) {
              await controller.close();
            }
          }
        }),
      );
    }

    StreamSubscription<double>? subscription;
    if (onProgress != null) {
      subscription = active.progressController.stream.listen((pct) {
        onProgress((pct * 100).toInt(), 100);
      });
    }

    try {
      return await active.result;
    } catch (error) {
      rethrow;
    } finally {
      await subscription?.cancel();
    }
  }

  Future<void> _copyPendingUploadToLocalDocument(
    PendingUpload pendingUpload,
    RemoteDocument document,
  ) async {
    final source = File(pendingUpload.filePath);
    if (!await source.exists()) {
      return;
    }
    final target = await _localDocumentFile(document);
    await target.parent.create(recursive: true);
    await source.copy(target.path);
  }

  String _localDocumentFileName(RemoteDocument document) {
    return '${document.id}_${_sanitizeFileName(document.fileName)}';
  }

  Future<File> _localDocumentFile(RemoteDocument document) async {
    final directory = await _localStorage.documentsDirectory(
      preferredPath: _preferences.localStorageDirectoryPath,
    );
    return File(path.join(directory.path, _localDocumentFileName(document)));
  }
}

class _ActiveDownload {
  _ActiveDownload({required this.result, required this.progressController});

  final Future<String> result;
  final StreamController<double> progressController;
}
