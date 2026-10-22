import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/providers/providers.dart';
import '../../models/chat_models.dart';

/// Apple-style dialog for scheduled messages on desktop
class ScheduledMessagesDialog extends StatelessWidget {
  final String conversationId;
  final VoidCallback? onMessageSent;

  const ScheduledMessagesDialog({
    super.key,
    required this.conversationId,
    this.onMessageSent,
  });

  static Future<void> show(
    BuildContext context, {
    required String conversationId,
    VoidCallback? onMessageSent,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ScheduledMessagesDialog(
        conversationId: conversationId,
        onMessageSent: onMessageSent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1E1E20) : Colors.white;
    final borderColor = isDark ? Colors.white12 : const Color(0xFFE5E5EA);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 540,
          maxHeight: 660,
          minWidth: 420,
          minHeight: 320,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: ScheduledMessagesList(
            conversationId: conversationId,
            onMessageSent: onMessageSent,
            isInDialog: true,
          ),
        ),
      ),
    );
  }
}

/// Standalone & embedded widget for scheduled messages
class ScheduledMessagesList extends ConsumerStatefulWidget {
  final String conversationId;
  final VoidCallback? onMessageSent;
  final bool isInDialog;

  const ScheduledMessagesList({
    super.key,
    required this.conversationId,
    this.onMessageSent,
    this.isInDialog = false,
  });

  @override
  ConsumerState<ScheduledMessagesList> createState() => _ScheduledMessagesListState();
}

class _ScheduledMessagesListState extends ConsumerState<ScheduledMessagesList> {
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
    // Update countdown every 30 seconds
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

    try {
      await ref
          .read(chatRepositoryProvider)
          .sendScheduledMessageNow(msg.id);

      if (!mounted) return;

      setState(() {
        _messages.removeWhere((m) => m.id == msg.id);
        _actionInProgressId = null;
      });

      // Refresh conversation messages so it lands immediately
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF242426) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
              SizedBox(width: 8),
              Text('حذف الرسالة المجدولة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          content: const Text(
            'هل أنت متأكد من حذف هذه الرسالة؟ لن يتم إرسالها إلى المحادثة.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _actionInProgressId = msg.id);

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
    final dt = (msg.scheduledFor ?? msg.createdAt).toLocal();
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

  String _remainingTimeString(ChatMessage msg) {
    final dt = (msg.scheduledFor ?? msg.createdAt).toLocal();
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) {
      return 'جاهزة للإرسال';
    }
    if (diff.inMinutes < 1) {
      return 'خلال أقل من دقيقة';
    }
    if (diff.inMinutes < 60) {
      return 'متبقي ${diff.inMinutes} دقيقة';
    }
    if (diff.inHours < 24) {
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      if (minutes == 0) {
        return 'متبقي $hours ساعة';
      }
      return 'متبقي $hours س و $minutes د';
    }
    final days = diff.inDays;
    return 'متبقي $days يوم';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1E1E20) : Colors.white;
    final cardBgColor = isDark ? const Color(0xFF262628) : const Color(0xFFF7F8FA);
    final borderColor = isDark ? Colors.white12 : const Color(0xFFE5E5EA);

    return Column(
      children: [
        // ── Header Row ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: surfaceColor,
            border: Border(bottom: BorderSide(color: borderColor, width: 0.8)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: Color(0xFF007AFF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'الرسائل المجدولة',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isLoading
                          ? 'جارٍ التحميل...'
                          : (_messages.isEmpty
                              ? 'لا توجد رسائل مجدولة'
                              : '${_messages.length} رسالة مجدولة'),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              // Refresh button
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'تحديث',
                onPressed: _isLoading ? null : () => _loadMessages(),
              ),
              if (widget.isInDialog)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.of(context).pop(),
                ),
            ],
          ),
        ),

        // ── Body ────────────────────────────────────────────────────────────
        Expanded(
          child: _buildBody(context, cardBgColor, borderColor, isDark),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    Color cardBgColor,
    Color borderColor,
    bool isDark,
  ) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupertinoActivityIndicator(radius: 13),
            const SizedBox(height: 12),
            Text(
              'جارٍ تحميل الرسائل المجدولة...',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 44, color: Colors.redAccent),
              const SizedBox(height: 12),
              const Text(
                'تعذر تحميل الرسائل المجدولة',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => _loadMessages(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
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
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.schedule_send_rounded,
                  size: 32,
                  color: Color(0xFF007AFF),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'لا توجد رسائل مجدولة',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'يمكنك جدولة إرسال أي رسالة في وقت لاحق بالضغط على أيقونة الجدولة المجاورة لحقل الكتابة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isOperating = _actionInProgressId == msg.id;
        final dt = (msg.scheduledFor ?? msg.createdAt).toLocal();
        final isReady = dt.isBefore(DateTime.now());
        final isSilent = msg.metadata?['isSilent'] == true;

        return Container(
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Capsule Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  children: [
                    // Time Capsule
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.alarm_rounded,
                            size: 13,
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
                    // Silent Badge
                    if (isSilent) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.volume_off_rounded,
                              size: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'بدون صوت',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Status Badge
                    if (isReady)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF34C759).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline_rounded, size: 12, color: Color(0xFF34C759)),
                            SizedBox(width: 4),
                            Text(
                              'جاهزة للإرسال',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF34C759),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _remainingTimeString(msg),
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

              // Content Text
              if (msg.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: SelectableText(
                    msg.content,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                      color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                    ),
                  ),
                ),

              // Attachment Preview
              if (msg.hasAttachment)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E20) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor, width: 0.6),
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
                          size: 22,
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
              Divider(height: 1, thickness: 0.6, color: borderColor),

              // Action Buttons Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    // Delete Button
                    TextButton.icon(
                      onPressed: isOperating ? null : () => _deleteScheduled(msg),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text(
                        'حذف',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Spacer(),
                    // Send Now Button
                    FilledButton.tonalIcon(
                      onPressed: isOperating ? null : () => _sendNow(msg),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF).withValues(alpha: 0.12),
                        foregroundColor: const Color(0xFF007AFF),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
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
                          : const Icon(Icons.send_rounded, size: 15),
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
    );
  }
}
