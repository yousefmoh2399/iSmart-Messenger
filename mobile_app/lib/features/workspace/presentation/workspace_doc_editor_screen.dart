import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  static const List<String> _popularIcons = [
    '📝', '💡', '🎯', '📋', '🚀', '📌', '💼', '📊',
    '🛠️', '🧾', '👥', '✨', '🏢', '⚡', '🔍', '⭐',
  ];

  static const List<Map<String, dynamic>> _coverPresets = [
    {'color': '0xFFE0F2FE', 'name': 'سماوي'},
    {'color': '0xFFDCFCE7', 'name': 'أخضر'},
    {'color': '0xFFFEF3C7', 'name': 'أصفر'},
    {'color': '0xFFF3E8FF', 'name': 'بنفسجي'},
    {'color': '0xFFFCE7F3', 'name': 'وردي'},
    {'color': '0xFFF1F5F9', 'name': 'رمادي'},
    {'color': '0xFF1E293B', 'name': 'ليلي'},
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
    super.dispose();
  }

  void _saveDoc() {
    ref.read(workspaceDocsProvider.notifier).updateDoc(_doc);
    setState(() {});
  }

  void _addBlock(WorkspaceBlockType type) {
    HapticFeedback.lightImpact();
    setState(() {
      _doc.blocks.add(
        WorkspaceBlock(
          type: type,
          content: '',
        ),
      );
    });
    _saveDoc();
  }

  void _pickIcon() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اختر أيقونة الصفحة',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _popularIcons.map((emoji) {
                    final isSelected = _doc.icon == emoji;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _doc.icon = emoji;
                        });
                        _saveDoc();
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark ? Colors.white24 : const Color(0xFFE2E8F0))
                              : (isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF8FAFC)),
                          borderRadius: BorderRadius.circular(10),
                          border: isSelected
                              ? Border.all(color: const Color(0xFF007AFF), width: 2)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(emoji, style: const TextStyle(fontSize: 22)),
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'لون غلاف الصفحة',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: _coverPresets.map((preset) {
                    final hexStr = preset['color'] as String;
                    final colorVal = Color(int.parse(hexStr));
                    final isSelected = _doc.coverColor == hexStr;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _doc.coverColor = hexStr;
                        });
                        _saveDoc();
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: colorVal,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? const Color(0xFF007AFF) : Colors.black12,
                            width: isSelected ? 3 : 1,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 20, color: Color(0xFF007AFF))
                            : null,
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تصنيف المستند',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 12),
                ..._categories.map((cat) {
                  final isSelected = _doc.category == cat;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(cat, style: TextStyle(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
                    trailing: isSelected ? const Icon(Icons.check_rounded, color: Color(0xFF007AFF)) : null,
                    onTap: () {
                      setState(() {
                        _doc.category = cat;
                      });
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

  void _shareAsText() {
    HapticFeedback.lightImpact();
    final buffer = StringBuffer();
    buffer.writeln('${_doc.icon} ${_doc.title}');
    buffer.writeln('---------------------------');
    for (final b in _doc.blocks) {
      if (b.type == WorkspaceBlockType.heading1) {
        buffer.writeln('\n## ${b.content}');
      } else if (b.type == WorkspaceBlockType.heading2) {
        buffer.writeln('\n### ${b.content}');
      } else if (b.type == WorkspaceBlockType.todo) {
        buffer.writeln('${b.isChecked ? '[x]' : '[ ]'} ${b.content}');
      } else if (b.type == WorkspaceBlockType.bullet) {
        buffer.writeln('• ${b.content}');
      } else if (b.type == WorkspaceBlockType.callout) {
        buffer.writeln('> ${b.calloutIcon} ${b.content}');
      } else if (b.type == WorkspaceBlockType.quote) {
        buffer.writeln('> ${b.content}');
      } else if (b.type == WorkspaceBlockType.divider) {
        buffer.writeln('\n---\n');
      } else {
        buffer.writeln(b.content);
      }
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ نص المستند كاملاً إلى الحافظة للمشاركة!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final coverColorVal = Color(int.tryParse(_doc.coverColor) ?? 0xFFE2E8F0);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF161618) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_back, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Text(_doc.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _doc.title.trim().isNotEmpty ? _doc.title : 'بدون عنوان',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _doc.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              size: 20,
              color: _doc.isPinned ? const Color(0xFFF59E0B) : (isDark ? Colors.white60 : Colors.black54),
            ),
            tooltip: _doc.isPinned ? 'إلغاء التثبيت' : 'تثبيت في الأعلى',
            onPressed: () {
              setState(() {
                _doc.isPinned = !_doc.isPinned;
              });
              _saveDoc();
            },
          ),
          IconButton(
            icon: Icon(
              _doc.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              size: 20,
              color: _doc.isFavorite ? const Color(0xFFF59E0B) : (isDark ? Colors.white60 : Colors.black54),
            ),
            tooltip: _doc.isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
            onPressed: () {
              setState(() {
                _doc.isFavorite = !_doc.isFavorite;
              });
              _saveDoc();
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 20),
            tooltip: 'نسخ ومشاركة',
            onPressed: _shareAsText,
          ),
        ],
      ),
      body: Column(
        children: [
          // Content Editor Scrollable
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Cover Banner (Notion style)
                  GestureDetector(
                    onTap: _pickCoverColor,
                    child: Container(
                      height: 70,
                      decoration: BoxDecoration(
                        color: coverColorVal,
                      ),
                      alignment: Alignment.bottomLeft,
                      padding: const EdgeInsets.all(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'تغيير الغلاف 🎨',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),

                  // 2. Icon & Category header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Big Emoji Icon
                        GestureDetector(
                          onTap: _pickIcon,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _doc.icon,
                              style: const TextStyle(fontSize: 32),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Category pill
                        GestureDetector(
                          onTap: _pickCategory,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _doc.category,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_drop_down, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. Document Title
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: TextFormField(
                      controller: _titleController,
                      maxLines: null,
                      onChanged: (val) {
                        _doc.title = val;
                        _saveDoc();
                      },
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                      decoration: InputDecoration(
                        hintText: 'عنوان الصفحة...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white24 : Colors.black26,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(height: 1, thickness: 0.5),
                  ),
                  const SizedBox(height: 8),

                  // 4. Interactive Notion Blocks
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List.generate(_doc.blocks.length, (index) {
                        final block = _doc.blocks[index];
                        return Dismissible(
                          key: ValueKey(block.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            color: Colors.red.withValues(alpha: 0.15),
                            child: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          ),
                          onDismissed: (_) {
                            setState(() {
                              _doc.blocks.removeAt(index);
                            });
                            _saveDoc();
                          },
                          child: WorkspaceBlockWidget(
                            block: block,
                            isEditable: true,
                            isDark: isDark,
                            onChanged: _saveDoc,
                            onToggleTodo: () {
                              ref
                                  .read(workspaceDocsProvider.notifier)
                                  .toggleTodoItem(_doc.id, block.id);
                              setState(() {});
                            },
                            onDelete: () {
                              setState(() {
                                _doc.blocks.removeAt(index);
                              });
                              _saveDoc();
                            },
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // -----------------------------------------------------------------
          // 5. NOTION QUICK-INSERT TOOLBAR (Bottom Bar)
          // -----------------------------------------------------------------
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161618) : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                  width: 0.8,
                ),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildInsertChip('نص', Icons.short_text_rounded, () => _addBlock(WorkspaceBlockType.text), isDark),
                  _buildInsertChip('مهمة ☑️', Icons.check_box_outlined, () => _addBlock(WorkspaceBlockType.todo), isDark),
                  _buildInsertChip('عنوان H1', Icons.title_rounded, () => _addBlock(WorkspaceBlockType.heading1), isDark),
                  _buildInsertChip('عنوان H2', Icons.format_size_rounded, () => _addBlock(WorkspaceBlockType.heading2), isDark),
                  _buildInsertChip('نقطة •', Icons.format_list_bulleted_rounded, () => _addBlock(WorkspaceBlockType.bullet), isDark),
                  _buildInsertChip('صندوق 💡', Icons.lightbulb_outline_rounded, () => _addBlock(WorkspaceBlockType.callout), isDark),
                  _buildInsertChip('اقتباس ❝', Icons.format_quote_rounded, () => _addBlock(WorkspaceBlockType.quote), isDark),
                  _buildInsertChip('فاصل ──', Icons.horizontal_rule_rounded, () => _addBlock(WorkspaceBlockType.divider), isDark),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsertChip(String label, IconData icon, VoidCallback onTap, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: const Color(0xFF007AFF)),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
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
