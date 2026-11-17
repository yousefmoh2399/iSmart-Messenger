import 'dart:async';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';
import 'chat_local_cache.dart';
import 'chat_repository.dart';
import 'chat_socket_service.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;

bool isNetworkOrOfflineError(Object? error) {
  if (error == null) return false;
  final errStr = error.toString().toLowerCase();
  if (errStr.contains('socketexception') ||
      errStr.contains('connection refused') ||
      errStr.contains('connection timed out') ||
      errStr.contains('network is unreachable') ||
      errStr.contains('connection closed') ||
      errStr.contains('handshake failed') ||
      errStr.contains('connection reset') ||
      errStr.contains('econnreset') ||
      errStr.contains('etimedout') ||
      errStr.contains('enotfound') ||
      errStr.contains('epipe') ||
      errStr.contains('connection error') ||
      errStr.contains('receive timeout') ||
      errStr.contains('send timeout') ||
      errStr.contains('502') ||
      errStr.contains('503') ||
      errStr.contains('504') ||
      errStr.contains('offline') ||
      errStr.contains('failed to fetch') ||
      errStr.contains('xmlhttprequest error') ||
      errStr.contains('client is offline')) {
    return true;
  }
  if (error is DioException) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return true;
    }
    final status = error.response?.statusCode ?? 0;
    if (status == 502 || status == 503 || status == 504 || status == 429) {
      return true;
    }
  }
  return false;
}

class ChatOutboxItem {
  ChatOutboxItem({
    required this.clientMessageId,
    required this.conversationId,
    required this.content,
    this.messageType,
    this.fileUrl,
    this.localFilePath,
    this.fileName,
    this.sourceFileName,
    this.customFileName,
    this.replyToMessageId,
    this.metadata,
    this.isSilent = false,
    DateTime? createdAt,
    this.retryAttempts = 0,
    this.isProcessing = false,
  }) : createdAt = createdAt ?? DateTime.now();

  final String clientMessageId;
  final String conversationId;
  final String content;
  final String? messageType;
  final String? fileUrl;
  final String? localFilePath;
  final String? fileName;
  final String? sourceFileName;
  final String? customFileName;
  final String? replyToMessageId;
  final Map<String, dynamic>? metadata;
  final bool isSilent;
  final DateTime createdAt;
  int retryAttempts;
  bool isProcessing;

  bool get isFile =>
      (localFilePath != null && localFilePath!.isNotEmpty) ||
      (fileName != null && fileName!.isNotEmpty && messageType != 'text' && messageType != 'poll' && messageType != 'checklist');

  Map<String, dynamic> toJson() => {
    'clientMessageId': clientMessageId,
    'conversationId': conversationId,
    'content': content,
    'messageType': messageType,
    'fileUrl': fileUrl,
    'localFilePath': localFilePath,
    'fileName': fileName,
    'sourceFileName': sourceFileName,
    'customFileName': customFileName,
    'replyToMessageId': replyToMessageId,
    'metadata': metadata,
    'isSilent': isSilent,
    'createdAt': createdAt.toIso8601String(),
    'retryAttempts': retryAttempts,
  };

  factory ChatOutboxItem.fromJson(Map<String, dynamic> json) => ChatOutboxItem(
    clientMessageId: json['clientMessageId']?.toString() ?? '',
    conversationId: json['conversationId']?.toString() ?? '',
    content: json['content']?.toString() ?? '',
    messageType: json['messageType']?.toString(),
    fileUrl: json['fileUrl']?.toString(),
    localFilePath: json['localFilePath']?.toString(),
    fileName: json['fileName']?.toString(),
    sourceFileName: json['sourceFileName']?.toString(),
    customFileName: json['customFileName']?.toString(),
    replyToMessageId: json['replyToMessageId']?.toString(),
    metadata: json['metadata'] is Map ? Map<String, dynamic>.from(json['metadata'] as Map) : null,
    isSilent: json['isSilent'] == true,
    createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
    retryAttempts: (json['retryAttempts'] as num?)?.toInt() ?? 0,
  );
}

abstract class ChatOutboxEvent {
  const ChatOutboxEvent({
    required this.clientMessageId,
    required this.conversationId,
  });

  final String clientMessageId;
  final String conversationId;
}

class ChatOutboxProgressEvent extends ChatOutboxEvent {
  const ChatOutboxProgressEvent({
    required super.clientMessageId,
    required super.conversationId,
    required this.progress,
  });

  final double progress;
}

class ChatOutboxConfirmedEvent extends ChatOutboxEvent {
  const ChatOutboxConfirmedEvent({
    required super.clientMessageId,
    required super.conversationId,
    required this.message,
  });

  final ChatMessage message;
}

class ChatOutboxFailedEvent extends ChatOutboxEvent {
  const ChatOutboxFailedEvent({
    required super.clientMessageId,
    required super.conversationId,
    required this.error,
  });

  final String error;
}

class ChatOutboxService {
  ChatOutboxService({
    required ChatRepository repository,
    required ChatLocalCache cache,
    ChatSocketService? socketService,
  })  : _repository = repository,
        _cache = cache,
        _socketService = socketService {
    _init();
  }

  final ChatRepository _repository;
  final ChatLocalCache _cache;
  final ChatSocketService? _socketService;

  final List<ChatOutboxItem> _queue = <ChatOutboxItem>[];
  final StreamController<ChatOutboxEvent> _eventsController =
      StreamController<ChatOutboxEvent>.broadcast();

  StreamSubscription<ChatSocketEvent>? _socketSub;
  Timer? _drainTimer;
  bool _isDraining = false;
  bool _initialized = false;

  Stream<ChatOutboxEvent> get events => _eventsController.stream;

  List<ChatOutboxItem> get queue => List<ChatOutboxItem>.unmodifiable(_queue);

  bool hasItem(String clientMessageId) {
    return _queue.any((item) => item.clientMessageId == clientMessageId);
  }

  List<ChatOutboxItem> getPendingForConversation(String conversationId) {
    return _queue
        .where((item) => item.conversationId == conversationId)
        .toList(growable: false);
  }

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final saved = await _cache.loadOutboxItems();
      if (saved != null && saved.isNotEmpty) {
        for (final json in saved) {
          try {
            final item = ChatOutboxItem.fromJson(json);
            if (item.clientMessageId.isNotEmpty &&
                !_queue.any((q) => q.clientMessageId == item.clientMessageId)) {
              _queue.add(item);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // Listen to socket connection/reconnection to flush outbox automatically
    final sock = _socketService;
    if (sock != null) {
      _socketSub = sock.events.listen((event) {
        if (event.type == 'socket_connected') {
          drainQueue();
        }
      });
    }

    // Periodic drain timer: checks every 5 seconds if there are items to send
    _drainTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_queue.isNotEmpty && !_isDraining) {
        drainQueue();
      }
    });

    if (_queue.isNotEmpty) {
      drainQueue();
    }
  }

  Future<void> _persistQueue() async {
    try {
      final items = _queue.map((item) => item.toJson()).toList(growable: false);
      await _cache.saveOutboxItems(items);
    } catch (_) {}
  }

  Future<void> enqueue(ChatOutboxItem item) async {
    final existingIndex = _queue.indexWhere((q) => q.clientMessageId == item.clientMessageId);
    if (existingIndex == -1) {
      _queue.add(item);
    } else {
      _queue[existingIndex] = item;
    }
    await _persistQueue();
    unawaited(drainQueue());
  }

  Future<void> remove(String clientMessageId) async {
    _queue.removeWhere((item) => item.clientMessageId == clientMessageId);
    await _persistQueue();
  }

  void retryAll() {
    for (final item in _queue) {
      item.isProcessing = false;
    }
    drainQueue();
  }

  Future<void> drainQueue() async {
    if (_isDraining || _queue.isEmpty) return;
    _isDraining = true;

    try {
      final itemsToProcess = List<ChatOutboxItem>.from(_queue);
      for (final item in itemsToProcess) {
        // If item was removed or is actively processing in another loop
        if (!_queue.any((q) => q.clientMessageId == item.clientMessageId)) {
          continue;
        }

        item.isProcessing = true;
        try {
          final ChatPostResult result;

          if (item.isFile) {
            final localPath = item.localFilePath ?? '';
            // Verify file exists if running natively or in Electron
            if (localPath.isNotEmpty) {
              final bool exists;
              if (kIsWeb) {
                exists = web_bridge.isElectron()
                    ? await web_bridge.electronFileExists(localPath)
                    : true;
              } else {
                exists = io.File(localPath).existsSync();
              }

              if (!exists) {
                if (_socketService != null && !_socketService.isConnected) {
                  break;
                }
                _eventsController.add(ChatOutboxFailedEvent(
                  clientMessageId: item.clientMessageId,
                  conversationId: item.conversationId,
                  error: 'الملف لم يعد موجوداً في الجهاز لإعادة رفعه.',
                ));
                _queue.removeWhere((q) => q.clientMessageId == item.clientMessageId);
                await _persistQueue();
                continue;
              }
            }

            result = await _repository.sendFileMessage(
              conversationId: item.conversationId,
              filePath: localPath,
              sourceFileName: item.sourceFileName ?? item.fileName,
              customFileName: item.customFileName ?? item.fileName,
              content: item.content.isNotEmpty ? item.content : null,
              replyToMessageId: item.replyToMessageId,
              metadata: {
                ...?item.metadata,
                'clientMessageId': item.clientMessageId,
              },
              onProgress: (sent, total) {
                final fraction = total <= 0 ? 0.0 : (sent / total).clamp(0.0, 1.0).toDouble();
                _eventsController.add(ChatOutboxProgressEvent(
                  clientMessageId: item.clientMessageId,
                  conversationId: item.conversationId,
                  progress: fraction,
                ));
              },
            );
          } else {
            result = await _repository.sendTextMessage(
              conversationId: item.conversationId,
              content: item.content,
              clientMessageId: item.clientMessageId,
              replyToMessageId: item.replyToMessageId,
              metadata: {
                ...?item.metadata,
                'clientMessageId': item.clientMessageId,
              },
              messageType: item.messageType,
              fileUrl: item.fileUrl,
              isSilent: item.isSilent,
            );
          }

          // Successfully sent and confirmed!
          _eventsController.add(ChatOutboxConfirmedEvent(
            clientMessageId: item.clientMessageId,
            conversationId: item.conversationId,
            message: result.message,
          ));

          _queue.removeWhere((q) => q.clientMessageId == item.clientMessageId);
          await _persistQueue();
        } catch (error) {
          item.isProcessing = false;
          item.retryAttempts++;

          final isNetErr = isNetworkOrOfflineError(error) ||
              (_socketService != null && !_socketService.isConnected);

          if (isNetErr) {
            // Network is unreachable or server is offline.
            // Keep in outbox with 'pending' status so it will be retried automatically upon reconnection.
            debugPrint('[ChatOutbox] Network offline for message ${item.clientMessageId}. Will auto-retry on reconnect.');
            break; // Stop draining remaining items until connectivity is back
          } else {
            // Permanent failure (e.g. 400 Bad Request, blocked user, etc.)
            _eventsController.add(ChatOutboxFailedEvent(
              clientMessageId: item.clientMessageId,
              conversationId: item.conversationId,
              error: error.toString(),
            ));
            _queue.removeWhere((q) => q.clientMessageId == item.clientMessageId);
            await _persistQueue();
          }
        }
      }
    } finally {
      _isDraining = false;
    }
  }

  void dispose() {
    _socketSub?.cancel();
    _drainTimer?.cancel();
    _eventsController.close();
  }
}
