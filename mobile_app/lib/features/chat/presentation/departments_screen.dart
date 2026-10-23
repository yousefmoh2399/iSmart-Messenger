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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    return Material(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
          width: 0.5,
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
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: EdgeInsets.zero,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF34C759).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.apartment_rounded,
              color: Color(0xFF34C759),
              size: 22,
            ),
          ),
          title: Text(
            widget.department.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          subtitle: Text(
            widget.department.description.isEmpty
                ? 'كود القسم: ${widget.department.code}'
                : widget.department.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: colorScheme.onSurfaceVariant,
            ),
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
                    style: const TextStyle(
                      color: Color(0xFF34C759),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    widget.conversation == null ? 'بدون غرفة' : 'غرفة متاحة',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
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
            Divider(
              height: 0.5,
              thickness: 0.5,
              color: colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
            if (widget.onOpenRoom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonalIcon(
                    onPressed: widget.onOpenRoom,
                    icon: const Icon(Icons.forum_rounded, size: 18),
                    label: Text(
                      widget.conversation!.unreadCount > 0
                          ? 'غرفة القسم (${widget.conversation!.unreadCount})'
                          : 'غرفة القسم',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF34C759).withValues(alpha: 0.12),
                      foregroundColor: const Color(0xFF34C759),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.users.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'لا يوجد موظفون ظاهرون داخل هذا القسم حاليًا.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...List.generate(widget.users.length, (idx) {
                final user = widget.users[idx];
                final isLast = idx == widget.users.length - 1;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DepartmentUserTile(
                      user: user,
                      onTap: () => widget.onUserTap(user),
                    ),
                    if (!isLast)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 70.0),
                        child: Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                        ),
                      ),
                  ],
                );
              }),
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
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Stack(
                children: [
                  ChatAvatar(
                    radius: 22,
                    backgroundColor: const Color(
                      0xFF34C759,
                    ).withValues(alpha: 0.12),
                    avatarUrl: user.avatarUrl,
                    fallback: Text(
                      _avatarLabel(user.displayName),
                      style: const TextStyle(
                        color: Color(0xFF34C759),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
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
                          color: Theme.of(context).colorScheme.surface,
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.jobTitle.isNotEmpty ? user.jobTitle : '@${user.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _presenceText(user),
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'محادثة',
                      style: TextStyle(
                        color: Color(0xFF34C759),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
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
