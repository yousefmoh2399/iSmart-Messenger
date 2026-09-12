import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../../../core/network/api_client.dart';
import '../../../core/settings/user_preferences.dart';
import '../../../shared/models/remote_document.dart';
import '../../../shared/services/local_media_storage_service.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../../auth/data/auth_repository.dart';

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
  DocumentRepository(
    this._apiClient,
    this._authRepository,
    this._localStorage,
    this._preferences,
  );

  final ApiClient _apiClient;
  final AuthRepository _authRepository;
  final LocalMediaStorageService _localStorage;
  final UserPreferences _preferences;

  String _sanitizeFileName(String fileName) {
    final baseName = path.basename(fileName.trim());
    final cleaned = baseName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    final normalized = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    var safeName = normalized.isEmpty ? 'document' : normalized;
    final extension = path.extension(baseName);
    if (extension.isNotEmpty && !safeName.endsWith(extension)) {
      safeName = '$safeName$extension';
    }
    final reserved = {
      'CON',
      'PRN',
      'AUX',
      'NUL',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9',
    };
    final stem = path.basenameWithoutExtension(safeName).toUpperCase();
    if (reserved.contains(stem)) {
      safeName = 'file_$safeName';
    }
    return safeName;
  }

  Future<RemoteDocumentsPage> fetchDocumentsPage({
    bool includeAll = false,
    int page = 1,
    int limit = 40,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/documents',
      queryParameters: {
        if (includeAll) 'scope': 'all',
        'page': page,
        'limit': limit,
      },
    );
    final list = response.data?['documents'] as List<dynamic>? ?? const [];
    final pagination = response.data?['pagination'];
    return RemoteDocumentsPage(
      documents: list
          .cast<Map<String, dynamic>>()
          .map(RemoteDocument.fromJson)
          .toList(),
      page: pagination is Map ? (pagination['page'] as int? ?? page) : page,
      limit: pagination is Map ? (pagination['limit'] as int? ?? limit) : limit,
      hasMore: pagination is Map ? pagination['hasMore'] == true : false,
    );
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

  Future<int> syncPendingLocalDocuments({
    void Function(int received, int total)? onProgress,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/documents/pending-local-sync',
    );
    final list = response.data?['documents'] as List<dynamic>? ?? const [];
    final documents = list
        .cast<Map<String, dynamic>>()
        .map(RemoteDocument.fromJson)
        .toList();
    var synced = 0;
    for (final document in documents) {
      final bytesResponse = await _apiClient.dio.get<List<int>>(
        '/api/documents/${document.id}/download',
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: onProgress,
      );
      final safeName = _localDocumentFileName(document);
      final bytes = Uint8List.fromList(bytesResponse.data ?? const <int>[]);
      if (kIsWeb) {
        final savedPath = await web_bridge.downloadBytes(
          bytes: bytes,
          fileName: safeName,
          mimeType: document.mimeType,
          preferredDirectoryPath: await _electronDocumentsDirectoryPath(),
        );
        if (web_bridge.isElectron() &&
            (savedPath == null || savedPath.trim().isEmpty)) {
          throw Exception('Electron did not return the saved document path.');
        }
      } else {
        final file = await _localDocumentFile(document);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      }
      await _apiClient.dio.post<void>(
        '/api/documents/${document.id}/local-sync',
      );
      synced++;
    }
    return synced;
  }

  Future<RemoteDocument> renameDocument(
    String documentId,
    String fileName,
  ) async {
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/documents/$documentId/rename',
      data: {'fileName': fileName},
    );
    return RemoteDocument.fromJson(
      response.data?['document'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteDocument(String documentId) async {
    await _apiClient.dio.delete<void>('/api/documents/$documentId');
  }

  Future<Uint8List> fetchDocumentBytes(
    RemoteDocument document, {
    void Function(int received, int total)? onProgress,
  }) async {
    final response = await _apiClient.dio.get<List<int>>(
      '/api/documents/${document.id}/download',
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onProgress,
    );
    final bytes = Uint8List.fromList(response.data ?? const <int>[]);
    if (bytes.isEmpty) {
      throw Exception('Downloaded document is empty.');
    }
    return bytes;
  }

  final Map<String, _ActiveDownload> _activeDownloads = {};

  Future<String> downloadDocument(
    RemoteDocument document, {
    void Function(int received, int total)? onProgress,
  }) async {
    final docId = document.id;

    if (kIsWeb && web_bridge.isElectron()) {
      final localPath = await _electronLocalDocumentPath(document);
      if (localPath != null && await web_bridge.electronFileExists(localPath)) {
        return localPath;
      }
      final legacyPath = await _electronLegacyLocalDocumentPath(document);
      if (legacyPath != null &&
          await web_bridge.electronFileExists(legacyPath)) {
        return legacyPath;
      }
    }

    if (!kIsWeb) {
      final localFile = await _localDocumentFile(document);
      if (await localFile.exists()) {
        return localFile.path;
      }
    }

    _ActiveDownload? active = _activeDownloads[docId];
    if (active == null) {
      final controller = StreamController<double>.broadcast();

      final progressDispatcher = (int received, int total) {
        if (!controller.isClosed) {
          final progress = total <= 0
              ? 0.0
              : (received / total).clamp(0.0, 1.0);
          controller.add(progress);
        }
      };

      final Future<String> future = () async {
        if (kIsWeb) {
          final response = await _apiClient.dio.get<List<int>>(
            '/api/documents/${document.id}/download',
            options: Options(responseType: ResponseType.bytes),
            onReceiveProgress: progressDispatcher,
          );
          final bytes = Uint8List.fromList(response.data ?? const <int>[]);
          await web_bridge.downloadBytes(
            bytes: bytes,
            fileName: _localDocumentFileName(document),
            mimeType: 'application/pdf',
            preferredDirectoryPath: await _electronDocumentsDirectoryPath(),
          );
          return await _electronLocalDocumentPath(document) ??
              document.downloadUrl;
        }

        final downloadsDir = await _localStorage.documentsDirectory(
          preferredPath: _preferences.localStorageDirectoryPath,
        );
        await downloadsDir.create(recursive: true);
        final filePath = path.join(
          downloadsDir.path,
          _localDocumentFileName(document),
        );

        await _apiClient.dio.download(
          '/api/documents/${document.id}/download',
          filePath,
          onReceiveProgress: progressDispatcher,
        );
        return filePath;
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

  String _localDocumentFileName(RemoteDocument document) {
    return '${document.id}_${_sanitizeFileName(document.fileName)}';
  }

  Future<File> _localDocumentFile(RemoteDocument document) async {
    final directory = await _localStorage.documentsDirectory(
      preferredPath: _preferences.localStorageDirectoryPath,
    );
    return File(path.join(directory.path, _localDocumentFileName(document)));
  }

  Future<String?> _electronDocumentsDirectoryPath() async {
    if (!kIsWeb || !web_bridge.isElectron()) {
      return _preferences.localStorageDirectoryPath;
    }
    final root =
        _preferences.localStorageDirectoryPath ??
        await web_bridge.getElectronStorageRoot();
    if (root == null || root.trim().isEmpty) {
      return null;
    }
    return _joinWindowsPath(root.trim(), 'Documents');
  }

  Future<String?> _electronLocalDocumentPath(RemoteDocument document) async {
    final directory = await _electronDocumentsDirectoryPath();
    if (directory == null || directory.isEmpty) {
      return null;
    }
    return _joinWindowsPath(directory, _localDocumentFileName(document));
  }

  Future<String?> _electronLegacyLocalDocumentPath(
    RemoteDocument document,
  ) async {
    final root =
        _preferences.localStorageDirectoryPath ??
        await web_bridge.getElectronStorageRoot();
    if (root == null || root.trim().isEmpty) {
      return null;
    }
    return _joinWindowsPath(root.trim(), _localDocumentFileName(document));
  }

  String _joinWindowsPath(String left, String right) {
    final separator = left.contains(r'\') ? r'\' : '/';
    final normalizedLeft = left.endsWith(r'\') || left.endsWith('/')
        ? left.substring(0, left.length - 1)
        : left;
    return '$normalizedLeft$separator$right';
  }
}

class _ActiveDownload {
  _ActiveDownload({required this.result, required this.progressController});

  final Future<String> result;
  final StreamController<double> progressController;
}
