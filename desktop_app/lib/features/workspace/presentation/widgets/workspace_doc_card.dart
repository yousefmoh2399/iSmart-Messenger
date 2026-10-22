import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/workspace_doc.dart';

class WorkspaceDocCard extends StatelessWidget {
  const WorkspaceDocCard({
    super.key,
    required this.doc,
    required this.isGrid,
    required this.isDark,
    required this.onTap,
    required this.onTogglePin,
    required this.onToggleFavorite,
    required this.onDuplicate,
    required this.onDelete,
  });

  final WorkspaceDoc doc;
  final bool isGrid;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) {
      return diff.inMinutes <= 1 ? 'الآن' : 'منذ ${diff.inMinutes} دقيقة';
    }
    if (diff.inHours < 24 && dt.day == now.day) {
      return DateFormat('hh:mm a', 'ar').format(dt);
    }
    if (diff.inDays == 1 || (diff.inDays < 2 && dt.day == now.day - 1)) {
      return 'أمس';
    }
    return DateFormat('d MMM', 'ar').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    if (isGrid) {
      return _buildGridCard(context);
    }
    return _buildListTile(context);
  }

  Widget _buildGridCard(BuildContext context) {
    final totalTodos = doc.todoCount;
    final completedTodos = doc.completedTodoCount;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
          width: 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        doc.icon,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const Spacer(),
                    if (doc.isPinned)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.push_pin_rounded, size: 16, color: Color(0xFFF59E0B)),
                      ),
                    if (doc.isFavorite)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                      ),
                    _buildDocContextMenu(context),
                  ],
                ),
                const SizedBox(height: 12),

                // Title
                Text(
                  doc.title.trim().isNotEmpty ? doc.title : 'بدون عنوان',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),

                // Preview or Todo progress
                if (totalTodos > 0) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 14,
                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$completedTodos من $totalTodos مهام',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: completedTodos / totalTodos,
                      minHeight: 4,
                      backgroundColor: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF007AFF)),
                    ),
                  ),
                ] else ...[
                  Text(
                    doc.previewText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                ],

                const Spacer(),
                const SizedBox(height: 10),

                // Footer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        doc.category,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                        ),
                      ),
                    ),
                    Text(
                      _formatDate(doc.updatedAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
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

  Widget _buildListTile(BuildContext context) {
    final totalTodos = doc.todoCount;
    final completedTodos = doc.completedTodoCount;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
          width: 0.6,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    doc.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              doc.title.trim().isNotEmpty ? doc.title : 'بدون عنوان',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          if (doc.isPinned)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(Icons.push_pin_rounded, size: 16, color: Color(0xFFF59E0B)),
                            ),
                          if (doc.isFavorite)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (totalTodos > 0)
                        Text(
                          '$completedTodos من $totalTodos مهام مكتملة',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white54 : const Color(0xFF64748B),
                          ),
                        )
                      else
                        Text(
                          doc.previewText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white54 : const Color(0xFF64748B),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatDate(doc.updatedAt),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        doc.category,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                _buildDocContextMenu(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocContextMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        size: 18,
        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
      ),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (val) {
        switch (val) {
          case 'pin':
            onTogglePin();
            break;
          case 'favorite':
            onToggleFavorite();
            break;
          case 'duplicate':
            onDuplicate();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'pin',
          child: Row(
            children: [
              Icon(
                doc.isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                size: 18,
                color: const Color(0xFFF59E0B),
              ),
              const SizedBox(width: 10),
              Text(doc.isPinned ? 'إلغاء التثبيت' : 'تثبيت في الأعلى'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'favorite',
          child: Row(
            children: [
              Icon(
                doc.isFavorite ? Icons.star_border_rounded : Icons.star_rounded,
                size: 18,
                color: const Color(0xFFF59E0B),
              ),
              const SizedBox(width: 10),
              Text(doc.isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 18),
              SizedBox(width: 10),
              Text('تكرار المستند'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
              SizedBox(width: 10),
              Text('حذف', style: TextStyle(color: Color(0xFFEF4444))),
            ],
          ),
        ),
      ],
    );
  }
}
