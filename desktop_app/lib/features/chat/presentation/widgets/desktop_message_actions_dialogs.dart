import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/providers/providers.dart';
import '../../../workspace/models/workspace_doc.dart';
import '../../../workspace/presentation/workspace_controller.dart';
import '../../data/chat_socket_service.dart';
import '../../models/chat_models.dart';

class AppColors {
  static const Color primary = Color(0xFF007AFF);
  static const Color textMuted = Color(0xFF64748B);
  static const Color success = Color(0xFF10B981);
  static const Color danger = Color(0xFFEF4444);
}

class DesktopMessageReminder {
  const DesktopMessageReminder({
    required this.id,
    required this.conversationId,
    required this.conversationTitle,
    required this.messageId,
    required this.senderName,
    required this.messagePreview,
    required this.remindAt,
    required this.createdAt,
    this.note = '',
    this.isNotified = false,
  });

  final String id;
  final String conversationId;
  final String conversationTitle;
  final String messageId;
  final String senderName;
  final String messagePreview;
  final DateTime remindAt;
  final DateTime createdAt;
  final String note;
  final bool isNotified;

  DesktopMessageReminder copyWith({bool? isNotified}) {
    return DesktopMessageReminder(
      id: id,
      conversationId: conversationId,
      conversationTitle: conversationTitle,
      messageId: messageId,
      senderName: senderName,
      messagePreview: messagePreview,
      remindAt: remindAt,
      createdAt: createdAt,
      note: note,
      isNotified: isNotified ?? this.isNotified,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'conversationTitle': conversationTitle,
    'messageId': messageId,
    'senderName': senderName,
    'messagePreview': messagePreview,
    'contentPreview': messagePreview,
    'remindAt': remindAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'note': note,
    'isNotified': isNotified,
  };

  factory DesktopMessageReminder.fromJson(Map<String, dynamic> json) {
    return DesktopMessageReminder(
      id: (json['id'] ?? '').toString(),
      conversationId: (json['conversationId'] ?? '').toString(),
      conversationTitle: (json['conversationTitle'] ?? '').toString(),
      messageId: (json['messageId'] ?? '').toString(),
      senderName: (json['senderName'] ?? '').toString(),
      messagePreview:
          (json['messagePreview'] ?? json['contentPreview'] ?? '').toString(),
      remindAt:
          DateTime.tryParse((json['remindAt'] ?? '').toString())?.toLocal() ??
          DateTime.now(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString())?.toLocal() ??
          DateTime.now(),
      note: (json['note'] ?? '').toString(),
      isNotified: json['isNotified'] == true,
    );
  }
}

final desktopMessageRemindersProvider =
    StateNotifierProvider<
      DesktopMessageRemindersController,
      List<DesktopMessageReminder>
    >((ref) => DesktopMessageRemindersController(ref));

class DesktopMessageRemindersController
    extends StateNotifier<List<DesktopMessageReminder>> {
  DesktopMessageRemindersController(this._ref) : super(const []) {
    _listenToSocketSync();
    _load();
  }

  final Ref _ref;
  Timer? _nextDueTimer;
  StreamSubscription<ChatSocketEvent>? _socketSub;
  static const _storageKey = 'ismart_desktop_message_reminders_v1';

  void _listenToSocketSync() {
    _socketSub?.cancel();
    final socketService = _ref.read(chatSocketServiceProvider);
    _socketSub = socketService.events.listen((event) {
      if (!mounted) return;
      if (event.type == 'reminders_updated') {
        final rawList = event.payload['reminders'];
        if (rawList is List) {
          final parsed = rawList
              .whereType<Map>()
              .map(
                (e) => DesktopMessageReminder.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .where((e) => e.id.isNotEmpty)
              .toList(growable: false);
          unawaited(_save(parsed, syncToServer: false));
        }
      } else if (event.type == 'socket_connected') {
        unawaited(_pullFromServer());
      }
    });
  }

  Future<void> _pullFromServer() async {
    try {
      final sock = _ref.read(chatSocketServiceProvider).socket;
      if (sock == null || !sock.connected) return;
      sock.emitWithAck('reminders:get', const <String, dynamic>{}, ack: (res) {
        if (!mounted) return;
        try {
          if (res is Map && res['ok'] == true && res['data'] is Map) {
            final raw = (res['data'] as Map)['reminders'];
            if (raw is List && raw.isNotEmpty) {
              final remoteList = raw
                  .whereType<Map>()
                  .map(
                    (e) => DesktopMessageReminder.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .where((e) => e.id.isNotEmpty)
                  .toList(growable: false);
              unawaited(_save(remoteList, syncToServer: false));
              return;
            } else if (state.isNotEmpty) {
              unawaited(_pushToServer(state));
            }
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<void> _pushToServer(List<DesktopMessageReminder> items) async {
    try {
      final sock = _ref.read(chatSocketServiceProvider).socket;
      if (sock == null || !sock.connected) return;
      sock.emit('reminders:sync', {
        'reminders': items.map((e) => e.toJson()).toList(),
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final list = decoded
              .whereType<Map>()
              .map(
                (e) => DesktopMessageReminder.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .where((e) => e.id.isNotEmpty)
              .toList(growable: false);
          if (mounted) {
            state = list;
            _scheduleNextTimer();
          }
        }
      }
    } catch (_) {}
    unawaited(_pullFromServer());
  }

  Future<void> _save(
    List<DesktopMessageReminder> next, {
    bool syncToServer = true,
  }) async {
    state = next;
    _scheduleNextTimer();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(next.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
    if (syncToServer) {
      unawaited(_pushToServer(next));
    }
  }

  void _scheduleNextTimer() {
    _nextDueTimer?.cancel();
    final pending = state.where((r) => !r.isNotified).toList();
    if (pending.isEmpty) return;

    pending.sort((a, b) => a.remindAt.compareTo(b.remindAt));
    final nextReminder = pending.first;
    final delay = nextReminder.remindAt.difference(DateTime.now());
    final effectiveDelay = delay.isNegative
        ? const Duration(milliseconds: 300)
        : delay;

    _nextDueTimer = Timer(effectiveDelay, _checkDueReminders);
  }

  Future<void> _checkDueReminders() async {
    if (!mounted) return;
    final now = DateTime.now();
    var changed = false;
    final updated = <DesktopMessageReminder>[];

    for (final item in state) {
      if (!item.isNotified && !item.remindAt.isAfter(now)) {
        changed = true;
        updated.add(item.copyWith(isNotified: true));
        final body = item.note.trim().isNotEmpty
            ? '${item.note.trim()} — "${item.messagePreview}"'
            : item.messagePreview;
        try {
          await _ref
              .read(localNotificationServiceProvider)
              .showIncomingMessage(
                title:
                    '⏰ تذكير برسالة من ${item.senderName} (${item.conversationTitle})',
                body: body,
              );
        } catch (_) {}
      } else {
        updated.add(item);
      }
    }

    if (changed) {
      await _save(updated);
    } else {
      _scheduleNextTimer();
    }
  }

  Future<void> addReminder({
    required String conversationId,
    required String conversationTitle,
    required ChatMessage message,
    required DateTime remindAt,
    String note = '',
  }) async {
    final preview = message.content.trim().isNotEmpty
        ? message.content.trim()
        : (message.hasAttachment ? '📎 مرفق في المحادثة' : 'رسالة');
    final item = DesktopMessageReminder(
      id: 'rem_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: conversationId,
      conversationTitle: conversationTitle,
      messageId: message.id,
      senderName: message.sender?.displayName ?? 'عضو',
      messagePreview: preview,
      remindAt: remindAt,
      createdAt: DateTime.now(),
      note: note.trim(),
    );
    final next = [item, ...state]
      ..sort((a, b) => a.remindAt.compareTo(b.remindAt));
    await _save(next);
  }

  Future<void> removeReminder(String id) async {
    final next = state.where((r) => r.id != id).toList(growable: false);
    await _save(next);
  }

  @override
  void dispose() {
    _nextDueTimer?.cancel();
    _socketSub?.cancel();
    super.dispose();
  }
}

/// Dialog to schedule a reminder for a specific message on Desktop
Future<void> showDesktopMessageReminderDialog(
  BuildContext context, {
  required String conversationId,
  required String conversationTitle,
  required ChatMessage message,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _DesktopScheduleReminderDialog(
      conversationId: conversationId,
      conversationTitle: conversationTitle,
      message: message,
    ),
  );
}

class _DesktopScheduleReminderDialog extends ConsumerStatefulWidget {
  const _DesktopScheduleReminderDialog({
    required this.conversationId,
    required this.conversationTitle,
    required this.message,
  });

  final String conversationId;
  final String conversationTitle;
  final ChatMessage message;

  @override
  ConsumerState<_DesktopScheduleReminderDialog> createState() =>
      _DesktopScheduleReminderDialogState();
}

class _DesktopScheduleReminderDialogState
    extends ConsumerState<_DesktopScheduleReminderDialog> {
  final _noteCtrl = TextEditingController();
  DateTime _selectedTime = DateTime.now().add(const Duration(hours: 1));
  String _selectedPreset = '1h';

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  void _selectPreset(String key, DateTime target) {
    setState(() {
      _selectedPreset = key;
      _selectedTime = target;
    });
  }

  Future<void> _pickCustomDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedTime.isAfter(now) ? _selectedTime : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedTime),
    );
    if (time == null || !mounted) return;
    setState(() {
      _selectedPreset = 'custom';
      _selectedTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    await ref
        .read(desktopMessageRemindersProvider.notifier)
        .addReminder(
          conversationId: widget.conversationId,
          conversationTitle: widget.conversationTitle,
          message: widget.message,
          remindAt: _selectedTime,
          note: _noteCtrl.text,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '⏰ تم ضبط التذكير في ${formatEgyptDateTime(_selectedTime)}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final tomorrow9am = DateTime(now.year, now.month, now.day + 1, 9, 0);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.alarm_add_rounded,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تذكيرني بهذه الرسالة',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'سيصلك إشعار على سطح المكتب في الموعد المحدد',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.message.content.trim().isNotEmpty
                        ? widget.message.content.trim()
                        : '📎 مرفق من ${widget.message.sender?.displayName ?? 'عضو'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('بعد 30 دقيقة'),
                      selected: _selectedPreset == '30m',
                      onSelected: (_) => _selectPreset(
                        '30m',
                        now.add(const Duration(minutes: 30)),
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('بعد ساعة'),
                      selected: _selectedPreset == '1h',
                      onSelected: (_) => _selectPreset(
                        '1h',
                        now.add(const Duration(hours: 1)),
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('بعد 3 ساعات'),
                      selected: _selectedPreset == '3h',
                      onSelected: (_) => _selectPreset(
                        '3h',
                        now.add(const Duration(hours: 3)),
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('غداً 9:00 صباحاً'),
                      selected: _selectedPreset == 'tomorrow9',
                      onSelected: (_) =>
                          _selectPreset('tomorrow9', tomorrow9am),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.calendar_month_rounded, size: 16),
                      label: Text(
                        _selectedPreset == 'custom'
                            ? formatEgyptDateTime(_selectedTime)
                            : 'وقت مخصص...',
                      ),
                      onPressed: _pickCustomDateTime,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _noteCtrl,
                  decoration: InputDecoration(
                    labelText: 'ملاحظة إضافية للتذكير (اختياري)',
                    hintText: 'مثال: الرد بعد مراجعة المدير...',
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.alarm_on_rounded, size: 18),
                      label: const Text('حفظ التذكير'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog to view and manage all scheduled message reminders on Desktop
Future<void> showDesktopRemindersListDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => const _DesktopRemindersListDialog(),
  );
}

class _DesktopRemindersListDialog extends ConsumerWidget {
  const _DesktopRemindersListDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(desktopMessageRemindersProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 560,
            minWidth: 460,
            maxHeight: 580,
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تذكيرات الرسائل المجدولة',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'اضغط كليك يمين على أي رسالة في المحادثة لإضافة تذكير جديد',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: reminders.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد تذكيرات رسائل مجدولة حالياً.',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: reminders.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = reminders[index];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item.isNotified
                                        ? Icons.check_circle_rounded
                                        : Icons.schedule_rounded,
                                    color: item.isNotified
                                        ? AppColors.success
                                        : const Color(0xFFF59E0B),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${item.senderName} • ${item.conversationTitle}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          item.messagePreview,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'الموعد: ${formatEgyptDateTime(item.remindAt)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => ref
                                        .read(
                                          desktopMessageRemindersProvider
                                              .notifier,
                                        )
                                        .removeReminder(item.id),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: AppColors.danger,
                                      size: 18,
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
        ),
      ),
    );
  }
}

/// Dialog to convert any chat message on Desktop into an IT Support Ticket or Workspace Task in 1 click
Future<void> showDesktopMessageToTicketDialog(
  BuildContext context, {
  required String conversationTitle,
  required ChatMessage message,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _DesktopMessageToTicketDialog(
      conversationTitle: conversationTitle,
      message: message,
    ),
  );
}

class _DesktopMessageToTicketDialog extends ConsumerStatefulWidget {
  const _DesktopMessageToTicketDialog({
    required this.conversationTitle,
    required this.message,
  });

  final String conversationTitle;
  final ChatMessage message;

  @override
  ConsumerState<_DesktopMessageToTicketDialog> createState() =>
      _DesktopMessageToTicketDialogState();
}

class _DesktopMessageToTicketDialogState
    extends ConsumerState<_DesktopMessageToTicketDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  String _mode = 'ticket'; // 'ticket' or 'workspace'
  String _priority = 'normal';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final rawBody = widget.message.content.trim();
    final firstLine = rawBody.split('\n').first.trim();
    final suggestedTitle = firstLine.isNotEmpty
        ? (firstLine.length > 60 ? '${firstLine.substring(0, 60)}...' : firstLine)
        : 'بلاغ من محادثة ${widget.conversationTitle}';

    final buffer = StringBuffer();
    if (rawBody.isNotEmpty) {
      buffer.writeln(rawBody);
      buffer.writeln();
    }
    buffer.writeln('---');
    buffer.writeln('👤 المرسل: ${widget.message.sender?.displayName ?? 'عضو'}');
    buffer.writeln('💬 المحادثة: ${widget.conversationTitle}');
    if (widget.message.hasAttachment) {
      buffer.writeln(
        '📎 المرفق: ${widget.message.fileName ?? 'ملف مرفق'} (${widget.message.fileUrl ?? ''})',
      );
    }

    _titleCtrl = TextEditingController(text: suggestedTitle);
    _descCtrl = TextEditingController(text: buffer.toString().trim());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    if (title.isEmpty || _submitting) return;

    setState(() => _submitting = true);
    try {
      if (_mode == 'ticket') {
        await ref
            .read(ticketRepositoryProvider)
            .createTicket(
              title: title,
              description: desc.isEmpty ? title : desc,
              priority: _priority,
              ticketType: 'ticket',
            );
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم إنشاء تذكرة الدعم الفني بنجاح من الرسالة'),
          ),
        );
      } else {
        await ref
            .read(workspaceDocsProvider.notifier)
            .createDoc(
              title: title,
              icon: '📌',
              category: 'مهام من المحادثات',
              blocks: [
                WorkspaceBlock(
                  type: WorkspaceBlockType.todo,
                  content: title,
                  isChecked: false,
                ),
                WorkspaceBlock(
                  type: WorkspaceBlockType.text,
                  content: desc,
                ),
              ],
            );
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تمت إضافة المهمة إلى مساحة العمل الخاصة بك'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الحفظ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.support_agent_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تحويل الرسالة إلى تذكرة دعم أو مهمة',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'تم نسخ نص الرسالة ومعلومات المرسل والمرفقات تلقائياً',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'ticket',
                      icon: Icon(Icons.confirmation_number_outlined, size: 18),
                      label: Text('تذكرة دعم فني IT'),
                    ),
                    ButtonSegment(
                      value: 'workspace',
                      icon: Icon(Icons.task_alt_rounded, size: 18),
                      label: Text('مهمة في مساحة العمل'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: _mode == 'ticket' ? 'عنوان التذكرة' : 'عنوان المهمة',
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_mode == 'ticket') ...[
                  DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration: InputDecoration(
                      labelText: 'الأولوية',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('منخفضة')),
                      DropdownMenuItem(value: 'normal', child: Text('عادية')),
                      DropdownMenuItem(value: 'high', child: Text('مرتفعة')),
                      DropdownMenuItem(value: 'urgent', child: Text('عاجلة جداً')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _priority = v);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _descCtrl,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: 'التفاصيل والمرفقات المنسوخة',
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        _mode == 'ticket'
                            ? 'إنشاء تذكرة الدعم الآن'
                            : 'إضافة إلى مهامي',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
