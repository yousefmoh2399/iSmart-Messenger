import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ticket_models.dart';

class TicketsPalette {
  const TicketsPalette._();

  static const Color brand = Color(0xFF4F46E5);
  static const Color brandDark = Color(0xFF312E81);
  static const Color accent = Color(0xFF06B6D4);
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);
  static const Color complaint = Color(0xFFEA580C);
  static const Color suggestion = Color(0xFF7C3AED);

  static Color typeColor(String ticketType) => switch (ticketType) {
    'complaint' => complaint,
    'suggestion' => suggestion,
    _ => brand,
  };

  static IconData typeIcon(String ticketType) => switch (ticketType) {
    'complaint' => Icons.report_problem_rounded,
    'suggestion' => Icons.lightbulb_rounded,
    _ => Icons.support_agent_rounded,
  };

  static String typeLabel(String ticketType) => switch (ticketType) {
    'complaint' => 'شكوى',
    'suggestion' => 'مقترح',
    _ => 'تذكرة',
  };
}

String ticketStatusLabel(String status) => switch (status) {
  'open' => 'مفتوحة',
  'assigned' => 'تم الإسناد',
  'in_progress' => 'قيد المعالجة',
  'waiting_branch' => 'بانتظار الفرع',
  'resolved' => 'تم الحل',
  'closed' => 'مغلقة',
  _ => status,
};

Color ticketStatusColor(String status) => switch (status) {
  'open' => const Color(0xFF2563EB),
  'assigned' => const Color(0xFF7C3AED),
  'in_progress' => const Color(0xFFD97706),
  'waiting_branch' => const Color(0xFF0891B2),
  'resolved' => TicketsPalette.success,
  'closed' => const Color(0xFF64748B),
  _ => const Color(0xFF475569),
};

String ticketPriorityLabel(String priority) => switch (priority) {
  'low' => 'منخفضة',
  'normal' => 'عادية',
  'high' => 'عالية',
  'critical' => 'حرجة',
  _ => priority,
};

Color ticketPriorityColor(String priority) => switch (priority) {
  'low' => const Color(0xFF64748B),
  'normal' => const Color(0xFF2563EB),
  'high' => const Color(0xFFD97706),
  'critical' => TicketsPalette.danger,
  _ => const Color(0xFF475569),
};

class TicketsHeroHeader extends StatelessWidget {
  const TicketsHeroHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onCreate,
    required this.createLabel,
    this.onSecondary,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onTertiary,
    this.tertiaryLabel,
    this.tertiaryIcon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onCreate;
  final String createLabel;
  final VoidCallback? onSecondary;
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final VoidCallback? onTertiary;
  final String? tertiaryLabel;
  final IconData? tertiaryIcon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.22 : 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    elevation: 0,
                  ),
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(
                    createLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              if (onSecondary != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.09)
                          : Colors.black.withValues(alpha: 0.05),
                      foregroundColor: isDark ? Colors.white : Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      elevation: 0,
                    ),
                    onPressed: onSecondary,
                    icon: Icon(
                      secondaryIcon ?? Icons.settings_outlined,
                      size: 20,
                    ),
                    label: Text(
                      secondaryLabel ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
              if (onTertiary != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.09)
                          : Colors.black.withValues(alpha: 0.05),
                      foregroundColor: isDark ? Colors.white : Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      elevation: 0,
                    ),
                    onPressed: onTertiary,
                    icon: Icon(
                      tertiaryIcon ?? Icons.corporate_fare_rounded,
                      size: 20,
                    ),
                    label: Text(
                      tertiaryLabel ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class TicketsTypeSegmentBar extends StatelessWidget {
  const TicketsTypeSegmentBar({
    super.key,
    required this.labels,
    required this.icons,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final List<IconData> icons;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = index == selectedIndex;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: selected
                    ? (isDark ? const Color(0xFF3A3A3C) : Colors.white)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : [],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onChanged(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 9,
                      horizontal: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icons[index],
                          size: 16,
                          color: selected
                              ? (isDark ? Colors.white : Colors.black87)
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            labels[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: selected
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class TicketsStatGroup extends StatelessWidget {
  const TicketsStatGroup({super.key, required this.stats});

  final List<TicketStatItem> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: stats.asMap().entries.map((entry) {
            final index = entry.key;
            final stat = entry.value;
            final isLast = index == stats.length - 1;

            return Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: stat.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(stat.icon, size: 20, color: stat.color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  stat.value,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  stat.label,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!isLast)
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.06),
                      indent: 12,
                      endIndent: 12,
                    ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class TicketStatItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const TicketStatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class TicketStatusBadge extends StatelessWidget {
  const TicketStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = ticketStatusColor(status);
    return _TicketPill(label: ticketStatusLabel(status), color: color);
  }
}

class TicketPriorityBadge extends StatelessWidget {
  const TicketPriorityBadge({super.key, required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final color = ticketPriorityColor(priority);
    return _TicketPill(label: ticketPriorityLabel(priority), color: color);
  }
}

class _TicketPill extends StatelessWidget {
  const _TicketPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TicketMiniTag extends StatelessWidget {
  const _TicketMiniTag({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ModernTicketCard extends StatelessWidget {
  const ModernTicketCard({
    super.key,
    required this.ticket,
    required this.dateFormat,
    required this.onTap,
  });

  final TicketItem ticket;
  final String Function(DateTime value) dateFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final onSurface = theme.colorScheme.onSurface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final accent = TicketsPalette.typeColor(ticket.ticketType);
    final title = ticket.title.trim().isNotEmpty
        ? ticket.title
        : (ticket.ticketNumber.isNotEmpty
              ? 'طلب ${ticket.ticketNumber}'
              : 'طلب بدون عنوان');
    final preview = ticket.lastPublicMessage.trim().isNotEmpty
        ? ticket.lastPublicMessage
        : (ticket.description.trim().isNotEmpty
              ? ticket.description
              : 'لا يوجد وصف مختصر لهذا الطلب.');

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Row: Type Pill, Status & Priority Badges, Ticket Number
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            TicketsPalette.typeIcon(ticket.ticketType),
                            size: 14,
                            color: accent,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            TicketsPalette.typeLabel(ticket.ticketType),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TicketStatusBadge(status: ticket.status),
                    if (ticket.ticketType == 'ticket') ...[
                      const SizedBox(width: 6),
                      TicketPriorityBadge(priority: ticket.priority),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ticket.ticketNumber.isNotEmpty
                            ? '#${ticket.ticketNumber}'
                            : '—',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                // Metadata chips
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (ticket.targetDepartmentName != null &&
                        ticket.targetDepartmentName!.trim().isNotEmpty)
                      _TicketMiniTag(
                        icon: Icons.account_tree_outlined,
                        label: ticket.targetDepartmentName!,
                        color: const Color(0xFF0F766E),
                      ),
                    if (ticket.branchDepartmentName != null &&
                        ticket.branchDepartmentName!.trim().isNotEmpty)
                      _TicketMiniTag(
                        icon: Icons.store_outlined,
                        label: ticket.branchDepartmentName!,
                        color: const Color(0xFFD97706),
                      ),
                    _TicketMiniTag(
                      icon: Icons.person_outline_rounded,
                      label: ticket.createdBy.displayName,
                      color: TicketsPalette.suggestion,
                    ),
                    if (ticket.assignedTo != null)
                      _TicketMiniTag(
                        icon: Icons.assignment_ind_outlined,
                        label: ticket.assignedTo!.displayName,
                        color: TicketsPalette.brand,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 15,
                      color: onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        ticket.lastUpdateAt != null
                            ? 'آخر نشاط: ${dateFormat(ticket.lastUpdateAt!)}'
                            : 'تاريخ الإنشاء: ${dateFormat(ticket.createdAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'عرض التفاصيل',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 12,
                          color: accent,
                        ),
                      ],
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

class TicketDetailsHeaderCard extends StatelessWidget {
  const TicketDetailsHeaderCard({
    super.key,
    required this.ticket,
    required this.dateFormat,
    required this.canManage,
    this.onChangeStatus,
    this.onAssign,
  });

  final TicketItem ticket;
  final String Function(DateTime value) dateFormat;
  final bool canManage;
  final VoidCallback? onChangeStatus;
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final accent = TicketsPalette.typeColor(ticket.ticketType);
    final hasTitle = ticket.title.trim().isNotEmpty;
    final hasDescription = ticket.description.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Badges Row: Type Pill, Ticket #, Priority, Status
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      TicketsPalette.typeIcon(ticket.ticketType),
                      size: 15,
                      color: accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      TicketsPalette.typeLabel(ticket.ticketType),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Copyable Ticket Number
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: ticket.ticketNumber.isNotEmpty
                    ? () {
                        Clipboard.setData(
                          ClipboardData(text: ticket.ticketNumber),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                            content: Text('تم نسخ رقم التذكرة إلى الحافظة'),
                          ),
                        );
                      }
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ticket.ticketNumber.isNotEmpty
                            ? '#${ticket.ticketNumber}'
                            : '—',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: onSurfaceVariant,
                        ),
                      ),
                      if (ticket.ticketNumber.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (ticket.ticketType == 'ticket')
                    TicketPriorityBadge(priority: ticket.priority),
                  TicketStatusBadge(status: ticket.status),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 2. Title
          SelectableText(
            hasTitle ? ticket.title : 'طلب بدون عنوان',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: onSurface,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),

          // 3. Inset Description Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF252528)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 15,
                      color: onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'تفاصيل ووصف الطلب:',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  hasDescription
                      ? ticket.description
                      : 'لا يوجد وصف تفصيلي لهذا الطلب.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onSurface.withValues(alpha: 0.9),
                    height: 1.65,
                    fontSize: 14.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 4. Structured Metadata Bento Tiles
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _TicketMetaTile(
                icon: Icons.person_outline_rounded,
                label: 'مقدم الطلب',
                value: ticket.createdBy.displayName,
                color: TicketsPalette.suggestion,
              ),
              if (ticket.targetDepartmentName != null &&
                  ticket.targetDepartmentName!.trim().isNotEmpty)
                _TicketMetaTile(
                  icon: Icons.account_tree_outlined,
                  label: 'القسم المعني',
                  value: ticket.targetDepartmentName!,
                  color: const Color(0xFF0F766E),
                ),
              if (ticket.branchDepartmentName != null &&
                  ticket.branchDepartmentName!.trim().isNotEmpty)
                _TicketMetaTile(
                  icon: Icons.store_outlined,
                  label: 'فرع مقدم الطلب',
                  value: ticket.branchDepartmentName!,
                  color: const Color(0xFFD97706),
                ),
              _TicketMetaTile(
                icon: Icons.assignment_ind_outlined,
                label: 'المسؤول الحالي',
                value: ticket.assignedTo?.displayName ?? 'غير مسند بعد',
                color: ticket.assignedTo != null
                    ? TicketsPalette.brand
                    : const Color(0xFF64748B),
              ),
              _TicketMetaTile(
                icon: Icons.access_time_rounded,
                label: 'تاريخ الإنشاء',
                value: dateFormat(ticket.createdAt),
                color: const Color(0xFF64748B),
              ),
              if (ticket.lastUpdateAt != null)
                _TicketMetaTile(
                  icon: Icons.update_rounded,
                  label: 'آخر نشاط',
                  value: dateFormat(ticket.lastUpdateAt!),
                  color: const Color(0xFF64748B),
                ),
            ],
          ),

          // 5. Admin/Manager Action Buttons
          if (canManage && (onChangeStatus != null || onAssign != null)) ...[
            const SizedBox(height: 20),
            Divider(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (onChangeStatus != null)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFF1F5F9),
                        foregroundColor: isDark ? Colors.white : Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                          ),
                        ),
                        elevation: 0,
                      ),
                      onPressed: onChangeStatus,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                      label: Text(
                        'تغيير الحالة (${ticketStatusLabel(ticket.status)})',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                if (onChangeStatus != null && onAssign != null)
                  const SizedBox(width: 12),
                if (onAssign != null)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent.withValues(alpha: 0.12),
                        foregroundColor: accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: accent.withValues(alpha: 0.25),
                          ),
                        ),
                        elevation: 0,
                      ),
                      onPressed: onAssign,
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                      label: Text(
                        ticket.assignedTo != null
                            ? 'إعادة الإسناد (${ticket.assignedTo!.displayName})'
                            : 'إسناد لموظف دعم',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TicketMetaTile extends StatelessWidget {
  const _TicketMetaTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252528) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TicketTimelineTile extends StatelessWidget {
  const TicketTimelineTile({
    super.key,
    required this.label,
    required this.message,
    required this.actor,
    required this.visibilityLabel,
    required this.timestamp,
    required this.accent,
    required this.isInternal,
    this.isFirst = false,
    this.isLast = false,
  });

  final String label;
  final String message;
  final String actor;
  final String visibilityLabel;
  final String timestamp;
  final Color accent;
  final bool isInternal;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final actorLabel = actor.trim().isNotEmpty ? actor : 'مستخدم';
    final body = message.trim().isNotEmpty ? message : '—';

    final tileBg = isInternal
        ? (isDark ? const Color(0xFF2A2038) : const Color(0xFFFAF5FF))
        : (isDark ? const Color(0xFF242426) : Colors.white);

    final tileBorder = isInternal
        ? TicketsPalette.suggestion.withValues(alpha: isDark ? 0.35 : 0.25)
        : (isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.black.withValues(alpha: 0.06));

    final iconColor = isInternal ? TicketsPalette.suggestion : accent;

    return Container(
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tileBorder, width: isInternal ? 1.5 : 1),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar Circle
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isInternal
                      ? Icons.lock_rounded
                      : (label.contains('حالة')
                          ? Icons.published_with_changes_rounded
                          : (label.contains('مسؤول') || label.contains('إسناد')
                              ? Icons.person_pin_rounded
                              : Icons.chat_bubble_outline_rounded)),
                  size: 18,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            actorLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _TimelineTag(label: label, color: accent),
                        if (isInternal) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: TicketsPalette.suggestion
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.lock_rounded,
                                  size: 11,
                                  color: TicketsPalette.suggestion,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'ملاحظة داخلية',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: TicketsPalette.suggestion,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timestamp,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 48),
            child: SelectableText(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.65,
                color: onSurface.withValues(alpha: 0.95),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineTag extends StatelessWidget {
  const _TimelineTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class TicketsEmptyIllustration extends StatelessWidget {
  const TicketsEmptyIllustration({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: accent),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
