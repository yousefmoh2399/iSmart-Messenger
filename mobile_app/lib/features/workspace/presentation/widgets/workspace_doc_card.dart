import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      return diff.inMinutes <= 1 ? 'الآن' : 'منذ ${diff.inMinutes} د';
    }
    if (diff.inHours < 24 && dt.day == now.day) {
      return DateFormat('hh:mm a', 'ar').format(dt);
    }
    if (diff.inDays == 1) {
      return 'أمس';
    }
    return DateFormat('d MMM', 'ar').format(dt);
  }

  List<Color> _resolveCoverGradient(String coverHex) {
    switch (coverHex) {
      case '0xFFDCFCE7':
        return [const Color(0xFF10B981), const Color(0xFF34D399)];
      case '0xFFFEF3C7':
        return [const Color(0xFFF59E0B), const Color(0xFFFBBF24)];
      case '0xFFF3E8FF':
        return [const Color(0xFF8B5CF6), const Color(0xFFA78BFA)];
      case '0xFFFCE7F3':
        return [const Color(0xFFEC4899), const Color(0xFFF472B6)];
      case '0xFF1E293B':
        return [const Color(0xFF1E293B), const Color(0xFF475569)];
      case '0xFFE0F2FE':
      default:
        return [const Color(0xFF007AFF), const Color(0xFF38BDF8)];
    }
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
    final gradColors = _resolveCoverGradient(doc.coverColor);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Gradient Banner Strip
              Container(
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradColors,
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Text(doc.icon, style: const TextStyle(fontSize: 18)),
                    const Spacer(),
                    if (doc.isPinned)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(CupertinoIcons.pin_fill, size: 13, color: Colors.white),
                      ),
                    if (doc.isFavorite)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(CupertinoIcons.star_fill, size: 13, color: Color(0xFFFDE047)),
                      ),
                    _buildDocContextMenu(context, onHeader: true),
                  ],
                ),
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        doc.title.trim().isNotEmpty ? doc.title : 'بدون عنوان',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          height: 1.25,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Preview or Checklist progress
                      if (totalTodos > 0) ...[
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.checkmark_alt_circle_fill,
                              size: 13,
                              color: completedTodos == totalTodos
                                  ? const Color(0xFF10B981)
                                  : gradColors.first,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$completedTodos/$totalTodos مهام',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: completedTodos / totalTodos,
                            minHeight: 4,
                            backgroundColor: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              completedTodos == totalTodos
                                  ? const Color(0xFF10B981)
                                  : gradColors.first,
                            ),
                          ),
                        ),
                      ] else ...[
                        Expanded(
                          child: Text(
                            doc.previewText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? Colors.white54 : const Color(0xFF64748B),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],

                      const Spacer(),

                      // Category & Time Footer
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: gradColors.first.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              doc.category,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: gradColors.first,
                              ),
                            ),
                          ),
                          Text(
                            _formatDate(doc.updatedAt),
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
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
      ),
    );
  }

  Widget _buildListTile(BuildContext context) {
    final totalTodos = doc.todoCount;
    final completedTodos = doc.completedTodoCount;
    final gradColors = _resolveCoverGradient(doc.coverColor);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
          width: 0.7,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        gradColors.first.withValues(alpha: 0.16),
                        gradColors.last.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(doc.icon, style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
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
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          if (doc.isPinned)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3),
                              child: Icon(CupertinoIcons.pin_fill, size: 14, color: Color(0xFFF59E0B)),
                            ),
                          if (doc.isFavorite)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3),
                              child: Icon(CupertinoIcons.star_fill, size: 14, color: Color(0xFFF59E0B)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        totalTodos > 0
                            ? '$completedTodos من $totalTodos مهام مكتملة • ${doc.previewText}'
                            : doc.previewText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatDate(doc.updatedAt),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: gradColors.first.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        doc.category,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: gradColors.first,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                _buildDocContextMenu(context, onHeader: false),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocContextMenu(BuildContext context, {required bool onHeader}) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_horiz_rounded,
        size: 18,
        color: onHeader
            ? Colors.white
            : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                doc.isPinned ? CupertinoIcons.pin_slash : CupertinoIcons.pin_fill,
                size: 17,
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
                doc.isFavorite ? CupertinoIcons.star_slash : CupertinoIcons.star_fill,
                size: 17,
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
              Icon(CupertinoIcons.plus_square_on_square, size: 17),
              SizedBox(width: 10),
              Text('تكرار الصفحة'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(CupertinoIcons.trash, size: 17, color: Color(0xFFEF4444)),
              SizedBox(width: 10),
              Text('حذف الصفحة', style: TextStyle(color: Color(0xFFEF4444))),
            ],
          ),
        ),
      ],
    );
  }
}
