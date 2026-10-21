import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/providers.dart';
import '../../models/chat_models.dart';
import 'chat_avatar.dart';

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

class ChatForwardSheet extends ConsumerStatefulWidget {
  const ChatForwardSheet({
    super.key,
    required this.currentUserId,
    required this.currentConversationId,
    required this.selectedMessageCount,
  });

  final String currentUserId;
  final String currentConversationId;
  final int selectedMessageCount;

  static Future<List<ForwardTarget>?> show(
    BuildContext context, {
    required String currentUserId,
    required String currentConversationId,
    required int selectedMessageCount,
  }) {
    return showModalBottomSheet<List<ForwardTarget>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatForwardSheet(
        currentUserId: currentUserId,
        currentConversationId: currentConversationId,
        selectedMessageCount: selectedMessageCount,
      ),
    );
  }

  @override
  ConsumerState<ChatForwardSheet> createState() => _ChatForwardSheetState();
}

class _ChatForwardSheetState extends ConsumerState<ChatForwardSheet>
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
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final overview = ref.watch(chatOverviewControllerProvider).valueOrNull;

    final sheetBgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final searchBgColor =
        isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final borderColor =
        isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);

    if (overview == null) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          height: 300,
          decoration: BoxDecoration(
            color: sheetBgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: const Center(child: CircularProgressIndicator.adaptive()),
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

    // Map users to departments without duplicates
    final usersByDept = <String, List<ChatDirectoryUser>>{};
    final userSeenInDept = <String, Set<String>>{};

    for (final user in allOtherUsers) {
      final deptId = user.departmentId?.trim();
      if (deptId != null && deptId.isNotEmpty) {
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

    // 1. Recent chats
    final recentConversations = overview.conversations
        .where((conv) => conv.id != widget.currentConversationId)
        .where((conv) {
          if (query.isEmpty) return true;
          final title = conv.displayTitle(widget.currentUserId).toLowerCase();
          return title.contains(query);
        })
        .toList();

    // 2. Users
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

    // 4. Groups
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

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        top: false,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: BoxDecoration(
            color: sheetBgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // ── Drag Handle ──────────────────────────────────────────────
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 36,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),

              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.forward_to_inbox_rounded,
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
                      onPressed: () => Navigator.of(context).pop(null),
                      tooltip: 'إغلاق',
                    ),
                  ],
                ),
              ),

              // ── Search Field ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: searchBgColor,
                      hintText: 'ابحث بالاسم، كود القسم، الفرع، أو اسم المستخدم...',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.cancel_rounded, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),

              // ── Tab Bar ─────────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: searchBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(2.5),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: sheetBgColor,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  labelColor: isDark ? Colors.white : const Color(0xFF1C1C1E),
                  unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
                  labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                          const SizedBox(width: 4),
                          Text('المحادثات (${recentConversations.length})'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person_outline_rounded, size: 14),
                          const SizedBox(width: 4),
                          Text('الزملاء (${filteredUsers.length})'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.corporate_fare_rounded, size: 14),
                          const SizedBox(width: 4),
                          Text('الأقسام (${filteredDepartments.length})'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.groups_outlined, size: 14),
                          const SizedBox(width: 4),
                          Text('المجموعات (${filteredGroups.length})'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Tab Bar Views ───────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRecentConversationsTab(recentConversations, isDark, borderColor),
                    _buildUsersTab(filteredUsers, departmentsById, isDark, borderColor),
                    _buildDepartmentsTab(filteredDepartments, usersByDept, overview.conversations, isDark, borderColor),
                    _buildGroupsTab(filteredGroups, isDark, borderColor),
                  ],
                ),
              ),

              // ── Footer Bar with Multi-select Actions ───────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: sheetBgColor,
                  border: Border(
                    top: BorderSide(color: borderColor, width: 0.8),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedTargets.isEmpty
                                ? 'يرجى اختيار جهة واحدة على الأقل'
                                : 'تم تحديد: ${_selectedTargets.length} وجهة',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _selectedTargets.isEmpty
                                  ? (isDark ? Colors.white38 : Colors.black38)
                                  : const Color(0xFF007AFF),
                            ),
                          ),
                          if (_selectedTargets.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            GestureDetector(
                              onTap: () => setState(() => _selectedTargets.clear()),
                              child: const Text(
                                'مسح كل التحديدات',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      onPressed: _selectedTargets.isNotEmpty
                          ? () => Navigator.of(context).pop(_selectedTargets.toList())
                          : null,
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: Text(
                        _selectedTargets.length > 1
                            ? 'إرسال (${_selectedTargets.length})'
                            : 'إعادة التوجيه',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab 1: Recent Conversations ──────────────────────────────────────────
  Widget _buildRecentConversationsTab(
    List<ChatConversation> conversations,
    bool isDark,
    Color borderColor,
  ) {
    if (conversations.isEmpty) {
      return _buildEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'لا توجد محادثات سابقة',
        subtitle: 'يمكنك اختيار أحد الزملاء أو الأقسام من التبويبات الأخرى.',
        isDark: isDark,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final conv = conversations[index];
        final targetId = 'conv_' + conv.id;
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
          borderColor: borderColor,
          leading: ChatAvatar(
            radius: 19,
            backgroundColor: const Color(0xFF007AFF).withValues(alpha: 0.15),
            avatarUrl: conv.members.where((m) => m.id != widget.currentUserId).firstOrNull?.avatarUrl,
            fallback: Text(
              conv.displayTitle(widget.currentUserId).isNotEmpty
                  ? conv.displayTitle(widget.currentUserId)[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF007AFF),
              ),
            ),
          ),
          title: conv.displayTitle(widget.currentUserId),
          subtitle: _conversationTypeLabel(conv),
        );
      },
    );
  }

  // ── Tab 2: Users Directory ───────────────────────────────────────────────
  Widget _buildUsersTab(
    List<ChatDirectoryUser> users,
    Map<String, DepartmentSummary> departmentsById,
    bool isDark,
    Color borderColor,
  ) {
    if (users.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_search_rounded,
        title: 'لا يوجد زملاء مطابقون للبحث',
        subtitle: 'جرّب البحث باسم الموظف أو كود الفرع أو القسم.',
        isDark: isDark,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        final targetId = 'user_' + user.id;
        final isSelected = _isTargetSelected(targetId);

        final deptName = departmentsById[user.departmentId]?.name ?? '';
        final subtitle = deptName.isNotEmpty
            ? deptName + ' • ' + user.branchCode
            : '@' + user.username + ' • ' + user.branchCode;

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
          borderColor: borderColor,
          leading: Stack(
            children: [
              ChatAvatar(
                radius: 19,
                backgroundColor: const Color(0xFF007AFF).withValues(alpha: 0.15),
                avatarUrl: user.avatarUrl,
                fallback: Text(
                  user.displayName.isNotEmpty
                      ? user.displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF007AFF),
                  ),
                ),
              ),
              if (user.isOnline)
                Positioned(
                  bottom: 0,
                  right: 0,
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
          ),
          title: user.displayName,
          subtitle: subtitle,
          trailingBadge: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '@' + user.username,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Tab 3: Departments ───────────────────────────────────────────────────
  Widget _buildDepartmentsTab(
    List<DepartmentSummary> departments,
    Map<String, List<ChatDirectoryUser>> usersByDept,
    List<ChatConversation> allConversations,
    bool isDark,
    Color borderColor,
  ) {
    if (departments.isEmpty) {
      return _buildEmptyState(
        icon: Icons.domain_disabled_rounded,
        title: 'لا توجد أقسام مطابقة للبحث',
        subtitle: 'جرّب البحث باسم القسم أو الكود.',
        isDark: isDark,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: departments.length,
      itemBuilder: (context, index) {
        final dept = departments[index];
        final deptUsers = usersByDept[dept.id] ?? const <ChatDirectoryUser>[];
        final targetId = 'dept_' + dept.id;
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

        final target = ForwardTarget(
          id: targetId,
          kind: ForwardTargetKind.department,
          title: 'قسم ' + dept.name,
          subtitle: dept.code + ' • ' + deptUsers.length.toString() + ' أعضاء',
          department: dept,
          departmentUsers: deptUsers,
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isDeptSelected
                ? const Color(0xFF007AFF).withValues(alpha: isDark ? 0.12 : 0.06)
                : (isDark ? const Color(0xFF242426) : const Color(0xFFF8F9FA)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDeptSelected
                  ? const Color(0xFF007AFF).withValues(alpha: 0.4)
                  : borderColor,
              width: isDeptSelected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              InkWell(
                onTap: () => _toggleTarget(target),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  dept.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF34C759).withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    'كامل القسم',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF34C759),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dept.code + ' • ' + deptUsers.length.toString() + ' أعضاء بالقسم',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Checkbox for full department
                      Checkbox(
                        value: isDeptSelected,
                        activeColor: const Color(0xFF007AFF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (_) => _toggleTarget(target),
                      ),
                      // Expand members button
                      if (deptUsers.isNotEmpty)
                        IconButton(
                          icon: Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 22,
                            color: isDark ? Colors.white60 : Colors.black45,
                          ),
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

              // Expanded individual members list
              if (isExpanded && visibleDeptUsers.isNotEmpty) ...[
                Divider(height: 1, color: borderColor),
                Container(
                  color: isDark
                      ? const Color(0xFF1E1E20).withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.6),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: visibleDeptUsers.map((member) {
                      final memberTargetId = 'user_' + member.id;
                      final isMemberSelected = _isTargetSelected(memberTargetId);

                      final memberTarget = ForwardTarget(
                        id: memberTargetId,
                        kind: ForwardTargetKind.user,
                        title: member.displayName,
                        subtitle: dept.name + ' • ' + member.branchCode,
                        avatarUrl: member.avatarUrl,
                        user: member,
                      );

                      return InkWell(
                        onTap: () => _toggleTarget(memberTarget),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                          child: Row(
                            children: [
                              ChatAvatar(
                                radius: 15,
                                backgroundColor: const Color(0xFF007AFF).withValues(alpha: 0.12),
                                avatarUrl: member.avatarUrl,
                                fallback: Text(
                                  member.displayName.isNotEmpty
                                      ? member.displayName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: Color(0xFF007AFF),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  member.displayName,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                                ),
                              ),
                              Text(
                                member.branchCode,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                              Checkbox(
                                value: isMemberSelected,
                                activeColor: const Color(0xFF007AFF),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                onChanged: (_) => _toggleTarget(memberTarget),
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

  // ── Tab 4: Groups ────────────────────────────────────────────────────────
  Widget _buildGroupsTab(
    List<ChatConversation> groups,
    bool isDark,
    Color borderColor,
  ) {
    if (groups.isEmpty) {
      return _buildEmptyState(
        icon: Icons.groups_outlined,
        title: 'لا توجد مجموعات مطابقة',
        subtitle: 'جرّب البحث باسم المجموعة أو تصفح الأقسام.',
        isDark: isDark,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final targetId = 'conv_' + group.id;
        final isSelected = _isTargetSelected(targetId);

        final target = ForwardTarget(
          id: targetId,
          kind: ForwardTargetKind.conversation,
          title: group.name,
          subtitle: group.type == 'broadcast' ? 'قناة إعلانية' : 'مجموعة عمل',
          conversation: group,
        );

        return _buildSelectableTile(
          isSelected: isSelected,
          onTap: () => _toggleTarget(target),
          isDark: isDark,
          borderColor: borderColor,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (group.type == 'broadcast'
                      ? const Color(0xFFFF9500)
                      : const Color(0xFF5856D6))
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              group.type == 'broadcast' ? Icons.campaign_rounded : Icons.groups_rounded,
              color: group.type == 'broadcast'
                  ? const Color(0xFFFF9500)
                  : const Color(0xFF5856D6),
              size: 20,
            ),
          ),
          title: group.name,
          subtitle: group.description.isNotEmpty
              ? group.description
              : (group.type == 'broadcast' ? 'قناة إعلانية' : 'مجموعة عمل'),
        );
      },
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  Widget _buildSelectableTile({
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    required Color borderColor,
    required Widget leading,
    required String title,
    required String subtitle,
    Widget? trailingBadge,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF007AFF).withValues(alpha: isDark ? 0.12 : 0.06)
            : (isDark ? const Color(0xFF242426) : const Color(0xFFF8F9FA)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF007AFF).withValues(alpha: 0.4)
              : borderColor,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (_) => onTap(),
        activeColor: const Color(0xFF007AFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        secondary: leading,
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ),
            if (trailingBadge != null) trailingBadge,
          ],
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 42, color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _conversationTypeLabel(ChatConversation conv) {
    return switch (conv.type) {
      'direct' => 'محادثة مباشرة',
      'department' => 'غرفة قسم',
      'broadcast' => 'قناة إعلانية',
      _ => 'مجموعة عمل',
    };
  }
}
