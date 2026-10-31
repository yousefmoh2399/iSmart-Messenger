import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/safe_network_avatar.dart';
import '../../models/chat_models.dart';
import '../../../../shared/providers/providers.dart';

enum ForwardTargetKind {
  conversation,
  user,
  department,
}

class ForwardTarget {
  const ForwardTarget({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle,
    this.avatarUrl,
    this.conversation,
    this.user,
    this.department,
    this.departmentUsers,
  });

  final String id;
  final ForwardTargetKind kind;
  final String title;
  final String? subtitle;
  final String? avatarUrl;
  final ChatConversation? conversation;
  final ChatDirectoryUser? user;
  final DepartmentSummary? department;
  final List<ChatDirectoryUser>? departmentUsers;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForwardTarget &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class ChatForwardDialog extends ConsumerStatefulWidget {
  const ChatForwardDialog({
    super.key,
    required this.currentUserId,
    required this.currentConversationId,
    required this.selectedMessageCount,
    this.token,
  });

  final String currentUserId;
  final String currentConversationId;
  final int selectedMessageCount;
  final String? token;

  static Future<List<ForwardTarget>?> show(
    BuildContext context, {
    required String currentUserId,
    required String currentConversationId,
    required int selectedMessageCount,
    String? token,
  }) {
    return showDialog<List<ForwardTarget>>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ChatForwardDialog(
        currentUserId: currentUserId,
        currentConversationId: currentConversationId,
        selectedMessageCount: selectedMessageCount,
        token: token,
      ),
    );
  }

  @override
  ConsumerState<ChatForwardDialog> createState() => _ChatForwardDialogState();
}

class _ChatForwardDialogState extends ConsumerState<ChatForwardDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<ForwardTarget> _selectedTargets = <ForwardTarget>{};
  final Set<String> _expandedDepartmentIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _isTargetSelected(String id) {
    return _selectedTargets.any((target) => target.id == id);
  }

  void _toggleTarget(ForwardTarget target) {
    setState(() {
      if (_isTargetSelected(target.id)) {
        _selectedTargets.removeWhere((t) => t.id == target.id);
      } else {
        _selectedTargets.add(target);
      }
    });
  }

  Map<String, String>? get _authHeaders => widget.token != null
      ? {'Authorization': 'Bearer ${widget.token}'}
      : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

    final overview = ref.watch(chatOverviewControllerProvider).valueOrNull;

    if (overview == null) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: const SizedBox(
            width: 320,
            height: 200,
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
        ),
      );
    }

    final departmentsById = <String, DepartmentSummary>{
      for (final dept in overview.departments) dept.id: dept,
    };

    final seenUserIds = <String>{};
    final allOtherUsers = overview.users
        .where((user) => user.id != widget.currentUserId && seenUserIds.add(user.id))
        .toList();

    final usersByDept = <String, List<ChatDirectoryUser>>{};
    final userSeenInDept = <String, Set<String>>{};

    for (final user in allOtherUsers) {
      final deptIdSet = <String>{};
      if (user.departmentId != null && user.departmentId!.trim().isNotEmpty) {
        deptIdSet.add(user.departmentId!.trim());
      }
      for (final id in user.departmentIds) {
        final trimmed = id.trim();
        if (trimmed.isNotEmpty) {
          deptIdSet.add(trimmed);
        }
      }

      for (final deptId in deptIdSet) {
        final seen = userSeenInDept.putIfAbsent(deptId, () => <String>{});
        if (seen.add(user.id)) {
          usersByDept.putIfAbsent(deptId, () => <ChatDirectoryUser>[]).add(user);
        }
      }
    }

    for (final list in usersByDept.values) {
      list.sort((a, b) => a.displayName.compareTo(b.displayName));
    }

    final query = _searchQuery.trim().toLowerCase();

    // 1. Recent chats (excluding current chat)
    final recentConversations = overview.conversations
        .where((conv) => conv.id != widget.currentConversationId)
        .where((conv) {
          if (query.isEmpty) return true;
          final title = conv.displayTitle(widget.currentUserId).toLowerCase();
          return title.contains(query);
        })
        .toList();

    // 2. All Directory Users
    final filteredUsers = allOtherUsers.where((user) {
      if (query.isEmpty) return true;
      final name = user.displayName.toLowerCase();
      final username = user.username.toLowerCase();
      final branch = user.branchCode.toLowerCase();
      final deptName = (departmentsById[user.departmentId]?.name ?? '').toLowerCase();
      return name.contains(query) ||
          username.contains(query) ||
          branch.contains(query) ||
          deptName.contains(query);
    }).toList();

    // 3. Departments
    final filteredDepartments = overview.departments.where((dept) {
      if (query.isEmpty) return true;
      final deptMatches = dept.name.toLowerCase().contains(query) ||
          dept.code.toLowerCase().contains(query) ||
          dept.description.toLowerCase().contains(query);
      if (deptMatches) return true;
      final deptMembers = usersByDept[dept.id] ?? const [];
      return deptMembers.any((u) =>
          u.displayName.toLowerCase().contains(query) ||
          u.username.toLowerCase().contains(query) ||
          u.branchCode.toLowerCase().contains(query));
    }).toList();

    // 4. Groups & Broadcasts
    final filteredGroups = overview.conversations
        .where((conv) =>
            conv.id != widget.currentConversationId &&
            (conv.type == 'group' || conv.type == 'broadcast'))
        .where((conv) {
          if (query.isEmpty) return true;
          final name = conv.name.toLowerCase();
          final desc = conv.description.toLowerCase();
          return name.contains(query) || desc.contains(query);
        })
        .toList();

    final cardBgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final searchBgColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final borderColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: cardBgColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: borderColor, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: SizedBox(
          width: 580,
          height: 660,
          child: Column(
            children: [
              // ── Header Bar ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: borderColor, width: 0.8)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.forward_rounded,
                        color: Color(0xFF007AFF),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.selectedMessageCount > 1
                                ? 'إعادة توجيه ${widget.selectedMessageCount} رسائل'
                                : 'إعادة توجيه رسالة',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'اختر شخصاً، قسماً بالكامل، أو مجموعة لإعادة التوجيه',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.of(context).pop(null),
                    ),
                  ],
                ),
              ),

              // ── Search Field ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: searchBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم، كود القسم، الفرع، أو اسم المستخدم...',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      prefixIconColor: isDark ? Colors.white54 : Colors.black45,
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.cancel_rounded, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                    ),
                  ),
                ),
              ),

              // ── Tab Bar ─────────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: searchBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(3),
                child: TabBar(
                  controller: _tabController,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: isDark ? const Color(0xFF3A3A3C) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  labelColor: isDark ? Colors.white : Colors.black87,
                  unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
                  labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 12),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                          const SizedBox(width: 5),
                          Text('المحادثات (${recentConversations.length})'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person_outline_rounded, size: 16),
                          const SizedBox(width: 5),
                          Text('الزملاء (${filteredUsers.length})'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.corporate_fare_rounded, size: 16),
                          const SizedBox(width: 5),
                          Text('الأقسام (${filteredDepartments.length})'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.groups_outlined, size: 16),
                          const SizedBox(width: 5),
                          Text('المجموعات (${filteredGroups.length})'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Tab Bar Content ─────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Recent Conversations
                    _buildRecentConversationsTab(
                      recentConversations,
                      isDark,
                    ),

                    // Tab 2: Users Directory
                    _buildUsersTab(
                      filteredUsers,
                      departmentsById,
                      isDark,
                    ),

                    // Tab 3: Departments
                    _buildDepartmentsTab(
                      filteredDepartments,
                      usersByDept,
                      overview.conversations,
                      isDark,
                    ),

                    // Tab 4: Groups & Channels
                    _buildGroupsTab(
                      filteredGroups,
                      isDark,
                    ),
                  ],
                ),
              ),

              // ── Bottom Selected Tray & Action Buttons ──────────────────
              _buildBottomBar(context, isDark, borderColor),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab 1: Recent Conversations ─────────────────────────────────────────
  Widget _buildRecentConversationsTab(
    List<ChatConversation> conversations,
    bool isDark,
  ) {
    if (conversations.isEmpty) {
      return _buildEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'لا توجد محادثات مطابقة',
        subtitle: 'جرّب البحث باسم محادثة أو تصفح تبويب الزملاء والأقسام.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: conversations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final conv = conversations[index];
        final targetId = 'conv_${conv.id}';
        final isSelected = _isTargetSelected(targetId);

        final target = ForwardTarget(
          id: targetId,
          kind: ForwardTargetKind.conversation,
          title: conv.displayTitle(widget.currentUserId),
          subtitle: _conversationTypeLabel(conv),
          conversation: conv,
        );

        return _buildSelectableTile(
          isSelected: isSelected,
          onTap: () => _toggleTarget(target),
          isDark: isDark,
          leading: _buildConversationAvatar(conv, isDark),
          title: conv.displayTitle(widget.currentUserId),
          subtitle: _conversationTypeLabel(conv),
          badge: _buildConversationTypeBadge(conv.type, isDark),
        );
      },
    );
  }

  // ── Tab 2: Users Directory ──────────────────────────────────────────────
  Widget _buildUsersTab(
    List<ChatDirectoryUser> users,
    Map<String, DepartmentSummary> departmentsById,
    bool isDark,
  ) {
    if (users.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_search_rounded,
        title: 'لا يوجد زملاء مطابقون',
        subtitle: 'جرّب تغيير كلمات البحث بالاسم أو الكود أو الفرع.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final user = users[index];
        final targetId = 'user_${user.id}';
        final isSelected = _isTargetSelected(targetId);

        final deptName = departmentsById[user.departmentId]?.name ?? '';
        final subtitle = deptName.isNotEmpty
            ? '$deptName • ${user.branchCode}'
            : '@${user.username} • ${user.branchCode}';

        final target = ForwardTarget(
          id: targetId,
          kind: ForwardTargetKind.user,
          title: user.displayName,
          subtitle: subtitle,
          avatarUrl: user.avatarUrl,
          user: user,
        );

        return _buildSelectableTile(
          isSelected: isSelected,
          onTap: () => _toggleTarget(target),
          isDark: isDark,
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              SafeNetworkAvatar(
                radius: 18,
                backgroundColor: isDark
                    ? const Color(0xFF2C3E50)
                    : const Color(0xFFDCE6F2),
                imageUrl: user.avatarUrl,
                httpHeaders: _authHeaders,
                fallbackText: user.displayName.isNotEmpty
                    ? user.displayName[0].toUpperCase()
                    : '?',
                fallbackTextStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF24415C),
                ),
              ),
              if (user.isOnline)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759),
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
          title: user.displayName,
          subtitle: subtitle,
          badge: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '@${user.username}',
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Tab 3: Departments ──────────────────────────────────────────────────
  Widget _buildDepartmentsTab(
    List<DepartmentSummary> departments,
    Map<String, List<ChatDirectoryUser>> usersByDept,
    List<ChatConversation> allConversations,
    bool isDark,
  ) {
    if (departments.isEmpty) {
      return _buildEmptyState(
        icon: Icons.domain_disabled_rounded,
        title: 'لا توجد أقسام مطابقة',
        subtitle: 'جرّب البحث باسم أو رمز القسم.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: departments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final dept = departments[index];
        final deptUsers = usersByDept[dept.id] ?? const <ChatDirectoryUser>[];
        final targetId = 'dept_${dept.id}';
        final isDeptSelected = _isTargetSelected(targetId);

        final query = _searchQuery.trim().toLowerCase();
        final deptDirectMatch = query.isEmpty ||
            dept.name.toLowerCase().contains(query) ||
            dept.code.toLowerCase().contains(query) ||
            dept.description.toLowerCase().contains(query);

        final visibleDeptUsers = deptDirectMatch
            ? deptUsers
            : deptUsers.where((u) {
                return u.displayName.toLowerCase().contains(query) ||
                    u.username.toLowerCase().contains(query) ||
                    u.branchCode.toLowerCase().contains(query);
              }).toList();

        final isExpanded = _expandedDepartmentIds.contains(dept.id);

        ChatConversation? roomConv;
        for (final c in allConversations) {
          if (c.departmentId == dept.id || c.id == dept.defaultConversationId) {
            roomConv = c;
            break;
          }
        }

        final target = ForwardTarget(
          id: targetId,
          kind: ForwardTargetKind.department,
          title: 'قسم ${dept.name}',
          subtitle: '${dept.code} • ${deptUsers.length} أعضاء',
          department: dept,
          departmentUsers: deptUsers,
        );

        final borderColor = isDeptSelected
            ? const Color(0xFF007AFF)
            : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA));

        return Container(
          decoration: BoxDecoration(
            color: isDeptSelected
                ? const Color(0xFF007AFF).withValues(alpha: isDark ? 0.12 : 0.06)
                : (isDark ? const Color(0xFF252528) : const Color(0xFFF9F9FB)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: isDeptSelected ? 1.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              InkWell(
                onTap: () => _toggleTarget(target),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    children: [
                      // Department Icon
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF34C759).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.corporate_fare_rounded,
                          color: Color(0xFF34C759),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Name & Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    dept.name,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF3A3A3C)
                                        : const Color(0xFFE5E5EA),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    dept.code,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Colors.white70 : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              roomConv != null
                                  ? '${deptUsers.length} أعضاء • غرفة القسم متوفرة'
                                  : '${deptUsers.length} أعضاء • إرسال لجميع الأعضاء',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Checkbox for whole department
                      Tooltip(
                        message: isDeptSelected
                            ? 'إلغاء تحديد القسم بالكامل'
                            : 'تحديد القسم بالكامل',
                        child: IconButton(
                          icon: Icon(
                            isDeptSelected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: isDeptSelected
                                ? const Color(0xFF007AFF)
                                : (isDark ? Colors.white38 : Colors.black38),
                            size: 22,
                          ),
                          onPressed: () => _toggleTarget(target),
                        ),
                      ),
                      // Chevron to expand members
                      if (deptUsers.isNotEmpty)
                        IconButton(
                          icon: Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                          tooltip: isExpanded ? 'طي الأعضاء' : 'عرض أعضاء القسم',
                          onPressed: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedDepartmentIds.remove(dept.id);
                              } else {
                                _expandedDepartmentIds.add(dept.id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ),

              // Expanded members list
              if (isExpanded && visibleDeptUsers.isNotEmpty) ...[
                Divider(
                  height: 1,
                  thickness: 0.8,
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                ),
                Container(
                  color: isDark ? const Color(0xFF1E1E20) : const Color(0xFFF3F3F5),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: visibleDeptUsers.map((member) {
                      final memberTargetId = 'user_${member.id}';
                      final isMemberSelected = _isTargetSelected(memberTargetId);

                      final memberTarget = ForwardTarget(
                        id: memberTargetId,
                        kind: ForwardTargetKind.user,
                        title: member.displayName,
                        subtitle: '@${member.username} • ${dept.name}',
                        avatarUrl: member.avatarUrl,
                        user: member,
                      );

                      return InkWell(
                        onTap: () => _toggleTarget(memberTarget),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              SafeNetworkAvatar(
                                radius: 14,
                                backgroundColor: isDark
                                    ? const Color(0xFF2C3E50)
                                    : const Color(0xFFDCE6F2),
                                imageUrl: member.avatarUrl,
                                httpHeaders: _authHeaders,
                                fallbackText: member.displayName.isNotEmpty
                                    ? member.displayName[0].toUpperCase()
                                    : '?',
                                fallbackTextStyle: TextStyle(
                                  fontSize: 10,
                                  color: isDark ? Colors.white : const Color(0xFF24415C),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  member.displayName,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                              Icon(
                                isMemberSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: isMemberSelected
                                    ? const Color(0xFF007AFF)
                                    : (isDark ? Colors.white38 : Colors.black38),
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Tab 4: Groups & Channels ────────────────────────────────────────────
  Widget _buildGroupsTab(
    List<ChatConversation> groups,
    bool isDark,
  ) {
    if (groups.isEmpty) {
      return _buildEmptyState(
        icon: Icons.groups_rounded,
        title: 'لا توجد مجموعات أو قنوات مطابقة',
        subtitle: 'المجموعات والقنوات التي تشارك فيها ستظهر هنا.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final group = groups[index];
        final targetId = 'conv_${group.id}';
        final isSelected = _isTargetSelected(targetId);

        final target = ForwardTarget(
          id: targetId,
          kind: ForwardTargetKind.conversation,
          title: group.name,
          subtitle: group.type == 'broadcast'
              ? 'قناة بث إعلانية'
              : 'مجموعة • ${group.members.length} أعضاء',
          conversation: group,
        );

        final isBroadcast = group.type == 'broadcast';

        return _buildSelectableTile(
          isSelected: isSelected,
          onTap: () => _toggleTarget(target),
          isDark: isDark,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (isBroadcast
                      ? const Color(0xFFFF9500)
                      : const Color(0xFF5856D6))
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isBroadcast ? Icons.campaign_rounded : Icons.groups_rounded,
              color: isBroadcast ? const Color(0xFFFF9500) : const Color(0xFF5856D6),
              size: 20,
            ),
          ),
          title: group.name,
          subtitle: group.type == 'broadcast'
              ? 'قناة بث إعلانية'
              : 'مجموعة • ${group.members.length} أعضاء',
          badge: _buildConversationTypeBadge(group.type, isDark),
        );
      },
    );
  }

  // ── Tile Builder Helper ─────────────────────────────────────────────────
  Widget _buildSelectableTile({
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    required Widget leading,
    required String title,
    required String subtitle,
    Widget? badge,
  }) {
    final borderColor = isSelected
        ? const Color(0xFF007AFF)
        : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF007AFF).withValues(alpha: isDark ? 0.12 : 0.06)
              : (isDark ? const Color(0xFF252528) : const Color(0xFFF9F9FB)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        badge,
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isSelected
                  ? const Color(0xFF007AFF)
                  : (isDark ? Colors.white38 : Colors.black38),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ── Conversation Avatar Helper ──────────────────────────────────────────
  Widget _buildConversationAvatar(ChatConversation conv, bool isDark) {
    if (conv.type == 'direct') {
      final other = conv.members.where((m) => m.id != widget.currentUserId).firstOrNull;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          SafeNetworkAvatar(
            radius: 18,
            backgroundColor: isDark
                ? const Color(0xFF2C3E50)
                : const Color(0xFFDCE6F2),
            imageUrl: other?.avatarUrl,
            httpHeaders: _authHeaders,
            fallbackText: conv.displayTitle(widget.currentUserId).isNotEmpty
                ? conv.displayTitle(widget.currentUserId)[0].toUpperCase()
                : '?',
            fallbackTextStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF24415C),
            ),
          ),
          if (other?.isOnline ?? false)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    final isBroadcast = conv.type == 'broadcast';
    final isDept = conv.type == 'department';

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: (isDept
                ? const Color(0xFF34C759)
                : isBroadcast
                    ? const Color(0xFFFF9500)
                    : const Color(0xFF5856D6))
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        isDept
            ? Icons.corporate_fare_rounded
            : isBroadcast
                ? Icons.campaign_rounded
                : Icons.groups_rounded,
        color: isDept
            ? const Color(0xFF34C759)
            : isBroadcast
                ? const Color(0xFFFF9500)
                : const Color(0xFF5856D6),
        size: 20,
      ),
    );
  }

  // ── Conversation Type Badge Helper ──────────────────────────────────────
  Widget _buildConversationTypeBadge(String type, bool isDark) {
    final (label, color) = switch (type) {
      'direct' => ('مباشرة', const Color(0xFF007AFF)),
      'department' => ('قسم', const Color(0xFF34C759)),
      'broadcast' => ('قناة', const Color(0xFFFF9500)),
      _ => ('مجموعة', const Color(0xFF5856D6)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _conversationTypeLabel(ChatConversation conv) {
    return switch (conv.type) {
      'direct' => 'محادثة مباشرة خاصة',
      'department' => 'غرفة تابعة للقسم',
      'broadcast' => 'قناة إعلانية عامة',
      _ => 'مجموعة (${conv.members.length} أعضاء)',
    };
  }

  // ── Empty State ─────────────────────────────────────────────────────────
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom Action Bar ───────────────────────────────────────────────────
  Widget _buildBottomBar(
    BuildContext context,
    bool isDark,
    Color borderColor,
  ) {
    final count = _selectedTargets.length;
    final hasSelection = count > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E20) : const Color(0xFFF9F9FB),
        border: Border(top: BorderSide(color: borderColor, width: 0.8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Selected chips row
          if (hasSelection) ...[
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedTargets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final target = _selectedTargets.elementAt(index);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          target.title,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF007AFF),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => setState(() => _selectedTargets.remove(target)),
                          borderRadius: BorderRadius.circular(8),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: Color(0xFF007AFF),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],

          Row(
            children: [
              if (hasSelection) ...[
                Text(
                  'تم تحديد $count وجهة',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(_selectedTargets.clear),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.redAccent,
                  ),
                  child: const Text('مسح الكل', style: TextStyle(fontSize: 11.5)),
                ),
              ] else
                Text(
                  'حدد جهة واحدة أو عدة جهات للمتابعة',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),

              const Spacer(),

              // Cancel button
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(null),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  side: BorderSide(color: borderColor),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: const Text('إلغاء', style: TextStyle(fontSize: 12.5)),
              ),
              const SizedBox(width: 8),

              // Confirm Forward button
              FilledButton.icon(
                onPressed: hasSelection
                    ? () => Navigator.of(context).pop(_selectedTargets.toList())
                    : null,
                icon: const Icon(Icons.send_rounded, size: 15),
                label: Text(
                  hasSelection ? 'إعادة توجيه ($count)' : 'إعادة توجيه',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
