import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../models/workspace_doc.dart';
import 'widgets/workspace_block_widgets.dart';
import 'workspace_controller.dart';

class WorkspaceDocEditorScreen extends ConsumerStatefulWidget {
  const WorkspaceDocEditorScreen({
    super.key,
    required this.doc,
  });

  final WorkspaceDoc doc;

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
    HapticFeedback.lightImpact();
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
    HapticFeedback.selectionClick();
    setState(() {
      final item = _doc.blocks.removeAt(index);
      _doc.blocks.insert(newIndex, item);
    });
    _saveDoc();
  }

  void _duplicateBlock(int index) {
    HapticFeedback.lightImpact();
    final original = _doc.blocks[index];
    final copy = original.copyWith(id: null);
    setState(() {
      _doc.blocks.insert(index + 1, copy);
    });
    _saveDoc();
  }

  void _transformBlockType(int index, WorkspaceBlockType newType) {
    HapticFeedback.selectionClick();
    final block = _doc.blocks[index];
    setState(() {
      block.type = newType;
    });
    _saveDoc();
    _focusBlock(block.id);
  }

  void _deleteBlock(int index) {
    HapticFeedback.mediumImpact();
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
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'اختر أيقونة الصفحة',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _popularIcons.map((emoji) {
                    final isSelected = _doc.icon == emoji;
                    return GestureDetector(
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
                              : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF1F5F9)),
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
              ],
            ),
          ),
        );
      },
    );
  }

  void _pickCoverColor() {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'اختر مظهر ترويسة الصفحة',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _coverPresets.map((preset) {
                    final hexStr = preset['color'] as String;
                    final c1 = Color(preset['c1'] as int);
                    final c2 = Color(preset['c2'] as int);
                    final isSelected = _doc.coverColor == hexStr;

                    return GestureDetector(
                      onTap: () {
                        setState(() => _doc.coverColor = hexStr);
                        _saveDoc();
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        width: 100,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [c1, c2]),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.transparent,
                            width: 2.5,
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(color: c1.withValues(alpha: 0.4), blurRadius: 8)]
                              : null,
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
              ],
            ),
          ),
        );
      },
    );
  }

  void _pickCategory() {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'تصنيف الصفحة',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 10),
                ..._categories.map((cat) {
                  final isSelected = _doc.category == cat;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: Text(
                      cat,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? const Color(0xFF007AFF) : null,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(CupertinoIcons.checkmark_circle_fill, color: Color(0xFF007AFF))
                        : null,
                    onTap: () {
                      setState(() => _doc.category = cat);
                      _saveDoc();
                      Navigator.of(ctx).pop();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _shareAsMarkdown() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _doc.toMarkdown()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ الصفحة بالكامل إلى الحافظة لمشاركتها ✓'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showDocInfoModal() {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalTodos = _doc.todoCount;
    final doneTodos = _doc.completedTodoCount;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(_doc.icon, style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _doc.title.trim().isNotEmpty ? _doc.title : 'بدون عنوان',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24, thickness: 0.5),
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
                _buildInfoRow(
                  'تاريخ الإنشاء',
                  DateFormat('d MMM yyyy - hh:mm a', 'ar').format(_doc.createdAt),
                  CupertinoIcons.calendar,
                ),
                _buildInfoRow(
                  'آخر تعديل',
                  DateFormat('d MMM yyyy - hh:mm a', 'ar').format(_doc.updatedAt),
                  CupertinoIcons.time,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 18),
                    label: const Text('نسخ المحتوى لمشاركته في المحادثات', style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _shareAsMarkdown();
                    },
                  ),
                ),
              ],
            ),
          ),
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
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
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

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final paperColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final coverColors = _resolveCoverGradient(_doc.coverColor);
    final primaryAccent = coverColors.first;
    final totalTodos = _doc.todoCount;
    final doneTodos = _doc.completedTodoCount;
    final progressRatio = totalTodos > 0 ? (doneTodos / totalTodos).clamp(0.0, 1.0) : 0.0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: paperColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              child: const Icon(CupertinoIcons.right_chevron, size: 17),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          titleSpacing: 0,
          title: Row(
            children: [
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
                    const SizedBox(width: 5),
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
            ],
          ),
          actions: [
            _buildTopActionButton(
              icon: _doc.isPinned ? CupertinoIcons.pin_fill : CupertinoIcons.pin,
              color: _doc.isPinned ? const Color(0xFFFF9500) : null,
              tooltip: _doc.isPinned ? 'إلغاء التثبيت' : 'تثبيت الصفحة',
              isDark: isDark,
              paperColor: paperColor,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _doc.isPinned = !_doc.isPinned);
                _saveDoc();
              },
            ),
            const SizedBox(width: 6),
            _buildTopActionButton(
              icon: _doc.isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
              color: _doc.isFavorite ? const Color(0xFFFFCC00) : null,
              tooltip: 'المفضلة',
              isDark: isDark,
              paperColor: paperColor,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _doc.isFavorite = !_doc.isFavorite);
                _saveDoc();
              },
            ),
            const SizedBox(width: 6),
            _buildTopActionButton(
              icon: CupertinoIcons.share,
              tooltip: 'نسخ ومشاركة',
              isDark: isDark,
              paperColor: paperColor,
              onTap: _shareAsMarkdown,
            ),
            const SizedBox(width: 6),
            _buildTopActionButton(
              icon: CupertinoIcons.info_circle,
              tooltip: 'تفاصيل وإحصائيات',
              isDark: isDark,
              paperColor: paperColor,
              onTap: _showDocInfoModal,
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
                children: [
                  // 1. Apple Bento Document Hero Card
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
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Soft Gradient Banner Strip with Quick Customization Pills
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                coverColors[0].withValues(alpha: isDark ? 0.32 : 0.14),
                                coverColors[1].withValues(alpha: isDark ? 0.12 : 0.05),
                              ],
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Interactive Squircle Emoji Badge
                              GestureDetector(
                                onTap: _pickIcon,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: primaryAccent.withValues(alpha: 0.35),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: primaryAccent.withValues(alpha: 0.15),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(_doc.icon, style: const TextStyle(fontSize: 32)),
                                    ),
                                    Positioned(
                                      bottom: -3,
                                      left: -3,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: primaryAccent,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: const Icon(
                                          CupertinoIcons.sparkles,
                                          size: 10,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              // Category + Theme Color + Updated Date Pills
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        GestureDetector(
                                          onTap: _pickCategory,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                                                Icon(CupertinoIcons.folder_fill, size: 12, color: primaryAccent),
                                                const SizedBox(width: 5),
                                                Text(
                                                  _doc.category,
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: primaryAccent,
                                                  ),
                                                ),
                                                const SizedBox(width: 3),
                                                Icon(CupertinoIcons.chevron_down, size: 10, color: primaryAccent),
                                              ],
                                            ),
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: _pickCoverColor,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: isDark ? Colors.black38 : Colors.white.withValues(alpha: 0.9),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 10,
                                                  height: 10,
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(colors: coverColors),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  'المظهر',
                                                  style: TextStyle(
                                                    fontSize: 11,
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
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          CupertinoIcons.clock,
                                          size: 11.5,
                                          color: isDark ? Colors.white38 : const Color(0xFF64748B),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'آخر تعديل: ${DateFormat('d MMM - hh:mm a', 'ar').format(_doc.updatedAt)}',
                                          style: TextStyle(
                                            fontSize: 11,
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

                        // Document Title Input + Stats & Progress Bar
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
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
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                  height: 1.25,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'عنوان الصفحة أو الملاحظة...',
                                  hintStyle: TextStyle(
                                    color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                                    fontSize: 23,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Mini Metrics & Progress Strip
                              Row(
                                children: [
                                  _buildMiniMetricPill(
                                    icon: CupertinoIcons.square_stack_3d_up,
                                    label: '${_doc.blocks.length} عنصر',
                                    isDark: isDark,
                                  ),
                                  const SizedBox(width: 6),
                                  _buildMiniMetricPill(
                                    icon: CupertinoIcons.text_alignright,
                                    label: '${_doc.wordCount} كلمة',
                                    isDark: isDark,
                                  ),
                                  if (totalTodos > 0) ...[
                                    const Spacer(),
                                    Text(
                                      'إنجاز المهام ${(progressRatio * 100).round()}% ($doneTodos/$totalTodos)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: doneTodos == totalTodos
                                            ? const Color(0xFF10B981)
                                            : primaryAccent,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (totalTodos > 0) ...[
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: progressRatio,
                                    minHeight: 6,
                                    backgroundColor: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : const Color(0xFFF1F5F9),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      doneTodos == totalTodos
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

                  const SizedBox(height: 12),

                  // 2. Elevated Document Paper Sheet for Blocks
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
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
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_doc.blocks.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Column(
                              children: [
                                Icon(
                                  CupertinoIcons.doc_text,
                                  size: 38,
                                  color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'الصفحة فارغة حالياً — ابدأ بكتابة ملاحظاتك أو إضافة مهام',
                                  style: TextStyle(
                                    fontSize: 13,
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

                        const SizedBox(height: 12),

                        // Subtle "+ سطر جديد" area inside the paper card
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _addBlock(WorkspaceBlockType.text),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
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
                                  size: 17,
                                  color: primaryAccent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'اضغط هنا لإضافة سطر جديد أو اكتب / للأوامر السريعة',
                                  style: TextStyle(
                                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                    fontSize: 12.5,
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

            // 3. Floating Apple Dock Toolbar for Instant Block Insertion
            Container(
              decoration: BoxDecoration(
                color: paperColor,
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFE2E8F0),
                    width: 0.8,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    children: [
                      _buildToolbarAction(
                        icon: CupertinoIcons.checkmark_circle_fill,
                        label: 'مهمة',
                        color: const Color(0xFF10B981),
                        isDark: isDark,
                        onTap: () => _addBlock(WorkspaceBlockType.todo),
                      ),
                      _buildToolbarAction(
                        icon: CupertinoIcons.table,
                        label: 'جدول',
                        color: const Color(0xFF059669),
                        isDark: isDark,
                        onTap: () => _addBlock(WorkspaceBlockType.table),
                      ),
                      _buildToolbarAction(
                        icon: CupertinoIcons.textformat,
                        label: 'عنوان H1',
                        color: const Color(0xFF007AFF),
                        isDark: isDark,
                        onTap: () => _addBlock(WorkspaceBlockType.heading1),
                      ),
                      _buildToolbarAction(
                        icon: CupertinoIcons.textformat_size,
                        label: 'عنوان H2',
                        color: const Color(0xFF5856D6),
                        isDark: isDark,
                        onTap: () => _addBlock(WorkspaceBlockType.heading2),
                      ),
                      _buildToolbarAction(
                        icon: CupertinoIcons.list_bullet,
                        label: 'قائمة',
                        color: const Color(0xFFF59E0B),
                        isDark: isDark,
                        onTap: () => _addBlock(WorkspaceBlockType.bullet),
                      ),
                      _buildToolbarAction(
                        icon: CupertinoIcons.list_number,
                        label: 'مرقمة',
                        color: const Color(0xFF0EA5E9),
                        isDark: isDark,
                        onTap: () => _addBlock(WorkspaceBlockType.numbered),
                      ),
                      _buildToolbarAction(
                        icon: CupertinoIcons.chevron_down_square_fill,
                        label: 'قائمة مطوية',
                        color: const Color(0xFF6366F1),
                        isDark: isDark,
                        onTap: () => _addBlock(WorkspaceBlockType.toggle),
                      ),
                      _buildToolbarAction(
                        icon: CupertinoIcons.lightbulb_fill,
                        label: 'تنبيه بارز',
                        color: const Color(0xFFD97706),
                        isDark: isDark,
                        onTap: () => _addBlock(WorkspaceBlockType.callout),
                      ),
                      _buildToolbarAction(
                        icon: CupertinoIcons.chevron_left_slash_chevron_right,
                        label: 'كود',
                        color: const Color(0xFF334155),
                        isDark: isDark,
                        onTap: () => _addBlock(WorkspaceBlockType.code),
                      ),
                      _buildToolbarAction(
                        icon: CupertinoIcons.quote_bubble_fill,
                        label: 'اقتباس',
                        color: const Color(0xFFEC4899),
                        isDark: isDark,
                        onTap: () => _addBlock(WorkspaceBlockType.quote),
                      ),
                      _buildToolbarAction(
                        icon: CupertinoIcons.minus,
                        label: 'فاصل',
                        color: const Color(0xFF94A3B8),
                        isDark: isDark,
                        onTap: () => _addBlock(WorkspaceBlockType.divider),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActionButton({
    required IconData icon,
    Color? color,
    required String tooltip,
    required bool isDark,
    required Color paperColor,
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
            color: paperColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 17,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarAction({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE2E8F0),
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
