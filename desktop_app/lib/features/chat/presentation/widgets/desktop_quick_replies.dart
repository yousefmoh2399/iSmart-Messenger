import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppColors {
  static const Color primary = Color(0xFF007AFF);
  static const Color textMuted = Color(0xFF64748B);
  static const Color danger = Color(0xFFEF4444);
}

class QuickReplyTemplate {
  const QuickReplyTemplate({
    required this.id,
    required this.shortcut,
    required this.title,
    required this.content,
    required this.category,
  });

  final String id;
  final String shortcut;
  final String title;
  final String content;
  final String category;

  QuickReplyTemplate copyWith({
    String? id,
    String? shortcut,
    String? title,
    String? content,
    String? category,
  }) {
    return QuickReplyTemplate(
      id: id ?? this.id,
      shortcut: shortcut ?? this.shortcut,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'shortcut': shortcut,
    'title': title,
    'content': content,
    'category': category,
  };

  factory QuickReplyTemplate.fromJson(Map<String, dynamic> json) {
    return QuickReplyTemplate(
      id: (json['id'] ?? '').toString(),
      shortcut: (json['shortcut'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      category: (json['category'] ?? 'عام').toString(),
    );
  }
}

const List<QuickReplyTemplate> kDefaultQuickReplies = [
  QuickReplyTemplate(
    id: 'default_received',
    shortcut: 'استلام',
    title: 'تأكيد استلام ومراجعة',
    content: 'تم الاستلام بنجاح وجاري المراجعة، سأوافيك بالتحديث قريباً.',
    category: 'العمل اليومي',
  ),
  QuickReplyTemplate(
    id: 'default_print',
    shortcut: 'طباعة',
    title: 'تم الإرسال للطباعة',
    content: 'تم استلام المستند وإرساله للطباعة الآن.',
    category: 'المستندات',
  ),
  QuickReplyTemplate(
    id: 'default_asset',
    shortcut: 'أصل',
    title: 'طلب رقم الأصل / الجهاز',
    content: 'يرجى إرفاق رقم الأصل (Asset Tag) أو صورة الملصق لسرعة المتابعة.',
    category: 'الدعم الفني',
  ),
  QuickReplyTemplate(
    id: 'default_meeting',
    shortcut: 'اجتماع',
    title: 'في اجتماع حالياً',
    content: 'أنا في اجتماع حالياً، سأقوم بالرد عليك فور الانتهاء إن شاء الله.',
    category: 'الحالة',
  ),
  QuickReplyTemplate(
    id: 'default_done',
    shortcut: 'تم',
    title: 'إنجاز المهمة',
    content: 'تم إنجاز المطلوب بالكامل. يرجى التأكد وإبلاغي في حال وجود أي ملاحظات.',
    category: 'العمل اليومي',
  ),
];

final desktopQuickRepliesProvider =
    StateNotifierProvider<DesktopQuickRepliesController, List<QuickReplyTemplate>>(
      (ref) => DesktopQuickRepliesController(),
    );

class DesktopQuickRepliesController
    extends StateNotifier<List<QuickReplyTemplate>> {
  DesktopQuickRepliesController() : super(kDefaultQuickReplies) {
    _load();
  }

  static const _storageKey = 'ismart_quick_replies_v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.trim().isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final parsed = decoded
          .whereType<Map>()
          .map((item) => QuickReplyTemplate.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.id.isNotEmpty && item.content.trim().isNotEmpty)
          .toList(growable: false);
      if (parsed.isNotEmpty && mounted) {
        state = parsed;
      }
    } catch (_) {}
  }

  Future<void> _persist(List<QuickReplyTemplate> next) async {
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(next.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> addReply({
    required String shortcut,
    required String title,
    required String content,
    String category = 'مخصص',
  }) async {
    final cleanShortcut = shortcut.trim().replaceAll(RegExp(r'^/+'), '');
    final item = QuickReplyTemplate(
      id: 'qr_${DateTime.now().millisecondsSinceEpoch}',
      shortcut: cleanShortcut.isEmpty ? 'رد' : cleanShortcut,
      title: title.trim().isEmpty ? cleanShortcut : title.trim(),
      content: content.trim(),
      category: category.trim().isEmpty ? 'مخصص' : category.trim(),
    );
    await _persist([item, ...state]);
  }

  Future<void> updateReply(QuickReplyTemplate updated) async {
    final cleanShortcut = updated.shortcut.trim().replaceAll(RegExp(r'^/+'), '');
    final normalized = updated.copyWith(
      shortcut: cleanShortcut.isEmpty ? 'رد' : cleanShortcut,
      title: updated.title.trim().isEmpty ? cleanShortcut : updated.title.trim(),
      content: updated.content.trim(),
    );
    final next = state
        .map((item) => item.id == normalized.id ? normalized : item)
        .toList(growable: false);
    await _persist(next);
  }

  Future<void> deleteReply(String id) async {
    final next = state.where((item) => item.id != id).toList(growable: false);
    await _persist(next);
  }

  Future<void> resetDefaults() async {
    await _persist(kDefaultQuickReplies);
  }
}

/// Inline popup rendered right above the Desktop composer when typing `/`
class DesktopQuickRepliesSlashPopup extends ConsumerWidget {
  const DesktopQuickRepliesSlashPopup({
    super.key,
    required this.query,
    required this.onSelectReply,
    required this.onManageTap,
    required this.onClose,
  });

  final String query;
  final ValueChanged<QuickReplyTemplate> onSelectReply;
  final VoidCallback onManageTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allReplies = ref.watch(desktopQuickRepliesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final normalizedQuery = query.trim().toLowerCase();

    final filtered = allReplies.where((item) {
      if (normalizedQuery.isEmpty) return true;
      return item.shortcut.toLowerCase().contains(normalizedQuery) ||
          item.title.toLowerCase().contains(normalizedQuery) ||
          item.content.toLowerCase().contains(normalizedQuery) ||
          item.category.toLowerCase().contains(normalizedQuery);
    }).toList(growable: false);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '/',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  normalizedQuery.isEmpty
                      ? 'الردود السريعة الجاهزة'
                      : 'بحث في الردود السريعة: "$query"',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onManageTap,
                  icon: const Icon(Icons.tune_rounded, size: 15),
                  label: const Text(
                    'إدارة وإضافة ردود',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.primary,
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'إغلاق',
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE2E8F0),
          ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'لا يوجد رد سريع مطابق. يمكنك إضافة ردودك الخاصة من زر الإدارة.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: onManageTap,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('إضافة رد جديد'),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  indent: 14,
                  endIndent: 14,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF1F5F9),
                ),
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  return InkWell(
                    onTap: () => onSelectReply(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              '/${item.shortcut}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.content,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? Colors.white70
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.07)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.category,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white60
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Full management dialog for adding, editing, and deleting Quick Replies on Desktop
Future<void> showDesktopQuickRepliesDialog(
  BuildContext context, {
  ValueChanged<QuickReplyTemplate>? onInsertReply,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _DesktopQuickRepliesManagerDialog(
      onInsertReply: onInsertReply,
    ),
  );
}

class _DesktopQuickRepliesManagerDialog extends ConsumerStatefulWidget {
  const _DesktopQuickRepliesManagerDialog({this.onInsertReply});

  final ValueChanged<QuickReplyTemplate>? onInsertReply;

  @override
  ConsumerState<_DesktopQuickRepliesManagerDialog> createState() =>
      _DesktopQuickRepliesManagerDialogState();
}

class _DesktopQuickRepliesManagerDialogState
    extends ConsumerState<_DesktopQuickRepliesManagerDialog> {
  final _shortcutCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController(text: 'العمل اليومي');
  String? _editingId;
  bool _showForm = false;

  @override
  void dispose() {
    _shortcutCtrl.dispose();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  void _startAdd() {
    setState(() {
      _editingId = null;
      _shortcutCtrl.clear();
      _titleCtrl.clear();
      _contentCtrl.clear();
      _categoryCtrl.text = 'العمل اليومي';
      _showForm = true;
    });
  }

  void _startEdit(QuickReplyTemplate item) {
    setState(() {
      _editingId = item.id;
      _shortcutCtrl.text = item.shortcut;
      _titleCtrl.text = item.title;
      _contentCtrl.text = item.content;
      _categoryCtrl.text = item.category;
      _showForm = true;
    });
  }

  Future<void> _saveForm() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) return;

    final notifier = ref.read(desktopQuickRepliesProvider.notifier);
    if (_editingId == null) {
      await notifier.addReply(
        shortcut: _shortcutCtrl.text,
        title: _titleCtrl.text,
        content: content,
        category: _categoryCtrl.text,
      );
    } else {
      await notifier.updateReply(
        QuickReplyTemplate(
          id: _editingId!,
          shortcut: _shortcutCtrl.text,
          title: _titleCtrl.text,
          content: content,
          category: _categoryCtrl.text,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _showForm = false;
      _editingId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final replies = ref.watch(desktopQuickRepliesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 680,
            minWidth: 520,
            maxHeight: 680,
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                        ),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الردود السريعة والقوالب الجاهزة (/)',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'اكتب / في أي محادثة لإدراج رد جاهز فوراً، أو أضف قوالبك الخاصة هنا',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_showForm)
                      FilledButton.icon(
                        onPressed: _startAdd,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('إضافة رد جديد'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_showForm) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _editingId == null
                              ? 'إضافة قالب رد سريع جديد'
                              : 'تعديل الرد السريع',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _shortcutCtrl,
                                decoration: InputDecoration(
                                  labelText: 'الاختصار بعد / (مثال: استلام)',
                                  prefixText: '/ ',
                                  filled: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _titleCtrl,
                                decoration: InputDecoration(
                                  labelText: 'عنوان مختصر للرد',
                                  filled: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _categoryCtrl,
                                decoration: InputDecoration(
                                  labelText: 'التصنيف',
                                  filled: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _contentCtrl,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'نص الرسالة الكامل الذي سيتم إدراجه...',
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => setState(() {
                                _showForm = false;
                                _editingId = null;
                              }),
                              child: const Text('إلغاء'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _saveForm,
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('حفظ الرد السريع'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Expanded(
                  child: ListView.separated(
                    itemCount: replies.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = replies[index];
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.07)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '/${item.shortcut}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        item.title,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white.withValues(alpha: 0.08)
                                              : const Color(0xFFE2E8F0),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          item.category,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.content,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: isDark
                                          ? Colors.white70
                                          : const Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.onInsertReply != null)
                              IconButton(
                                tooltip: 'إدراج في المحادثة',
                                onPressed: () {
                                  widget.onInsertReply!(item);
                                  Navigator.of(context).pop();
                                },
                                icon: const Icon(
                                  Icons.send_rounded,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                              ),
                            IconButton(
                              tooltip: 'تعديل',
                              onPressed: () => _startEdit(item),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                            ),
                            IconButton(
                              tooltip: 'حذف',
                              onPressed: () => ref
                                  .read(desktopQuickRepliesProvider.notifier)
                                  .deleteReply(item.id),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: AppColors.danger,
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
