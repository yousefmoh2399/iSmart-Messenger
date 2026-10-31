import 'package:flutter/cupertino.dart';
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
  int _selectedFilterIndex = 0; // 0: الكل, 1: متصل الآن, 2+: departments

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _startConversation(ChatDirectoryUser user) async {
    try {
      final conversation = await widget.onStartDirectConversation(user.id);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConversationScreen(conversation: conversation),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final query = _searchController.text.trim().toLowerCase();

    final directoryUsers = widget.users
        .where((user) => user.id != widget.currentUser?.id)
        .toList();

    final departmentById = {
      for (final department in widget.departments) department.id: department,
    };

    final onlineUsers = directoryUsers
        .where((u) => u.presenceStatus == 'online' || u.isOnline)
        .toList();

    // Departments that actually have users
    final activeDepartments = widget.departments
        .where((dept) => directoryUsers.any((u) => u.departmentId == dept.id))
        .toList();

    // ── Build Filter Pills ──
    final filterPills = <Map<String, dynamic>>[
      {
        'label': 'الكل',
        'count': directoryUsers.length,
        'icon': CupertinoIcons.person_2_fill,
      },
      {
        'label': 'متصل الآن',
        'count': onlineUsers.length,
        'icon': CupertinoIcons.circle_fill,
        'isOnline': true,
      },
      for (final dept in activeDepartments)
        {
          'label': dept.name,
          'count': directoryUsers.where((u) => u.departmentId == dept.id).length,
          'icon': CupertinoIcons.building_2_fill,
          'deptId': dept.id,
        },
    ];

    if (_selectedFilterIndex >= filterPills.length) {
      _selectedFilterIndex = 0;
    }

    // ── Apple Top Search Bar ──
    final searchBar = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.search,
            size: 18,
            color: isDark ? Colors.white54 : const Color(0xFF8E8E93),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: 'البحث في دليل الموظفين والأقسام...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : const Color(0xFF8E8E93),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_searchController.text.trim().isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() {});
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black26,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
              ),
            ),
        ],
      ),
    );

    // ── Horizontal Filter Bar ──
    final filterBar = SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filterPills.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          final isSelected = _selectedFilterIndex == idx;
          final pill = filterPills[idx];
          final isOnlinePill = pill['isOnline'] == true;

          return GestureDetector(
            onTap: () => setState(() => _selectedFilterIndex = idx),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF007AFF)
                    : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF007AFF)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.08)),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    pill['icon'] as IconData,
                    size: isOnlinePill ? 8 : 13,
                    color: isSelected
                        ? Colors.white
                        : (isOnlinePill
                            ? const Color(0xFF22C55E)
                            : (isDark ? Colors.white70 : const Color(0xFF6E6E73))),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${pill['label']}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.25)
                          : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${pill['count']}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF6E6E73)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    // ── Content builder ──
    List<Widget> contentWidgets = [];

    if (directoryUsers.isEmpty) {
      contentWidgets.add(_buildEmptyDirectoryState(isDark));
    } else if (query.isNotEmpty) {
      final searchResults = directoryUsers.where((u) {
        final dept = departmentById[u.departmentId];
        return u.displayName.toLowerCase().contains(query) ||
            u.username.toLowerCase().contains(query) ||
            u.jobTitle.toLowerCase().contains(query) ||
            (dept?.name.toLowerCase().contains(query) ?? false);
      }).toList();

      if (searchResults.isEmpty) {
        contentWidgets.add(_buildEmptySearchState(query, isDark));
      } else {
        contentWidgets.add(
          _buildSectionHeader('نتائج البحث', searchResults.length, isDark),
        );
        contentWidgets.add(
          _buildUserGroupCard(searchResults, departmentById, cardBg, isDark),
        );
      }
    } else if (_selectedFilterIndex == 1) {
      // Online users
      if (onlineUsers.isEmpty) {
        contentWidgets.add(_buildNoOnlineUsersState(isDark));
      } else {
        contentWidgets.add(
          _buildSectionHeader('المتصلون الآن', onlineUsers.length, isDark),
        );
        contentWidgets.add(
          _buildUserGroupCard(onlineUsers, departmentById, cardBg, isDark),
        );
      }
    } else if (_selectedFilterIndex >= 2) {
      // Specific department
      final selectedPill = filterPills[_selectedFilterIndex];
      final deptId = selectedPill['deptId'] as String?;
      final deptUsers = directoryUsers.where((u) => u.departmentId == deptId).toList();
      contentWidgets.add(
        _buildSectionHeader(selectedPill['label'] as String, deptUsers.length, isDark),
      );
      contentWidgets.add(
        _buildUserGroupCard(deptUsers, departmentById, cardBg, isDark),
      );
    } else {
      // All - grouped by department
      for (final dept in activeDepartments) {
        final deptUsers = directoryUsers.where((u) => u.departmentId == dept.id).toList();
        if (deptUsers.isEmpty) continue;
        deptUsers.sort((a, b) => a.displayName.compareTo(b.displayName));

        contentWidgets.add(
          _buildSectionHeader(dept.name, deptUsers.length, isDark),
        );
        contentWidgets.add(
          _buildUserGroupCard(deptUsers, departmentById, cardBg, isDark),
        );
        contentWidgets.add(const SizedBox(height: 14));
      }

      // Users without department
      final noDeptUsers = directoryUsers.where((u) => u.departmentId == null).toList();
      if (noDeptUsers.isNotEmpty) {
        noDeptUsers.sort((a, b) => a.displayName.compareTo(b.displayName));
        contentWidgets.add(
          _buildSectionHeader('بدون قسم', noDeptUsers.length, isDark),
        );
        contentWidgets.add(
          _buildUserGroupCard(noDeptUsers, departmentById, cardBg, isDark),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
      children: [
        searchBar,
        const SizedBox(height: 10),
        filterBar,
        const SizedBox(height: 14),
        ...contentWidgets,
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : const Color(0xFF6E6E73),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white60 : const Color(0xFF8E8E93),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserGroupCard(
    List<ChatDirectoryUser> users,
    Map<String, DepartmentSummary> departmentById,
    Color cardBg,
    bool isDark,
  ) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Column(
        children: List.generate(users.length, (idx) {
          final user = users[idx];
          final isLast = idx == users.length - 1;
          final dept = departmentById[user.departmentId];

          return Column(
            children: [
              _AppleContactTile(
                user: user,
                departmentName: dept?.name,
                isDark: isDark,
                onTap: () => _startConversation(user),
              ),
              if (!isLast)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 68.0),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildEmptySearchState(String query, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          children: [
            Icon(
              CupertinoIcons.search,
              size: 48,
              color: isDark ? Colors.white30 : const Color(0xFFC7C7CC),
            ),
            const SizedBox(height: 12),
            const Text(
              'لا توجد نتائج بحث',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'لم يتم العثور على موظف يطابق "$query"',
              style: TextStyle(
                color: isDark ? Colors.white54 : const Color(0xFF8E8E93),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoOnlineUsersState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          children: [
            Icon(
              CupertinoIcons.moon_fill,
              size: 46,
              color: isDark ? Colors.white30 : const Color(0xFFC7C7CC),
            ),
            const SizedBox(height: 12),
            const Text(
              'لا يوجد زملاء متصلون الآن',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'جميع الموظفين غير متصلين حالياً أو خاملين',
              style: TextStyle(
                color: isDark ? Colors.white54 : const Color(0xFF8E8E93),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyDirectoryState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(50),
      child: Center(
        child: Column(
          children: [
            Icon(
              CupertinoIcons.person_2,
              size: 52,
              color: isDark ? Colors.white30 : const Color(0xFFC7C7CC),
            ),
            const SizedBox(height: 14),
            const Text(
              'دليل الموظفين فارغ',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            const SizedBox(height: 6),
            Text(
              'حين يتم إنشاء وتفعيل حسابات الموظفين ستظهر هنا تلقائياً.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white54 : const Color(0xFF8E8E93),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppleContactTile extends StatelessWidget {
  const _AppleContactTile({
    required this.user,
    this.departmentName,
    required this.isDark,
    required this.onTap,
  });

  final ChatDirectoryUser user;
  final String? departmentName;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOnline = user.presenceStatus == 'online' || user.isOnline;
    final isIdle = user.presenceStatus == 'idle';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // Avatar with presence badge
              Stack(
                children: [
                  ChatAvatar(
                    radius: 22,
                    avatarUrl: user.avatarUrl,
                    backgroundColor: const Color(0xFF007AFF).withValues(alpha: isDark ? 0.2 : 0.12),
                    fallback: Text(
                      _avatarLabel(user.displayName),
                      style: const TextStyle(
                        color: Color(0xFF007AFF),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (isOnline || isIdle)
                    PositionedDirectional(
                      end: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isOnline ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Name + Job/Department
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.jobTitle.isNotEmpty
                                ? user.jobTitle
                                : (departmentName ?? '@${user.username}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : const Color(0xFF8E8E93),
                            ),
                          ),
                        ),
                        if (departmentName != null && user.jobTitle.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              departmentName!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white60 : const Color(0xFF6E6E73),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Presence text + Quick chat button
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _presenceText(user),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isOnline ? FontWeight.w600 : FontWeight.w400,
                      color: isOnline
                          ? const Color(0xFF22C55E)
                          : (isDark ? Colors.white38 : const Color(0xFF8E8E93)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withValues(alpha: isDark ? 0.18 : 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.chat_bubble_fill,
                      size: 14,
                      color: Color(0xFF007AFF),
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

String _presenceText(ChatDirectoryUser user) {
  if (user.presenceStatus == 'online' || user.isOnline) return 'متصل الآن';
  if (user.presenceStatus == 'idle') {
    final at = user.lastActiveAt ?? user.lastSeen;
    return at == null ? 'خامل' : 'خامل ${formatEgyptTime(at)}';
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
