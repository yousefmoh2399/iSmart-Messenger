import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/media_url_resolver.dart';
import '../../../core/settings/user_preferences.dart';
import '../../../shared/services/local_media_storage_service.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../../auth/data/auth_repository.dart';
import '../models/chat_models.dart';
import 'chat_local_cache.dart';
import 'chat_socket_service.dart';

// Top-level function required by compute() — must not be a closure or instance method.
// Computes SHA-256 of raw bytes in a background isolate to avoid blocking the UI thread.
String _computeSha256Bytes(Uint8List bytes) => sha256.convert(bytes).toString();

class ChatRepository {
  ChatRepository(
    this._apiClient,
    this._authRepository,
    this._localStorage,
    this._preferences,
    this._cache, {
    ChatSocketService? socketService,
  }) : _socketService = socketService;

  final Set<String> _missingAttachmentPreviewUrls = <String>{};
  final Map<String, Future<Uint8List>> _attachmentPreviewLoads =
      <String, Future<Uint8List>>{};

  final ApiClient _apiClient;
  final AuthRepository _authRepository;
  final LocalMediaStorageService _localStorage;
  final UserPreferences _preferences;
  final ChatLocalCache _cache;
  final ChatSocketService? _socketService;

  ChatLocalCache get cache => _cache;

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

  List<ChatConversation> _parseConversationsSafely(
    List<Map<String, dynamic>> rawItems,
  ) {
    final parsed = <ChatConversation>[];
    for (final item in rawItems) {
      try {
        final conv = ChatConversation.fromJson(item);
        if (conv.id.isNotEmpty) {
          parsed.add(conv);
        }
      } catch (_) {
        // Ignore single malformed conversation so others still load
      }
    }
    return parsed;
  }

  Future<List<ChatConversation>> fetchConversations() async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/chat/conversations',
      );
      final list = _parseConversationsSafely(
        _extractList(response.data, 'conversations'),
      );
      if (response.data != null) {
        await _cache.saveRawJson('conversations', response.data!);
      }
      return list;
    } catch (e) {
      if (e is DioException) {
        final cached = await _cache.loadRawJson('conversations');
        if (cached != null) {
          return _parseConversationsSafely(
            _extractList(cached, 'conversations'),
          );
        }
      }
      rethrow;
    }
  }

  Future<List<ChatConversation>> fetchManageableConversations() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/chat/admin/conversations',
    );
    return _parseConversationsSafely(
      _extractList(response.data, 'conversations'),
    );
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
    String? avatarUrl,
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
        if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
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
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/chat/conversations/$conversationId/messages',
        queryParameters: {
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          'limit': limit,
          if (isScheduled) 'isScheduled': 'true',
        },
      );
      final meta = response.data?['meta'] as Map<String, dynamic>? ?? const {};
      if (cursor == null && !isScheduled && response.data != null) {
        await _cache.saveRawJson('messages_$conversationId', response.data!);
      }
      return ChatMessagesPage(
        messages: _extractList(
          response.data,
          'messages',
        ).map(ChatMessage.fromJson).toList(),
        nextCursor: meta['nextCursor'] as String?,
        hasMore: meta['hasMore'] == true,
        limit: meta['limit'] as int? ?? limit,
      );
    } catch (e) {
      if (e is DioException && cursor == null && !isScheduled) {
        final cached = await _cache.loadRawJson('messages_$conversationId');
        if (cached != null) {
          final meta = cached['meta'] as Map<String, dynamic>? ?? const {};
          return ChatMessagesPage(
            messages: _extractList(cached, 'messages').map(ChatMessage.fromJson).toList(),
            nextCursor: meta['nextCursor'] as String?,
            hasMore: meta['hasMore'] == true,
            limit: meta['limit'] as int? ?? limit,
          );
        }
      }
      rethrow;
    }
  }

  Future<ChatMessagesPage?> getCachedMessages(String conversationId) async {
    final cached = await _cache.loadRawJson('messages_$conversationId');
    if (cached != null) {
      final meta = cached['meta'] as Map<String, dynamic>? ?? const {};
      return ChatMessagesPage(
        messages: _extractList(cached, 'messages').map(ChatMessage.fromJson).toList(),
        nextCursor: meta['nextCursor'] as String?,
        hasMore: meta['hasMore'] == true,
        limit: meta['limit'] as int? ?? 40,
      );
    }
    return null;
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
    String? clientMessageId,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
    String? messageType,
    String? fileUrl,
    bool isSilent = false,
    bool isScheduled = false,
    DateTime? scheduledFor,
  }) async {
    final payload = <String, dynamic>{
      'conversationId': conversationId,
      'content': content,
      if (clientMessageId != null) 'clientMessageId': clientMessageId,
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      if (metadata != null) 'metadata': metadata,
      if (messageType != null) 'messageType': messageType,
      if (fileUrl != null) 'fileUrl': fileUrl,
      if (isSilent) 'isSilent': isSilent,
      if (isScheduled) 'isScheduled': isScheduled,
      if (scheduledFor != null)
        'scheduledFor': scheduledFor.toIso8601String(),
    };

    // Fast-path: send via active Socket.io channel if connected (instant single-hop, no HTTP handshake)
    final socketService = _socketService;
    if (!isScheduled && socketService != null && socketService.isConnected) {
      try {
        final ack = await socketService.emitWithAck(
          'send_message',
          payload,
          timeout: const Duration(seconds: 4),
        );
        if (ack['ok'] == true && ack['data'] is Map) {
          final data = Map<String, dynamic>.from(ack['data'] as Map);
          if (data['message'] is Map && data['conversation'] is Map) {
            return ChatPostResult(
              conversation: ChatConversation.fromJson(
                Map<String, dynamic>.from(data['conversation'] as Map),
              ),
              message: ChatMessage.fromJson(
                Map<String, dynamic>.from(data['message'] as Map),
              ),
            );
          }
        }
      } catch (_) {
        // Socket failed or timed out; seamlessly fall back to HTTP POST
      }
    }

    // Resilient HTTP sending with automatic retry on weak/VPN connections
    Object? lastError;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await _apiClient.dio.post<Map<String, dynamic>>(
          '/api/chat/messages',
          data: payload,
          options: Options(
            connectTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 25),
            receiveTimeout: const Duration(seconds: 25),
          ),
        );
        return ChatPostResult(
          conversation: ChatConversation.fromJson(
            response.data?['conversation'] as Map<String, dynamic>,
          ),
          message: ChatMessage.fromJson(
            response.data?['message'] as Map<String, dynamic>,
          ),
        );
      } catch (err) {
        lastError = err;
        if (err is DioException) {
          final status = err.response?.statusCode ?? 0;
          // Re-throw immediately on client 4xx validation or permission errors (not retryable)
          if (status >= 400 && status < 500 && status != 408) {
            rethrow;
          }
        }
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 600 * attempt));
        }
      }
    }
    throw lastError!;
  }

  Future<ChatPostResult> sendFileMessage({
    required String conversationId,
    required String filePath,
    Uint8List? fileBytes,
    String? sourceFileName,
    String? content,
    String? replyToMessageId,
    String? customFileName,
    Map<String, dynamic>? metadata,
    String? transferId,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    final safeCustomName = customFileName?.trim();
    final resolvedFileName = sourceFileName?.trim().isNotEmpty == true
        ? sourceFileName!.trim()
        : p.basename(filePath);

    // Fast-path for Electron Desktop: Direct native streaming upload via Node.js
    // Zero Base64, zero Dart memory allocation, and zero UI thread freezing.
    if (kIsWeb && web_bridge.isElectron() && filePath.isNotEmpty && (fileBytes == null || fileBytes.isEmpty)) {
      final token = _authRepository.currentToken ?? await _authRepository.getToken();
      final uploadUrl = resolveApiUrl('/api/chat/messages');

      // Calculate SHA256 natively in Node.js worker thread (< 50ms)
      final fileSha256 = await web_bridge.calculateElectronFileSha256(filePath);

      final nextMetadata = <String, dynamic>{
        ...?metadata,
        if (fileSha256.isNotEmpty)
          'attachmentArchive': {'sha256': fileSha256},
      };

      final res = await web_bridge.uploadElectronChatAttachment(
        url: uploadUrl,
        filePath: filePath,
        token: token,
        conversationId: conversationId,
        content: content,
        replyToMessageId: replyToMessageId,
        fileName: safeCustomName ?? resolvedFileName,
        metadata: nextMetadata,
        transferId: transferId,
        onProgress: onProgress,
      );

      if (res['success'] != true) {
        final errMsg = res['error']?.toString() ?? 'فشل رفع الملف عبر التطبيق.';
        if (res['isCancelled'] == true || errMsg.contains('إلغاء')) {
          throw DioException(
            requestOptions: RequestOptions(path: uploadUrl),
            type: DioExceptionType.cancel,
            message: errMsg,
          );
        }
        throw Exception(errMsg);
      }

      final responseJson = res['responseJson']?.toString();
      final Map<String, dynamic> payloadMap;
      if (responseJson != null && responseJson.isNotEmpty) {
        final decoded = jsonDecode(responseJson);
        payloadMap = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
      } else if (res['data'] is Map) {
        payloadMap = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        payloadMap = <String, dynamic>{};
      }

      final dataMap = payloadMap['data'] is Map
          ? Map<String, dynamic>.from(payloadMap['data'] as Map)
          : payloadMap;

      final rawConv = dataMap['conversation'] ?? payloadMap['conversation'];
      final rawMsg = dataMap['message'] ?? payloadMap['message'];

      if (rawConv is! Map || rawMsg is! Map) {
        throw Exception('استجابة غير صالحة من السيرفر بعد رفع الملف.');
      }

      final result = ChatPostResult(
        conversation: ChatConversation.fromJson(
          Map<String, dynamic>.from(rawConv),
        ),
        message: ChatMessage.fromJson(
          Map<String, dynamic>.from(rawMsg),
        ),
      );

      // Fast archive in Electron (direct 1ms file copy on disk)
      unawaited(
        _archiveSentAttachment(
          message: result.message,
          sha256Hex: fileSha256,
          filePath: filePath,
          fileName: resolvedFileName,
        ),
      );

      return result;
    }

    final fileLength = fileBytes?.length ?? (kIsWeb ? 0 : await File(filePath).length());
    // PERF FIX: When fileBytes is in memory (clipboard paste), computing SHA256 on the
    // Dart UI isolate blocks the event loop. Offload to a background isolate via compute().
    final fileSha256 = fileBytes != null
        ? await compute(_computeSha256Bytes, fileBytes)
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
      if (content != null && content.trim().isNotEmpty)
        'content': content.trim(),
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
      cancelToken: cancelToken,
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
    unawaited(
      _archiveSentAttachment(
        message: result.message,
        sha256Hex: fileSha256,
        filePath: fileBytes == null ? filePath : null,
        fileBytes: fileBytes,
        fileName: resolvedFileName,
      ),
    );
    if (fileBytes != null && result.message.isImageMessage) {
      unawaited(_cacheAttachmentPreviewBytes(result.message, fileBytes));
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

  Future<ChatMessage> sendScheduledMessageNow(String messageId) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat/messages/$messageId/send-now',
    );
    final data = response.data?['data'] ?? response.data;
    final msgJson = (data is Map<String, dynamic> ? data['message'] : null) ?? data;
    return ChatMessage.fromJson(msgJson as Map<String, dynamic>);
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

  Future<ChatMessage> togglePollStatus(String messageId) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/chat/messages/$messageId/poll/toggle',
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
    await cache.removeConversation(conversationId);
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

  Future<ChatConversation?> clearConversationMessages(
    String conversationId,
  ) async {
    await cache.clearConversationMessages(conversationId);
    final response = await _apiClient.dio.delete<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId',
      queryParameters: {'scope': 'clear'},
    );
    final conversationData = response.data?['conversation'];
    if (conversationData is Map<String, dynamic>) {
      return ChatConversation.fromJson(conversationData);
    }
    return null;
  }

  Future<String?> getCachedAttachmentPath(ChatMessage message) async {
    if (message.fileUrl == null || message.fileUrl!.isEmpty) return null;
    final fileName = p.basename(message.fileName ?? 'attachment');
    if (kIsWeb) {
      if (web_bridge.isElectron()) {
        return web_bridge.getElectronCachedAttachmentPath(
          messageId: message.id,
          fileName: fileName,
          preferredDirectoryPath: _preferences.localStorageDirectoryPath,
        );
      }
      return null;
    }

    final cacheDirectory = await _localStorage.chatDirectory(
      preferredPath: _preferences.localStorageDirectoryPath,
    );
    final targetPath = p.join(
      cacheDirectory.path,
      '${message.id}_${_localStorage.sanitizeFileName(fileName)}',
    );
    if (await File(targetPath).exists()) {
      return targetPath;
    }
    return null;
  }

  Future<String> downloadAttachment(
    ChatMessage message, {
    void Function(int received, int total)? onProgress,
  }) async {
    final fileName = p.basename(message.fileName ?? 'attachment');

    if (kIsWeb) {
      if (web_bridge.isElectron()) {
        final existingPath = await web_bridge.getElectronCachedAttachmentPath(
          messageId: message.id,
          fileName: fileName,
          preferredDirectoryPath: _preferences.localStorageDirectoryPath,
        );
        if (existingPath != null) {
          return existingPath;
        }

        final downloadUrl = _downloadUrlFor(message.fileUrl!);
        final response = await _downloadAttachmentBytesWithRestore(
          message,
          downloadUrl,
          onProgress: onProgress,
        );

        final cachedPath = await web_bridge.cacheElectronChatAttachment(
          messageId: message.id,
          fileName: fileName,
          bytes: response,
          preferredDirectoryPath: _preferences.localStorageDirectoryPath,
        );
        return cachedPath ?? fileName;
      }

      final downloadUrl = _downloadUrlFor(message.fileUrl!);
      final response = await _apiClient.dio.get<List<int>>(
        downloadUrl,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: onProgress,
      );
      await web_bridge.downloadBytes(
        bytes: Uint8List.fromList(response.data ?? const <int>[]),
        fileName: fileName,
        preferredDirectoryPath: _preferences.localStorageDirectoryPath,
      );
      return fileName;
    }

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

  Future<String> resolveEffectiveSaveDirectoryPath({String? customPath}) async {
    final preferred = customPath?.trim().isNotEmpty == true
        ? customPath!.trim()
        : _preferences.localStorageDirectoryPath?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      if (!kIsWeb) {
        try {
          final dir = Directory(preferred);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        } catch (_) {}
      }
      return preferred;
    }

    if (kIsWeb) {
      if (web_bridge.isElectron()) {
        try {
          final root = await web_bridge.getElectronStorageRoot();
          if (root != null && root.trim().isNotEmpty) {
            return root.trim();
          }
        } catch (_) {}
      }
      return '';
    }

    if (Platform.isWindows) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null && await downloads.exists()) {
          final ismartDir = Directory(p.join(downloads.path, 'iSmart Messenger'));
          if (!await ismartDir.exists()) {
            await ismartDir.create(recursive: true);
          }
          return ismartDir.path;
        }
      } catch (_) {}
    }

    try {
      final rootDir = await _localStorage.resolveRootDirectory();
      return rootDir.path;
    } catch (_) {
      return '';
    }
  }

  Future<Directory> resolveEffectiveSaveDirectory({String? customPath}) async {
    if (kIsWeb) {
      throw UnsupportedError('resolveEffectiveSaveDirectory is not supported on web. Use resolveEffectiveSaveDirectoryPath instead.');
    }
    final path = await resolveEffectiveSaveDirectoryPath(customPath: customPath);
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _resolveCleanFileName(ChatMessage message) {
    var rawName = (message.fileName ?? '').trim();
    if (rawName.isEmpty) {
      final shortId = message.id.length > 8 ? message.id.substring(0, 8) : message.id;
      rawName = 'ملف_$shortId';
    }
    var safeName = _localStorage.sanitizeFileName(rawName);
    if (p.extension(safeName).isEmpty) {
      final ext = _resolveFallbackExtension(
        mimeType: message.mimeType,
        fileUrl: message.fileUrl,
        messageType: message.messageType,
        isImage: message.isImageMessage,
        isPdf: message.isPdfMessage,
        isAudio: message.isAudioMessage,
      );
      if (ext.isNotEmpty) {
        safeName = '$safeName$ext';
      }
    }
    return safeName;
  }

  String _resolveFallbackExtension({
    String? mimeType,
    String? fileUrl,
    String? messageType,
    bool isImage = false,
    bool isPdf = false,
    bool isAudio = false,
  }) {
    final mime = (mimeType ?? '').trim().toLowerCase();
    if (mime.isNotEmpty) {
      if (mime == 'application/pdf') return '.pdf';
      if (mime.contains('spreadsheet') || mime.contains('excel')) return '.xlsx';
      if (mime.contains('wordprocessing') || mime.contains('msword')) return '.docx';
      if (mime.contains('presentation') || mime.contains('powerpoint')) return '.pptx';
      if (mime == 'image/jpeg' || mime == 'image/jpg') return '.jpg';
      if (mime == 'image/png') return '.png';
      if (mime == 'image/webp') return '.webp';
      if (mime == 'image/gif') return '.gif';
      if (mime == 'application/zip') return '.zip';
      if (mime == 'application/x-rar-compressed') return '.rar';
      if (mime == 'text/plain') return '.txt';
      if (mime.startsWith('image/')) return '.jpg';
      if (mime.startsWith('video/')) return '.mp4';
      if (mime.startsWith('audio/')) return '.mp3';
    }

    if (fileUrl != null && fileUrl.isNotEmpty) {
      try {
        final uri = Uri.tryParse(fileUrl);
        final path = uri?.path ?? fileUrl;
        final ext = p.extension(path).toLowerCase();
        if (ext.isNotEmpty && ext.length <= 6 && RegExp(r'^\.[a-z0-9]+$').hasMatch(ext)) {
          return ext;
        }
      } catch (_) {}
    }

    if (isImage || messageType == 'image') return '.jpg';
    if (isAudio || messageType == 'audio') return '.mp3';
    if (isPdf || messageType == 'pdf') return '.pdf';
    if (messageType == 'video') return '.mp4';
    return '';
  }

  Future<String?> getSavedAttachmentPath(
    ChatMessage message, {
    String? customSaveDirectory,
  }) async {
    if (message.fileUrl == null || message.fileUrl!.isEmpty) return null;
    final safeFileName = _resolveCleanFileName(message);

    if (kIsWeb) {
      if (web_bridge.isElectron()) {
        final targetDirPath = await resolveEffectiveSaveDirectoryPath(customPath: customSaveDirectory);
        if (targetDirPath.isNotEmpty) {
          final candidate = p.join(targetDirPath, safeFileName);
          final exists = await web_bridge.electronFileExists(candidate);
          if (exists) return candidate;
        }
        return await web_bridge.getElectronCachedAttachmentPath(
          messageId: message.id,
          fileName: safeFileName,
          preferredDirectoryPath: targetDirPath.isNotEmpty ? targetDirPath : null,
        );
      }
      return null;
    }

    final targetDir = await resolveEffectiveSaveDirectory(customPath: customSaveDirectory);
    final candidatePath = p.join(targetDir.path, safeFileName);
    final candidateFile = File(candidatePath);
    if (await candidateFile.exists()) {
      if (message.fileSize != null && message.fileSize! > 0) {
        final len = await candidateFile.length();
        if (len == message.fileSize) {
          return candidatePath;
        }
      } else {
        return candidatePath;
      }
    }
    return null;
  }

  Future<String> saveAttachmentToLocalStorage(
    ChatMessage message, {
    String? customSaveDirectory,
    String? targetFilePath,
    CancelToken? cancelToken,
    String? transferId,
    void Function(int received, int total)? onProgress,
  }) async {
    final safeFileName = _resolveCleanFileName(message);

    if (kIsWeb) {
      if (web_bridge.isElectron()) {
        final targetDirPath = targetFilePath != null
            ? p.dirname(targetFilePath)
            : await resolveEffectiveSaveDirectoryPath(customPath: customSaveDirectory);
        final existingPath = targetFilePath ??
            (targetDirPath.isNotEmpty ? p.join(targetDirPath, safeFileName) : safeFileName);

        // Check if message is already archived/cached locally in Electron
        final cachedPath = await web_bridge.getElectronCachedAttachmentPath(
          messageId: message.id,
          fileName: safeFileName,
          preferredDirectoryPath: targetFilePath == null && targetDirPath.isNotEmpty ? targetDirPath : null,
        );
        if (cachedPath != null && cachedPath.isNotEmpty) {
          if (targetFilePath != null) {
            final copied = await web_bridge.copyElectronFile(
              sourcePath: cachedPath,
              destinationPath: targetFilePath,
            );
            if (copied) return targetFilePath;
          } else {
            return cachedPath;
          }
        }

        // Direct streaming download via Electron (zero Dart memory, zero UI thread lag)
        if (message.fileUrl != null && message.fileUrl!.isNotEmpty) {
          final downloadUrl = _downloadUrlFor(message.fileUrl!);
          final token = _authRepository.currentToken ?? await _authRepository.getToken();
          final res = await web_bridge.downloadElectronChatAttachment(
            url: downloadUrl,
            destinationPath: existingPath,
            token: token,
            transferId: transferId,
            onProgress: onProgress,
          );
          if (res['success'] == true && res['path'] != null) {
            return res['path'].toString();
          }
        }

        final localBytes = await _readLocalAttachmentBytes(message);
        final Uint8List bytes;
        if (localBytes != null && localBytes.isNotEmpty) {
          bytes = localBytes;
        } else {
          bytes = await _downloadAttachmentBytesWithRestore(
            message,
            _downloadUrlFor(message.fileUrl!),
            cancelToken: cancelToken,
            onProgress: onProgress,
          );
          unawaited(_cacheAttachmentPreviewBytes(message, bytes).catchError((_) {}));
        }
        final saved = await web_bridge.downloadBytes(
          bytes: bytes,
          fileName: safeFileName,
          mimeType: message.mimeType,
          preferredDirectoryPath: targetDirPath.isNotEmpty ? targetDirPath : null,
        );
        return saved ?? existingPath;
      }

      final bytes = await _downloadAttachmentBytesWithRestore(
        message,
        _downloadUrlFor(message.fileUrl!),
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
      await web_bridge.downloadBytes(
        bytes: bytes,
        fileName: safeFileName,
        mimeType: message.mimeType,
      );
      return safeFileName;
    }

    // Native Desktop (Windows / macOS / Linux)
    if (targetFilePath != null && targetFilePath.isNotEmpty) {
      final destFile = File(targetFilePath);
      if (!destFile.parent.existsSync()) {
        await destFile.parent.create(recursive: true);
      }
      final cached = await getCachedAttachmentPath(message);
      if (cached != null && File(cached).existsSync()) {
        await File(cached).copy(targetFilePath);
        return targetFilePath;
      }
      final downloadUrl = _downloadUrlFor(message.fileUrl!);
      for (var attempt = 0; attempt < 4; attempt++) {
        try {
          await _apiClient.dio.download(
            downloadUrl,
            targetFilePath,
            cancelToken: cancelToken,
            deleteOnError: false,
            options: Options(
              extra: <String, Object?>{
                'isTransfer': true,
              },
            ),
            onReceiveProgress: onProgress,
          );
          return targetFilePath;
        } on DioException {
          if (cancelToken?.isCancelled == true) rethrow;
          if (attempt == 3) rethrow;
          await Future<void>.delayed(Duration(seconds: 1 + attempt * 2));
        }
      }
      return targetFilePath;
    }
    final targetDir = await resolveEffectiveSaveDirectory(customPath: customSaveDirectory);
    final baseName = p.basenameWithoutExtension(safeFileName);
    final extension = p.extension(safeFileName);
    final primaryCandidate = p.join(targetDir.path, safeFileName);
    final primaryFile = File(primaryCandidate);

    if (await primaryFile.exists()) {
      final existingSize = await primaryFile.length();
      if (message.fileSize == null || message.fileSize! <= 0 || existingSize == message.fileSize) {
        return primaryCandidate;
      }
    }

    Uint8List? bytes = await _readLocalAttachmentBytes(message);
    if (bytes == null || bytes.isEmpty) {
      bytes = await _downloadAttachmentBytesWithRestore(
        message,
        _downloadUrlFor(message.fileUrl!),
        onProgress: onProgress,
      );
      await _cacheAttachmentPreviewBytes(message, bytes);
    }

    var finalPath = primaryCandidate;
    var counter = 1;
    var candidateFile = File(finalPath);
    while (await candidateFile.exists()) {
      final existingLen = await candidateFile.length();
      if (existingLen == bytes.length) {
        return finalPath;
      }
      finalPath = p.join(targetDir.path, '$baseName ($counter)$extension');
      candidateFile = File(finalPath);
      counter++;
    }

    await candidateFile.writeAsBytes(bytes, flush: true);
    return finalPath;
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
    
    // Prevent infinite growth: max 100 items
    if (_attachmentPreviewLoads.length > 100) {
      final firstKey = _attachmentPreviewLoads.keys.first;
      _attachmentPreviewLoads.remove(firstKey);
    }
    
    load.catchError((e, st) {
      if (identical(_attachmentPreviewLoads[cacheKey], load)) {
        _attachmentPreviewLoads.remove(cacheKey);
      }
      Error.throwWithStackTrace(e, st);
    });
    return load;
  }

  Future<Uint8List> _fetchAttachmentPreviewBytes(ChatMessage message) async {
    final localBytes = await _readLocalAttachmentBytes(message);
    if (localBytes != null) {
      return localBytes;
    }
    if (message.fileUrl == null || message.fileUrl!.isEmpty) {
      throw StateError('Attachment preview is pending upload.');
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
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
    bool skipErrorLog = false,
  }) async {
    try {
      final response = await _apiClient.dio.get<List<int>>(
        downloadUrl,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.bytes,
          extra: <String, Object?>{
            if (skipErrorLog) 'skipErrorLog': true,
            'isTransfer': true,
          },
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
      if (kIsWeb && web_bridge.isElectron()) {
        await web_bridge.archiveElectronChatAttachment(
          messageId: message.id,
          sha256Hex: sha256Hex,
          fileName: fileName,
          bytes: fileBytes,
          sourcePath: filePath,
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
    final localPath = message.metadata?['localFilePath']?.toString();
    if (localPath != null && localPath.isNotEmpty) {
      try {
        if (!kIsWeb) {
          final f = File(localPath);
          if (await f.exists()) {
            return await f.readAsBytes();
          }
        }
      } catch (_) {}
    }
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

    if (kIsWeb) {
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

  Future<void> cacheAttachmentPreviewBytes(ChatMessage message, Uint8List bytes) => _cacheAttachmentPreviewBytes(message, bytes);

  Future<void> _cacheAttachmentPreviewBytes(
    ChatMessage message,
    Uint8List bytes,
  ) async {
    if (bytes.isEmpty) return;
    try {
      if (kIsWeb) {
        if (web_bridge.isElectron()) {
          await web_bridge.cacheElectronChatAttachment(
            messageId: message.id,
            fileName: message.fileName ?? 'attachment',
            bytes: bytes,
            preferredDirectoryPath: _preferences.localStorageDirectoryPath,
          );
        }
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
    List<String> managers = const [],
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/admin/departments',
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

Future<ChatConversation> uploadConversationAvatar({
    required String conversationId,
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    final token = _authRepository.currentToken ?? await _authRepository.getToken();
    final resolvedFileName = fileName?.trim().isNotEmpty == true
        ? fileName!.trim()
        : (filePath != null ? p.basename(filePath) : 'avatar.jpg');

    final MultipartFile multipartFile;
    if (fileBytes != null) {
      multipartFile = MultipartFile.fromBytes(fileBytes, filename: resolvedFileName);
    } else if (filePath != null && filePath.isNotEmpty) {
      multipartFile = await MultipartFile.fromFile(filePath, filename: resolvedFileName);
    } else {
      throw ArgumentError('Either filePath or fileBytes must be provided');
    }

    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId/avatar',
      data: FormData.fromMap({
        'avatar': multipartFile,
      }),
      options: Options(
        headers: {
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        contentType: 'multipart/form-data',
      ),
    );
    final raw = response.data?['data']?['conversation'] ??
        response.data?['conversation'];
    return ChatConversation.fromJson(raw as Map<String, dynamic>);
  }

  Future<ChatConversation> removeConversationAvatar(String conversationId) async {
    final token = _authRepository.currentToken ?? await _authRepository.getToken();
    final response = await _apiClient.dio.delete<Map<String, dynamic>>(
      '/api/chat/conversations/$conversationId/avatar',
      options: Options(
        headers: {
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ),
    );
    final raw = response.data?['data']?['conversation'] ??
        response.data?['conversation'];
    return ChatConversation.fromJson(raw as Map<String, dynamic>);
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

  Future<ChatFolder> updateFolderMembership({
    required String folderId,
    required String conversationId,
    required bool add,
  }) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/chat/folders/$folderId/membership',
      data: {
        'conversationId': conversationId,
        'action': add ? 'add' : 'remove',
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

  Future<String> downloadPollExport(String messageId) async {
    final response = await _apiClient.dio.get<List<int>>(
      "/api/chat/messages/$messageId/poll/export",
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception("ملف نتائج الاستطلاع فارغ أو تعذر تحميله.");
    }
    final disposition = response.headers.value("content-disposition") ?? "";
    String filename = "poll_export_$messageId.xlsx";
    if (disposition.contains("filename=")) {
      filename = disposition
          .split("filename=")
          .last
          .replaceAll("\"", "")
          .trim();
      try {
        filename = Uri.decodeComponent(filename);
      } catch (_) {}
    }

    if (kIsWeb) {
      final savedPath = await web_bridge.downloadBytes(
        bytes: Uint8List.fromList(bytes),
        fileName: filename,
        mimeType:
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        preferredDirectoryPath: _preferences.localStorageDirectoryPath,
      );
      return savedPath ?? filename;
    }

    final directory = await _localStorage.chatDirectory(
      preferredPath: _preferences.localStorageDirectoryPath,
    );
    final targetPath = p.join(directory.path, filename);
    final file = File(targetPath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Map<String, dynamic>> fetchUserStickers() async {
    final response =
        await _apiClient.dio.get<Map<String, dynamic>>("/api/chat/stickers");
    return response.data ?? const <String, dynamic>{};
  }

  Future<void> syncUserStickers({
    required List<Map<String, dynamic>> stickers,
    required List<Map<String, dynamic>> packs,
  }) async {
    await _apiClient.dio.put<void>(
      "/api/chat/stickers",
      data: {
        "stickers": stickers,
        "packs": packs,
      },
    );
  }

  Future<void> saveUserSticker(Map<String, dynamic> sticker) async {
    await _apiClient.dio.post<void>(
      "/api/chat/stickers",
      data: sticker,
    );
  }

  Future<void> deleteUserSticker(String stickerId) async {
    await _apiClient.dio.delete<void>("/api/chat/stickers/$stickerId");
  }
}
