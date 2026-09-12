import 'package:flutter/material.dart';

import '../../../shared/models/app_user.dart';
import '../models/chat_models.dart';
import 'conversation_screen.dart';
import 'widgets/chat_avatar.dart';

class DepartmentsScreen extends StatelessWidget {
  const DepartmentsScreen({
    super.key,
    required this.currentUser,
    required this.conversations,
    required this.departments,
    required this.users,
    required this.onUserTap,
  });

  final AppUser? currentUser;
  final List<ChatConversation> conversations;
  final List<DepartmentSummary> departments;
  final List<ChatDirectoryUser> users;
  final Future<void> Function(ChatDirectoryUser user) onUserTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (departments.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.apartment_outlined,
        title: 'لا توجد أقسام متاحة',
        subtitle: 'ستظهر هنا الأقسام التي ينشئها الأدمن داخل النظام.',
      );
    }

    final usersByDepartment = <String?, List<ChatDirectoryUser>>{};
    for (final user in users) {
      if (user.id == currentUser?.id) {
        continue;
      }
      usersByDepartment
          .putIfAbsent(user.departmentId, () => <ChatDirectoryUser>[])
          .add(user);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      itemCount: departments.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          final totalUsers = usersByDepartment.values.fold<int>(
            0,
            (sum, items) => sum + items.length,
          );
          return Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF19A974).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.apartment_outlined,
                  color: Color(0xFF19A974),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الأقسام',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${departments.length} قسمًا • $totalUsers موظفًا.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final department = departments[index - 1];
        final departmentUsers = [
          ...(usersByDepartment[department.id] ?? const <ChatDirectoryUser>[]),
        ]..sort((a, b) => a.displayName.compareTo(b.displayName));

        ChatConversation? roomConversation;
        for (final item in conversations) {
          if (item.departmentId == department.id ||
              item.id == department.defaultConversationId) {
            roomConversation = item;
            break;
          }
        }

        return _DepartmentGroupCard(
          department: department,
          users: departmentUsers,
          conversation: roomConversation,
          onOpenRoom: roomConversation == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ConversationScreen(conversation: roomConversation!),
                  ),
                ),
          onUserTap: onUserTap,
        );
      },
    );
  }
}

class _DepartmentGroupCard extends StatefulWidget {
  const _DepartmentGroupCard({
    required this.department,
    required this.users,
    required this.conversation,
    required this.onOpenRoom,
    required this.onUserTap,
  });

  final DepartmentSummary department;
  final List<ChatDirectoryUser> users;
  final ChatConversation? conversation;
  final VoidCallback? onOpenRoom;
  final Future<void> Function(ChatDirectoryUser user) onUserTap;

  @override
  State<_DepartmentGroupCard> createState() => _DepartmentGroupCardState();
}

class _DepartmentGroupCardState extends State<_DepartmentGroupCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _isExpanded,
          onExpansionChanged: (value) {
            setState(() {
              _isExpanded = value;
            });
          },
          tilePadding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF19A974).withValues(alpha: 0.12),
            child: const Icon(
              Icons.apartment_outlined,
              color: Color(0xFF19A974),
            ),
          ),
          title: Text(
            widget.department.name,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            widget.department.description.isEmpty
                ? 'كود القسم: ${widget.department.code}'
                : widget.department.description,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${widget.users.length} موظف',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF19A974),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    widget.conversation == null ? 'بدون غرفة' : 'غرفة متاحة',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: _isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          children: [
            if (widget.onOpenRoom != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    onPressed: widget.onOpenRoom,
                    icon: const Icon(Icons.forum_outlined),
                    label: Text(
                      widget.conversation!.unreadCount > 0
                          ? 'فتح غرفة القسم (${widget.conversation!.unreadCount})'
                          : 'فتح غرفة القسم',
                    ),
                  ),
                ),
              ),
            if (widget.users.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'لا يوجد موظفون ظاهرون داخل هذا القسم حاليًا.',
                      ),
                    ),
                  ],
                ),
              )
            else
              ...widget.users.map(
                (user) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DepartmentUserTile(
                    user: user,
                    onTap: () => widget.onUserTap(user),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentUserTile extends StatelessWidget {
  const _DepartmentUserTile({required this.user, required this.onTap});

  final ChatDirectoryUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Stack(
                children: [
                  ChatAvatar(
                    radius: 22,
                    backgroundColor: const Color(
                      0xFF19A974,
                    ).withValues(alpha: 0.12),
                    avatarUrl: user.avatarUrl,
                    fallback: Text(
                      _avatarLabel(user.displayName),
                      style: const TextStyle(
                        color: Color(0xFF19A974),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    end: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _presenceColor(user.presenceStatus),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.surface,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${user.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _presenceText(user),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryEmptyState extends StatelessWidget {
  const _CategoryEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 120),
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                child: Icon(icon, size: 30, color: colorScheme.primary),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _avatarLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '؟';
  }
  return trimmed.substring(0, 1).toUpperCase();
}

String _presenceText(ChatDirectoryUser user) {
  if (user.presenceStatus == 'online') {
    return 'متصل';
  }
  if (user.presenceStatus == 'idle') {
    return 'خامل';
  }
  return 'غير متصل';
}

Color _presenceColor(String status) => switch (status) {
  'online' => const Color(0xFF22C55E),
  'idle' => const Color(0xFFF59E0B),
  _ => const Color(0xFF94A3B8),
};
