import 'package:flutter/material.dart';

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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(20),
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
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.3),
                      blurRadius: 12,
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
                      ),
                    ),
                    const SizedBox(height: 2),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.05),
                      foregroundColor: isDark ? Colors.white : Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
                      style: const TextStyle(fontWeight: FontWeight.w600),
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
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.05),
                      foregroundColor: isDark ? Colors.white : Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
                      style: const TextStyle(fontWeight: FontWeight.w600),
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
        borderRadius: BorderRadius.circular(10),
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
                borderRadius: BorderRadius.circular(8),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : [],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onChanged(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
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
                                  ? FontWeight.bold
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
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? null
            : Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
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
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.05),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
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
              : 'لا يوجد وصف مختصر.');

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isDark
            ? null
            : Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            TicketsPalette.typeIcon(ticket.ticketType),
                            size: 14,
                            color: accent,
                          ),
                          const SizedBox(width: 6),
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
                    const Spacer(),
                    Text(
                      ticket.ticketNumber.isNotEmpty
                          ? ticket.ticketNumber
                          : '—',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: onSurfaceVariant,
                        fontWeight: FontWeight.w700,
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
                const SizedBox(height: 8),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TicketStatusBadge(status: ticket.status),
                    if (ticket.ticketType == 'ticket')
                      TicketPriorityBadge(priority: ticket.priority),
                    if (ticket.targetDepartmentName != null &&
                        ticket.targetDepartmentName!.trim().isNotEmpty)
                      _TicketPill(
                        label: 'إلى: ${ticket.targetDepartmentName}',
                        color: const Color(0xFF0F766E),
                      ),
                    if (ticket.assignedTo != null)
                      _TicketPill(
                        label: ticket.assignedTo!.displayName,
                        color: TicketsPalette.brand,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        ticket.lastUpdateAt != null
                            ? 'آخر تحديث ${dateFormat(ticket.lastUpdateAt!)}'
                            : 'بدون تحديثات',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_left_rounded,
                      size: 18,
                      color: onSurfaceVariant.withValues(alpha: 0.5),
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
        borderRadius: BorderRadius.circular(24),
        border: isDark
            ? null
            : Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      TicketsPalette.typeIcon(ticket.ticketType),
                      size: 16,
                      color: accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      TicketsPalette.typeLabel(ticket.ticketType),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                ticket.ticketNumber.isNotEmpty ? ticket.ticketNumber : '—',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            hasTitle ? ticket.title : 'بدون عنوان',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasDescription ? ticket.description : 'لا يوجد وصف لهذا الطلب.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TicketStatusBadge(status: ticket.status),
              if (ticket.ticketType == 'ticket')
                TicketPriorityBadge(priority: ticket.priority),
              if (ticket.targetDepartmentName != null &&
                  ticket.targetDepartmentName!.trim().isNotEmpty)
                _TicketPill(
                  label: 'موجه إلى: ${ticket.targetDepartmentName}',
                  color: const Color(0xFF0F766E),
                ),
              if (ticket.branchDepartmentName != null &&
                  ticket.branchDepartmentName!.trim().isNotEmpty)
                _TicketPill(
                  label: 'قسم مقدم الطلب: ${ticket.branchDepartmentName}',
                  color: TicketsPalette.brand,
                ),
              _TicketPill(
                label: 'مقدم الطلب: ${ticket.createdBy.displayName}',
                color: TicketsPalette.suggestion,
              ),
              if (ticket.assignedTo != null)
                _TicketPill(
                  label: 'المسؤول: ${ticket.assignedTo!.displayName}',
                  color: TicketsPalette.brand,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'تاريخ الإنشاء: ${dateFormat(ticket.createdAt)} • آخر تحديث: ${ticket.lastUpdateAt != null ? dateFormat(ticket.lastUpdateAt!) : '—'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (canManage && onChangeStatus != null && onAssign != null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.05),
                      foregroundColor: isDark ? Colors.white : Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: onChangeStatus,
                    icon: const Icon(Icons.flag_rounded, size: 20),
                    label: const Text(
                      'تغيير الحالة',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.05),
                      foregroundColor: isDark ? Colors.white : Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: onAssign,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                    label: const Text(
                      'إسناد',
                      style: TextStyle(fontWeight: FontWeight.w600),
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
  });

  final String label;
  final String message;
  final String actor;
  final String visibilityLabel;
  final String timestamp;
  final Color accent;
  final bool isInternal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final actorLabel = actor.trim().isNotEmpty ? actor : 'مستخدم';
    final body = message.trim().isNotEmpty ? message : '—';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TimelineTag(label: label, color: accent),
                    _TimelineTag(
                      label: visibilityLabel,
                      color: isInternal
                          ? TicketsPalette.suggestion
                          : TicketsPalette.brand,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timestamp,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            actorLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: onSurface,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.7,
              color: onSurface,
              fontSize: 14,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12.5,
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
