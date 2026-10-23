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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('اختر أيقونة الصفحة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 340,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _popularIcons.map((emoji) {
                final isSelected = _doc.icon == emoji;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() => _doc.icon = emoji);
                    _saveDoc();
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF007AFF).withValues(alpha: 0.15)
                          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(12),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('اختر مظهر غلاف الصفحة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 350,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _coverPresets.map((preset) {
                final hexStr = preset['color'] as String;
                final c1 = Color(preset['c1'] as int);
                final c2 = Color(preset['c2'] as int);
                final isSelected = _doc.coverColor == hexStr;

                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() => _doc.coverColor = hexStr);
                    _saveDoc();
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    width: 102,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [c1, c2]),
                      borderRadius: BorderRadius.circular(12),
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
                        fontWeight: FontWeight.w700,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('تصنيف الصفحة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _categories.map((cat) {
                final isSelected = _doc.category == cat;
                return ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  title: Text(cat, style: TextStyle(fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500)),
                  trailing: isSelected ? const Icon(CupertinoIcons.checkmark_alt, color: Color(0xFF007AFF)) : null,
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
        content: Text('تم نسخ الصفحة بالكامل إلى الحافظة ✓'),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Text(_doc.icon, style: const TextStyle(fontSize: 24)),
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
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _buildStatCard('الكلمات', '${_doc.wordCount}', isDark),
                    const SizedBox(width: 8),
                    _buildStatCard('الحروف', '${_doc.characterCount}', isDark),
                    const SizedBox(width: 8),
                    _buildStatCard('الكتل', '${_doc.blocks.length}', isDark),
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
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? Colors.white38 : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String title, String val, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: const Color(0xFF007AFF)),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
          const Spacer(),
          Text(val, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradColors = _resolveCoverGradient(_doc.coverColor);
    final totalTodos = _doc.todoCount;
    final completedTodos = _doc.completedTodoCount;

    int numberedCounter = 1;

    return Container(
      color: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: Column(
        children: [
          // Top Editor Action Header
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              children: [
                if (widget.onBack != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF007AFF),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      icon: const Icon(CupertinoIcons.square_grid_2x2, size: 15),
                      label: const Text('كل الصفحات', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      onPressed: widget.onBack,
                    ),
                  ),
                Text(_doc.icon, style: const TextStyle(fontSize: 17)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _doc.title.trim().isNotEmpty ? _doc.title : 'بدون عنوان',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'محفوظ تلقائياً ✓',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: _doc.isPinned ? 'إلغاء التثبيت' : 'تثبيت الصفحة',
                  icon: Icon(
                    _doc.isPinned ? CupertinoIcons.pin_fill : CupertinoIcons.pin,
                    size: 18,
                    color: _doc.isPinned
                        ? const Color(0xFFF59E0B)
                        : (isDark ? Colors.white54 : Colors.black54),
                  ),
                  onPressed: () {
                    setState(() => _doc.isPinned = !_doc.isPinned);
                    _saveDoc();
                  },
                ),
                IconButton(
                  tooltip: _doc.isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
                  icon: Icon(
                    _doc.isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
                    size: 18,
                    color: _doc.isFavorite
                        ? const Color(0xFFF59E0B)
                        : (isDark ? Colors.white54 : Colors.black54),
                  ),
                  onPressed: () {
                    setState(() => _doc.isFavorite = !_doc.isFavorite);
                    _saveDoc();
                  },
                ),
                IconButton(
                  tooltip: 'نسخ المحتوى (Markdown)',
                  icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 18),
                  onPressed: _shareAsMarkdown,
                ),
                IconButton(
                  tooltip: 'إحصائيات وتفاصيل الصفحة',
                  icon: const Icon(CupertinoIcons.info_circle, size: 18),
                  onPressed: _showStatsDialog,
                ),
                if (widget.onDeleteDoc != null)
                  IconButton(
                    tooltip: 'حذف الصفحة',
                    icon: const Icon(CupertinoIcons.trash, size: 18, color: Colors.redAccent),
                    onPressed: widget.onDeleteDoc,
                  ),
              ],
            ),
          ),

          // Main Scrollable Notion Canvas
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 100),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Notion Cover + Overlapping Floating Emoji Icon
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GestureDetector(
                            onTap: _pickCoverColor,
                            child: Container(
                              height: 135,
                              margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: gradColors,
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              alignment: Alignment.topLeft,
                              padding: const EdgeInsets.all(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.28),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(CupertinoIcons.paintbrush_fill, color: Colors.white, size: 12),
                                    SizedBox(width: 5),
                                    Text(
                                      'تغيير الغلاف',
                                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: -30,
                            right: 44,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _pickIcon,
                              child: Tooltip(
                                message: 'اضغط لتغيير الأيقونة',
                                child: Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                      width: 3.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.12),
                                        blurRadius: 14,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(_doc.icon, style: const TextStyle(fontSize: 36)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 38),

                      // 2. Metadata Pills (Category + Task Progress + Word Count)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: _pickCategory,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: gradColors.first.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(CupertinoIcons.tag_fill, size: 12, color: gradColors.first),
                                    const SizedBox(width: 5),
                                    Text(
                                      _doc.category,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: gradColors.first,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.arrow_drop_down, size: 15, color: gradColors.first),
                                  ],
                                ),
                              ),
                            ),
                            if (totalTodos > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '☑️ $completedTodos من $totalTodos مهام مكتملة',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ),
                            Text(
                              '${_doc.wordCount} كلمة • ${_doc.blocks.length} عنصر',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 3. Page Title
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 14, 32, 8),
                        child: TextField(
                          controller: _titleController,
                          maxLines: null,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) {
                            if (_doc.blocks.isEmpty) {
                              _addBlock(WorkspaceBlockType.text);
                            } else {
                              _focusBlock(_doc.blocks.first.id);
                            }
                          },
                          onChanged: (val) {
                            _doc.title = val;
                            _saveDoc();
                          },
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            height: 1.25,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                          decoration: InputDecoration(
                            hintText: 'عنوان الصفحة...',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
                        child: Divider(
                          height: 1,
                          thickness: 0.6,
                          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                        ),
                      ),

                      // 4. Interactive Blocks
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: List.generate(_doc.blocks.length, (index) {
                            final block = _doc.blocks[index];
                            final currentNumber = block.type == WorkspaceBlockType.numbered
                                ? numberedCounter++
                                : 1;
                            if (block.type != WorkspaceBlockType.numbered) {
                              numberedCounter = 1;
                            }

                            return WorkspaceBlockWidget(
                              key: ValueKey(block.id),
                              block: block,
                              focusNode: _getFocusNode(block.id),
                              numberIndex: currentNumber,
                              isEditable: true,
                              isDark: isDark,
                              onChanged: _saveDoc,
                              onToggleTodo: () {
                                ref
                                    .read(workspaceDocsProvider.notifier)
                                    .toggleTodoItem(_doc.id, block.id);
                                setState(() {});
                              },
                              onInsertBelow: (type) =>
                                  _addBlock(type, insertAtIndex: index + 1),
                              onEnterPressed: (rem) => _handleEnterOnBlock(index, rem),
                              onDelete: () => _deleteBlock(index),
                              onMoveUp: index > 0 ? () => _moveBlock(index, -1) : null,
                              onMoveDown: index < _doc.blocks.length - 1
                                  ? () => _moveBlock(index, 1)
                                  : null,
                              onDuplicate: () => _duplicateBlock(index),
                              onTransformType: (type) => _transformBlockType(index, type),
                            );
                          }),
                        ),
                      ),

                      // 5. Click-to-append Empty Canvas Space
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _addBlock(WorkspaceBlockType.text),
                        child: Container(
                          height: 160,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                          alignment: Alignment.topRight,
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.plus_circle,
                                size: 16,
                                color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "اضغط هنا لإضافة سطر جديد، أو اكتب '/' لإدراج جدول أو قائمة...",
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 6. Floating Quick-Insert Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE2E8F0),
                  width: 0.8,
                ),
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildToolbarChip('مهمة ☑️', CupertinoIcons.checkmark_square, const Color(0xFF10B981), () => _addBlock(WorkspaceBlockType.todo), isDark),
                      _buildToolbarChip('جدول 📊', CupertinoIcons.table, const Color(0xFF059669), () => _addBlock(WorkspaceBlockType.table), isDark),
                      _buildToolbarChip('عنوان H1', CupertinoIcons.textformat, const Color(0xFF007AFF), () => _addBlock(WorkspaceBlockType.heading1), isDark),
                      _buildToolbarChip('عنوان H2', CupertinoIcons.textformat_size, const Color(0xFF5856D6), () => _addBlock(WorkspaceBlockType.heading2), isDark),
                      _buildToolbarChip('نقطة •', CupertinoIcons.list_bullet, const Color(0xFFF59E0B), () => _addBlock(WorkspaceBlockType.bullet), isDark),
                      _buildToolbarChip('ترقيم 1.', CupertinoIcons.list_number, const Color(0xFF0EA5E9), () => _addBlock(WorkspaceBlockType.numbered), isDark),
                      _buildToolbarChip('قائمة طي ▶', CupertinoIcons.chevron_down_square, const Color(0xFF6366F1), () => _addBlock(WorkspaceBlockType.toggle), isDark),
                      _buildToolbarChip('صندوق 💡', CupertinoIcons.lightbulb, const Color(0xFFD97706), () => _addBlock(WorkspaceBlockType.callout), isDark),
                      _buildToolbarChip('كود 💻', CupertinoIcons.chevron_left_slash_chevron_right, const Color(0xFF334155), () => _addBlock(WorkspaceBlockType.code), isDark),
                      _buildToolbarChip('اقتباس ❝', CupertinoIcons.quote_bubble, const Color(0xFFEC4899), () => _addBlock(WorkspaceBlockType.quote), isDark),
                      _buildToolbarChip('فاصل ──', CupertinoIcons.minus, const Color(0xFF94A3B8), () => _addBlock(WorkspaceBlockType.divider), isDark),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarChip(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                width: 0.7,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 5),
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
      ),
    );
  }
}
