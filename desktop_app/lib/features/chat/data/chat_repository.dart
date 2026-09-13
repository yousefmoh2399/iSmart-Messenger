import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/network/api_client.dart';
import '../../../core/network/media_url_resolver.dart';
import '../../../core/settings/user_preferences.dart';
import '../../../shared/services/local_media_storage_service.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../../auth/data/auth_repository.dart';
import '../models/chat_models.dart';

class ChatRepository {
  ChatRepository(
    this._apiClient,
    this._authRepository,
    this._localStorage,
    this._preferences,
  );

  final Set<String> _missingAttachmentPreviewUrls = <String>{};
  final Map<String, Future<Uint8List>> _attachmentPreviewLoads =
      <String, Future<Uint8List>>{};

  final ApiClient _apiClient;
  final AuthRepository _authRepository;
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
      options: Options(
        connectTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 90),
      ),
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
      options: Options(
        connectTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 90),
      ),
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
    bool isScheduled = false,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId/messages',
      queryParameters: {
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': limit,
        if (isScheduled) 'isScheduled': 'true',
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
        if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
        if (metadata != null) 'metadata': metadata,
        if (messageType != null) 'messageType': messageType,
        if (fileUrl != null) 'fileUrl': fileUrl,
        if (isSilent) 'isSilent': isSilent,
        if (isScheduled) 'isScheduled': isScheduled,
        if (scheduledFor != null)
          'scheduledFor': scheduledFor.toIso8601String(),
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
    Uint8List? fileBytes,
    String? sourceFileName,
    String? replyToMessageId,
    String? customFileName,
    Map<String, dynamic>? metadata,
    void Function(int sent, int total)? onProgress,
  }) async {
    final safeCustomName = customFileName?.trim();
    final resolvedFileName = sourceFileName?.trim().isNotEmpty == true
        ? sourceFileName!.trim()
        : p.basename(filePath);
    final fileLength = fileBytes?.length ?? await File(filePath).length();
    final fileSha256 = fileBytes != null
        ? sha256.convert(fileBytes).toString()
        : await _localStorage.calculateFileSha256(filePath);
    final nextMetadata = <String, dynamic>{
      ...?metadata,
      'attachmentArchive': {'sha256': fileSha256, 'fileSize': fileLength},
    };
    final uploadTimeout = _uploadTimeoutForBytes(fileLength);
    final multipartFile = fileBytes != null
        ? MultipartFile.fromBytes(fileBytes, filename: resolvedFileName)
        : await MultipartFile.fromFile(filePath, filename: resolvedFileName);
    final formData = FormData.fromMap({
      'conversationId': conversationId,
      if (replyToMessageId != null && replyToMessageId.isNotEmpty)
        'replyToMessageId': replyToMessageId,
      if (safeCustomName != null && safeCustomName.isNotEmpty)
        'fileName': safeCustomName,
      'metadata': jsonEncode(nextMetadata),
      'file': multipartFile,
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
      filePath: fileBytes == null ? filePath : null,
      fileBytes: fileBytes,
      fileName: resolvedFileName,
    );
    if (fileBytes != null && result.message.isImageMessage) {
      await _cacheAttachmentPreviewBytes(result.message, fileBytes);
    }
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

  Future<ChatMessage> toggleFavoriteMessage({required String messageId}) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/chat/messages/$messageId/favorite',
    );
    return ChatMessage.fromJson(
      response.data?['message'] as Map<String, dynamic>,
    );
  }

  Future<void> removeMessage(String messageId) async {
    await _apiClient.dio.delete<Map<String, dynamic>>(
      '/api/chat/messages/$messageId',
    );
  }

  Future<ChatMessage> votePoll({
    required String messageId,
    required List<String> optionIds,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat/messages/$messageId/poll/vote',
      data: {'optionIds': optionIds},
    );
    return ChatMessage.fromJson(
      (response.data?['data']?['message'] as Map<String, dynamic>?) ??
          (response.data?['message'] as Map<String, dynamic>),
    );
  }

  String exportPollUrl(String messageId) {
    final token = _authRepository.currentToken;
    final path = '/api/chat/messages/$messageId/poll/export?token=$token';
    return resolveApiUrl(path);
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
    if (kIsWeb) {
      final downloadUrl = _downloadUrlFor(message.fileUrl!);
      final response = await _apiClient.dio.get<List<int>>(
        downloadUrl,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: onProgress,
      );
      final fileName = p.basename(message.fileName ?? 'attachment');
      await web_bridge.downloadBytes(
        bytes: Uint8List.fromList(response.data ?? const <int>[]),
        fileName: fileName,
        preferredDirectoryPath: _preferences.localStorageDirectoryPath,
      );
      return fileName;
    }

    final fileName = p.basename(message.fileName ?? 'attachment');
    final cacheDirectory = await _localStorage.chatDirectory(
      preferredPath: _preferences.localStorageDirectoryPath,
    );
    final targetPath = p.join(
      cacheDirectory.path,
      '${message.id}_${_localStorage.sanitizeFileName(fileName)}',
    );
    if (await File(targetPath).exists()) return targetPath;
    final downloadUrl = _downloadUrlFor(message.fileUrl!);
    final response = await _downloadAttachmentBytesWithRestore(
      message,
      downloadUrl,
      onProgress: onProgress,
    );

    await File(targetPath).writeAsBytes(response, flush: true);

    return targetPath;
  }

  Future<Uint8List> fetchAttachmentBytes(ChatMessage message) async {
    return _downloadAttachmentBytesWithRestore(
      message,
      _downloadUrlFor(message.fileUrl!),
    );
  }

  Future<Uint8List> fetchAttachmentPreviewBytes(ChatMessage message) async {
    final cacheKey = _attachmentPreviewCacheKey(message);
    final existingLoad = _attachmentPreviewLoads[cacheKey];
    if (existingLoad != null) {
      return existingLoad;
    }
    final load = _fetchAttachmentPreviewBytes(message);
    _attachmentPreviewLoads[cacheKey] = load;
    load.whenComplete(() {
      if (identical(_attachmentPreviewLoads[cacheKey], load)) {
        _attachmentPreviewLoads.remove(cacheKey);
      }
    });
    return load;
  }

  Future<Uint8List> _fetchAttachmentPreviewBytes(ChatMessage message) async {
    final localBytes = await _readLocalAttachmentBytes(message);
    if (localBytes != null) {
      return localBytes;
    }
    final previewUrl = _inlineUrlFor(message.fileUrl!);
    if (_missingAttachmentPreviewUrls.contains(previewUrl)) {
      throw StateError('Attachment preview is unavailable.');
    }
    try {
      final bytes = await _downloadAttachmentBytesWithRestore(
        message,
        previewUrl,
        skipErrorLog: true,
      );
      await _cacheAttachmentPreviewBytes(message, bytes);
      return bytes;
    } on DioException catch (error) {
      if ((error.response?.statusCode ?? 0) == 404) {
        _missingAttachmentPreviewUrls.add(previewUrl);
      }
      rethrow;
    }
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

    if (kIsWeb && web_bridge.isElectron()) {
      final bytes = await web_bridge.readElectronArchivedChatAttachment(
        messageId: messageId,
        sha256Hex: sha256Hex,
        preferredDirectoryPath: _preferences.localStorageDirectoryPath,
      );
      if (bytes == null) return;
      await _uploadRestoredBytes(messageId, fileName, bytes);
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
      final status = error.response?.statusCode ?? 0;
      if (status != 404) rethrow;
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
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
  }) async {
    try {
      if (kIsWeb && web_bridge.isElectron() && fileBytes != null) {
        await web_bridge.archiveElectronChatAttachment(
          messageId: message.id,
          sha256Hex: sha256Hex,
          fileName: fileName,
          bytes: fileBytes,
          preferredDirectoryPath: _preferences.localStorageDirectoryPath,
        );
        return;
      }
      await _localStorage.archiveSentChatFile(
        messageId: message.id,
        sha256Hex: sha256Hex,
        fileName: fileName,
        sourcePath: filePath,
        bytes: fileBytes,
        preferredPath: _preferences.localStorageDirectoryPath,
      );
    } catch (_) {}
  }

  Future<Uint8List?> _readLocalAttachmentBytes(ChatMessage message) async {
    final archive = _attachmentArchiveMetadata(message);
    final sha256Hex = archive?['sha256']?.toString().trim().toLowerCase();
    if (kIsWeb && web_bridge.isElectron()) {
      final cachedBytes = await web_bridge.readElectronCachedChatAttachment(
        messageId: message.id,
        fileName: message.fileName ?? 'attachment',
        preferredDirectoryPath: _preferences.localStorageDirectoryPath,
      );
      if (cachedBytes != null && cachedBytes.isNotEmpty) {
        return cachedBytes;
      }
      if (sha256Hex != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256Hex)) {
        return web_bridge.readElectronArchivedChatAttachment(
          messageId: message.id,
          sha256Hex: sha256Hex,
          preferredDirectoryPath: _preferences.localStorageDirectoryPath,
        );
      }
      return null;
    }

    final fileName = p.basename(message.fileName ?? 'attachment');
    final cacheDirectory = await _localStorage.chatDirectory(
      preferredPath: _preferences.localStorageDirectoryPath,
    );
    final cachedPath = p.join(
      cacheDirectory.path,
      '${message.id}_${_localStorage.sanitizeFileName(fileName)}',
    );
    final cachedFile = File(cachedPath);
    if (await cachedFile.exists()) {
      return cachedFile.readAsBytes();
    }

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

  Future<void> _cacheAttachmentPreviewBytes(
    ChatMessage message,
    Uint8List bytes,
  ) async {
    if (bytes.isEmpty) return;
    try {
      if (kIsWeb && web_bridge.isElectron()) {
        await web_bridge.cacheElectronChatAttachment(
          messageId: message.id,
          fileName: message.fileName ?? 'attachment',
          bytes: bytes,
          preferredDirectoryPath: _preferences.localStorageDirectoryPath,
        );
        return;
      }

      final fileName = p.basename(message.fileName ?? 'attachment');
      final cacheDirectory = await _localStorage.chatDirectory(
        preferredPath: _preferences.localStorageDirectoryPath,
      );
      final targetPath = p.join(
        cacheDirectory.path,
        '${message.id}_${_localStorage.sanitizeFileName(fileName)}',
      );
      final targetFile = File(targetPath);
      if (!await targetFile.exists()) {
        await targetFile.writeAsBytes(bytes, flush: true);
      }
    } catch (_) {}
  }

  String _attachmentPreviewCacheKey(ChatMessage message) {
    return [
      message.id,
      message.updatedAt.toIso8601String(),
      message.fileUrl ?? '',
      message.fileName ?? '',
    ].join('|');
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

  Future<void> _uploadRestoredBytes(
    String messageId,
    String fileName,
    Uint8List bytes,
  ) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    await _apiClient.dio.post<void>(
      '/api/chat/messages/$messageId/rehydrate',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
  }

  String _downloadUrlFor(String fileUrl) {
    // Ensure we always have an absolute URL — the server sometimes returns
    // relative paths like "api/chatmessages/.../file" without a leading slash,
    // which Dio would concatenate incorrectly as "http://ip:5000api/...".
    final trimmed = fileUrl.trim();
    final resolved = resolveApiUrl(trimmed);

    // Swap /file → /download at the end of the path if needed.
    final uri = Uri.tryParse(resolved);
    if (uri != null) {
      final segments = List<String>.from(uri.pathSegments);
      if (segments.isNotEmpty && segments.last == 'file') {
        segments[segments.length - 1] = 'download';
        return uri.replace(pathSegments: segments).toString();
      }
    }
    return resolved;
  }

  String _inlineUrlFor(String fileUrl) {
    final resolved = resolveApiUrl(fileUrl.trim());
    final uri = Uri.tryParse(resolved);
    if (uri != null) {
      final segments = List<String>.from(uri.pathSegments);
      if (segments.isNotEmpty && segments.last == 'download') {
        segments[segments.length - 1] = 'file';
        return uri.replace(pathSegments: segments).toString();
      }
    }
    return resolved;
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
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/chat/folders',
    );
    final data = response.data?['data'] as List?;
    if (data == null) return [];
    return data
        .map((json) => ChatFolder.fromJson(json as Map<String, dynamic>))
        .toList();
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
    return data
        .map((json) => ChatFolder.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getReadReceipts(String messageId) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      "/api/chat/messages/$messageId/read-receipts",
    );
    return response.data?["data"] as Map<String, dynamic>? ?? {};
  }

  Future<File> downloadPollExport(String messageId) async {
    final response = await _apiClient.dio.get<List<int>>(
      "/api/chat/messages/$messageId/poll/export",
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null) throw Exception("Failed to download export");
    final directory = await _localStorage.chatDirectory(
      preferredPath: _preferences.localStorageDirectoryPath,
    );
    final disposition = response.headers.value("content-disposition") ?? "";
    String filename = "poll_export_$messageId.xlsx";
    if (disposition.contains("filename=")) {
      filename = disposition
          .split("filename=")
          .last
          .replaceAll("\"", "")
          .trim();
    }
    final file = File(p.join(directory.path, filename));
    await file.writeAsBytes(bytes);
    return file;
  }
}
