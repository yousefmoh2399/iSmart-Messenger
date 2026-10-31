import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/providers/providers.dart';
import '../../data/chat_socket_service.dart';

/// Represents a customizable quick reply / slash command template.
class QuickReplyTemplate {
  const QuickReplyTemplate({
    required this.id,
    required this.shortcut,
    required this.content,
    required this.createdAt,
    this.title = '',
    this.category = 'عام',
    this.usageCount = 0,
  });

  final String id;
  final String shortcut;
  final String content;
  final DateTime createdAt;
  final String title;
  final String category;
  final int usageCount;

  /// Normalized shortcut without leading `/` for display or matching.
  String get cleanShortcut {
    final trimmed = shortcut.trim();
    if (trimmed.startsWith('/')) {
      return trimmed.substring(1).trim();
    }
    return trimmed;
  }

  /// Display title (falls back to cleanShortcut when empty).
  String get displayTitle {
    final trimmed = title.trim();
    return trimmed.isNotEmpty ? trimmed : cleanShortcut;
  }

  /// Formatted slash trigger (e.g. `/استلام`).
  String get triggerCommand {
    final clean = cleanShortcut;
    return clean.isEmpty ? '/' : '/$clean';
  }

  QuickReplyTemplate copyWith({
    String? id,
    String? shortcut,
    String? content,
    DateTime? createdAt,
    String? title,
    String? category,
    int? usageCount,
  }) {
    return QuickReplyTemplate(
      id: id ?? this.id,
      shortcut: shortcut ?? this.shortcut,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      title: title ?? this.title,
      category: category ?? this.category,
      usageCount: usageCount ?? this.usageCount,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'shortcut': cleanShortcut,
      'title': displayTitle,
      'content': content,
      'category': category.trim().isNotEmpty ? category.trim() : 'عام',
      'createdAt': createdAt.toIso8601String(),
      'usageCount': usageCount,
    };
  }

  factory QuickReplyTemplate.fromJson(Map<String, dynamic> json) {
    final rawShortcut = json['shortcut']?.toString().trim() ?? '';
    final clean = rawShortcut.startsWith('/')
        ? rawShortcut.substring(1).trim()
        : rawShortcut;
    final rawTitle = json['title']?.toString().trim() ?? '';
    final rawCategory = json['category']?.toString().trim() ?? '';
    return QuickReplyTemplate(
      id: json['id']?.toString() ?? '',
      shortcut: clean,
      title: rawTitle.isNotEmpty ? rawTitle : clean,
      content: json['content']?.toString() ?? '',
      category: rawCategory.isNotEmpty ? rawCategory : 'عام',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Matches a user query typed after `/` against shortcut, title, category, and content.
  bool matchesQuery(String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final cleanQ = q.startsWith('/') ? q.substring(1).trim() : q;
    if (cleanQ.isEmpty) return true;
    return cleanShortcut.toLowerCase().contains(cleanQ) ||
        displayTitle.toLowerCase().contains(cleanQ) ||
        category.toLowerCase().contains(cleanQ) ||
        content.toLowerCase().contains(cleanQ);
  }

  static List<QuickReplyTemplate> defaultTemplates() {
    final now = DateTime.now();
    return <QuickReplyTemplate>[
      QuickReplyTemplate(
        id: 'qr_default_1',
        shortcut: 'استلام',
        content: 'تم الاستلام وجاري المراجعة، سأوافيك بالرد قريباً.',
        createdAt: now,
      ),
      QuickReplyTemplate(
        id: 'qr_default_2',
        shortcut: 'طباعة',
        content: 'تم إرسال المستند للطباعة بنجاح.',
        createdAt: now,
      ),
      QuickReplyTemplate(
        id: 'qr_default_3',
        shortcut: 'أصل',
        content: 'يرجى إرفاق رقم الأصل أو صورة الباركود للمتابعة.',
        createdAt: now,
      ),
      QuickReplyTemplate(
        id: 'qr_default_4',
        shortcut: 'اعتماد',
        content: 'تمت المراجعة والاعتماد، شكراً لك.',
        createdAt: now,
      ),
      QuickReplyTemplate(
        id: 'qr_default_5',
        shortcut: 'اجتماع',
        content: 'أنا في اجتماع حالياً، سأعاود التواصل معك فور الانتهاء.',
        createdAt: now,
      ),
    ];
  }
}

/// Controller that persists customizable Quick Replies / Slash Commands in
/// `SharedPreferences` and provides CRUD + filtering operations.
class QuickRepliesController extends AsyncNotifier<List<QuickReplyTemplate>> {
  static const String _storageKey = 'chat_quick_replies_v1';
  static const String _seededKey = 'chat_quick_replies_seeded_v1';
  StreamSubscription<ChatSocketEvent>? _socketSub;

  @override
  Future<List<QuickReplyTemplate>> build() async {
    _listenToSocketSync();
    ref.onDispose(() => _socketSub?.cancel());
    final local = await _loadFromStorage();
    unawaited(_pullFromServer(local));
    return local;
  }

  void _listenToSocketSync() {
    _socketSub?.cancel();
    final socketService = ref.read(chatSocketServiceProvider);
    _socketSub = socketService.events.listen((event) {
      if (event.type == 'quick_replies_updated') {
        final rawList = event.payload['quickReplies'];
        if (rawList is List) {
          final parsed = rawList
              .whereType<Map>()
              .map(
                (e) =>
                    QuickReplyTemplate.fromJson(Map<String, dynamic>.from(e)),
              )
              .where((item) => item.content.trim().isNotEmpty)
              .toList();
          if (parsed.isNotEmpty) {
            state = AsyncData(parsed);
            unawaited(_saveToStorage(parsed, syncToServer: false));
          }
        }
      } else if (event.type == 'socket_connected') {
        final current = state.valueOrNull ?? const <QuickReplyTemplate>[];
        unawaited(_pullFromServer(current));
      }
    });
  }

  Future<void> _pullFromServer(List<QuickReplyTemplate> fallbackLocal) async {
    try {
      final sock = ref.read(chatSocketServiceProvider).socket;
      if (sock == null || !sock.connected) return;
      final completer = Completer<void>();
      sock.emitWithAck('quick_replies:get', const <String, dynamic>{}, ack: (res) {
        try {
          if (res is Map && res['ok'] == true && res['data'] is Map) {
            final raw = (res['data'] as Map)['quickReplies'];
            if (raw is List && raw.isNotEmpty) {
              final remoteList = raw
                  .whereType<Map>()
                  .map(
                    (e) => QuickReplyTemplate.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .where((item) => item.content.trim().isNotEmpty)
                  .toList();
              if (remoteList.isNotEmpty) {
                state = AsyncData(remoteList);
                unawaited(_saveToStorage(remoteList, syncToServer: false));
                completer.complete();
                return;
              }
            } else if (fallbackLocal.isNotEmpty) {
              unawaited(_pushToServer(fallbackLocal));
            }
          }
        } catch (_) {}
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future.timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  Future<void> _pushToServer(List<QuickReplyTemplate> items) async {
    try {
      final sock = ref.read(chatSocketServiceProvider).socket;
      if (sock == null || !sock.connected) return;
      sock.emit('quick_replies:sync', {
        'quickReplies': items
            .map(
              (e) => {
                'id': e.id,
                'shortcut': e.cleanShortcut,
                'title': e.displayTitle,
                'content': e.content,
                'category': e.category.trim().isNotEmpty
                    ? e.category.trim()
                    : 'عام',
              },
            )
            .toList(),
      });
    } catch (_) {}
  }

  Future<List<QuickReplyTemplate>> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      final alreadySeeded = prefs.getBool(_seededKey) ?? false;

      if ((raw == null || raw.isEmpty) && !alreadySeeded) {
        final defaults = QuickReplyTemplate.defaultTemplates();
        await _saveToStorage(defaults, markSeeded: true, syncToServer: false);
        return defaults;
      }

      if (raw == null || raw.isEmpty) {
        return const <QuickReplyTemplate>[];
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <QuickReplyTemplate>[];

      final list = decoded
          .whereType<Map>()
          .map(
            (e) => QuickReplyTemplate.fromJson(Map<String, dynamic>.from(e)),
          )
          .where((item) => item.content.trim().isNotEmpty)
          .toList();
      return list;
    } catch (_) {
      return QuickReplyTemplate.defaultTemplates();
    }
  }

  Future<void> _saveToStorage(
    List<QuickReplyTemplate> items, {
    bool markSeeded = true,
    bool syncToServer = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
      if (markSeeded) {
        await prefs.setBool(_seededKey, true);
      }
    } catch (_) {}
    if (syncToServer) {
      unawaited(_pushToServer(items));
    }
  }

  String _normalizeShortcut(String shortcut, String content) {
    var clean = shortcut.trim();
    if (clean.startsWith('/')) {
      clean = clean.substring(1).trim();
    }
    clean = clean.replaceAll(RegExp(r'\s+'), '_');
    if (clean.isNotEmpty) return clean;

    final words = content
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .join('_');
    return words.isNotEmpty ? words : 'رد_سريع';
  }

  /// Adds a new quick reply template or updates an existing one if [id] is provided.
  Future<QuickReplyTemplate> upsertTemplate({
    String? id,
    required String shortcut,
    required String content,
  }) async {
    final trimmedContent = content.trim();
    final normalizedShortcut = _normalizeShortcut(shortcut, trimmedContent);
    final current = List<QuickReplyTemplate>.from(
      state.valueOrNull ?? await _loadFromStorage(),
    );

    if (id != null && id.isNotEmpty) {
      final idx = current.indexWhere((e) => e.id == id);
      if (idx >= 0) {
        final updated = current[idx].copyWith(
          shortcut: normalizedShortcut,
          content: trimmedContent,
        );
        current[idx] = updated;
        state = AsyncData(current);
        await _saveToStorage(current);
        return updated;
      }
    }

    final created = QuickReplyTemplate(
      id: 'qr_${DateTime.now().millisecondsSinceEpoch}',
      shortcut: normalizedShortcut,
      content: trimmedContent,
      createdAt: DateTime.now(),
    );
    current.insert(0, created);
    state = AsyncData(current);
    await _saveToStorage(current);
    return created;
  }

  /// Deletes a quick reply template by [id].
  Future<void> deleteTemplate(String id) async {
    final current = List<QuickReplyTemplate>.from(
      state.valueOrNull ?? const <QuickReplyTemplate>[],
    );
    current.removeWhere((e) => e.id == id);
    state = AsyncData(current);
    await _saveToStorage(current);
  }

  /// Increments usage count for a template so frequently used replies can stand out.
  Future<void> recordUsage(String id) async {
    final current = List<QuickReplyTemplate>.from(
      state.valueOrNull ?? const <QuickReplyTemplate>[],
    );
    final idx = current.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    current[idx] = current[idx].copyWith(
      usageCount: current[idx].usageCount + 1,
    );
    state = AsyncData(current);
    await _saveToStorage(current);
  }

  /// Reorders templates from [oldIndex] to [newIndex].
  Future<void> reorderTemplates(int oldIndex, int newIndex) async {
    final current = List<QuickReplyTemplate>.from(
      state.valueOrNull ?? const <QuickReplyTemplate>[],
    );
    if (oldIndex < 0 || oldIndex >= current.length) return;
    var targetIndex = newIndex;
    if (oldIndex < targetIndex) {
      targetIndex -= 1;
    }
    targetIndex = targetIndex.clamp(0, current.length - 1);
    final item = current.removeAt(oldIndex);
    current.insert(targetIndex, item);
    state = AsyncData(current);
    await _saveToStorage(current);
  }

  /// Restores default workplace templates (merging without duplicating existing shortcuts).
  Future<void> restoreDefaultTemplates() async {
    final current = List<QuickReplyTemplate>.from(
      state.valueOrNull ?? const <QuickReplyTemplate>[],
    );
    final existingShortcuts = current
        .map((e) => e.cleanShortcut.toLowerCase())
        .toSet();
    for (final def in QuickReplyTemplate.defaultTemplates()) {
      if (!existingShortcuts.contains(def.cleanShortcut.toLowerCase())) {
        current.add(def);
      }
    }
    state = AsyncData(current);
    await _saveToStorage(current);
  }
}

final quickRepliesProvider =
    AsyncNotifierProvider<QuickRepliesController, List<QuickReplyTemplate>>(
      QuickRepliesController.new,
    );

/// Opens an Apple-style modal sheet to create or edit a Quick Reply template.
Future<QuickReplyTemplate?> showUpsertQuickReplySheet({
  required BuildContext context,
  required WidgetRef ref,
  QuickReplyTemplate? existing,
  String? initialContent,
}) {
  return showModalBottomSheet<QuickReplyTemplate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _UpsertQuickReplySheet(
      existing: existing,
      initialContent: initialContent,
    ),
  );
}

class _UpsertQuickReplySheet extends ConsumerStatefulWidget {
  const _UpsertQuickReplySheet({
    this.existing,
    this.initialContent,
  });

  final QuickReplyTemplate? existing;
  final String? initialContent;

  @override
  ConsumerState<_UpsertQuickReplySheet> createState() =>
      _UpsertQuickReplySheetState();
}

class _UpsertQuickReplySheetState
    extends ConsumerState<_UpsertQuickReplySheet> {
  late final TextEditingController _shortcutController;
  late final TextEditingController _contentController;
  String? _errorText;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _shortcutController = TextEditingController(
      text: widget.existing?.cleanShortcut ?? '',
    );
    _contentController = TextEditingController(
      text: widget.existing?.content ?? widget.initialContent ?? '',
    );
  }

  @override
  void dispose() {
    _shortcutController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      setState(() => _errorText = 'يرجى كتابة نص الرد الجاهز أولاً.');
      return;
    }

    setState(() {
      _errorText = null;
      _saving = true;
    });

    HapticFeedback.mediumImpact();
    final saved = await ref
        .read(quickRepliesProvider.notifier)
        .upsertTemplate(
          id: widget.existing?.id,
          shortcut: _shortcutController.text,
          content: content,
        );
    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? Colors.white60 : const Color(0xFF64748B);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black26,
                      borderRadius: BorderRadius.circular(99),
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
                        color: const Color(0xFF007AFF).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        CupertinoIcons.bolt_horizontal_circle_fill,
                        color: Color(0xFF007AFF),
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing
                                ? 'تعديل الرد السريع'
                                : 'إضافة رد سريع جديد',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'اكتب / في أي محادثة لإدراج هذا الرد فوراً',
                            style: TextStyle(
                              fontSize: 12,
                              color: subColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Shortcut field
                Text(
                  'أمر الاختصار (بعد علامة /)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: subColor,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '/',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF007AFF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _shortcutController,
                          textInputAction: TextInputAction.next,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                          decoration: InputDecoration(
                            hintText: 'مثال: استلام، طباعة، أصل، اجتماع...',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: subColor,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Content field
                Text(
                  'نص الرسالة الجاهزة',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: subColor,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: TextField(
                    controller: _contentController,
                    autofocus: !isEditing,
                    minLines: 3,
                    maxLines: 6,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: textColor,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'مثال: تم الاستلام وجاري المراجعة، سأوافيك بالرد قريباً...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: subColor,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),

                if (_errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorText!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF3B30),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _saving ? null : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        child: const Text(
                          'إلغاء',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF007AFF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        icon: Icon(
                          isEditing
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.add_circled_solid,
                          size: 18,
                        ),
                        label: Text(
                          isEditing ? 'حفظ التعديلات' : 'إضافة للردود السريعة',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
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

/// Full-featured Apple-style management screen for Quick Replies & Slash Commands,
/// accessible from Profile/Settings (`ProfileScreen`) and directly from the `/`
/// popup inside `ConversationScreen`.
class QuickRepliesManagementScreen extends ConsumerWidget {
  const QuickRepliesManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    final templatesAsync = ref.watch(quickRepliesProvider);
    final templates =
        templatesAsync.valueOrNull ?? const <QuickReplyTemplate>[];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'الردود السريعة والقوالب (/)',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'خيارات إضافية',
            onSelected: (value) async {
              if (value == 'restore_defaults') {
                await ref
                    .read(quickRepliesProvider.notifier)
                    .restoreDefaultTemplates();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تمت استعادة القوالب الافتراضية بنجاح'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'restore_defaults',
                child: Row(
                  children: [
                    Icon(CupertinoIcons.arrow_counterclockwise, size: 18),
                    SizedBox(width: 10),
                    Text('استعادة القوالب الافتراضية للعمل'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF007AFF),
        foregroundColor: Colors.white,
        onPressed: () async {
          final added = await showUpsertQuickReplySheet(
            context: context,
            ref: ref,
          );
          if (added != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('تمت إضافة الرد السريع (${added.triggerCommand})'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        icon: const Icon(CupertinoIcons.add, size: 20),
        label: const Text(
          'إضافة رد جديد',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          // Header explanation card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [Color(0xFF1E293B), Color(0xFF0F172A)]
                    : const [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF007AFF).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    CupertinoIcons.command,
                    color: Color(0xFF007AFF),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'كيف تعمل الردود السريعة؟',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'بمجرد كتابة علامة ( / ) في صندوق الرسائل داخل أي محادثة، ستظهر لك كل ردودك الجاهزة هنا لتختار منها بضغطة واحدة أو تفلترها بكتابة الاختصار.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: templates.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 66,
                            height: 66,
                            decoration: BoxDecoration(
                              color: const Color(0xFF007AFF)
                                  .withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              CupertinoIcons.bolt_horizontal_circle,
                              size: 32,
                              color: Color(0xFF007AFF),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'لا توجد ردود سريعة مضافة حالياً',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'أضف ردودك المتكررة في العمل لتوفير وقت الكتابة والرد بضغطة واحدة عبر الرمز /',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: subColor,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () {
                              ref
                                  .read(quickRepliesProvider.notifier)
                                  .restoreDefaultTemplates();
                            },
                            icon: const Icon(
                              CupertinoIcons.sparkles,
                              size: 17,
                            ),
                            label: const Text('إضافة قوالب العمل المقترحة'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 96),
                    itemCount: templates.length,
                    onReorder: (oldIndex, newIndex) {
                      HapticFeedback.selectionClick();
                      ref
                          .read(quickRepliesProvider.notifier)
                          .reorderTemplates(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final item = templates[index];
                      return Container(
                        key: ValueKey(item.id),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          onTap: () {
                            showUpsertQuickReplySheet(
                              context: context,
                              ref: ref,
                              existing: item,
                            );
                          },
                          leading: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF007AFF)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              item.triggerCommand,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF007AFF),
                              ),
                            ),
                          ),
                          title: Text(
                            item.content,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.38,
                              color: textColor,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'تعديل',
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  showUpsertQuickReplySheet(
                                    context: context,
                                    ref: ref,
                                    existing: item,
                                  );
                                },
                                icon: Icon(
                                  CupertinoIcons.pencil,
                                  size: 19,
                                  color: subColor,
                                ),
                              ),
                              IconButton(
                                tooltip: 'حذف',
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  ref
                                      .read(quickRepliesProvider.notifier)
                                      .deleteTemplate(item.id);
                                },
                                icon: const Icon(
                                  CupertinoIcons.trash,
                                  size: 18,
                                  color: Color(0xFFFF3B30),
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Icon(
                                    CupertinoIcons.line_horizontal_3,
                                    size: 18,
                                    color: subColor,
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

/// Compact floating slash-command picker displayed right above the message
/// composer in `ConversationScreen` when the user types `/`.
class QuickRepliesSlashPopup extends StatelessWidget {
  const QuickRepliesSlashPopup({
    super.key,
    required this.templates,
    required this.query,
    required this.onSelectTemplate,
    required this.onSendTemplateImmediately,
    required this.onManageTemplates,
    required this.onAddQuickTemplate,
  });

  final List<QuickReplyTemplate> templates;
  final String query;
  final ValueChanged<QuickReplyTemplate> onSelectTemplate;
  final ValueChanged<QuickReplyTemplate> onSendTemplateImmediately;
  final VoidCallback onManageTemplates;
  final VoidCallback onAddQuickTemplate;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.08);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header bar with title + Add & Manage buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Center(
                    child: Text(
                      '/',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    query.trim().isEmpty
                        ? 'الردود السريعة والقوالب الجاهزة'
                        : 'نتائج البحث عن "/${query.trim()}"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onAddQuickTemplate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          CupertinoIcons.add_circled,
                          size: 15,
                          color: Color(0xFF007AFF),
                        ),
                        const SizedBox(width: 3),
                        const Text(
                          'إضافة',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF007AFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onManageTemplates,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.slider_horizontal_3,
                          size: 14,
                          color: subColor,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'إدارة',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: subColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 0.6, color: borderColor),
          if (templates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'لا يوجد رد مطابق لـ "/$query" — يمكنك إضافته فوراً',
                      style: TextStyle(fontSize: 12.5, color: subColor),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onAddQuickTemplate,
                    icon: const Icon(CupertinoIcons.add, size: 15),
                    label: const Text('إضافة كرد سريع'),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: templates.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  thickness: 0.4,
                  indent: 14,
                  endIndent: 14,
                  color: borderColor,
                ),
                itemBuilder: (context, index) {
                  final item = templates[index];
                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSelectTemplate(item);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF007AFF)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              item.triggerCommand,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF007AFF),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'إرسال فوري',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(99),
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                onSendTemplateImmediately(item);
                              },
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF007AFF)
                                      .withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.send_rounded,
                                  size: 15,
                                  color: Color(0xFF007AFF),
                                ),
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
