import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/providers/providers.dart';
import '../../models/chat_models.dart';

/// Model representing a scheduled reminder for a specific chat message.
class ChatMessageReminder {
  const ChatMessageReminder({
    required this.id,
    required this.messageId,
    required this.conversationId,
    required this.conversationTitle,
    required this.senderName,
    required this.contentPreview,
    required this.remindAt,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String messageId;
  final String conversationId;
  final String conversationTitle;
  final String senderName;
  final String contentPreview;
  final DateTime remindAt;
  final DateTime createdAt;
  final String? note;

  ChatMessageReminder copyWith({
    DateTime? remindAt,
    String? note,
  }) {
    return ChatMessageReminder(
      id: id,
      messageId: messageId,
      conversationId: conversationId,
      conversationTitle: conversationTitle,
      senderName: senderName,
      contentPreview: contentPreview,
      remindAt: remindAt ?? this.remindAt,
      createdAt: createdAt,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'messageId': messageId,
        'conversationId': conversationId,
        'conversationTitle': conversationTitle,
        'senderName': senderName,
        'contentPreview': contentPreview,
        'remindAt': remindAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
      };

  factory ChatMessageReminder.fromJson(Map<String, dynamic> json) {
    return ChatMessageReminder(
      id: json['id']?.toString() ?? '',
      messageId: json['messageId']?.toString() ?? '',
      conversationId: json['conversationId']?.toString() ?? '',
      conversationTitle: json['conversationTitle']?.toString() ?? 'محادثة',
      senderName: json['senderName']?.toString() ?? 'رسالة',
      contentPreview: json['contentPreview']?.toString() ?? '',
      remindAt: DateTime.tryParse(json['remindAt']?.toString() ?? '') ??
          DateTime.now(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      note: json['note']?.toString(),
    );
  }
}

/// Controller that persists message reminders, schedules exact one-shot
/// wakeup timers for the next due reminder, and dispatches local notifications
/// + in-app alerts when due.
class ChatMessageRemindersController
    extends AsyncNotifier<List<ChatMessageReminder>> {
  static const String _storageKey = 'chat_message_reminders_v1';

  /// Broadcasts the most recently triggered reminder for in-app toast/banner display.
  static final ValueNotifier<ChatMessageReminder?> dueReminderAlertNotifier =
      ValueNotifier<ChatMessageReminder?>(null);

  Timer? _nextReminderTimer;

  @override
  Future<List<ChatMessageReminder>> build() async {
    ref.onDispose(() {
      _nextReminderTimer?.cancel();
    });
    _nextReminderTimer?.cancel();

    final loaded = await _loadFromStorage();
    _scheduleNextDueTimer(loaded);
    // Run an immediate check in case any reminder became due while the app was closed
    unawaited(Future<void>.microtask(_checkDueReminders));
    return loaded;
  }

  void _scheduleNextDueTimer(List<ChatMessageReminder> items) {
    _nextReminderTimer?.cancel();
    if (items.isEmpty) return;

    final now = DateTime.now();
    DateTime? earliest;
    for (final item in items) {
      if (earliest == null || item.remindAt.isBefore(earliest)) {
        earliest = item.remindAt;
      }
    }
    if (earliest == null) return;

    final delay = earliest.difference(now);
    final effectiveDelay = delay.isNegative
        ? const Duration(milliseconds: 200)
        : delay + const Duration(milliseconds: 250);
    _nextReminderTimer = Timer(effectiveDelay, _checkDueReminders);
  }

  Future<List<ChatMessageReminder>> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final items = decoded
          .whereType<Map>()
          .map((e) => ChatMessageReminder.fromJson(Map<String, dynamic>.from(e)))
          .where((r) => r.messageId.isNotEmpty)
          .toList()
        ..sort((a, b) => a.remindAt.compareTo(b.remindAt));
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveToStorage(List<ChatMessageReminder> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (_) {}
  }

  Future<void> _checkDueReminders() async {
    final current = state.valueOrNull;
    if (current == null || current.isEmpty) return;

    final now = DateTime.now();
    final due = <ChatMessageReminder>[];
    final remaining = <ChatMessageReminder>[];

    for (final reminder in current) {
      if (!reminder.remindAt.isAfter(now)) {
        due.add(reminder);
      } else {
        remaining.add(reminder);
      }
    }

    if (due.isEmpty) return;

    remaining.sort((a, b) => a.remindAt.compareTo(b.remindAt));
    state = AsyncData(remaining);
    await _saveToStorage(remaining);
    _scheduleNextDueTimer(remaining);

    final notificationService = ref.read(localNotificationServiceProvider);
    for (final reminder in due) {
      HapticFeedback.heavyImpact();
      dueReminderAlertNotifier.value = reminder;
      final hasNote = reminder.note != null && reminder.note!.trim().isNotEmpty;
      final bodyText = hasNote
          ? '📝 ${reminder.note!.trim()} — ${reminder.contentPreview}'
          : reminder.contentPreview;
      try {
        await notificationService.showIncomingMessage(
          title: '⏰ تذكير: ${reminder.senderName} (${reminder.conversationTitle})',
          body: bodyText,
          payload: <String, dynamic>{
            'type': 'chat',
            'conversationId': reminder.conversationId,
            'messageId': reminder.messageId,
          },
        );
      } catch (_) {}
    }
  }

  /// Adds or updates a reminder for a specific message.
  Future<ChatMessageReminder> setReminder({
    required ChatMessage message,
    required String conversationTitle,
    required DateTime remindAt,
    String? note,
  }) async {
    final current = List<ChatMessageReminder>.from(state.valueOrNull ?? const []);
    current.removeWhere((r) => r.messageId == message.id);

    final senderName = message.sender?.displayName.trim().isNotEmpty == true
        ? message.sender!.displayName.trim()
        : 'رسالة';
    final preview = message.content.trim().isNotEmpty
        ? message.content.trim()
        : (message.fileName?.trim().isNotEmpty == true
            ? '📎 ${message.fileName!.trim()}'
            : 'رسالة صوتية / مرفق');

    final reminder = ChatMessageReminder(
      id: 'rem_${message.id}_${DateTime.now().millisecondsSinceEpoch}',
      messageId: message.id,
      conversationId: message.conversationId,
      conversationTitle: conversationTitle,
      senderName: senderName,
      contentPreview: preview,
      remindAt: remindAt,
      createdAt: DateTime.now(),
      note: note?.trim().isNotEmpty == true ? note!.trim() : null,
    );

    current.add(reminder);
    current.sort((a, b) => a.remindAt.compareTo(b.remindAt));
    state = AsyncData(current);
    await _saveToStorage(current);
    _scheduleNextDueTimer(current);
    return reminder;
  }

  /// Snoozes an existing reminder by [duration].
  Future<void> snoozeReminder(String reminderId, Duration duration) async {
    final current = List<ChatMessageReminder>.from(state.valueOrNull ?? const []);
    final idx = current.indexWhere((r) => r.id == reminderId);
    if (idx < 0) return;
    current[idx] = current[idx].copyWith(
      remindAt: DateTime.now().add(duration),
    );
    current.sort((a, b) => a.remindAt.compareTo(b.remindAt));
    state = AsyncData(current);
    await _saveToStorage(current);
    _scheduleNextDueTimer(current);
  }

  /// Removes a reminder by its ID or message ID.
  Future<void> removeReminderByMessageId(String messageId) async {
    final current = List<ChatMessageReminder>.from(state.valueOrNull ?? const []);
    current.removeWhere((r) => r.messageId == messageId);
    state = AsyncData(current);
    await _saveToStorage(current);
    _scheduleNextDueTimer(current);
  }

  Future<void> removeReminderById(String reminderId) async {
    final current = List<ChatMessageReminder>.from(state.valueOrNull ?? const []);
    current.removeWhere((r) => r.id == reminderId);
    state = AsyncData(current);
    await _saveToStorage(current);
    _scheduleNextDueTimer(current);
  }
}

final chatMessageRemindersProvider = AsyncNotifierProvider<
    ChatMessageRemindersController, List<ChatMessageReminder>>(
  ChatMessageRemindersController.new,
);

String formatReminderDateTime(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final targetDay = DateTime(dt.year, dt.month, dt.day);
  final timeStr = DateFormat('hh:mm a', 'ar').format(dt);

  if (targetDay == today) {
    return 'اليوم الساعة $timeStr';
  } else if (targetDay == today.add(const Duration(days: 1))) {
    return 'غداً الساعة $timeStr';
  } else {
    final dateStr = DateFormat('yyyy/MM/dd', 'ar').format(dt);
    return '$dateStr الساعة $timeStr';
  }
}

/// Opens the Apple-style bottom sheet to set or edit a reminder on [message].
Future<ChatMessageReminder?> showSetMessageReminderSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ChatMessage message,
  required String conversationTitle,
}) async {
  final existingReminders =
      ref.read(chatMessageRemindersProvider).valueOrNull ?? const [];
  final existing = existingReminders
      .cast<ChatMessageReminder?>()
      .firstWhere((r) => r?.messageId == message.id, orElse: () => null);

  final noteController = TextEditingController(text: existing?.note ?? '');
  final now = DateTime.now();
  final today6PM = DateTime(now.year, now.month, now.day, 18, 0);
  final tomorrow9AM = DateTime(now.year, now.month, now.day + 1, 9, 0);

  final result = await showModalBottomSheet<ChatMessageReminder?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
      final sheetBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
      final cardBg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
      final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
      final subColor = isDark ? Colors.white54 : const Color(0xFF64748B);
      const accent = Color(0xFF007AFF);

      Future<void> selectTime(DateTime targetTime) async {
        HapticFeedback.mediumImpact();
        final saved = await ref
            .read(chatMessageRemindersProvider.notifier)
            .setReminder(
              message: message,
              conversationTitle: conversationTitle,
              remindAt: targetTime,
              note: noteController.text,
            );
        if (sheetContext.mounted) {
          Navigator.of(sheetContext).pop(saved);
        }
      }

      final preview = message.content.trim().isNotEmpty
          ? message.content.trim()
          : (message.fileName ?? 'رسالة صوتية / مرفق');

      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.alarm_fill,
                          color: accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              existing != null
                                  ? 'تعديل تذكير الرسالة'
                                  : 'تذكير بهذه الرسالة',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                              ),
                            ),
                            Text(
                              existing != null
                                  ? 'مضبوط حالياً: ${formatReminderDateTime(existing.remindAt)}'
                                  : 'سيصلك إشعار وتنبيه للرد أو متابعة الرسالة',
                              style: TextStyle(
                                fontSize: 12,
                                color: existing != null ? accent : subColor,
                                fontWeight: existing != null
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (existing != null)
                        TextButton.icon(
                          onPressed: () async {
                            HapticFeedback.lightImpact();
                            await ref
                                .read(chatMessageRemindersProvider.notifier)
                                .removeReminderByMessageId(message.id);
                            if (sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم إلغاء التذكير'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                          icon: const Icon(CupertinoIcons.trash, size: 16),
                          label: const Text('إلغاء'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Message Preview Box
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: textColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Optional Note Input
                  TextField(
                    controller: noteController,
                    style: TextStyle(fontSize: 13.5, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'إضافة ملاحظة مع التذكير (اختياري)...',
                      hintStyle: TextStyle(fontSize: 13, color: subColor),
                      prefixIcon: const Icon(
                        CupertinoIcons.pencil_outline,
                        size: 18,
                        color: accent,
                      ),
                      filled: true,
                      fillColor: cardBg,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Quick Presets Group
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ReminderOptionTile(
                          icon: CupertinoIcons.timer,
                          iconColor: const Color(0xFF34C759),
                          title: 'بعد 15 دقيقة',
                          trailingText: DateFormat('hh:mm a', 'ar')
                              .format(now.add(const Duration(minutes: 15))),
                          onTap: () =>
                              selectTime(now.add(const Duration(minutes: 15))),
                        ),
                        _buildDivider(isDark),
                        _ReminderOptionTile(
                          icon: CupertinoIcons.timer,
                          iconColor: const Color(0xFF007AFF),
                          title: 'بعد 30 دقيقة',
                          trailingText: DateFormat('hh:mm a', 'ar')
                              .format(now.add(const Duration(minutes: 30))),
                          onTap: () =>
                              selectTime(now.add(const Duration(minutes: 30))),
                        ),
                        _buildDivider(isDark),
                        _ReminderOptionTile(
                          icon: CupertinoIcons.clock_fill,
                          iconColor: const Color(0xFF5856D6),
                          title: 'بعد ساعة واحدة',
                          trailingText: DateFormat('hh:mm a', 'ar')
                              .format(now.add(const Duration(hours: 1))),
                          onTap: () =>
                              selectTime(now.add(const Duration(hours: 1))),
                        ),
                        _buildDivider(isDark),
                        _ReminderOptionTile(
                          icon: CupertinoIcons.clock,
                          iconColor: const Color(0xFFFF9500),
                          title: 'بعد 3 ساعات',
                          trailingText: DateFormat('hh:mm a', 'ar')
                              .format(now.add(const Duration(hours: 3))),
                          onTap: () =>
                              selectTime(now.add(const Duration(hours: 3))),
                        ),
                        if (now.isBefore(
                          today6PM.subtract(const Duration(minutes: 30)),
                        )) ...[
                          _buildDivider(isDark),
                          _ReminderOptionTile(
                            icon: CupertinoIcons.moon_stars_fill,
                            iconColor: const Color(0xFFAF52DE),
                            title: 'مساء اليوم',
                            trailingText: '06:00 م',
                            onTap: () => selectTime(today6PM),
                          ),
                        ],
                        _buildDivider(isDark),
                        _ReminderOptionTile(
                          icon: CupertinoIcons.sun_max_fill,
                          iconColor: const Color(0xFFFF9500),
                          title: 'غداً في بداية الدوام',
                          trailingText: '09:00 ص',
                          onTap: () => selectTime(tomorrow9AM),
                        ),
                        _buildDivider(isDark),
                        _ReminderOptionTile(
                          icon: CupertinoIcons.calendar_badge_plus,
                          iconColor: accent,
                          title: 'تحديد تاريخ ووقت مخصص...',
                          trailingText: 'اختيار',
                          onTap: () async {
                            final pickedDate = await showDatePicker(
                              context: sheetContext,
                              initialDate: now,
                              firstDate: now,
                              lastDate: now.add(const Duration(days: 365)),
                            );
                            if (pickedDate == null || !sheetContext.mounted) {
                              return;
                            }
                            final pickedTime = await showTimePicker(
                              context: sheetContext,
                              initialTime: TimeOfDay.fromDateTime(
                                now.add(const Duration(hours: 1)),
                              ),
                            );
                            if (pickedTime == null || !sheetContext.mounted) {
                              return;
                            }
                            final customDt = DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              pickedTime.hour,
                              pickedTime.minute,
                            );
                            if (customDt.isAfter(DateTime.now())) {
                              await selectTime(customDt);
                            } else if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'يرجى اختيار وقت في المستقبل للتذكير.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  noteController.dispose();
  return result;
}

Widget _buildDivider(bool isDark) {
  return Divider(
    height: 0.5,
    thickness: 0.5,
    indent: 52,
    color: isDark ? Colors.white12 : const Color(0xFFE5E5EA),
  );
}

class _ReminderOptionTile extends StatelessWidget {
  const _ReminderOptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.trailingText,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String trailingText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
            Text(
              trailingText,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white54 : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full Apple/iOS style bottom sheet listing active message reminders
/// (either for a specific [conversationId] or across all conversations).
class MessageRemindersSheet extends ConsumerWidget {
  const MessageRemindersSheet({
    super.key,
    this.conversationId,
    this.onJumpToMessage,
  });

  final String? conversationId;
  final void Function(ChatMessageReminder reminder)? onJumpToMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final allReminders =
        ref.watch(chatMessageRemindersProvider).valueOrNull ?? const [];
    final reminders = conversationId == null
        ? allReminders
        : allReminders
            .where((r) => r.conversationId == conversationId)
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      maxChildSize: 0.94,
      minChildSize: 0.45,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
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
                      color: const Color(0xFFFF9500).withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.alarm_fill,
                      color: Color(0xFFFF9500),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تذكيرات الرسائل',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          reminders.isEmpty
                              ? 'لا توجد تذكيرات نشطة'
                              : '${reminders.length} تذكير قادم',
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
            Expanded(
              child: reminders.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9500)
                                    .withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                CupertinoIcons.alarm,
                                size: 34,
                                color: Color(0xFFFF9500),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'لا توجد تذكيرات مضبوطة',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'اضغط مطوّلاً على أي رسالة داخل المحادثة واختر "تذكير بهذه الرسالة" ليصلك إشعار في الوقت المحدد.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.4,
                                color:
                                    isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: reminders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final rem = reminders[index];
                        return Container(
                          decoration: BoxDecoration(
                            color: surfaceColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white12
                                  : const Color(0xFFE5E5EA),
                              width: 0.8,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(14, 12, 14, 6),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF9500)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            CupertinoIcons.alarm_fill,
                                            size: 13,
                                            color: Color(0xFFFF9500),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            formatReminderDateTime(
                                              rem.remindAt,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFFFF9500),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${rem.senderName} • ${rem.conversationTitle}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white54
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (rem.note != null && rem.note!.isNotEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 4, 14, 2),
                                  child: Text(
                                    '📝 ${rem.note!}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF007AFF),
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                child: Text(
                                  rem.contentPreview,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                              Divider(
                                height: 1,
                                thickness: 0.5,
                                color: isDark
                                    ? Colors.white12
                                    : const Color(0xFFE5E5EA),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        ref
                                            .read(
                                              chatMessageRemindersProvider
                                                  .notifier,
                                            )
                                            .removeReminderById(rem.id);
                                      },
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.redAccent,
                                      ),
                                      icon: const Icon(
                                        CupertinoIcons.checkmark_circle,
                                        size: 17,
                                      ),
                                      label: const Text(
                                        'تم / حذف',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        ref
                                            .read(
                                              chatMessageRemindersProvider
                                                  .notifier,
                                            )
                                            .snoozeReminder(
                                              rem.id,
                                              const Duration(minutes: 30),
                                            );
                                      },
                                      icon: const Icon(
                                        CupertinoIcons.zzz,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'تأجيل 30 د',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (onJumpToMessage != null)
                                      FilledButton.tonalIcon(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          onJumpToMessage!(rem);
                                        },
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF007AFF)
                                                  .withValues(alpha: 0.12),
                                          foregroundColor:
                                              const Color(0xFF007AFF),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                        ),
                                        icon: const Icon(
                                          CupertinoIcons.arrow_up_left_circle,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'عرض الرسالة',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
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
            ),
          ],
        ),
      ),
    );
  }
}
