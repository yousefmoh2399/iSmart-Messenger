import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../../shared/providers/providers.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../models/chat_models.dart';
import '../utils/chat_attachment_policy.dart';

enum ChatTransferType { upload, download }

enum ChatTransferStatus { running, completed, failed }

class ChatTransferTask {
  const ChatTransferTask({
    required this.id,
    required this.conversationId,
    required this.fileName,
    required this.type,
    required this.progress,
    required this.status,
    required this.createdAt,
    this.messageId,
    this.savedPath,
    this.errorMessage,
  });

  final String id;
  final String conversationId;
  final String? messageId;
  final String fileName;
  final ChatTransferType type;
  final double progress;
  final ChatTransferStatus status;
  final DateTime createdAt;
  final String? savedPath;
  final String? errorMessage;

  bool get isRunning => status == ChatTransferStatus.running;
  bool get isCompleted => status == ChatTransferStatus.completed;
  bool get isFailed => status == ChatTransferStatus.failed;
  bool get isUpload => type == ChatTransferType.upload;
  bool get isDownload => type == ChatTransferType.download;

  ChatTransferTask copyWith({
    double? progress,
    ChatTransferStatus? status,
    String? savedPath,
    String? errorMessage,
  }) {
    return ChatTransferTask(
      id: id,
      conversationId: conversationId,
      messageId: messageId,
      fileName: fileName,
      type: type,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      createdAt: createdAt,
      savedPath: savedPath ?? this.savedPath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class ChatTransferManagerState {
  const ChatTransferManagerState({
    this.tasks = const <ChatTransferTask>[],
  });

  final List<ChatTransferTask> tasks;

  List<ChatTransferTask> get activeTasks =>
      tasks.where((t) => t.isRunning).toList(growable: false);

  List<ChatTransferTask> activeForConversation(String conversationId) =>
      tasks
          .where((t) => t.conversationId == conversationId && t.isRunning)
          .toList(growable: false);

  List<ChatTransferTask> recentOrActiveForConversation(String conversationId) =>
      tasks
          .where((t) => t.conversationId == conversationId)
          .toList(growable: false);

  List<ChatTransferTask> activeInOtherConversations(String conversationId) =>
      tasks
          .where((t) => t.conversationId != conversationId && t.isRunning)
          .toList(growable: false);

  bool isDownloadingMessage(String messageId) => tasks.any(
        (t) =>
            t.isDownload &&
            t.isRunning &&
            t.messageId != null &&
            t.messageId == messageId,
      );

  ChatTransferManagerState copyWith({
    List<ChatTransferTask>? tasks,
  }) {
    return ChatTransferManagerState(
      tasks: tasks ?? this.tasks,
    );
  }
}

class ChatTransferManager extends Notifier<ChatTransferManagerState> {
  int _taskCounter = 0;
  int _lastProgressUpdateTimestamp = 0;
  final Map<String, Timer> _cleanupTimers = <String, Timer>{};
  final Map<String, CancelToken> _activeCancelTokens = <String, CancelToken>{};

  void cancelTask(String taskId) {
    _cleanupTimers.remove(taskId)?.cancel();
    final cancelToken = _activeCancelTokens.remove(taskId);
    cancelToken?.cancel('تم إلغاء النقل من قبل المستخدم.');
    if (kIsWeb && web_bridge.isElectron()) {
      unawaited(web_bridge.cancelElectronDownload(taskId));
      unawaited(web_bridge.cancelElectronUpload(taskId));
    }
    final idx = state.tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      final task = state.tasks[idx];
      _upsertTask(
        task.copyWith(
          status: ChatTransferStatus.failed,
          errorMessage: task.isUpload ? 'تم إلغاء الرفع' : 'تم إلغاء التحميل',
        ),
      );
      _scheduleTaskCleanup(taskId, delay: const Duration(seconds: 2));
    }
  }

  @override
  ChatTransferManagerState build() {
    ref.onDispose(() {
      for (final timer in _cleanupTimers.values) {
        timer.cancel();
      }
      _cleanupTimers.clear();
    });
    return const ChatTransferManagerState();
  }

  String _nextTaskId(String prefix) {
    _taskCounter++;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_taskCounter';
  }

  void _upsertTask(ChatTransferTask task) {
    final current = state.tasks;
    final idx = current.indexWhere((t) => t.id == task.id);
    if (idx == -1) {
      state = state.copyWith(tasks: <ChatTransferTask>[...current, task]);
    } else {
      final next = List<ChatTransferTask>.from(current);
      next[idx] = task;
      state = state.copyWith(tasks: next);
    }
  }

  void _updateTaskProgress(String taskId, double progress) {
    final current = state.tasks;
    final idx = current.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    final existing = current[idx];
    final clamped = progress.clamp(0.0, 1.0).toDouble();
    final now = DateTime.now().millisecondsSinceEpoch;
    // Throttle progress updates to at most ~8 FPS (120ms) or at least 2% change, unless complete (1.0).
    // Prevents hundreds of Riverpod rebuilds per second during fast background transfers.
    if (clamped < 1.0) {
      if ((existing.progress - clamped).abs() < 0.02 || (now - _lastProgressUpdateTimestamp < 120)) {
        return;
      }
    }
    _lastProgressUpdateTimestamp = now;
    final next = List<ChatTransferTask>.from(current);
    next[idx] = existing.copyWith(progress: clamped);
    state = state.copyWith(tasks: next);
  }

  void dismissTask(String taskId) {
    _cleanupTimers.remove(taskId)?.cancel();
    state = state.copyWith(
      tasks: state.tasks.where((t) => t.id != taskId).toList(growable: false),
    );
  }

  void _scheduleTaskCleanup(
    String taskId, {
    Duration delay = const Duration(seconds: 4),
  }) {
    _cleanupTimers.remove(taskId)?.cancel();
    _cleanupTimers[taskId] = Timer(delay, () {
      _cleanupTimers.remove(taskId);
      dismissTask(taskId);
    });
  }

  /// Starts a persistent background file upload that continues even if the user
  /// switches conversations, navigates to another tab, or minimizes to tray.
  /// Multiple calls run concurrently without blocking one another.
  Future<bool> startUpload({
    required String conversationId,
    required String sendPath,
    required String displayName,
    required Map<String, dynamic> metadata,
    String? caption,
    Uint8List? fileBytes,
    String? sourceFileName,
    String? replyToMessageId,
    void Function(String errorMessage)? onError,
    VoidCallback? onCompleted,
  }) async {
    if (isChatAttachmentExtensionBlocked(sendPath)) {
      onError?.call(kChatBlockedAttachmentUserMessage);
      return false;
    }

    final taskId = _nextTaskId('upload');
    final cancelToken = CancelToken();
    _activeCancelTokens[taskId] = cancelToken;
    final task = ChatTransferTask(
      id: taskId,
      conversationId: conversationId,
      fileName: displayName,
      type: ChatTransferType.upload,
      progress: 0.0,
      status: ChatTransferStatus.running,
      createdAt: DateTime.now(),
    );
    _upsertTask(task);

    try {
      await ref
          .read(conversationMessagesControllerProvider(conversationId).notifier)
          .sendFile(
            sendPath,
            fileBytes: fileBytes,
            sourceFileName: sourceFileName ?? displayName,
            content: caption,
            replyToMessageId: replyToMessageId,
            customFileName: displayName,
            metadata: metadata,
            transferId: taskId,
            cancelToken: cancelToken,
            onProgress: (sent, total) {
              final fraction =
                  total <= 0 ? 0.0 : (sent / total).clamp(0.0, 1.0).toDouble();
              _updateTaskProgress(taskId, fraction);
            },
          );

      _upsertTask(
        task.copyWith(
          progress: 1.0,
          status: ChatTransferStatus.completed,
        ),
      );
      _scheduleTaskCleanup(taskId, delay: const Duration(seconds: 2));
      onCompleted?.call();

      final activeConvId = ref.read(activeConversationIdProvider);
      final isSectionVisible = ref.read(chatSectionVisibleProvider);
      if (activeConvId != conversationId || !isSectionVisible) {
        unawaited(
          ref
              .read(localNotificationServiceProvider)
              .showIncomingMessage(
                title: 'اكتمل رفع الملف',
                body: 'تم إرسال "$displayName" بنجاح في الشات.',
                requestAttention: false,
              )
              .catchError((_) {}),
        );
      }

      return true;
    } catch (error) {
      _activeCancelTokens.remove(taskId);
      if (cancelToken.isCancelled) {
        _upsertTask(
          task.copyWith(
            status: ChatTransferStatus.failed,
            errorMessage: 'تم إلغاء الرفع',
          ),
        );
        _scheduleTaskCleanup(taskId, delay: const Duration(seconds: 2));
        return false;
      }
      final errMsg = messageFromChatDioError(error);
      _upsertTask(
        task.copyWith(
          status: ChatTransferStatus.failed,
          errorMessage: errMsg,
        ),
      );
      _scheduleTaskCleanup(taskId, delay: const Duration(seconds: 6));
      onError?.call(errMsg);
      return false;
    } finally {
      _activeCancelTokens.remove(taskId);
    }
  }

  /// Starts a persistent background file download to the user's configured
  /// local storage directory. Continues even if the user leaves the chat or
  /// minimizes the window, and supports downloading multiple files simultaneously.
  Future<String?> startDownload({
    required ChatMessage message,
    String? targetFilePath,
    bool openAfterDownload = false,
    void Function(String savedPath)? onCompleted,
    void Function(String errorMessage)? onError,
  }) async {
    final existingRunning = state.tasks
        .where(
          (t) =>
              t.isDownload &&
              t.isRunning &&
              t.messageId != null &&
              t.messageId == message.id,
        )
        .firstOrNull;
    if (existingRunning != null) {
      // Already downloading this exact message in parallel; avoid duplicate file write collision
      return null;
    }

    final fileName = targetFilePath != null
        ? p.basename(targetFilePath)
        : (message.fileName ?? 'مرفق');
    final taskId = _nextTaskId('download');
    final task = ChatTransferTask(
      id: taskId,
      conversationId: message.conversationId,
      messageId: message.id,
      fileName: fileName,
      type: ChatTransferType.download,
      progress: 0.0,
      status: ChatTransferStatus.running,
      createdAt: DateTime.now(),
    );
    _upsertTask(task);

    final cancelToken = CancelToken();
    _activeCancelTokens[taskId] = cancelToken;

    try {
      final repo = ref.read(chatRepositoryProvider);
      final savedPath = await repo.saveAttachmentToLocalStorage(
        message,
        customSaveDirectory: targetFilePath != null ? p.dirname(targetFilePath) : null,
        targetFilePath: targetFilePath,
        cancelToken: cancelToken,
        transferId: taskId,
        onProgress: (received, total) {
          final fraction =
              total <= 0 ? 0.0 : (received / total).clamp(0.0, 1.0).toDouble();
          _updateTaskProgress(taskId, fraction);
        },
      );

      _activeCancelTokens.remove(taskId);

      _upsertTask(
        task.copyWith(
          progress: 1.0,
          status: ChatTransferStatus.completed,
          savedPath: savedPath,
        ),
      );
      _scheduleTaskCleanup(taskId, delay: const Duration(seconds: 3));

      if (openAfterDownload && savedPath.isNotEmpty) {
        await openDownloadedFilePath(savedPath);
      }

      onCompleted?.call(savedPath);

      final activeConvId = ref.read(activeConversationIdProvider);
      final isSectionVisible = ref.read(chatSectionVisibleProvider);
      if (activeConvId != message.conversationId || !isSectionVisible) {
        final savedBaseName =
            savedPath.isNotEmpty ? p.basename(savedPath) : fileName;
        unawaited(
          ref
              .read(localNotificationServiceProvider)
              .showIncomingMessage(
                title: 'اكتمل تحميل الملف',
                body: openAfterDownload
                    ? 'تم حفظ وفتح "$savedBaseName" بنجاح.'
                    : 'تم حفظ "$savedBaseName" في مجلد الملفات بنجاح.',
                requestAttention: false,
              )
              .catchError((_) {}),
        );
      }

      return savedPath;
    } catch (error) {
      _activeCancelTokens.remove(taskId);
      if (cancelToken.isCancelled) {
        return null;
      }
      final raw = error.toString().trim();
      final errMsg = raw.isEmpty ? 'تعذر تنزيل المرفق حاليًا' : raw;
      _upsertTask(
        task.copyWith(
          status: ChatTransferStatus.failed,
          errorMessage: errMsg,
        ),
      );
      _scheduleTaskCleanup(taskId, delay: const Duration(seconds: 6));
      onError?.call(errMsg);
      return null;
    }
  }

  static Future<bool> openDownloadedFilePath(String localPath) async {
    if (localPath.trim().isEmpty) return false;
    if (kIsWeb) {
      if (web_bridge.isElectron()) {
        return web_bridge.openElectronLocalFile(localPath);
      }
      return true;
    }

    final openResult = await OpenFilex.open(localPath);
    if (openResult.type == ResultType.done) {
      return true;
    }
    if (Platform.isWindows) {
      try {
        final result = await Process.run(
          'cmd',
          ['/c', 'start', '', localPath],
          runInShell: true,
        );
        return result.exitCode == 0;
      } catch (_) {}
    }
    return false;
  }

  static Future<void> revealDownloadedFileInFolder(String filePath) async {
    if (filePath.trim().isEmpty) return;
    if (kIsWeb) {
      if (web_bridge.isElectron()) {
        try {
          await web_bridge.openElectronInboxFileLocation(filePath);
        } catch (_) {
          await web_bridge.openElectronLocalFile(p.dirname(filePath));
        }
      }
      return;
    }
    if (Platform.isWindows) {
      try {
        await Process.run('explorer.exe', ['/select,', filePath]);
        return;
      } catch (_) {}
    }
    try {
      await OpenFilex.open(p.dirname(filePath));
    } catch (_) {}
  }
}

final chatTransferManagerProvider =
    NotifierProvider<ChatTransferManager, ChatTransferManagerState>(
      ChatTransferManager.new,
    );

class ChatMultiTransferBanner extends ConsumerWidget {
  const ChatMultiTransferBanner({
    super.key,
    required this.conversationId,
    required this.isDark,
  });

  final String conversationId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transferState = ref.watch(chatTransferManagerProvider);
    final localTasks =
        transferState.recentOrActiveForConversation(conversationId);
    final otherActiveTasks =
        transferState.activeInOtherConversations(conversationId);

    if (localTasks.isEmpty && otherActiveTasks.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Material(
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        color: isDark ? const Color(0xFF1E2936) : colorScheme.surface,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 168),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (localTasks.length > 1 || otherActiveTasks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.swap_vert_circle_rounded,
                        size: 16,
                        color: Color(0xFF3390EC),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          localTasks.isNotEmpty
                              ? 'عمليات نقل الملفات الجارية (${localTasks.where((t) => t.isRunning).length} نشط)'
                              : 'يوجد ${otherActiveTasks.length} عملية نقل ملفات تعمل في الخلفية بمحادثات أخرى',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF3390EC),
                          ),
                        ),
                      ),
                      if (otherActiveTasks.isNotEmpty && localTasks.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF3390EC).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '+${otherActiveTasks.length} بالخلفية',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3390EC),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (localTasks.isNotEmpty)
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: localTasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final task = localTasks[index];
                      return _TransferTaskRow(
                        task: task,
                        isDark: isDark,
                        onDismiss: () => ref
                            .read(chatTransferManagerProvider.notifier)
                            .dismissTask(task.id),
                        onCancel: () => ref
                            .read(chatTransferManagerProvider.notifier)
                            .cancelTask(task.id),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferTaskRow extends StatelessWidget {
  const _TransferTaskRow({
    required this.task,
    required this.isDark,
    required this.onDismiss,
    required this.onCancel,
  });

  final ChatTransferTask task;
  final bool isDark;
  final VoidCallback onDismiss;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUpload = task.isUpload;
    final accentColor = task.isFailed
        ? const Color(0xFFE53935)
        : (task.isCompleted
              ? const Color(0xFF34C759)
              : (isUpload ? const Color(0xFF3390EC) : const Color(0xFF007AFF)));

    final percent = (task.progress * 100).clamp(0, 100).toStringAsFixed(0);
    final statusLabel = task.isFailed
        ? (task.errorMessage ?? 'فشل النقل')
        : (task.isCompleted
              ? (isUpload ? 'تم الإرسال ✓' : 'تم الحفظ ✓')
              : (isUpload ? 'جاري الرفع $percent%' : 'جاري التحميل $percent%'));

    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            task.isFailed
                ? Icons.error_outline_rounded
                : (task.isCompleted
                      ? Icons.check_circle_rounded
                      : (isUpload
                            ? Icons.upload_rounded
                            : Icons.download_rounded)),
            size: 17,
            color: accentColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: isDark ? Colors.white : const Color(0xFF1C2B3A),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 3.5,
                  value: task.isRunning && task.progress <= 0
                      ? null
                      : task.progress.clamp(0.0, 1.0),
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
            ],
          ),
        ),
        if (task.isCompleted && task.isDownload && task.savedPath != null) ...[
          const SizedBox(width: 6),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            tooltip: 'عرض في المجلد',
            icon: const Icon(
              Icons.folder_open_rounded,
              size: 16,
              color: Color(0xFF007AFF),
            ),
            onPressed: () =>
                ChatTransferManager.revealDownloadedFileInFolder(task.savedPath!),
          ),
        ],
        if (task.isRunning) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: 'إلغاء التحميل',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onCancel,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: isDark ? Colors.redAccent : const Color(0xFFEF4444),
                ),
              ),
            ),
          ),
        ] else ...[
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onDismiss,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 15,
                color: isDark ? Colors.white38 : const Color(0xFF9AA7B6),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
