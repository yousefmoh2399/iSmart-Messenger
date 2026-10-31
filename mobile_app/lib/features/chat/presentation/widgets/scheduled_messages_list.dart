import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/providers/providers.dart';
import '../../models/chat_models.dart';

/// Full Apple/iOS style bottom sheet for scheduled messages
class ScheduledMessagesSheet extends ConsumerStatefulWidget {
  final String conversationId;
  final VoidCallback? onMessageSent;

  const ScheduledMessagesSheet({
    super.key,
    required this.conversationId,
    this.onMessageSent,
  });

  @override
  ConsumerState<ScheduledMessagesSheet> createState() =>
      _ScheduledMessagesSheetState();
}

class _ScheduledMessagesSheetState extends ConsumerState<ScheduledMessagesSheet> {
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _actionInProgressId;
  StreamSubscription? _eventsSubscription;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _listenToSocket();
    _countdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _eventsSubscription?.cancel();
    super.dispose();
  }

  void _listenToSocket() {
    _eventsSubscription?.cancel();
    final socketService = ref.read(chatSocketServiceProvider);
    _eventsSubscription = socketService.events.listen((event) {
      if (!mounted) return;
      final convId = event.payload['conversationId']?.toString();
      if (convId != null && convId != widget.conversationId) return;

      if (event.type == 'scheduled_message_sent' ||
          event.type == 'receive_message' ||
          event.type == 'message_deleted') {
        _loadMessages(silent: true);
      }
    });
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final result = await ref
          .read(chatRepositoryProvider)
          .fetchMessages(widget.conversationId, isScheduled: true);
      if (!mounted) return;
      setState(() {
        _messages = result.messages;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _sendNow(ChatMessage msg) async {
    setState(() => _actionInProgressId = msg.id);
    HapticFeedback.mediumImpact();

    try {
      await ref
          .read(chatRepositoryProvider)
          .sendScheduledMessageNow(msg.id);

      if (!mounted) return;

      setState(() {
        _messages.removeWhere((m) => m.id == msg.id);
        _actionInProgressId = null;
      });

      ref
          .read(conversationMessagesControllerProvider(widget.conversationId).notifier)
          .refresh();

      widget.onMessageSent?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('تم إرسال الرسالة بنجاح'),
            ],
          ),
          backgroundColor: Color(0xFF34C759),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionInProgressId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل الإرسال: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _deleteScheduled(ChatMessage msg) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('حذف الرسالة المجدولة'),
        content: const Text('هل أنت متأكد من حذف هذه الرسالة؟ لن يتم إرسالها إلى المحادثة.'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _actionInProgressId = msg.id);
    HapticFeedback.lightImpact();

    try {
      await ref.read(chatRepositoryProvider).removeMessage(msg.id);

      if (!mounted) return;

      setState(() {
        _messages.removeWhere((m) => m.id == msg.id);
        _actionInProgressId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف الرسالة المجدولة'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionInProgressId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل الحذف: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  String _formatScheduledTime(ChatMessage msg) {
    final dt = msg.scheduledFor ?? msg.createdAt;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final scheduledDay = DateTime(dt.year, dt.month, dt.day);
    final timeStr = DateFormat('hh:mm a', 'ar').format(dt);

    if (scheduledDay == today) {
      return 'اليوم الساعة $timeStr';
    } else if (scheduledDay == today.add(const Duration(days: 1))) {
      return 'غداً الساعة $timeStr';
    } else {
      final dateStr = DateFormat('yyyy/MM/dd', 'ar').format(dt);
      return '$dateStr الساعة $timeStr';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // iOS Grab Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),

            // Header Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: surfaceColor,
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? Colors.white12 : const Color(0xFFE5E5EA),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.schedule_rounded,
                      color: Color(0xFF007AFF),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'الرسائل المجدولة',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          _isLoading
                              ? 'جارٍ التحميل...'
                              : '${_messages.length} رسالة مجدولة',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: _buildBody(context, scrollController, surfaceColor, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ScrollController scrollController,
    Color surfaceColor,
    bool isDark,
  ) {
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                'تعذر تحميل الرسائل المجدولة',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _loadMessages,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.schedule_send_rounded,
                  size: 36,
                  color: Color(0xFF007AFF),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'لا توجد رسائل مجدولة',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'يمكنك جدولة إرسال أي رسالة في وقت لاحق بالضغط المطول على زر الإرسال داخل المحادثة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMessages,
      child: ListView.separated(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _messages.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final msg = _messages[index];
          final isOperating = _actionInProgressId == msg.id;
          final isReady = msg.scheduledFor != null &&
              msg.scheduledFor!.isBefore(DateTime.now());

          return Container(
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white12 : const Color(0xFFE5E5EA),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Schedule time capsule badge
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.alarm_rounded,
                              size: 14,
                              color: Color(0xFF007AFF),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _formatScheduledTime(msg),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF007AFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (isReady)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF34C759).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'جاهزة للإرسال',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF34C759),
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'قيد الانتظار',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Message Content
                if (msg.content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Text(
                      msg.content,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),

                // Attachment preview if present
                if (msg.hasAttachment)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            msg.isImageMessage
                                ? Icons.image_rounded
                                : (msg.isPdfMessage
                                    ? Icons.picture_as_pdf_rounded
                                    : Icons.insert_drive_file_rounded),
                            color: const Color(0xFF007AFF),
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              msg.fileName ?? 'مرفق',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (msg.fileSize != null)
                            Text(
                              formatFileSize(msg.fileSize!),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 6),
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: isDark ? Colors.white12 : const Color(0xFFE5E5EA),
                ),

                // Action Buttons Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      // Delete Action
                      TextButton.icon(
                        onPressed: isOperating ? null : () => _deleteScheduled(msg),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text(
                          'حذف',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Spacer(),
                      // Send Now Action
                      FilledButton.tonalIcon(
                        onPressed: isOperating ? null : () => _sendNow(msg),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF007AFF).withValues(alpha: 0.12),
                          foregroundColor: const Color(0xFF007AFF),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: isOperating
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF007AFF),
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 16),
                        label: Text(
                          isOperating ? 'جارٍ الإرسال...' : 'إرسال الآن',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Standalone component retained for backwards compatibility
class ScheduledMessagesList extends StatelessWidget {
  final String conversationId;
  const ScheduledMessagesList({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context) {
    return ScheduledMessagesSheet(conversationId: conversationId);
  }
}
