import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';
import 'chat_local_cache.dart';
import 'chat_repository.dart';

class ChatOutboxItem {
  const ChatOutboxItem({
    required this.clientMessageId,
    required this.conversationId,
    required this.content,
    required this.messageType,
    this.filePath,
    this.customFileName,
    this.replyToMessageId,
    this.metadata,
    required this.createdAt,
    this.retryCount = 0,
  });

  final String clientMessageId;
  final String conversationId;
  final String content;
  final String messageType;
  final String? filePath;
  final String? customFileName;
  final String? replyToMessageId;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final int retryCount;

  String get tempMessageId => 'temp_$clientMessageId';

  Map<String, dynamic> toJson() => {
        'clientMessageId': clientMessageId,
        'conversationId': conversationId,
        'content': content,
        'messageType': messageType,
        'filePath': filePath,
        'customFileName': customFileName,
        'replyToMessageId': replyToMessageId,
        'metadata': metadata,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
      };

  factory ChatOutboxItem.fromJson(Map<String, dynamic> json) => ChatOutboxItem(
        clientMessageId: json['clientMessageId'] as String,
        conversationId: json['conversationId'] as String,
        content: (json['content'] ?? '').toString(),
        messageType: (json['messageType'] ?? 'text').toString(),
        filePath: json['filePath'] as String?,
        customFileName: json['customFileName'] as String?,
        replyToMessageId: json['replyToMessageId'] as String?,
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : null,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      );

  ChatOutboxItem copyWith({
    int? retryCount,
  }) =>
      ChatOutboxItem(
        clientMessageId: clientMessageId,
        conversationId: conversationId,
        content: content,
        messageType: messageType,
        filePath: filePath,
        customFileName: customFileName,
        replyToMessageId: replyToMessageId,
        metadata: metadata,
        createdAt: createdAt,
        retryCount: retryCount ?? this.retryCount,
      );
}

class ChatOutboxService {
  ChatOutboxService(this._cache);

  final ChatLocalCache _cache;
  static const String _outboxKey = 'outbox_items';

  List<ChatOutboxItem> _items = [];
  bool _isLoaded = false;
  bool _isDraining = false;

  final StreamController<void> _changeController =
      StreamController<void>.broadcast();
  Stream<void> get changes => _changeController.stream;

  Future<void> _ensureLoaded() async {
    if (_isLoaded) return;
    try {
      final raw = await _cache.loadRawJson(_outboxKey);
      if (raw != null && raw['items'] is List) {
        _items = (raw['items'] as List)
            .whereType<Map>()
            .map((entry) =>
                ChatOutboxItem.fromJson(Map<String, dynamic>.from(entry)))
            .toList();
      }
    } catch (_) {
      _items = [];
    } finally {
      _isLoaded = true;
    }
  }

  Future<void> _persist() async {
    try {
      await _cache.saveRawJson(_outboxKey, {
        'items': _items.map((i) => i.toJson()).toList(),
      });
      _changeController.add(null);
    } catch (_) {}
  }

  Future<void> enqueue(ChatOutboxItem item) async {
    await _ensureLoaded();
    _items.removeWhere((i) => i.clientMessageId == item.clientMessageId);
    _items.add(item);
    await _persist();
  }

  Future<void> remove(String clientMessageId) async {
    await _ensureLoaded();
    final countBefore = _items.length;
    _items.removeWhere((i) =>
        i.clientMessageId == clientMessageId ||
        i.tempMessageId == clientMessageId);
    if (_items.length != countBefore) {
      await _persist();
    }
  }

  Future<List<ChatOutboxItem>> getPendingItems() async {
    await _ensureLoaded();
    return List.unmodifiable(_items);
  }

  Future<List<ChatOutboxItem>> getPendingItemsForConversation(
      String conversationId) async {
    await _ensureLoaded();
    return _items.where((i) => i.conversationId == conversationId).toList();
  }

  bool isPending(String clientMessageId) {
    return _items.any((i) =>
        i.clientMessageId == clientMessageId ||
        i.tempMessageId == clientMessageId);
  }

  /// Drains all pending items in FIFO order.
  /// If an item succeeds: removes from outbox and calls [onConfirmed].
  /// If an item encounters a network error (offline): halts drain and leaves it pending for next reconnection.
  /// If an item encounters a permanent client/server error: removes from outbox and calls [onFailed].
  Future<void> drainQueue({
    required ChatRepository repository,
    void Function(ChatOutboxItem item, ChatMessage confirmedMessage)?
        onConfirmed,
    void Function(ChatOutboxItem item, Object error)? onFailed,
  }) async {
    if (_isDraining) return;
    await _ensureLoaded();
    if (_items.isEmpty) return;

    _isDraining = true;
    try {
      // Sort oldest first
      final queueCopy = List<ChatOutboxItem>.from(_items)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      for (final item in queueCopy) {
        try {
          ChatMessage confirmed;
          if (item.filePath != null && item.filePath!.isNotEmpty) {
            // File or voice note
            final result = await repository.sendFileMessage(
              conversationId: item.conversationId,
              filePath: item.filePath!,
              content: item.content.isNotEmpty ? item.content : null,
              replyToMessageId: item.replyToMessageId,
              customFileName: item.customFileName,
              metadata: item.metadata,
            );
            confirmed = result.message;
          } else {
            // Text or poll/checklist
            final result = await repository.sendTextMessage(
              conversationId: item.conversationId,
              content: item.content,
              clientMessageId: item.clientMessageId,
              replyToMessageId: item.replyToMessageId,
              metadata: item.metadata,
              messageType: item.messageType,
              isSilent: false,
              isScheduled: false,
            );
            confirmed = result.message;
          }

          // Successfully sent!
          await remove(item.clientMessageId);
          onConfirmed?.call(item, confirmed);
        } catch (error) {
          final isNetwork = _isNetworkError(error);
          if (isNetwork) {
            // Transient network failure — halt queue draining and keep pending.
            debugPrint('[ChatOutbox] Network error during drain, halting: $error');
            break;
          } else {
            // Permanent failure (400, 403, 404, etc.)
            debugPrint('[ChatOutbox] Permanent failure for ${item.clientMessageId}: $error');
            await remove(item.clientMessageId);
            onFailed?.call(item, error);
          }
        }
      }
    } finally {
      _isDraining = false;
    }
  }

  bool _isNetworkError(Object error) {
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;
    final str = error.toString().toLowerCase();
    if (str.contains('socketexception') ||
        str.contains('connection refused') ||
        str.contains('connection closed') ||
        str.contains('connection reset') ||
        str.contains('network is unreachable') ||
        str.contains('failed host lookup') ||
        str.contains('connection timeout') ||
        str.contains('sendtimeout') ||
        str.contains('receivetimeout') ||
        str.contains('software caused connection abort')) {
      return true;
    }
    return false;
  }

  void dispose() {
    _changeController.close();
  }
}
