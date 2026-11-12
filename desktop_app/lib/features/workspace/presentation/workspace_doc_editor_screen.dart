import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/workspace_doc.dart';
import 'widgets/workspace_block_widgets.dart';
import 'workspace_controller.dart';

class WorkspaceDocEditorScreen extends ConsumerStatefulWidget {
  const WorkspaceDocEditorScreen({
    super.key,
    required this.doc,
    this.onBack,
    this.onDeleteDoc,
  });

  final WorkspaceDoc doc;
  final VoidCallback? onBack;
  final VoidCallback? onDeleteDoc;

  @override
  ConsumerState<WorkspaceDocEditorScreen> createState() =>
      _WorkspaceDocEditorScreenState();
}

class _WorkspaceDocEditorScreenState
    extends ConsumerState<WorkspaceDocEditorScreen> {
  late WorkspaceDoc _doc;
  late TextEditingController _titleController;
  final Map<String, FocusNode> _blockFocusNodes = {};

  static const List<String> _popularIcons = [
    '📝', '💡', '🎯', '📋', '🚀', '📌', '💼', '📊',
    '🛠️', '🧾', '👥', '✨', '🏢', '⚡', '🔍', '⭐',
    '🔥', '✅', '🗂️', '📅', '🤝', '💻', '📦', '🏆',
  ];

  static const List<Map<String, dynamic>> _coverPresets = [
    {'color': '0xFFE0F2FE', 'name': 'أزرق سماوي', 'c1': 0xFF007AFF, 'c2': 0xFF38BDF8},
    {'color': '0xFFDCFCE7', 'name': 'أخضر زمردي', 'c1': 0xFF059669, 'c2': 0xFF34D399},
    {'color': '0xFFFEF3C7', 'name': 'ذهبي دافئ', 'c1': 0xFFD97706, 'c2': 0xFFFBBF24},
    {'color': '0xFFF3E8FF', 'name': 'بنفسجي ملكي', 'c1': 0xFF7C3AED, 'c2': 0xFFA78BFA},
    {'color': '0xFFFCE7F3', 'name': 'وردي ناعم', 'c1': 0xFFDB2777, 'c2': 0xFFF472B6},
    {'color': '0xFF1E293B', 'name': 'ليلي داكن', 'c1': 0xFF0F172A, 'c2': 0xFF334155},
  ];

  static const List<String> _categories = [
    'عام',
    'مهام الفرع',
    'استلام وتسليم',
    'أفكار ومشاريع',
    'اجتماعات',
    'شخصي',
  ];

  @override
  void initState() {
    super.initState();
    _doc = widget.doc;
    _titleController = TextEditingController(text: _doc.title);
  }

  @override
  void didUpdateWidget(covariant WorkspaceDocEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doc.id != widget.doc.id) {
      _doc = widget.doc;
      _titleController.text = _doc.title;
      for (final node in _blockFocusNodes.values) {
        node.dispose();
      }
      _blockFocusNodes.clear();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final node in _blockFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _getFocusNode(String blockId) {
    return _blockFocusNodes.putIfAbsent(blockId, () => FocusNode());
  }

  void _focusBlock(String blockId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _getFocusNode(blockId);
      node.requestFocus();
    });
  }

  void _saveDoc() {
    if (!mounted) return;
    ref.read(workspaceDocsProvider.notifier).updateDoc(_doc);
    setState(() {});
  }

  void _addBlock(WorkspaceBlockType type, {int? insertAtIndex, String initialContent = ''}) {
    final newBlock = WorkspaceBlock(
      type: type,
      content: initialContent,
    );
    setState(() {
      if (insertAtIndex != null &&
          insertAtIndex >= 0 &&
          insertAtIndex <= _doc.blocks.length) {
        _doc.blocks.insert(insertAtIndex, newBlock);
      } else {
        _doc.blocks.add(newBlock);
      }
    });
    _saveDoc();
    if (type != WorkspaceBlockType.divider && type != WorkspaceBlockType.table) {
      _focusBlock(newBlock.id);
    }
  }

  void _handleEnterOnBlock(int index, String remainderText) {
    final current = _doc.blocks[index];
    WorkspaceBlockType nextType = WorkspaceBlockType.text;
    if (current.type == WorkspaceBlockType.todo ||
        current.type == WorkspaceBlockType.bullet ||
        current.type == WorkspaceBlockType.numbered) {
      nextType = current.type;
    }
    _addBlock(
      nextType,
      insertAtIndex: index + 1,
      initialContent: remainderText,
    );
  }

  void _moveBlock(int index, int delta) {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _doc.blocks.length) return;
    setState(() {
      final item = _doc.blocks.removeAt(index);
      _doc.blocks.insert(newIndex, item);
    });
    _saveDoc();
  }

  void _duplicateBlock(int index) {
    final original = _doc.blocks[index];
    final copy = original.copyWith(id: null);
    setState(() {
      _doc.blocks.insert(index + 1, copy);
    });
    _saveDoc();
  }

  void _transformBlockType(int index, WorkspaceBlockType newType) {
    final block = _doc.blocks[index];
    setState(() {
      block.type = newType;
    });
    _saveDoc();
    _focusBlock(block.id);
  }

  void _deleteBlock(int index) {
    final removed = _doc.blocks[index];
    _blockFocusNodes.remove(removed.id)?.dispose();
    setState(() {
      _doc.blocks.removeAt(index);
    });
    _saveDoc();
  }

  List<Color> _resolveCoverGradient(String coverHex) {
    for (final preset in _coverPresets) {
      if (preset['color'] == coverHex) {
        return [Color(preset['c1'] as int), Color(preset['c2'] as int)];
      }
    }
    return [const Color(0xFF007AFF), const Color(0xFF38BDF8)];
  }

  void _pickIcon() {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('اختر أيقونة الصفحة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 350,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _popularIcons.map((emoji) {
                final isSelected = _doc.icon == emoji;
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    setState(() => _doc.icon = emoji);
                    _saveDoc();
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF007AFF).withValues(alpha: 0.15)
                          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(14),
                      border: isSelected
                          ? Border.all(color: const Color(0xFF007AFF), width: 2)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _pickCoverColor() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('اختر مظهر ترويسة الصفحة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 360,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _coverPresets.map((preset) {
                final hexStr = preset['color'] as String;
                final c1 = Color(preset['c1'] as int);
                final c2 = Color(preset['c2'] as int);
                final isSelected = _doc.coverColor == hexStr;

                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    setState(() => _doc.coverColor = hexStr);
                    _saveDoc();
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    width: 104,
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [c1, c2]),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      preset['name'] as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _pickCategory() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('تصنيف الصفحة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 290,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _categories.map((cat) {
                final isSelected = _doc.category == cat;
                return ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text(
                    cat,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? const Color(0xFF007AFF) : null,
                    ),
                  ),
                  trailing: isSelected ? const Icon(CupertinoIcons.checkmark_circle_fill, color: Color(0xFF007AFF)) : null,
                  onTap: () {
                    setState(() => _doc.category = cat);
                    _saveDoc();
                    Navigator.of(ctx).pop();
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _shareAsMarkdown() {
    Clipboard.setData(ClipboardData(text: _doc.toMarkdown()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ الصفحة بالكامل إلى الحافظة لمشاركتها ✓'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showStatsDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalTodos = _doc.todoCount;
    final doneTodos = _doc.completedTodoCount;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              Text(_doc.icon, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _doc.title.trim().isNotEmpty ? _doc.title : 'بدون عنوان',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _buildStatCard('الكلمات', '${_doc.wordCount}', isDark),
                    const SizedBox(width: 8),
                    _buildStatCard('الحروف', '${_doc.characterCount}', isDark),
                    const SizedBox(width: 8),
                    _buildStatCard('العناصر', '${_doc.blocks.length}', isDark),
                    if (totalTodos > 0) ...[
                      const SizedBox(width: 8),
                      _buildStatCard('المهام', '$doneTodos/$totalTodos', isDark),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _buildInfoRow('التصنيف', _doc.category, CupertinoIcons.tag),
                _buildInfoRow('تاريخ الإنشاء', DateFormat('d MMM yyyy - hh:mm a', 'ar').format(_doc.createdAt), CupertinoIcons.calendar),
                _buildInfoRow('آخر تعديل', DateFormat('d MMM yyyy - hh:mm a', 'ar').format(_doc.updatedAt), CupertinoIcons.time),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Color(0xFF007AFF),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String title, String val, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 15, color: const Color(0xFF007AFF)),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
          const Spacer(),
          Text(val, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  int _calculateNumberedIndex(int currentIndex) {
    int count = 1;
    for (int i = currentIndex - 1; i >= 0; i--) {
      if (_doc.blocks[i].type == WorkspaceBlockType.numbered) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvasBg = isDark ? const Color(0xFF0B1120) : const Color(0xFFF2F2F7);
    final paperColor = isDark ? const Color(0xFF151F32) : Colors.white;
    final gradColors = _resolveCoverGradient(_doc.coverColor);
    final primaryAccent = gradColors.first;
    final totalTodos = _doc.todoCount;
    final completedTodos = _doc.completedTodoCount;
    final progressRatio = totalTodos > 0 ? (completedTodos / totalTodos).clamp(0.0, 1.0) : 0.0;

    return Container(
      color: canvasBg,
      child: Column(
        children: [
          // 1. Sleek Top Breadcrumb & Action Bar
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: paperColor,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFE2E8F0),
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              children: [
                if (widget.onBack != null) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: widget.onBack,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.right_chevron,
                            size: 14,
                            color: isDark ? Colors.white70 : const Color(0xFF334155),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'مساحة العمل والملاحظات',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white70 : const Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '/',
                      style: TextStyle(
                        color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
                Text(_doc.icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _doc.title.trim().isNotEmpty ? _doc.title : 'صفحة بدون عنوان',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                // Auto-save pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'محفوظ تلقائياً',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _buildTopIconPill(
                  icon: _doc.isPinned ? CupertinoIcons.pin_fill : CupertinoIcons.pin,
                  color: _doc.isPinned ? const Color(0xFFFF9500) : null,
                  tooltip: _doc.isPinned ? 'إلغاء التثبيت' : 'تثبيت الصفحة',
                  isDark: isDark,
                  onTap: () {
                    setState(() => _doc.isPinned = !_doc.isPinned);
                    _saveDoc();
                  },
                ),
                const SizedBox(width: 6),
                _buildTopIconPill(
                  icon: _doc.isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
                  color: _doc.isFavorite ? const Color(0xFFFFCC00) : null,
                  tooltip: 'إضافة للمفضلة',
                  isDark: isDark,
                  onTap: () {
                    setState(() => _doc.isFavorite = !_doc.isFavorite);
                    _saveDoc();
                  },
                ),
                const SizedBox(width: 6),
                _buildTopIconPill(
                  icon: CupertinoIcons.doc_on_clipboard,
                  tooltip: 'نسخ المحتوى لمشاركته في المحادثات',
                  isDark: isDark,
                  onTap: _shareAsMarkdown,
                ),
                const SizedBox(width: 6),
                _buildTopIconPill(
                  icon: CupertinoIcons.chart_bar_square,
                  tooltip: 'إحصائيات وتفاصيل الصفحة',
                  isDark: isDark,
                  onTap: _showStatsDialog,
                ),
                if (widget.onDeleteDoc != null) ...[
                  const SizedBox(width: 6),
                  _buildTopIconPill(
                    icon: CupertinoIcons.trash,
                    color: Colors.redAccent,
                    tooltip: 'حذف الصفحة',
                    isDark: isDark,
                    onTap: widget.onDeleteDoc!,
                  ),
                ],
              ],
            ),
          ),

          // 2. Centered Apple Bento Document Canvas
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Hero Header Card
                      Container(
                        decoration: BoxDecoration(
                          color: paperColor,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : const Color(0xFFE2E8F0),
                            width: 0.9,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Soft Gradient Top Banner inside Hero Card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    gradColors[0].withValues(alpha: isDark ? 0.32 : 0.14),
                                    gradColors[1].withValues(alpha: isDark ? 0.12 : 0.04),
                                  ],
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Squircle Icon Picker
                                  InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: _pickIcon,
                                    child: Tooltip(
                                      message: 'تغيير أيقونة الصفحة',
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            width: 68,
                                            height: 68,
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(
                                                color: primaryAccent.withValues(alpha: 0.35),
                                                width: 1.5,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: primaryAccent.withValues(alpha: 0.16),
                                                  blurRadius: 14,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(_doc.icon, style: const TextStyle(fontSize: 36)),
                                          ),
                                          Positioned(
                                            bottom: -3,
                                            left: -3,
                                            child: Container(
                                              padding: const EdgeInsets.all(5),
                                              decoration: BoxDecoration(
                                                color: primaryAccent,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: paperColor,
                                                  width: 2,
                                                ),
                                              ),
                                              child: const Icon(
                                                CupertinoIcons.sparkles,
                                                size: 11,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            InkWell(
                                              borderRadius: BorderRadius.circular(20),
                                              onTap: _pickCategory,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: isDark ? Colors.black38 : Colors.white.withValues(alpha: 0.9),
                                                  borderRadius: BorderRadius.circular(20),
                                                  border: Border.all(
                                                    color: primaryAccent.withValues(alpha: 0.3),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(CupertinoIcons.folder_fill, size: 13, color: primaryAccent),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      _doc.category,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w800,
                                                        color: primaryAccent,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Icon(CupertinoIcons.chevron_down, size: 11, color: primaryAccent),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            InkWell(
                                              borderRadius: BorderRadius.circular(20),
                                              onTap: _pickCoverColor,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: isDark ? Colors.black38 : Colors.white.withValues(alpha: 0.9),
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                      width: 11,
                                                      height: 11,
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(colors: gradColors),
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      'تخصيص المظهر',
                                                      style: TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight: FontWeight.w700,
                                                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Icon(
                                              CupertinoIcons.clock,
                                              size: 12,
                                              color: isDark ? Colors.white38 : const Color(0xFF64748B),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'آخر تعديل: ${DateFormat('d MMM yyyy - hh:mm a', 'ar').format(_doc.updatedAt)}',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: isDark ? Colors.white38 : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Document Title & Progress Strip
                            Padding(
                              padding: const EdgeInsets.fromLTRB(26, 18, 26, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextField(
                                    controller: _titleController,
                                    onChanged: (val) {
                                      _doc.title = val;
                                      _saveDoc();
                                    },
                                    maxLines: null,
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.5,
                                      height: 1.25,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'عنوان الصفحة أو الملاحظة...',
                                      hintStyle: TextStyle(
                                        color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      _buildMiniMetricPill(
                                        icon: CupertinoIcons.square_stack_3d_up,
                                        label: '${_doc.blocks.length} عنصر',
                                        isDark: isDark,
                                      ),
                                      const SizedBox(width: 8),
                                      _buildMiniMetricPill(
                                        icon: CupertinoIcons.text_alignright,
                                        label: '${_doc.wordCount} كلمة',
                                        isDark: isDark,
                                      ),
                                      if (totalTodos > 0) ...[
                                        const Spacer(),
                                        Text(
                                          'إنجاز المهام ${(progressRatio * 100).round()}% ($completedTodos من $totalTodos مكتملة)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: completedTodos == totalTodos
                                                ? const Color(0xFF10B981)
                                                : primaryAccent,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (totalTodos > 0) ...[
                                    const SizedBox(height: 10),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: progressRatio,
                                        minHeight: 7,
                                        backgroundColor: isDark
                                            ? Colors.white.withValues(alpha: 0.08)
                                            : const Color(0xFFF1F5F9),
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          completedTodos == totalTodos
                                              ? const Color(0xFF10B981)
                                              : primaryAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Elevated Paper Sheet for Blocks
                      Container(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                        decoration: BoxDecoration(
                          color: paperColor,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : const Color(0xFFE2E8F0),
                            width: 0.9,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.03),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_doc.blocks.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 40),
                                child: Column(
                                  children: [
                                    Icon(
                                      CupertinoIcons.doc_text,
                                      size: 42,
                                      color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'الصفحة فارغة حالياً — ابدأ بالكتابة أو اختر عنصراً من الشريط السفلي',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ...List.generate(_doc.blocks.length, (idx) {
                              final block = _doc.blocks[idx];
                              final numIdx = block.type == WorkspaceBlockType.numbered
                                  ? _calculateNumberedIndex(idx)
                                  : 1;

                              return WorkspaceBlockWidget(
                                key: ValueKey(block.id),
                                block: block,
                                focusNode: _getFocusNode(block.id),
                                numberIndex: numIdx,
                                isEditable: true,
                                isDark: isDark,
                                onChanged: _saveDoc,
                                onToggleTodo: () {
                                  setState(() {
                                    block.isChecked = !block.isChecked;
                                  });
                                  _saveDoc();
                                },
                                onInsertBelow: (newType) =>
                                    _addBlock(newType, insertAtIndex: idx + 1),
                                onEnterPressed: (remainder) =>
                                    _handleEnterOnBlock(idx, remainder),
                                onMoveUp: idx > 0 ? () => _moveBlock(idx, -1) : null,
                                onMoveDown: idx < _doc.blocks.length - 1
                                    ? () => _moveBlock(idx, 1)
                                    : null,
                                onDuplicate: () => _duplicateBlock(idx),
                                onTransformType: (newType) =>
                                    _transformBlockType(idx, newType),
                                onDelete: () => _deleteBlock(idx),
                              );
                            }),

                            const SizedBox(height: 14),

                            // Quick "+ إضافة سطر جديد" area at the bottom of the paper card
                            InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _addBlock(WorkspaceBlockType.text),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.025)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      CupertinoIcons.add_circled_solid,
                                      size: 18,
                                      color: primaryAccent,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'اضغط هنا لإضافة سطر جديد أو اكتب / لإدراج الجداول والمهام والعناوين',
                                      style: TextStyle(
                                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. Bottom Apple Dock Toolbar for Instant Block Insertion
          Container(
            decoration: BoxDecoration(
              color: paperColor,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                  width: 0.8,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildQuickInsertChip('مهمة', CupertinoIcons.checkmark_circle_fill, const Color(0xFF10B981), WorkspaceBlockType.todo, isDark),
                    _buildQuickInsertChip('جدول تفاعلي', CupertinoIcons.table, const Color(0xFF059669), WorkspaceBlockType.table, isDark),
                    _buildQuickInsertChip('عنوان H1', CupertinoIcons.textformat, const Color(0xFF007AFF), WorkspaceBlockType.heading1, isDark),
                    _buildQuickInsertChip('عنوان H2', CupertinoIcons.textformat_size, const Color(0xFF5856D6), WorkspaceBlockType.heading2, isDark),
                    _buildQuickInsertChip('قائمة نقطية', CupertinoIcons.list_bullet, const Color(0xFFF59E0B), WorkspaceBlockType.bullet, isDark),
                    _buildQuickInsertChip('قائمة مرقمة', CupertinoIcons.list_number, const Color(0xFF0EA5E9), WorkspaceBlockType.numbered, isDark),
                    _buildQuickInsertChip('قائمة مطوية', CupertinoIcons.chevron_down_square_fill, const Color(0xFF6366F1), WorkspaceBlockType.toggle, isDark),
                    _buildQuickInsertChip('ملاحظة بارزة', CupertinoIcons.lightbulb_fill, const Color(0xFFD97706), WorkspaceBlockType.callout, isDark),
                    _buildQuickInsertChip('صندوق كود', CupertinoIcons.chevron_left_slash_chevron_right, const Color(0xFF334155), WorkspaceBlockType.code, isDark),
                    _buildQuickInsertChip('اقتباس', CupertinoIcons.quote_bubble_fill, const Color(0xFFEC4899), WorkspaceBlockType.quote, isDark),
                    _buildQuickInsertChip('فاصل', CupertinoIcons.minus, const Color(0xFF94A3B8), WorkspaceBlockType.divider, isDark),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopIconPill({
    required IconData icon,
    Color? color,
    required String tooltip,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 16,
            color: color ?? (isDark ? Colors.white70 : const Color(0xFF334155)),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniMetricPill({
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickInsertChip(
    String label,
    IconData icon,
    Color color,
    WorkspaceBlockType type,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _addBlock(type),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 13, color: color),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
