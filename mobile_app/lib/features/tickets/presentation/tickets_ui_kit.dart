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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [accent, Color.lerp(accent, Colors.black, 0.22)!],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
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
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
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
                    backgroundColor: Colors.white,
                    foregroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(createLabel),
                ),
              ),
              if (onSecondary != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: onSecondary,
                    icon: Icon(secondaryIcon ?? Icons.settings_outlined),
                    label: Text(secondaryLabel ?? ''),
                  ),
                ),
              ],
              if (onTertiary != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: onTertiary,
                    icon: Icon(tertiaryIcon ?? Icons.corporate_fare_rounded),
                    label: Text(tertiaryLabel ?? ''),
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
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.65,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = index == selectedIndex;
          return Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(start: index == 0 ? 0 : 4),
              child: Material(
                color: selected
                    ? theme.colorScheme.surface
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                elevation: selected ? 1 : 0,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onChanged(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icons[index],
                          size: 18,
                          color: selected
                              ? TicketsPalette.brand
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            labels[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: selected
                                  ? TicketsPalette.brand
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

class TicketsStatChip extends StatelessWidget {
  const TicketsStatChip({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(width: 5, color: accent),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
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
                            const SizedBox(width: 4),
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
                  const SizedBox(height: 10),
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
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 12),
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
                        Icons.arrow_back_ios_new_rounded,
                        size: 14,
                        color: onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16),
              child: Divider(
                height: 0.5,
                thickness: 0.5,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
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
    final onSurface = theme.colorScheme.onSurface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final accent = TicketsPalette.typeColor(ticket.ticketType);
    final hasTitle = ticket.title.trim().isNotEmpty;
    final hasDescription = ticket.description.trim().isNotEmpty;

    final isDark = theme.brightness == Brightness.dark;

    Widget buildRow(String title, Widget trailing, {VoidCallback? onTap}) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text(
                title,
                style: theme.textTheme.bodyLarge?.copyWith(color: onSurface),
              ),
              const Spacer(),
              trailing,
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and Description
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasTitle ? ticket.title : 'بدون عنوان',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    TicketsPalette.typeIcon(ticket.ticketType),
                    size: 16,
                    color: accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${TicketsPalette.typeLabel(ticket.ticketType)} #${ticket.ticketNumber.isNotEmpty ? ticket.ticketNumber : '—'}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dateFormat(
                      ticket.createdAt ?? ticket.updatedAt ?? DateTime.now(),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (hasDescription)
                Text(
                  ticket.description,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: onSurface,
                    height: 1.5,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Settings-style Metadata Table
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              buildRow(
                'الحالة',
                TicketStatusBadge(status: ticket.status),
                onTap: canManage ? onChangeStatus : null,
              ),
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 16,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              if (ticket.ticketType == 'ticket') ...[
                buildRow(
                  'الأولوية',
                  TicketPriorityBadge(priority: ticket.priority),
                ),
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 16,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ],
              buildRow(
                'مقدم الطلب',
                Text(
                  ticket.createdBy.displayName,
                  style: TextStyle(color: onSurfaceVariant),
                ),
              ),
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 16,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              if (ticket.targetDepartmentName != null &&
                  ticket.targetDepartmentName!.trim().isNotEmpty) ...[
                buildRow(
                  'القسم الموجه إليه',
                  Text(
                    ticket.targetDepartmentName!,
                    style: TextStyle(color: onSurfaceVariant),
                  ),
                ),
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 16,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ],
              buildRow(
                'المسؤول',
                Text(
                  ticket.assignedTo?.displayName ?? 'بدون مسؤول',
                  style: TextStyle(color: TicketsPalette.brand),
                ),
                onTap: canManage ? onAssign : null,
              ),
            ],
          ),
        ),
      ],
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

    final isMessage =
        label.contains('رد') ||
        label.contains('ملاحظة') ||
        label.contains('رسالة') ||
        label.contains('تعليق');

    if (!isMessage) {
      // System Event
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(
              '$actor قام بـ $label • $timestamp',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (message.trim().isNotEmpty && message != '—') ...[
              const SizedBox(height: 4),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }

    // Message Bubble
    final bubbleColor = isInternal
        ? (isDark
              ? const Color(0xFFD97706).withValues(alpha: 0.2)
              : const Color(0xFFFEF3C7))
        : (isDark ? const Color(0xFF262628) : const Color(0xFFE9E9EB));
    final textColor = isDark ? Colors.white : Colors.black;
    final internalLabel = isInternal ? ' (ملاحظة داخلية)' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              '$actor • $timestamp$internalLabel',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: textColor,
                height: 1.4,
              ),
            ),
          ),
        ],
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
