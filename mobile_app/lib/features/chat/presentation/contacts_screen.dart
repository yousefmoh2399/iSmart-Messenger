import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/app_user.dart';
import '../models/chat_models.dart';
import 'conversation_screen.dart';
import 'widgets/chat_avatar.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    required this.currentUser,
    required this.users,
    required this.departments,
    required this.onStartDirectConversation,
  });

  final AppUser? currentUser;
  final List<ChatDirectoryUser> users;
  final List<DepartmentSummary> departments;
  final Future<ChatConversation> Function(String userId)
  onStartDirectConversation;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final query = _searchController.text.trim().toLowerCase();
    final directoryUsers = widget.users
        .where((user) => user.id != widget.currentUser?.id)
        .toList();
    final departmentById = {
      for (final department in widget.departments) department.id: department,
    };

    if (directoryUsers.isEmpty) {
      return _ContactsEmptyState(colorScheme: colorScheme);
    }

    final groupedUsers = <String?, List<ChatDirectoryUser>>{};
    for (final user in directoryUsers) {
      final department = departmentById[user.departmentId];
      final matches =
          query.isEmpty ||
          user.displayName.toLowerCase().contains(query) ||
          user.username.toLowerCase().contains(query) ||
          (department?.name.toLowerCase().contains(query) ?? false);
      if (!matches) {
        continue;
      }
      groupedUsers
          .putIfAbsent(user.departmentId, () => <ChatDirectoryUser>[])
          .add(user);
    }

    final groups = <_ContactDepartmentGroup>[
      for (final department in widget.departments)
        if (groupedUsers[department.id]?.isNotEmpty == true)
          _ContactDepartmentGroup(
            id: department.id,
            title: department.name,
            subtitle: department.description.isEmpty
                ? 'كود القسم: ${department.code}'
                : department.description,
            users: groupedUsers[department.id]!,
          ),
      if (groupedUsers[null]?.isNotEmpty == true)
        _ContactDepartmentGroup(
          id: null,
          title: 'بدون قسم',
          subtitle: 'المستخدمون غير المرتبطين بقسم محدد.',
          users: groupedUsers[null]!,
        ),
    ];

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      itemCount: groups.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _ContactsHeaderCard(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            departmentsCount: groups.length,
            usersCount: groupedUsers.values.fold<int>(
              0,
              (sum, items) => sum + items.length,
            ),
          );
        }

        final group = groups[index - 1];
        final orderedUsers = [...group.users]
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
        return _ContactDepartmentCard(
          key: ValueKey('${group.id ?? 'none'}-$query'),
          title: group.title,
          subtitle: group.subtitle,
          users: orderedUsers,
          initiallyExpanded: query.isNotEmpty,
          onStartConversation: (user) async {
            try {
              final conversation = await widget.onStartDirectConversation(
                user.id,
              );
              if (!context.mounted) {
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ConversationScreen(conversation: conversation),
                ),
              );
            } catch (error) {
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(error.toString())));
            }
          },
        );
      },
    );
  }
}

class _ContactsHeaderCard extends StatelessWidget {
  const _ContactsHeaderCard({
    required this.controller,
    required this.onChanged,
    required this.departmentsCount,
    required this.usersCount,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final int departmentsCount;
  final int usersCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF3390EC).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.people_alt_outlined,
                color: Color(0xFF3390EC),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الأفراد',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$usersCount فردًا داخل $departmentsCount مجموعة مرتبة حسب الأقسام.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: 'ابحث بالاسم أو اسم المستخدم أو القسم',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'مسح',
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ContactDepartmentGroup {
  const _ContactDepartmentGroup({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.users,
  });

  final String? id;
  final String title;
  final String subtitle;
  final List<ChatDirectoryUser> users;
}

class _ContactDepartmentCard extends StatefulWidget {
  const _ContactDepartmentCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.users,
    required this.initiallyExpanded,
    required this.onStartConversation,
  });

  final String title;
  final String subtitle;
  final List<ChatDirectoryUser> users;
  final bool initiallyExpanded;
  final Future<void> Function(ChatDirectoryUser user) onStartConversation;

  @override
  State<_ContactDepartmentCard> createState() => _ContactDepartmentCardState();
}

class _ContactDepartmentCardState extends State<_ContactDepartmentCard> {
  late bool _isExpanded = widget.initiallyExpanded;

  @override
  void didUpdateWidget(covariant _ContactDepartmentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyExpanded != widget.initiallyExpanded &&
        widget.initiallyExpanded) {
      _isExpanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
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
              color: const Color(0xFF007AFF).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.groups_2_rounded,
              color: Color(0xFF007AFF),
              size: 22,
            ),
          ),
          title: Text(
            widget.title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          subtitle: Text(
            widget.subtitle,
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${widget.users.length}',
                  style: const TextStyle(
                    color: Color(0xFF007AFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
            ...List.generate(widget.users.length, (idx) {
              final user = widget.users[idx];
              final isLast = idx == widget.users.length - 1;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ContactUserTile(
                    user: user,
                    onTap: () => widget.onStartConversation(user),
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

class _ContactUserTile extends StatelessWidget {
  const _ContactUserTile({required this.user, required this.onTap});

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
                      0xFF007AFF,
                    ).withValues(alpha: 0.12),
                    avatarUrl: user.avatarUrl,
                    fallback: Text(
                      _avatarLabel(user.displayName),
                      style: const TextStyle(
                        color: Color(0xFF007AFF),
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
                      color: const Color(0xFF007AFF).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'محادثة',
                      style: TextStyle(
                        color: Color(0xFF007AFF),
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

class _ContactsEmptyState extends StatelessWidget {
  const _ContactsEmptyState({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
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
                backgroundColor: const Color(
                  0xFF3390EC,
                ).withValues(alpha: 0.12),
                child: const Icon(
                  Icons.people_outline,
                  size: 30,
                  color: Color(0xFF3390EC),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'لا يوجد أفراد متاحون حاليًا',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'حين تتوفر حسابات نشطة ستظهر هنا لتبدأ معها محادثات مباشرة.',
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

String _presenceText(ChatDirectoryUser user) {
  if (user.presenceStatus == 'online') return 'متصل الآن';
  if (user.presenceStatus == 'idle') {
    final at = user.lastActiveAt ?? user.lastSeen;
    return at == null ? 'خامل' : 'خامل منذ ${formatEgyptTime(at)}';
  }
  final lastSeen = user.lastSeen ?? user.lastActiveAt;
  return lastSeen == null
      ? 'غير متصل'
      : 'آخر ظهور ${formatEgyptDateTime(lastSeen, datePattern: 'dd/MM', separator: ' ')}';
}

String _avatarLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '؟';
  }
  return trimmed.substring(0, 1).toUpperCase();
}

Color _presenceColor(String status) => switch (status) {
  'online' => const Color(0xFF22C55E),
  'idle' => const Color(0xFFF59E0B),
  _ => const Color(0xFF94A3B8),
};
