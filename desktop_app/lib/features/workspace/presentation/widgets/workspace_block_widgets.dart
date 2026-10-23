import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/workspace_doc.dart';

class WorkspaceBlockWidget extends StatefulWidget {
  const WorkspaceBlockWidget({
    super.key,
    required this.block,
    this.focusNode,
    this.numberIndex = 1,
    required this.isEditable,
    required this.isDark,
    required this.onChanged,
    required this.onToggleTodo,
    required this.onDelete,
    this.onInsertBelow,
    this.onEnterPressed,
    this.onMoveUp,
    this.onMoveDown,
    this.onDuplicate,
    this.onTransformType,
  });

  final WorkspaceBlock block;
  final FocusNode? focusNode;
  final int numberIndex;
  final bool isEditable;
  final bool isDark;
  final VoidCallback onChanged;
  final VoidCallback onToggleTodo;
  final VoidCallback onDelete;
  final ValueChanged<WorkspaceBlockType>? onInsertBelow;
  final ValueChanged<String>? onEnterPressed;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onDuplicate;
  final ValueChanged<WorkspaceBlockType>? onTransformType;

  @override
  State<WorkspaceBlockWidget> createState() => _WorkspaceBlockWidgetState();
}

class _WorkspaceBlockWidgetState extends State<WorkspaceBlockWidget> {
  late TextEditingController _controller;
  late TextEditingController _subController;
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.content);
    _subController = TextEditingController(text: widget.block.subContent);
    widget.focusNode?.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!mounted) return;
    final focused = widget.focusNode?.hasFocus ?? false;
    if (_isFocused != focused) {
      setState(() => _isFocused = focused);
    }
  }

  @override
  void didUpdateWidget(covariant WorkspaceBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      widget.focusNode?.addListener(_onFocusChange);
    }
    if (oldWidget.block.id != widget.block.id ||
        (oldWidget.block.content != widget.block.content &&
            _controller.text != widget.block.content)) {
      _controller.value = TextEditingValue(
        text: widget.block.content,
        selection: TextSelection.collapsed(offset: widget.block.content.length),
      );
    }
    if (oldWidget.block.id != widget.block.id ||
        (oldWidget.block.subContent != widget.block.subContent &&
            _subController.text != widget.block.subContent)) {
      _subController.text = widget.block.subContent;
    }
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChange);
    _controller.dispose();
    _subController.dispose();
    super.dispose();
  }

  void _handleTextChanged(String val) {
    final block = widget.block;

    // 1. Detect Slash Command `/` on empty block
    if (val == '/' && block.type == WorkspaceBlockType.text) {
      _controller.clear();
      block.content = '';
      widget.onChanged();
      _showSlashCommandModal(context, replaceCurrent: true);
      return;
    }

    // 2. Detect Markdown live shortcuts at start of text
    if (block.type == WorkspaceBlockType.text) {
      if (val.startsWith('# ')) {
        _applyShortcut(WorkspaceBlockType.heading1, val.substring(2));
        return;
      } else if (val.startsWith('## ')) {
        _applyShortcut(WorkspaceBlockType.heading2, val.substring(3));
        return;
      } else if (val.startsWith('### ')) {
        _applyShortcut(WorkspaceBlockType.heading3, val.substring(4));
        return;
      } else if (val.startsWith('- ') || val.startsWith('* ')) {
        _applyShortcut(WorkspaceBlockType.bullet, val.substring(2));
        return;
      } else if (val.startsWith('1. ')) {
        _applyShortcut(WorkspaceBlockType.numbered, val.substring(3));
        return;
      } else if (val.startsWith('[] ') || val.startsWith('[ ] ')) {
        final rest = val.startsWith('[] ') ? val.substring(3) : val.substring(4);
        _applyShortcut(WorkspaceBlockType.todo, rest);
        return;
      } else if (val.startsWith('> ')) {
        _applyShortcut(WorkspaceBlockType.quote, val.substring(2));
        return;
      } else if (val == '---') {
        _controller.clear();
        block.content = '';
        widget.onTransformType?.call(WorkspaceBlockType.divider);
        widget.onEnterPressed?.call('');
        return;
      }
    }

    // 3. Detect Enter key in single-flow blocks
    if (block.type != WorkspaceBlockType.code &&
        val.contains('\n') &&
        widget.onEnterPressed != null) {
      final parts = val.split('\n');
      final firstLine = parts.first;
      final remainder = parts.sublist(1).join('\n');

      if (firstLine.trim().isEmpty &&
          remainder.trim().isEmpty &&
          (block.type == WorkspaceBlockType.todo ||
              block.type == WorkspaceBlockType.bullet ||
              block.type == WorkspaceBlockType.numbered ||
              block.type == WorkspaceBlockType.quote)) {
        _controller.clear();
        block.content = '';
        widget.onTransformType?.call(WorkspaceBlockType.text);
        return;
      }

      _controller.value = TextEditingValue(
        text: firstLine,
        selection: TextSelection.collapsed(offset: firstLine.length),
      );
      block.content = firstLine;
      widget.onChanged();
      widget.onEnterPressed!(remainder);
      return;
    }

    block.content = val;
    widget.onChanged();
  }

  void _applyShortcut(WorkspaceBlockType newType, String remainingText) {
    _controller.value = TextEditingValue(
      text: remainingText,
      selection: TextSelection.collapsed(offset: remainingText.length),
    );
    widget.block.content = remainingText;
    if (widget.onTransformType != null) {
      widget.onTransformType!(newType);
    } else {
      setState(() => widget.block.type = newType);
      widget.onChanged();
    }
  }

  void _showSlashCommandModal(BuildContext context, {bool replaceCurrent = false}) {
    final isDark = widget.isDark;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Container(
            width: 460,
            constraints: const BoxConstraints(maxHeight: 560),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          CupertinoIcons.sparkles,
                          size: 18,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        replaceCurrent ? 'تغيير نوع العنصر (/)' : 'إدراج عنصر جديد في الصفحة',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(CupertinoIcons.xmark_circle_fill, size: 20, color: Colors.grey),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.5),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    shrinkWrap: true,
                    children: [
                      _buildSectionHeader('النصوص والعناوين', isDark),
                      _buildSlashTile(ctx, WorkspaceBlockType.text, 'نص عادي (Paragraph)', 'كتابة فقرة نصية بسيطة', CupertinoIcons.text_alignright, const Color(0xFF64748B), replaceCurrent, isDark),
                      _buildSlashTile(ctx, WorkspaceBlockType.heading1, 'عنوان رئيسي كبير (H1)', 'اختصار: اكتب # ثم مسافة', CupertinoIcons.textformat, const Color(0xFF007AFF), replaceCurrent, isDark),
                      _buildSlashTile(ctx, WorkspaceBlockType.heading2, 'عنوان متوسط (H2)', 'اختصار: اكتب ## ثم مسافة', CupertinoIcons.textformat_size, const Color(0xFF5856D6), replaceCurrent, isDark),
                      _buildSlashTile(ctx, WorkspaceBlockType.heading3, 'عنوان فرعي (H3)', 'اختصار: اكتب ### ثم مسافة', CupertinoIcons.textformat_alt, const Color(0xFF8B5CF6), replaceCurrent, isDark),
                      const SizedBox(height: 10),
                      _buildSectionHeader('القوائم والمهام التفاعلية', isDark),
                      _buildSlashTile(ctx, WorkspaceBlockType.todo, 'قائمة مهام (To-do List)', 'اختصار: اكتب [] ثم مسافة', CupertinoIcons.checkmark_circle_fill, const Color(0xFF10B981), replaceCurrent, isDark),
                      _buildSlashTile(ctx, WorkspaceBlockType.bullet, 'قائمة نقطية (Bullet List)', 'اختصار: اكتب - ثم مسافة', CupertinoIcons.list_bullet, const Color(0xFFF59E0B), replaceCurrent, isDark),
                      _buildSlashTile(ctx, WorkspaceBlockType.numbered, 'قائمة مرقمة (1, 2, 3)', 'اختصار: اكتب 1. ثم مسافة', CupertinoIcons.list_number, const Color(0xFF0EA5E9), replaceCurrent, isDark),
                      _buildSlashTile(ctx, WorkspaceBlockType.toggle, 'قائمة قابلة للطي (Toggle)', 'عنوان يفتح ويغلق بداخله تفاصيل كاملة', CupertinoIcons.chevron_down_square_fill, const Color(0xFF6366F1), replaceCurrent, isDark),
                      const SizedBox(height: 10),
                      _buildSectionHeader('الجداول والعناصر المتقدمة', isDark),
                      _buildSlashTile(ctx, WorkspaceBlockType.table, 'جدول بيانات تفاعلي (Table)', 'صفوف وأعمدة قابلة للتعديل والإضافة', CupertinoIcons.table, const Color(0xFF059669), replaceCurrent, isDark),
                      _buildSlashTile(ctx, WorkspaceBlockType.callout, 'بطاقة ملاحظة ملونة (Callout)', 'إبراز تنبيه أو معلومة هامة بألوان وأيقونة', CupertinoIcons.lightbulb_fill, const Color(0xFFD97706), replaceCurrent, isDark),
                      _buildSlashTile(ctx, WorkspaceBlockType.quote, 'اقتباس مرجعي (Quote)', 'اختصار: اكتب > ثم مسافة', CupertinoIcons.quote_bubble_fill, const Color(0xFFEC4899), replaceCurrent, isDark),
                      _buildSlashTile(ctx, WorkspaceBlockType.code, 'صندوق كود / بيانات تقنية (Code)', 'لحفظ الأكواد، عناوين IP، والأوامر مع زر نسخ', CupertinoIcons.chevron_left_slash_chevron_right, const Color(0xFF334155), replaceCurrent, isDark),
                      _buildSlashTile(ctx, WorkspaceBlockType.divider, 'فاصل أفقي أنيق (Divider)', 'اختصار: اكتب ---', CupertinoIcons.minus, const Color(0xFF94A3B8), replaceCurrent, isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, right: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white38 : const Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _buildSlashTile(
    BuildContext ctx,
    WorkspaceBlockType type,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    bool replaceCurrent,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 11.5,
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
          ),
        ),
        onTap: () {
          Navigator.pop(ctx);
          if (replaceCurrent) {
            if (widget.onTransformType != null) {
              widget.onTransformType!(type);
            } else {
              setState(() => widget.block.type = type);
              widget.onChanged();
            }
          } else {
            widget.onInsertBelow?.call(type);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final isCardBlock = block.type == WorkspaceBlockType.callout ||
        block.type == WorkspaceBlockType.toggle ||
        block.type == WorkspaceBlockType.code ||
        block.type == WorkspaceBlockType.table ||
        block.type == WorkspaceBlockType.quote;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: EdgeInsets.symmetric(
          horizontal: isCardBlock ? 0 : 10,
          vertical: isCardBlock ? 2 : 3,
        ),
        decoration: BoxDecoration(
          color: (!isCardBlock && (_isFocused || _isHovered))
              ? (widget.isDark
                  ? Colors.white.withValues(alpha: _isFocused ? 0.035 : 0.02)
                  : const Color(0xFF007AFF).withValues(alpha: _isFocused ? 0.04 : 0.02))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildBlockContent(context, block)),
            if (widget.isEditable)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 140),
                opacity: (_isHovered || _isFocused) ? 1.0 : 0.0,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, right: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _showSlashCommandModal(context, replaceCurrent: false),
                        child: Tooltip(
                          message: 'إدراج عنصر بالأسفل (+)',
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: widget.isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              CupertinoIcons.plus,
                              size: 14,
                              color: widget.isDark ? Colors.white70 : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        tooltip: 'خيارات العنصر (تحويل، ترتيب، حذف)',
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            CupertinoIcons.ellipsis,
                            size: 14,
                            color: widget.isDark ? Colors.white70 : const Color(0xFF475569),
                          ),
                        ),
                        onSelected: (val) {
                          if (val == 'up') widget.onMoveUp?.call();
                          if (val == 'down') widget.onMoveDown?.call();
                          if (val == 'dup') widget.onDuplicate?.call();
                          if (val == 'transform') _showSlashCommandModal(context, replaceCurrent: true);
                          if (val == 'delete') widget.onDelete();
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'transform',
                            child: Row(
                              children: [
                                Icon(CupertinoIcons.arrow_2_squarepath, size: 16, color: Color(0xFF007AFF)),
                                SizedBox(width: 8),
                                Text('تغيير نوع العنصر...', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          if (widget.onMoveUp != null)
                            const PopupMenuItem(
                              value: 'up',
                              child: Row(
                                children: [
                                  Icon(CupertinoIcons.arrow_up, size: 16),
                                  SizedBox(width: 8),
                                  Text('تحريك لأعلى', style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                          if (widget.onMoveDown != null)
                            const PopupMenuItem(
                              value: 'down',
                              child: Row(
                                children: [
                                  Icon(CupertinoIcons.arrow_down, size: 16),
                                  SizedBox(width: 8),
                                  Text('تحريك لأسفل', style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                          if (widget.onDuplicate != null)
                            const PopupMenuItem(
                              value: 'dup',
                              child: Row(
                                children: [
                                  Icon(CupertinoIcons.plus_square_on_square, size: 16),
                                  SizedBox(width: 8),
                                  Text('تكرار العنصر', style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(CupertinoIcons.trash, size: 16, color: Colors.redAccent),
                                SizedBox(width: 8),
                                Text('حذف العنصر', style: TextStyle(fontSize: 13, color: Colors.redAccent)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockContent(BuildContext context, WorkspaceBlock block) {
    switch (block.type) {
      case WorkspaceBlockType.heading1:
        return _buildHeading(
          context,
          fontSize: 24,
          fontWeight: FontWeight.w900,
          hint: 'عنوان رئيسي للقسم...',
          topPad: 14,
          accentColor: const Color(0xFF007AFF),
          showBottomLine: true,
        );
      case WorkspaceBlockType.heading2:
        return _buildHeading(
          context,
          fontSize: 19.5,
          fontWeight: FontWeight.w800,
          hint: 'عنوان فرعي متوسط...',
          topPad: 10,
          accentColor: const Color(0xFF5856D6),
        );
      case WorkspaceBlockType.heading3:
        return _buildHeading(
          context,
          fontSize: 16.5,
          fontWeight: FontWeight.w700,
          hint: 'عنوان فرعي صغير...',
          topPad: 6,
          accentColor: const Color(0xFF8B5CF6),
        );
      case WorkspaceBlockType.todo:
        return _buildTodo(context);
      case WorkspaceBlockType.bullet:
        return _buildBullet(context);
      case WorkspaceBlockType.numbered:
        return _buildNumbered(context);
      case WorkspaceBlockType.callout:
        return _buildCallout(context);
      case WorkspaceBlockType.quote:
        return _buildQuote(context);
      case WorkspaceBlockType.code:
        return _buildCode(context);
      case WorkspaceBlockType.toggle:
        return _buildToggle(context);
      case WorkspaceBlockType.table:
        return _buildTable(context);
      case WorkspaceBlockType.divider:
        return _buildDivider(context);
      case WorkspaceBlockType.text:
        return _buildParagraph(context);
    }
  }

  Widget _buildHeading(
    BuildContext context, {
    required double fontSize,
    required FontWeight fontWeight,
    required String hint,
    required double topPad,
    required Color accentColor,
    bool showBottomLine = false,
  }) {
    final isDark = widget.isDark;
    return Padding(
      padding: EdgeInsets.only(top: topPad, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: fontSize * 0.95,
                margin: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  onChanged: _handleTextChanged,
                  maxLines: null,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    letterSpacing: -0.3,
                    height: 1.3,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                      fontSize: fontSize,
                      fontWeight: fontWeight,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          if (showBottomLine)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Divider(
                height: 1,
                thickness: 0.8,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFE2E8F0),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildParagraph(BuildContext context) {
    final isDark = widget.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: _controller,
        focusNode: widget.focusNode,
        onChanged: _handleTextChanged,
        maxLines: null,
        style: TextStyle(
          fontSize: 15.5,
          height: 1.65,
          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
        ),
        decoration: InputDecoration(
          hintText: "اكتب ملاحظتك هنا، أو اكتب '/' لإدراج مهمة أو جدول أو عنوان...",
          hintStyle: TextStyle(
            color: isDark ? Colors.white24 : const Color(0xFF94A3B8),
            fontSize: 14.5,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildTodo(BuildContext context) {
    final isDark = widget.isDark;
    final block = widget.block;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.symmetric(vertical: 2.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: block.isChecked
            ? (isDark
                ? const Color(0xFF10B981).withValues(alpha: 0.08)
                : const Color(0xFFECFDF5).withValues(alpha: 0.75))
            : (isDark
                ? Colors.white.withValues(alpha: 0.03)
                : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: block.isChecked
              ? const Color(0xFF10B981).withValues(alpha: 0.25)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFE2E8F0)),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: widget.onToggleTodo,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(top: 1, left: 10),
              width: 21,
              height: 21,
              decoration: BoxDecoration(
                color: block.isChecked
                    ? const Color(0xFF10B981)
                    : (isDark ? const Color(0xFF1E293B) : Colors.white),
                shape: BoxShape.circle,
                border: Border.all(
                  color: block.isChecked
                      ? const Color(0xFF10B981)
                      : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                  width: 1.8,
                ),
                boxShadow: block.isChecked
                    ? [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : null,
              ),
              child: block.isChecked
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              onChanged: _handleTextChanged,
              maxLines: null,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                fontWeight: block.isChecked ? FontWeight.w500 : FontWeight.w600,
                decoration: block.isChecked ? TextDecoration.lineThrough : null,
                color: block.isChecked
                    ? (isDark ? Colors.white38 : const Color(0xFF94A3B8))
                    : (isDark ? Colors.white : const Color(0xFF0F172A)),
              ),
              decoration: InputDecoration(
                hintText: 'مهمة جديدة (اضغط Enter لإضافة مهمة تالية)...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                  fontSize: 14.5,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBullet(BuildContext context) {
    final isDark = widget.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, left: 10, right: 4),
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF007AFF),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              onChanged: _handleTextChanged,
              maxLines: null,
              style: TextStyle(
                fontSize: 15.5,
                height: 1.5,
                color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
              ),
              decoration: InputDecoration(
                hintText: 'عنصر قائمة نقطية (اضغط Enter للبند التالي)...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                  fontSize: 14.5,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumbered(BuildContext context) {
    final isDark = widget.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2, left: 10),
            padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '${widget.numberIndex}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF007AFF),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              onChanged: _handleTextChanged,
              maxLines: null,
              style: TextStyle(
                fontSize: 15.5,
                height: 1.5,
                color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
              ),
              decoration: InputDecoration(
                hintText: 'خطوة مرقمة (اضغط Enter للخطوة التالية)...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                  fontSize: 14.5,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, Color> _resolveCalloutPalette(String colorKey, bool isDark) {
    switch (colorKey) {
      case 'green':
        return {
          'bg': isDark ? const Color(0xFF064E3B).withValues(alpha: 0.35) : const Color(0xFFECFDF5),
          'border': isDark ? const Color(0xFF10B981).withValues(alpha: 0.3) : const Color(0xFFA7F3D0),
          'dot': const Color(0xFF10B981),
        };
      case 'amber':
        return {
          'bg': isDark ? const Color(0xFF78350F).withValues(alpha: 0.35) : const Color(0xFFFFFBEB),
          'border': isDark ? const Color(0xFFF59E0B).withValues(alpha: 0.3) : const Color(0xFFFDE68A),
          'dot': const Color(0xFFF59E0B),
        };
      case 'purple':
        return {
          'bg': isDark ? const Color(0xFF4C1D95).withValues(alpha: 0.35) : const Color(0xFFF5F3FF),
          'border': isDark ? const Color(0xFF8B5CF6).withValues(alpha: 0.3) : const Color(0xFFDDD6FE),
          'dot': const Color(0xFF8B5CF6),
        };
      case 'rose':
        return {
          'bg': isDark ? const Color(0xFF881337).withValues(alpha: 0.35) : const Color(0xFFFFF1F2),
          'border': isDark ? const Color(0xFFF43F5E).withValues(alpha: 0.3) : const Color(0xFFFECDD3),
          'dot': const Color(0xFFF43F5E),
        };
      case 'blue':
      default:
        return {
          'bg': isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.32) : const Color(0xFFEFF6FF),
          'border': isDark ? const Color(0xFF3B82F6).withValues(alpha: 0.3) : const Color(0xFFBFDBFE),
          'dot': const Color(0xFF007AFF),
        };
    }
  }

  Widget _buildCallout(BuildContext context) {
    final isDark = widget.isDark;
    final block = widget.block;
    final palette = _resolveCalloutPalette(block.colorHex, isDark);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette['bg'],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette['border']!, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              const emojis = ['💡', '🎯', '⚠️', '📌', '🚀', '✅', '🧾', '🔥', '💬', '⭐'];
              final curIdx = emojis.indexOf(block.calloutIcon);
              setState(() {
                block.calloutIcon = emojis[(curIdx + 1) % emojis.length];
              });
              widget.onChanged();
            },
            child: Tooltip(
              message: 'اضغط لتغيير الأيقونة',
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(block.calloutIcon, style: const TextStyle(fontSize: 20)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              onChanged: (val) {
                block.content = val;
                widget.onChanged();
              },
              maxLines: null,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.55,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'اكتب ملاحظة بارزة أو تنبيه هام...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 14,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.only(top: 6),
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              const colors = ['blue', 'green', 'amber', 'purple', 'rose'];
              final idx = colors.indexOf(block.colorHex);
              setState(() {
                block.colorHex = colors[(idx + 1) % colors.length];
              });
              widget.onChanged();
            },
            child: Tooltip(
              message: 'تغيير لون الصندوق',
              child: Container(
                margin: const EdgeInsets.only(top: 8, right: 4),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: palette['dot'],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuote(BuildContext context) {
    final isDark = widget.isDark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(14), right: Radius.circular(4)),
        border: const Border(
          right: BorderSide(
            color: Color(0xFF007AFF),
            width: 4,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.quote_bubble_fill,
            size: 16,
            color: const Color(0xFF007AFF).withValues(alpha: 0.45),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              onChanged: _handleTextChanged,
              maxLines: null,
              style: TextStyle(
                fontSize: 15,
                height: 1.55,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : const Color(0xFF334155),
              ),
              decoration: InputDecoration(
                hintText: 'اكتب اقتباساً أو ملاحظة مرجعية...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                  fontSize: 14.5,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCode(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFFF5F56), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFFFBD2E), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF27C93F), shape: BoxShape.circle)),
              const SizedBox(width: 10),
              const Text(
                'CODE / TERMINAL',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _controller.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم نسخ النص البرمجي إلى الحافظة ✓'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.doc_on_doc, size: 12, color: Colors.white70),
                      SizedBox(width: 4),
                      Text('نسخ الكود', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              onChanged: (val) {
                widget.block.content = val;
                widget.onChanged();
              },
              maxLines: null,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.5,
                fontFamily: 'Consolas',
                color: Color(0xFF38BDF8),
              ),
              decoration: const InputDecoration(
                hintText: 'Write code, IP address, or command...',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(BuildContext context) {
    final isDark = widget.isDark;
    final block = widget.block;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    setState(() {
                      block.isExpanded = !block.isExpanded;
                    });
                    widget.onChanged();
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      block.isExpanded
                          ? CupertinoIcons.chevron_down
                          : CupertinoIcons.chevron_back,
                      size: 14,
                      color: const Color(0xFF007AFF),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: widget.focusNode,
                    onChanged: (val) {
                      block.content = val;
                      widget.onChanged();
                    },
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    decoration: InputDecoration(
                      hintText: 'عنوان القسم القابل للطي...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                        fontSize: 14.5,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (block.isExpanded)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 18, 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    width: 0.6,
                  ),
                ),
              ),
              child: TextField(
                controller: _subController,
                onChanged: (val) {
                  block.subContent = val;
                  widget.onChanged();
                },
                maxLines: null,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                ),
                decoration: InputDecoration(
                  hintText: 'اكتب التفاصيل والبنود الفرعية داخل هذا القسم...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white24 : const Color(0xFF94A3B8),
                    fontSize: 13.5,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final isDark = widget.isDark;
    final block = widget.block;
    if (block.tableData.isEmpty) {
      block.tableData = [
        ['العمود 1', 'العمود 2', 'العمود 3'],
        ['', '', ''],
      ];
    }
    final rows = block.tableData;
    final colCount = rows.first.length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: List.generate(rows.length, (rIdx) {
              final isHeader = rIdx == 0;
              return Container(
                decoration: BoxDecoration(
                  color: isHeader
                      ? (isDark
                          ? const Color(0xFF007AFF).withValues(alpha: 0.14)
                          : const Color(0xFFF1F5F9))
                      : Colors.transparent,
                  border: rIdx < rows.length - 1
                      ? Border(
                          bottom: BorderSide(
                            color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                          ),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    ...List.generate(colCount, (cIdx) {
                      return Expanded(
                        child: Container(
                          decoration: cIdx < colCount - 1
                              ? BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                )
                              : null,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          child: TextFormField(
                            key: ValueKey('${block.id}_r${rIdx}_c$cIdx'),
                            initialValue: rows[rIdx][cIdx],
                            onChanged: (val) {
                              rows[rIdx][cIdx] = val;
                              widget.onChanged();
                            },
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: isHeader ? FontWeight.w800 : FontWeight.w500,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              hintText: isHeader ? 'عنوان العمود...' : 'اكتب هنا...',
                              hintStyle: TextStyle(
                                color: isDark ? Colors.white24 : Colors.black26,
                                fontSize: 12.5,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      );
                    }),
                    if (!isHeader && rows.length > 2)
                      IconButton(
                        tooltip: 'حذف الصف',
                        icon: const Icon(CupertinoIcons.minus_circle, size: 16, color: Colors.redAccent),
                        onPressed: () {
                          setState(() {
                            rows.removeAt(rIdx);
                          });
                          widget.onChanged();
                        },
                      ),
                  ],
                ),
              );
            }),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF).withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(CupertinoIcons.add, size: 13, color: Color(0xFF007AFF)),
                  label: const Text('إضافة صف جديد', style: TextStyle(fontSize: 12, color: Color(0xFF007AFF), fontWeight: FontWeight.w700)),
                  onPressed: () {
                    setState(() {
                      rows.add(List<String>.filled(colCount, '', growable: true));
                    });
                    widget.onChanged();
                  },
                ),
                const SizedBox(width: 10),
                if (colCount < 6)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF5856D6).withValues(alpha: 0.08),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(CupertinoIcons.add_circled, size: 13, color: Color(0xFF5856D6)),
                    label: const Text('إضافة عمود', style: TextStyle(fontSize: 12, color: Color(0xFF5856D6), fontWeight: FontWeight.w700)),
                    onPressed: () {
                      setState(() {
                        for (var i = 0; i < rows.length; i++) {
                          rows[i] = List<String>.from(rows[i], growable: true)
                            ..add(i == 0 ? 'عمود ${rows[i].length + 1}' : '');
                        }
                      });
                      widget.onChanged();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    final isDark = widget.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              CupertinoIcons.sparkles,
              size: 12,
              color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
            ),
          ),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
            ),
          ),
        ],
      ),
    );
  }
}
