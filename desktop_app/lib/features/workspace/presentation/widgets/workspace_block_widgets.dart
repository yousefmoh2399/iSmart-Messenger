import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/workspace_doc.dart';

class WorkspaceBlockWidget extends StatefulWidget {
  const WorkspaceBlockWidget({
    super.key,
    required this.block,
    this.numberIndex = 1,
    required this.isEditable,
    required this.isDark,
    required this.onChanged,
    required this.onToggleTodo,
    required this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
    this.onDuplicate,
    this.onTransformType,
  });

  final WorkspaceBlock block;
  final int numberIndex;
  final bool isEditable;
  final bool isDark;
  final VoidCallback onChanged;
  final VoidCallback onToggleTodo;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onDuplicate;
  final ValueChanged<WorkspaceBlockType>? onTransformType;

  @override
  State<WorkspaceBlockWidget> createState() => _WorkspaceBlockWidgetState();
}

class _WorkspaceBlockWidgetState extends State<WorkspaceBlockWidget> {
  late TextEditingController _controller;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.content);
  }

  @override
  void didUpdateWidget(covariant WorkspaceBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.id != widget.block.id ||
        (oldWidget.block.content != widget.block.content &&
            _controller.text != widget.block.content)) {
      _controller.text = widget.block.content;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChange(String val) {
    widget.block.content = val;
    widget.onChanged();
  }

  void _showTransformDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('تحويل الكتلة إلى نوع آخر', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTransformTile(ctx, WorkspaceBlockType.text, 'نص فقرة عادية', CupertinoIcons.text_quote),
                _buildTransformTile(ctx, WorkspaceBlockType.heading1, 'عنوان رئيسي H1', CupertinoIcons.textformat),
                _buildTransformTile(ctx, WorkspaceBlockType.heading2, 'عنوان فرعي H2', CupertinoIcons.textformat_size),
                _buildTransformTile(ctx, WorkspaceBlockType.todo, 'مهمة فحص ☑️', CupertinoIcons.check_mark_circled),
                _buildTransformTile(ctx, WorkspaceBlockType.bullet, 'نقطة •', CupertinoIcons.list_bullet),
                _buildTransformTile(ctx, WorkspaceBlockType.numbered, 'قائمة مرقمة 1.', CupertinoIcons.list_number),
                _buildTransformTile(ctx, WorkspaceBlockType.callout, 'صندوق مميز 💡', CupertinoIcons.lightbulb),
                _buildTransformTile(ctx, WorkspaceBlockType.quote, 'اقتباس ❝', CupertinoIcons.quote_bubble),
                _buildTransformTile(ctx, WorkspaceBlockType.code, 'كتلة نص برمجي/أوامر 💻', CupertinoIcons.chevron_left_slash_chevron_right),
                _buildTransformTile(ctx, WorkspaceBlockType.toggle, 'قائمة قابلة للطي ▶', CupertinoIcons.arrowtriangle_right_fill),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransformTile(BuildContext ctx, WorkspaceBlockType type, String title, IconData icon) {
    return ListTile(
      leading: Icon(icon, size: 18, color: const Color(0xFF5856D6)),
      title: Text(title, style: const TextStyle(fontSize: 13.5)),
      dense: true,
      onTap: () {
        Navigator.pop(ctx);
        if (widget.onTransformType != null) {
          widget.onTransformType!(type);
        } else {
          setState(() {
            widget.block.type = type;
          });
          widget.onChanged();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Content
            Expanded(child: _buildBlockContent(context, block)),

            // Desktop Hover Action Handle
            if (widget.isEditable && block.type != WorkspaceBlockType.divider)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _isHovered ? 0.8 : 0.0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onMoveUp != null)
                      IconButton(
                        icon: const Icon(CupertinoIcons.chevron_up, size: 14),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                        tooltip: 'تحريك لأعلى',
                        onPressed: widget.onMoveUp,
                      ),
                    if (widget.onMoveDown != null)
                      IconButton(
                        icon: const Icon(CupertinoIcons.chevron_down, size: 14),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                        tooltip: 'تحريك لأسفل',
                        onPressed: widget.onMoveDown,
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz_rounded, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      tooltip: 'خيارات الكتلة',
                      onSelected: (val) {
                        if (val == 'up') widget.onMoveUp?.call();
                        if (val == 'down') widget.onMoveDown?.call();
                        if (val == 'dup') widget.onDuplicate?.call();
                        if (val == 'transform') _showTransformDialog(context);
                        if (val == 'delete') widget.onDelete();
                      },
                      itemBuilder: (ctx) => [
                        if (widget.onMoveUp != null)
                          const PopupMenuItem(
                            value: 'up',
                            child: Row(children: [Icon(CupertinoIcons.arrow_up, size: 16), SizedBox(width: 8), Text('تحريك لأعلى')]),
                          ),
                        if (widget.onMoveDown != null)
                          const PopupMenuItem(
                            value: 'down',
                            child: Row(children: [Icon(CupertinoIcons.arrow_down, size: 16), SizedBox(width: 8), Text('تحريك لأسفل')]),
                          ),
                        if (widget.onDuplicate != null)
                          const PopupMenuItem(
                            value: 'dup',
                            child: Row(children: [Icon(CupertinoIcons.plus_square_on_square, size: 16), SizedBox(width: 8), Text('تكرار الكتلة')]),
                          ),
                        const PopupMenuItem(
                          value: 'transform',
                          child: Row(children: [Icon(CupertinoIcons.arrow_2_squarepath, size: 16), SizedBox(width: 8), Text('تحويل إلى نوع آخر...')]),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [Icon(CupertinoIcons.trash, size: 16, color: Colors.red), SizedBox(width: 8), Text('حذف الكتلة', style: TextStyle(color: Colors.red))]),
                        ),
                      ],
                    ),
                  ],
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
        return _buildHeading(context, fontSize: 24, fontWeight: FontWeight.w800);
      case WorkspaceBlockType.heading2:
        return _buildHeading(context, fontSize: 19, fontWeight: FontWeight.w700);
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
      case WorkspaceBlockType.divider:
        return _buildDivider(context);
      case WorkspaceBlockType.text:
        return _buildParagraph(context);
    }
  }

  Widget _buildHeading(BuildContext context, {required double fontSize, required FontWeight fontWeight}) {
    final isDark = widget.isDark;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: TextFormField(
        controller: _controller,
        onChanged: _onTextChange,
        maxLines: null,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: -0.3,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          hintText: widget.block.type == WorkspaceBlockType.heading1 ? 'عنوان رئيسي H1...' : 'عنوان فرعي H2...',
          hintStyle: TextStyle(
            color: isDark ? Colors.white30 : Colors.black26,
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildParagraph(BuildContext context) {
    final isDark = widget.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextFormField(
        controller: _controller,
        onChanged: _onTextChange,
        maxLines: null,
        style: TextStyle(
          fontSize: 15,
          height: 1.55,
          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
        ),
        decoration: InputDecoration(
          hintText: 'اكتب نصاً، أو أدرج كتلة جديدة من الشريط أدناه...',
          hintStyle: TextStyle(
            color: isDark ? Colors.white24 : Colors.black26,
            fontSize: 15,
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: widget.onToggleTodo,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(top: 3, left: 8),
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                color: block.isChecked
                    ? const Color(0xFF5856D6)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: block.isChecked
                      ? const Color(0xFF5856D6)
                      : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                  width: 1.6,
                ),
              ),
              child: block.isChecked
                  ? const Icon(
                      Icons.check_rounded,
                      size: 13,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: _controller,
              onChanged: _onTextChange,
              maxLines: null,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                decoration: block.isChecked ? TextDecoration.lineThrough : null,
                color: block.isChecked
                    ? (isDark ? Colors.white38 : const Color(0xFF94A3B8))
                    : (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B)),
              ),
              decoration: InputDecoration(
                hintText: 'مهمة جديدة...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white24 : Colors.black26,
                  fontSize: 15,
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
          Padding(
            padding: const EdgeInsets.only(top: 7, left: 10, right: 2),
            child: Container(
              width: 5.5,
              height: 5.5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white70 : const Color(0xFF475569),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: _controller,
              onChanged: _onTextChange,
              maxLines: null,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
              ),
              decoration: InputDecoration(
                hintText: 'نقطة...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white24 : Colors.black26,
                  fontSize: 15,
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
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 8, right: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${widget.numberIndex}.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                ),
              ),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: _controller,
              onChanged: _onTextChange,
              maxLines: null,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
              ),
              decoration: InputDecoration(
                hintText: 'عنصر في قائمة مرقمة...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white24 : Colors.black26,
                  fontSize: 15,
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

  Widget _buildCallout(BuildContext context) {
    final isDark = widget.isDark;
    final block = widget.block;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.6)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              final emojis = ['💡', '🎯', '⚠️', '📌', '🚀', '✅', '💬', '🔥'];
              final curIdx = emojis.indexOf(block.calloutIcon);
              final nextEmoji = emojis[(curIdx + 1) % emojis.length];
              setState(() {
                block.calloutIcon = nextEmoji;
              });
              widget.onChanged();
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Text(
                block.calloutIcon,
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _controller,
              onChanged: _onTextChange,
              maxLines: null,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'ملاحظة مميزة أو تنبيه هام...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white30 : Colors.black38,
                  fontSize: 14,
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

  Widget _buildQuote(BuildContext context) {
    final isDark = widget.isDark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.only(right: 12, top: 4, bottom: 4),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Color(0xFF5856D6),
            width: 3.5,
          ),
        ),
      ),
      child: TextFormField(
        controller: _controller,
        onChanged: _onTextChange,
        maxLines: null,
        style: TextStyle(
          fontSize: 15,
          height: 1.55,
          fontStyle: FontStyle.italic,
          color: isDark ? Colors.white70 : const Color(0xFF334155),
        ),
        decoration: InputDecoration(
          hintText: 'اقتباس أو نص مقتبس...',
          hintStyle: TextStyle(
            color: isDark ? Colors.white24 : Colors.black26,
            fontSize: 15,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildCode(BuildContext context) {
    final isDark = widget.isDark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.code_rounded, color: Colors.white54, size: 14),
              const SizedBox(width: 6),
              const Text(
                'نص برمجي / أمر نظام',
                style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _controller.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم نسخ الكود للحافظة'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_rounded, size: 12, color: Colors.white70),
                      SizedBox(width: 4),
                      Text('نسخ', style: TextStyle(color: Colors.white70, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _controller,
            onChanged: _onTextChange,
            maxLines: null,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              fontFamily: 'monospace',
              color: Color(0xFF38BDF8),
            ),
            decoration: const InputDecoration(
              hintText: 'اكتب كود أو رقم أو نص تقني...',
              hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
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
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    block.isExpanded = !block.isExpanded;
                  });
                  widget.onChanged();
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, left: 6, right: 2),
                  child: Icon(
                    block.isExpanded
                        ? CupertinoIcons.arrowtriangle_down_fill
                        : CupertinoIcons.arrowtriangle_right_fill,
                    size: 13,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: _controller,
                  onChanged: _onTextChange,
                  maxLines: null,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    hintText: 'عنوان قائمة الطي...',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white24 : Colors.black26,
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
              ),
            ],
          ),
          if (block.isExpanded)
            Padding(
              padding: const EdgeInsets.only(right: 24, left: 12, bottom: 8),
              child: Text(
                'يمكنك إضافة بنود أو ملاحظات تحت هذا العنوان للطي والتوسيع.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    final isDark = widget.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Divider(
        height: 1,
        thickness: 0.8,
        color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
      ),
    );
  }
}
