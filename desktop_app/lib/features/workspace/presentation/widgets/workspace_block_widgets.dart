import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../models/workspace_doc.dart';

class WorkspaceBlockWidget extends StatelessWidget {
  const WorkspaceBlockWidget({
    super.key,
    required this.block,
    required this.isEditable,
    required this.isDark,
    required this.onChanged,
    required this.onToggleTodo,
    required this.onDelete,
  });

  final WorkspaceBlock block;
  final bool isEditable;
  final bool isDark;
  final VoidCallback onChanged;
  final VoidCallback onToggleTodo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    switch (block.type) {
      case WorkspaceBlockType.heading1:
        return _buildHeading(context, fontSize: 24, fontWeight: FontWeight.w800);
      case WorkspaceBlockType.heading2:
        return _buildHeading(context, fontSize: 19, fontWeight: FontWeight.w700);
      case WorkspaceBlockType.todo:
        return _buildTodo(context);
      case WorkspaceBlockType.bullet:
        return _buildBullet(context);
      case WorkspaceBlockType.callout:
        return _buildCallout(context);
      case WorkspaceBlockType.quote:
        return _buildQuote(context);
      case WorkspaceBlockType.divider:
        return _buildDivider(context);
      case WorkspaceBlockType.text:
        return _buildParagraph(context);
    }
  }

  Widget _buildHeading(BuildContext context, {required double fontSize, required FontWeight fontWeight}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: TextFormField(
        initialValue: block.content,
        onChanged: (val) {
          block.content = val;
          onChanged();
        },
        maxLines: null,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: -0.3,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          hintText: block.type == WorkspaceBlockType.heading1 ? 'عنوان رئيسي H1...' : 'عنوان فرعي H2...',
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextFormField(
        initialValue: block.content,
        onChanged: (val) {
          block.content = val;
          onChanged();
        },
        maxLines: null,
        style: TextStyle(
          fontSize: 15.5,
          height: 1.6,
          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
        ),
        decoration: InputDecoration(
          hintText: 'اكتب نصاً، أو استخدم شريط الإضافة في الأسفل...',
          hintStyle: TextStyle(
            color: isDark ? Colors.white24 : Colors.black26,
            fontSize: 15.5,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildTodo(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggleTodo,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(top: 3, left: 8),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: block.isChecked
                    ? const Color(0xFF007AFF)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: block.isChecked
                      ? const Color(0xFF007AFF)
                      : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                  width: 1.6,
                ),
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
            child: TextFormField(
              initialValue: block.content,
              onChanged: (val) {
                block.content = val;
                onChanged();
              },
              maxLines: null,
              style: TextStyle(
                fontSize: 15.5,
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
                  fontSize: 15.5,
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
              initialValue: block.content,
              onChanged: (val) {
                block.content = val;
                onChanged();
              },
              maxLines: null,
              style: TextStyle(
                fontSize: 15.5,
                height: 1.5,
                color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
              ),
              decoration: InputDecoration(
                hintText: 'نقطة...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white24 : Colors.black26,
                  fontSize: 15.5,
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
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
          Text(
            block.calloutIcon,
            style: const TextStyle(fontSize: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextFormField(
              initialValue: block.content,
              onChanged: (val) {
                block.content = val;
                onChanged();
              },
              maxLines: null,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'ملاحظة مميزة أو تنبيه هام...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white30 : Colors.black38,
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

  Widget _buildQuote(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.only(right: 14, top: 4, bottom: 4),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Color(0xFF007AFF),
            width: 3.5,
          ),
        ),
      ),
      child: TextFormField(
        initialValue: block.content,
        onChanged: (val) {
          block.content = val;
          onChanged();
        },
        maxLines: null,
        style: TextStyle(
          fontSize: 15.5,
          height: 1.55,
          fontStyle: FontStyle.italic,
          color: isDark ? Colors.white70 : const Color(0xFF334155),
        ),
        decoration: InputDecoration(
          hintText: 'اقتباس...',
          hintStyle: TextStyle(
            color: isDark ? Colors.white24 : Colors.black26,
            fontSize: 15.5,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(
        height: 1,
        thickness: 0.8,
        color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
      ),
    );
  }
}
