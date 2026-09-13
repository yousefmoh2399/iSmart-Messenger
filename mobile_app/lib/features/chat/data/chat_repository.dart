import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../../core/network/api_client.dart';
import '../../../core/settings/user_preferences.dart';
import '../../../shared/services/local_media_storage_service.dart';
import '../models/chat_models.dart';

class ChatRepository {
  ChatRepository(this._apiClient, this._localStorage, this._preferences);

  final Set<String> _missingAttachmentPreviewUrls = <String>{};
  static const int _maxConcurrentPreviewDownloads = 3;
  int _activePreviewDownloads = 0;
  final Queue<Completer<void>> _previewDownloadQueue = Queue<Completer<void>>();
  final Map<String, Future<Uint8List>> _attachmentBytesInFlight =
      <String, Future<Uint8List>>{};
  final Map<String, Future<Uint8List>> _attachmentPreviewInFlight =
      <String, Future<Uint8List>>{};

  final ApiClient _apiClient;
  final LocalMediaStorageService _localStorage;
  final UserPreferences _preferences;

  List<Map<String, dynamic>> _extractList(
    Map<String, dynamic>? data,
    String key,
  ) {
    return (data?[key] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Duration _uploadTimeoutForBytes(int bytes) {
    const minSeconds = 90;
    const maxSeconds = 420;
    final sizeInMb = bytes / (1024 * 1024);
    final scaledSeconds = minSeconds + (sizeInMb * 8).ceil();
    final seconds = scaledSeconds.clamp(minSeconds, maxSeconds);
    return Duration(seconds: seconds);
  }

  Future<List<ChatConversation>> fetchConversations() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/chat/conversations',
    );
    return _extractList(
      response.data,
      'conversations',
    ).map(ChatConversation.fromJson).toList();
  }

  Future<List<ChatConversation>> fetchManageableConversations() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/chat/admin/conversations',
    );
    return _extractList(
      response.data,
      'conversations',
    ).map(ChatConversation.fromJson).toList();
  }

  Future<ChatConversation> fetchConversation(String conversationId) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId',
    );
    return ChatConversation.fromJson(
      response.data?['conversation'] as Map<String, dynamic>,
    );
  }

  Future<ChatDirectoryUsersPage> fetchUsersPage({
    String? search,
    String? departmentId,
    String? branchId,
    int? page,
    int? limit,
  }) async {
    final resolvedPage = page ?? 1;
    final resolvedLimit = limit ?? 50;
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/chat/users',
      queryParameters: {
        if (page != null) 'page': page,
        if (limit != null) 'limit': limit,
        if (search != null && search.trim().isNotEmpty) 'q': search.trim(),
        if (departmentId != null && departmentId.trim().isNotEmpty)
          'departmentId': departmentId.trim(),
        if (branchId != null && branchId.trim().isNotEmpty)
          'branchId': branchId.trim(),
      },
    );
    final users = _extractList(
      response.data,
      'users',
    ).map(ChatDirectoryUser.fromJson).toList();
    final pagination = response.data?['pagination'];
    return ChatDirectoryUsersPage(
      users: users,
      page: pagination is Map
          ? (pagination['page'] as int? ?? resolvedPage)
          : resolvedPage,
      limit: pagination is Map
          ? (pagination['limit'] as int? ?? resolvedLimit)
          : resolvedLimit,
      hasMore: pagination is Map ? pagination['hasMore'] == true : false,
    );
  }

  Future<List<ChatDirectoryUser>> fetchUsers({
    String? search,
    String? departmentId,
    String? branchId,
    int? page,
    int? limit,
  }) async {
    final result = await fetchUsersPage(
      search: search,
      departmentId: departmentId,
      branchId: branchId,
      page: page,
      limit: limit,
    );
    return result.users;
  }

  Future<List<DepartmentSummary>> fetchDepartments() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/departments',
    );
    return _extractList(
      response.data,
      'departments',
    ).map(DepartmentSummary.fromJson).toList();
  }

  Future<List<BranchSummary>> fetchBranches() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/branches',
    );
    return _extractList(
      response.data,
      'branches',
    ).map(BranchSummary.fromJson).toList();
  }

  Future<List<ChatRole>> fetchRoles() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/chat/roles',
    );
    return _extractList(response.data, 'roles').map(ChatRole.fromJson).toList();
  }

  Future<List<ChatAuditLog>> fetchAuditLogs({
    String? departmentId,
    int limit = 100,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/chat/admin/audit-logs',
      queryParameters: {
        if (departmentId != null && departmentId.isNotEmpty)
          'departmentId': departmentId,
        'limit': limit,
      },
    );
    return _extractList(
      response.data,
      'logs',
    ).map(ChatAuditLog.fromJson).toList();
  }

  Future<List<ChatSystemError>> fetchSystemErrors({
    int limit = 100,
    int? statusCode,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/chat/admin/system-errors',
      queryParameters: {
        'limit': limit,
        if (statusCode != null) 'statusCode': statusCode,
      },
    );
    return _extractList(
      response.data,
      'logs',
    ).map(ChatSystemError.fromJson).toList();
  }

  Future<ChatConversation> createDirectConversation(String userId) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat/conversations',
      data: {
        'type': 'direct',
        'memberIds': [userId],
      },
    );
    return ChatConversation.fromJson(
      response.data?['conversation'] as Map<String, dynamic>,
    );
  }

  Future<ChatConversation> createConversation({
    required String type,
    required String name,
    String description = '',
    List<String> memberIds = const [],
    List<String> adminIds = const [],
    String? departmentId,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat/conversations',
      data: {
        'type': type,
        'name': name,
        'description': description,
        'memberIds': memberIds,
        'adminIds': adminIds,
        if (departmentId != null && departmentId.isNotEmpty)
          'departmentId': departmentId,
      },
    );
    return ChatConversation.fromJson(
      response.data?['conversation'] as Map<String, dynamic>,
    );
  }

  Future<ChatMessagesPage> fetchMessages(
    String conversationId, {
    String? cursor,
    int limit = 40,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId/messages',
      queryParameters: {
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': limit,
      },
    );
    final meta = response.data?['meta'] as Map<String, dynamic>? ?? const {};
    return ChatMessagesPage(
      messages: _extractList(
        response.data,
        'messages',
      ).map(ChatMessage.fromJson).toList(),
      nextCursor: meta['nextCursor'] as String?,
      hasMore: meta['hasMore'] == true,
      limit: meta['limit'] as int? ?? limit,
    );
  }

  Future<ChatSearchResult> searchMessages({
    required String query,
    String? conversationId,
    String? cursor,
    int limit = 25,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/chat/search/messages',
      queryParameters: {
        'q': query,
        if (conversationId != null && conversationId.isNotEmpty)
          'conversationId': conversationId,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': limit,
      },
    );
    final meta = response.data?['meta'] as Map<String, dynamic>? ?? const {};
    return ChatSearchResult(
      messages: _extractList(
        response.data,
        'messages',
      ).map(ChatMessage.fromJson).toList(),
      nextCursor: meta['nextCursor'] as String?,
      hasMore: meta['hasMore'] == true,
    );
  }

  Future<ChatFavoriteMessagesPage> fetchFavoriteMessages({
    String? cursor,
    int limit = 30,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/chat/messages/favorites',
      queryParameters: {
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': limit,
      },
    );
    final meta = response.data?['meta'] as Map<String, dynamic>? ?? const {};
    return ChatFavoriteMessagesPage(
      items: _extractList(
        response.data,
        'items',
      ).map(ChatFavoriteMessageEntry.fromJson).toList(),
      nextCursor: meta['nextCursor'] as String?,
      hasMore: meta['hasMore'] == true,
      limit: meta['limit'] as int? ?? limit,
    );
  }

  Future<ChatPostResult> sendTextMessage({
    required String conversationId,
    required String content,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
    String? messageType,
    String? fileUrl,
    bool isSilent = false,
    bool isScheduled = false,
    DateTime? scheduledFor,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat/messages',
      data: {
        'conversationId': conversationId,
        'content': content,
        'messageType': messageType ?? 'text',
        if (replyToMessageId != null && replyToMessageId.isNotEmpty)
          'replyToMessageId': replyToMessageId,
        if (metadata != null) 'metadata': metadata,
        if (fileUrl != null) 'fileUrl': fileUrl,
        if (isSilent) 'isSilent': isSilent,
        if (isScheduled) 'isScheduled': isScheduled,
        if (scheduledFor != null) 'scheduledFor': scheduledFor.toIso8601String(),
      },
    );
    return ChatPostResult(
      conversation: ChatConversation.fromJson(
        response.data?['conversation'] as Map<String, dynamic>,
      ),
      message: ChatMessage.fromJson(
        response.data?['message'] as Map<String, dynamic>,
      ),
    );
  }

  Future<ChatPostResult> sendFileMessage({
    required String conversationId,
    required String filePath,
    String? replyToMessageId,
    String? customFileName,
    Map<String, dynamic>? metadata,
    void Function(int sent, int total)? onProgress,
  }) async {
    final fileName = p.basename(filePath);
    final safeCustomName = customFileName?.trim();
    final fileLength = await File(filePath).length();
    final fileSha256 = await _localStorage.calculateFileSha256(filePath);
    final nextMetadata = <String, dynamic>{
      ...?metadata,
      'attachmentArchive': {'sha256': fileSha256, 'fileSize': fileLength},
    };
    final uploadTimeout = _uploadTimeoutForBytes(fileLength);
    final formData = FormData.fromMap({
      'conversationId': conversationId,
      if (replyToMessageId != null && replyToMessageId.isNotEmpty)
        'replyToMessageId': replyToMessageId,
      if (safeCustomName != null && safeCustomName.isNotEmpty)
        'fileName': safeCustomName,
      'metadata': jsonEncode(nextMetadata),
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });

    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat/messages',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        connectTimeout: uploadTimeout,
        sendTimeout: uploadTimeout,
        receiveTimeout: uploadTimeout,
      ),
      onSendProgress: onProgress,
    );

    final result = ChatPostResult(
      conversation: ChatConversation.fromJson(
        response.data?['conversation'] as Map<String, dynamic>,
      ),
      message: ChatMessage.fromJson(
        response.data?['message'] as Map<String, dynamic>,
      ),
    );
    await _archiveSentAttachment(
      message: result.message,
      sha256Hex: fileSha256,
      filePath: filePath,
      fileName: fileName,
    );
    return result;
  }

  Future<ChatPostResult> forwardMessage({
    required String conversationId,
    required String sourceMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat/messages',
      data: {
        'conversationId': conversationId,
        'forwardFromMessageId': sourceMessageId,
        if (metadata != null) 'metadata': metadata,
      },
    );

    return ChatPostResult(
      conversation: ChatConversation.fromJson(
        response.data?['conversation'] as Map<String, dynamic>,
      ),
      message: ChatMessage.fromJson(
        response.data?['message'] as Map<String, dynamic>,
      ),
    );
  }

  Future<ChatMessage> editMessage({
    required String messageId,
    required String content,
  }) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/chat/messages/$messageId',
      data: {'content': content},
    );
    return ChatMessage.fromJson(
      response.data?['message'] as Map<String, dynamic>,
    );
  }

  Future<ChatMessage> toggleReaction({
    required String messageId,
    required String emoji,
  }) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/chat/messages/$messageId/reactions',
      data: {'emoji': emoji},
    );
    return ChatMessage.fromJson(
      response.data?['message'] as Map<String, dynamic>,
    );
  }

  Future<ChatMessage> votePoll(String messageId, List<String> optionIds) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat/messages/$messageId/poll/vote',
      data: {'optionIds': optionIds},
    );
    return ChatMessage.fromJson(
      (response.data?['data']?['message'] as Map<String, dynamic>?) ?? 
      (response.data?['message'] as Map<String, dynamic>),
    );
  }

  Future<String> exportPollUrl(String messageId, {String? token}) async {
    final url = '/api/chat/messages/$messageId/poll/export';
    return '\${_apiClient.dio.options.baseUrl}$url?token=\${token ?? ''}';
  }

  Future<ChatMessage> toggleFavoriteMessage({required String messageId}) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/chat/messages/$messageId/favorite',
    );
    return ChatMessage.fromJson(
      response.data?['message'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteMessage(String messageId) async {
    await _apiClient.dio.delete<void>('/api/chat/messages/$messageId');
  }

  Future<void> markConversationSeen(String conversationId) async {
    await _apiClient.dio.post<void>(
      '/api/chat/conversations/$conversationId/seen',
    );
  }

  Future<ChatConversation> updateConversationPreferences({
    required String conversationId,
    bool? isMuted,
    bool? isArchived,
    bool? isPinned,
    bool? isFavorite,
  }) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId/preferences',
      data: {
        if (isMuted != null) 'isMuted': isMuted,
        if (isArchived != null) 'isArchived': isArchived,
        if (isPinned != null) 'isPinned': isPinned,
        if (isFavorite != null) 'isFavorite': isFavorite,
      },
    );
    return ChatConversation.fromJson(
      response.data?['conversation'] as Map<String, dynamic>,
    );
  }

  Future<ChatConversation> setGroupPinnedMessage({
    required String conversationId,
    required String content,
    String? messageId,
  }) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId/pinned-message',
      data: {
        'content': content.trim(),
        if (messageId != null) 'messageId': messageId,
      },
    );
    return ChatConversation.fromJson(
      response.data?['conversation'] as Map<String, dynamic>,
    );
  }

  Future<ChatConversation> clearGroupPinnedMessage({
    required String conversationId,
  }) async {
    final response = await _apiClient.dio.delete<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId/pinned-message',
    );
    return ChatConversation.fromJson(
      response.data?['conversation'] as Map<String, dynamic>,
    );
  }

  Future<void> leaveConversation(String conversationId) async {
    await _apiClient.dio.post<void>(
      '/api/chat/conversations/$conversationId/leave',
    );
  }

  Future<ChatConversation?> deleteConversation(
    String conversationId, {
    bool deleteForEveryone = false,
  }) async {
    final response = await _apiClient.dio.delete<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId',
      queryParameters: {'scope': deleteForEveryone ? 'global' : 'self'},
    );
    final conversationData = response.data?['conversation'];
    if (conversationData is Map<String, dynamic>) {
      return ChatConversation.fromJson(conversationData);
    }
    return null;
  }

  Future<String> downloadAttachment(
    ChatMessage message, {
    void Function(int received, int total)? onProgress,
  }) async {
    final targetFile = await _fullAttachmentCacheFile(message);
    if (await targetFile.exists()) return targetFile.path;
    final downloadUrl = _downloadUrlFor(message.fileUrl!);
    final response = await _downloadAttachmentBytesWithRestore(
      message,
      downloadUrl,
      onProgress: onProgress,
    );

    await targetFile.writeAsBytes(response, flush: true);

    return targetFile.path;
  }

  Future<String> saveAttachmentCopy(
    ChatMessage message,
    String destinationDirectoryPath,
  ) async {
    final sourcePath = await downloadAttachment(message);
    final sourceFile = File(sourcePath);
    final fileName = p.basename(message.fileName ?? p.basename(sourcePath));
    final destinationPath = _resolveUniqueFilePath(
      destinationDirectoryPath,
      fileName,
    );
    await sourceFile.copy(destinationPath);
    return destinationPath;
  }

  String _resolveUniqueFilePath(String directoryPath, String fileName) {
    final baseName = p.basenameWithoutExtension(fileName);
    final extension = p.extension(fileName);
    var candidate = p.join(directoryPath, fileName);
    var counter = 1;
    while (File(candidate).existsSync()) {
      candidate = p.join(directoryPath, '${baseName}_$counter$extension');
      counter++;
    }
    return candidate;
  }

  Future<Uint8List> fetchAttachmentBytes(ChatMessage message) async {
    final cacheFile = await _fullAttachmentCacheFile(message);
    if (await cacheFile.exists()) {
      return cacheFile.readAsBytes();
    }

    final cacheKey = cacheFile.path;
    final existing = _attachmentBytesInFlight[cacheKey];
    if (existing != null) return existing;

    final future =
        _downloadAttachmentBytesWithRestore(
          message,
          _downloadUrlFor(message.fileUrl!),
        ).then((bytes) async {
          if (bytes.isNotEmpty) {
            await cacheFile.writeAsBytes(bytes, flush: true);
          }
          return bytes;
        });
    _attachmentBytesInFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _attachmentBytesInFlight.remove(cacheKey);
    }
  }

  Future<Uint8List> fetchAttachmentPreviewBytes(ChatMessage message) async {
    final localBytes = await _readLocalAttachmentBytes(message);
    if (localBytes != null) {
      return localBytes;
    }
    final cacheFile = await _previewAttachmentCacheFile(message);
    if (await cacheFile.exists()) {
      return cacheFile.readAsBytes();
    }

    final previewUrl = _inlineUrlFor(message.fileUrl!);
    if (_missingAttachmentPreviewUrls.contains(previewUrl)) {
      throw StateError('Attachment preview is unavailable.');
    }

    final cacheKey = cacheFile.path;
    final existing = _attachmentPreviewInFlight[cacheKey];
    if (existing != null) return existing;

    final future = _fetchAndCacheAttachmentPreview(
      message,
      previewUrl,
      cacheFile,
    );
    _attachmentPreviewInFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _attachmentPreviewInFlight.remove(cacheKey);
    }
  }

  Future<Uint8List> _fetchAndCacheAttachmentPreview(
    ChatMessage message,
    String previewUrl,
    File cacheFile,
  ) async {
    await _acquirePreviewDownloadSlot();
    try {
      final bytes = await _downloadAttachmentBytesWithRestore(
        message,
        previewUrl,
        skipErrorLog: true,
      );
      if (bytes.isNotEmpty) {
        await cacheFile.writeAsBytes(bytes, flush: true);
      }
      return bytes;
    } on DioException catch (error) {
      if ((error.response?.statusCode ?? 0) == 404) {
        _missingAttachmentPreviewUrls.add(previewUrl);
      }
      rethrow;
    } finally {
      _releasePreviewDownloadSlot();
    }
  }

  Future<void> _acquirePreviewDownloadSlot() async {
    if (_activePreviewDownloads < _maxConcurrentPreviewDownloads) {
      _activePreviewDownloads += 1;
      return;
    }
    final completer = Completer<void>();
    _previewDownloadQueue.add(completer);
    await completer.future;
  }

  void _releasePreviewDownloadSlot() {
    final next = _previewDownloadQueue.isEmpty
        ? null
        : _previewDownloadQueue.removeFirst();
    if (next == null) {
      _activePreviewDownloads = (_activePreviewDownloads - 1)
          .clamp(0, _maxConcurrentPreviewDownloads)
          .toInt();
      return;
    }
    next.complete();
  }

  Future<void> requestAttachmentRehydrate(
    ChatMessage message, {
    bool skipErrorLog = false,
  }) async {
    try {
      await _apiClient.dio.post<void>(
        '/api/chat/messages/${message.id}/rehydrate/request',
        options: Options(
          extra: <String, Object?>{if (skipErrorLog) 'skipErrorLog': true},
        ),
      );
    } on DioException catch (error) {
      if ((error.response?.statusCode ?? 0) == 409) {
        return;
      }
      rethrow;
    }
  }

  Future<void> respondToAttachmentRehydrate(
    Map<String, dynamic> payload,
  ) async {
    final messageId = payload['messageId']?.toString().trim() ?? '';
    final sha256Hex = payload['sha256']?.toString().trim().toLowerCase() ?? '';
    final fileName = payload['fileName']?.toString().trim().isNotEmpty == true
        ? payload['fileName'].toString().trim()
        : 'attachment';
    if (messageId.isEmpty || !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256Hex)) {
      return;
    }
    final file = await _localStorage.findSentChatArchive(
      messageId: messageId,
      sha256Hex: sha256Hex,
      preferredPath: _preferences.localStorageDirectoryPath,
    );
    if (file == null) return;
    await _uploadRestoredFile(messageId, fileName, file.path);
  }

  Future<Uint8List> _downloadAttachmentBytesWithRestore(
    ChatMessage message,
    String downloadUrl, {
    void Function(int received, int total)? onProgress,
    bool skipErrorLog = false,
  }) async {
    try {
      final response = await _apiClient.dio.get<List<int>>(
        downloadUrl,
        options: Options(
          responseType: ResponseType.bytes,
          extra: <String, Object?>{if (skipErrorLog) 'skipErrorLog': true},
        ),
        onReceiveProgress: onProgress,
      );
      return Uint8List.fromList(response.data ?? const <int>[]);
    } on DioException catch (error) {
      if ((error.response?.statusCode ?? 0) != 404) rethrow;
      await requestAttachmentRehydrate(message, skipErrorLog: skipErrorLog);
      for (var attempt = 0; attempt < 8; attempt += 1) {
        await Future<void>.delayed(const Duration(seconds: 2));
        try {
          final response = await _apiClient.dio.get<List<int>>(
            downloadUrl,
            options: Options(
              responseType: ResponseType.bytes,
              extra: <String, Object?>{if (skipErrorLog) 'skipErrorLog': true},
            ),
            onReceiveProgress: onProgress,
          );
          return Uint8List.fromList(response.data ?? const <int>[]);
        } on DioException catch (retryError) {
          if ((retryError.response?.statusCode ?? 0) != 404 || attempt == 7) {
            rethrow;
          }
        }
      }
      rethrow;
    }
  }

  Future<void> _archiveSentAttachment({
    required ChatMessage message,
    required String sha256Hex,
    required String filePath,
    required String fileName,
  }) async {
    try {
      await _localStorage.archiveSentChatFile(
        messageId: message.id,
        sha256Hex: sha256Hex,
        fileName: fileName,
        sourcePath: filePath,
        preferredPath: _preferences.localStorageDirectoryPath,
      );
    } catch (_) {}
  }

  Future<Uint8List?> _readLocalAttachmentBytes(ChatMessage message) async {
    final cachedFile = await _fullAttachmentCacheFile(message);
    if (await cachedFile.exists()) {
      return cachedFile.readAsBytes();
    }

    final archive = _attachmentArchiveMetadata(message);
    final sha256Hex = archive?['sha256']?.toString().trim().toLowerCase();
    if (sha256Hex != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256Hex)) {
      final sentArchive = await _localStorage.findSentChatArchive(
        messageId: message.id,
        sha256Hex: sha256Hex,
        preferredPath: _preferences.localStorageDirectoryPath,
      );
      if (sentArchive != null && await sentArchive.exists()) {
        return sentArchive.readAsBytes();
      }
    }
    return null;
  }

  Future<File> _fullAttachmentCacheFile(ChatMessage message) async {
    final fileName = p.basename(message.fileName ?? 'attachment');
    final cacheDirectory = await _localStorage.chatDirectory(
      preferredPath: _preferences.localStorageDirectoryPath,
    );
    return File(
      p.join(
        cacheDirectory.path,
        '${message.id}_${_localStorage.sanitizeFileName(fileName)}',
      ),
    );
  }

  Future<File> _previewAttachmentCacheFile(ChatMessage message) async {
    final cacheDirectory = await _localStorage.chatDirectory(
      preferredPath: _preferences.localStorageDirectoryPath,
    );
    final previewsDirectory = Directory(
      p.join(cacheDirectory.path, 'previews'),
    );
    await previewsDirectory.create(recursive: true);
    final source = '${message.id}:${message.fileUrl ?? ''}';
    final hash = sha1.convert(utf8.encode(source)).toString();
    return File(p.join(previewsDirectory.path, '${message.id}_$hash.preview'));
  }

  Map<String, dynamic>? _attachmentArchiveMetadata(ChatMessage message) {
    final raw = message.metadata?['attachmentArchive'];
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  Future<void> _uploadRestoredFile(
    String messageId,
    String fileName,
    String filePath,
  ) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    await _apiClient.dio.post<void>(
      '/api/chat/messages/$messageId/rehydrate',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
  }

  String _downloadUrlFor(String fileUrl) {
    final uri = Uri.parse(fileUrl);
    final segments = List<String>.from(uri.pathSegments);
    if (segments.isNotEmpty && segments.last == 'file') {
      segments[segments.length - 1] = 'download';
      final downloadUri = uri.replace(pathSegments: segments);
      return downloadUri.toString();
    }
    return fileUrl;
  }

  String _inlineUrlFor(String fileUrl) {
    final uri = Uri.tryParse(fileUrl.trim());
    if (uri != null) {
      final segments = List<String>.from(uri.pathSegments);
      if (segments.isNotEmpty && segments.last == 'download') {
        segments[segments.length - 1] = 'file';
        return uri.replace(pathSegments: segments).toString();
      }
    }
    return fileUrl.trim();
  }

  Future<DepartmentSummary> createDepartment({
    required String name,
    required String code,
    String description = '',
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/admin/departments',
      data: {'name': name, 'code': code, 'description': description},
    );
    return DepartmentSummary.fromJson(
      response.data?['department'] as Map<String, dynamic>,
    );
  }

  Future<DepartmentSummary> updateDepartment({
    required String departmentId,
    required String name,
    required String code,
    String description = '',
    List<String> managers = const [],
  }) async {
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/admin/departments/$departmentId',
      data: {
        'name': name,
        'code': code,
        'description': description,
        'managers': managers,
      },
    );
    return DepartmentSummary.fromJson(
      response.data?['department'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteDepartment(String departmentId) async {
    await _apiClient.dio.delete<void>('/api/admin/departments/$departmentId');
  }

  Future<BranchSummary> createBranch({
    required String name,
    required String code,
    String description = '',
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/admin/branches',
      data: {'name': name, 'code': code, 'description': description},
    );
    return BranchSummary.fromJson(
      response.data?['branch'] as Map<String, dynamic>,
    );
  }

  Future<BranchSummary> updateBranch({
    required String branchId,
    required String name,
    required String code,
    String description = '',
  }) async {
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/admin/branches/$branchId',
      data: {'name': name, 'code': code, 'description': description},
    );
    return BranchSummary.fromJson(
      response.data?['branch'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteBranch(String branchId) async {
    await _apiClient.dio.delete<void>('/api/admin/branches/$branchId');
  }

  Future<ChatRole> updateRolePermissions({
    required String roleId,
    required ChatPermissionSet permissions,
  }) async {
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/admin/roles/$roleId',
      data: {'permissions': permissions.toJson()},
    );

    return ChatRole.fromJson(response.data?['role'] as Map<String, dynamic>);
  }

  Future<ChatConversation> updateManagedConversation({
    required String conversationId,
    String? name,
    String? description,
    List<String>? memberIds,
    List<String>? adminIds,
    bool? isArchived,
    bool? isActive,
  }) async {
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId',
      data: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (memberIds != null) 'memberIds': memberIds,
        if (adminIds != null) 'adminIds': adminIds,
        if (isArchived != null) 'isArchived': isArchived,
        if (isActive != null) 'isActive': isActive,
      },
    );
    return ChatConversation.fromJson(
      response.data?['conversation'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteManagedConversation(String conversationId) async {
    await deleteConversation(conversationId, deleteForEveryone: true);
  }

  Future<ChatConversation> addGroupMembers({
    required String conversationId,
    required List<String> userIds,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId/members',
      data: {'userIds': userIds},
    );
    return ChatConversation.fromJson(
      response.data?['conversation'] as Map<String, dynamic>,
    );
  }

  Future<ChatConversation> removeGroupMember({
    required String conversationId,
    required String userId,
  }) async {
    final response = await _apiClient.dio.delete<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId/members/$userId',
    );
    return ChatConversation.fromJson(
      response.data?['conversation'] as Map<String, dynamic>,
    );
  }

  Future<ChatConversation> promoteGroupAdmin({
    required String conversationId,
    required String userId,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId/admins/$userId',
    );
    return ChatConversation.fromJson(
      response.data?['conversation'] as Map<String, dynamic>,
    );
  }

  Future<ChatConversation> demoteGroupAdmin({
    required String conversationId,
    required String userId,
  }) async {
    final response = await _apiClient.dio.delete<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId/admins/$userId',
    );
    return ChatConversation.fromJson(
      response.data?['conversation'] as Map<String, dynamic>,
    );
  }

  Future<ChatConversation> blockGroupMember({
    required String conversationId,
    required String userId,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId/blocked-members/$userId',
    );
    return ChatConversation.fromJson(
      response.data?['conversation'] as Map<String, dynamic>,
    );
  }

  Future<ChatConversation> unblockGroupMember({
    required String conversationId,
    required String userId,
  }) async {
    final response = await _apiClient.dio.delete<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId/blocked-members/$userId',
    );
    return ChatConversation.fromJson(
      response.data?['conversation'] as Map<String, dynamic>,
    );
  }

  // --- Chat Folders ---
  Future<List<ChatFolder>> getFolders() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/api/chat/folders');
    final data = response.data?['data'] as List?;
    if (data == null) return [];
    return data.map((json) => ChatFolder.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<ChatFolder> createFolder({
    required String name,
    String? icon,
    List<String> conversationIds = const [],
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat/folders',
      data: {
        'name': name,
        if (icon != null) 'icon': icon,
        'conversationIds': conversationIds,
      },
    );
    return ChatFolder.fromJson(response.data?['data'] as Map<String, dynamic>);
  }

  Future<ChatFolder> updateFolder({
    required String folderId,
    String? name,
    String? icon,
    List<String>? conversationIds,
  }) async {
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/chat/folders/$folderId',
      data: {
        if (name != null) 'name': name,
        if (icon != null) 'icon': icon,
        if (conversationIds != null) 'conversationIds': conversationIds,
      },
    );
    return ChatFolder.fromJson(response.data?['data'] as Map<String, dynamic>);
  }

  Future<void> deleteFolder(String folderId) async {
    await _apiClient.dio.delete<void>('/api/chat/folders/$folderId');
  }

  Future<List<ChatFolder>> reorderFolders(List<String> folderIds) async {
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/chat/folders/reorder',
      data: {'folderIds': folderIds},
    );
    final data = response.data?['data'] as List?;
    if (data == null) return [];
    return data.map((json) => ChatFolder.fromJson(json as Map<String, dynamic>)).toList();
  }
}
