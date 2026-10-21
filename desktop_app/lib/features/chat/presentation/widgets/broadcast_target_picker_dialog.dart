import 'package:flutter/material.dart';

import '../../../../shared/widgets/safe_network_avatar.dart';
import '../../models/chat_models.dart';

class BroadcastTargetPickerDialog extends StatefulWidget {
  const BroadcastTargetPickerDialog({
    super.key,
    required this.departments,
    required this.users,
    required this.currentUserId,
    this.initialSendToAll = true,
    this.initialDepartmentIds = const {},
    this.initialUserIds = const {},
    this.token,
  });

  final List<DepartmentSummary> departments;
  final List<ChatDirectoryUser> users;
  final String currentUserId;
  final bool initialSendToAll;
  final Set<String> initialDepartmentIds;
  final Set<String> initialUserIds;
  final String? token;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required List<DepartmentSummary> departments,
    required List<ChatDirectoryUser> users,
    required String currentUserId,
    bool initialSendToAll = true,
    Set<String> initialDepartmentIds = const {},
    Set<String> initialUserIds = const {},
    String? token,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (_) => BroadcastTargetPickerDialog(
        departments: departments,
        users: users,
        currentUserId: currentUserId,
        initialSendToAll: initialSendToAll,
        initialDepartmentIds: initialDepartmentIds,
        initialUserIds: initialUserIds,
        token: token,
      ),
    );
  }

  @override
  State<BroadcastTargetPickerDialog> createState() =>
      _BroadcastTargetPickerDialogState();
}

class _BroadcastTargetPickerDialogState
    extends State<BroadcastTargetPickerDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  late bool _sendToAll;
  late final Set<String> _selectedDepartmentIds;
  late final Set<String> _selectedUserIds;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _sendToAll = widget.initialSendToAll;
    _selectedDepartmentIds = Set<String>.from(widget.initialDepartmentIds);
    _selectedUserIds = Set<String>.from(widget.initialUserIds);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Map<String, String>? get _authHeaders => widget.token != null
      ? {'Authorization': 'Bearer ${widget.token}'}
      : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardBgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final searchBgColor =
        isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final borderColor =
        isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);

    final departmentsById = {
      for (final dept in widget.departments) dept.id: dept,
    };

    final allOtherUsers = widget.users
        .where((user) => user.id != widget.currentUserId)
        .toList();

    final query = _searchQuery.trim().toLowerCase();

    final filteredDepartments = widget.departments.where((dept) {
      if (query.isEmpty) return true;
      return dept.name.toLowerCase().contains(query) ||
          dept.code.toLowerCase().contains(query) ||
          dept.description.toLowerCase().contains(query);
    }).toList();

    final filteredUsers = allOtherUsers.where((user) {
      if (query.isEmpty) return true;
      final name = user.displayName.toLowerCase();
      final username = user.username.toLowerCase();
      final branch = user.branchCode.toLowerCase();
      final deptName =
          (departmentsById[user.departmentId]?.name ?? '').toLowerCase();
      return name.contains(query) ||
          username.contains(query) ||
          branch.contains(query) ||
          deptName.contains(query);
    }).toList();

    final canConfirm = _sendToAll ||
        _selectedDepartmentIds.isNotEmpty ||
        _selectedUserIds.isNotEmpty;

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
          height: 640,
          child: Column(
            children: [
              // ── Top Header ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: borderColor, width: 0.8),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9500).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.campaign_rounded,
                        color: Color(0xFFFF9500),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'تحديد وجهة رسالة البث',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'اختر الأقسام أو الموظفين المستهدفين باستلام هذه الرسالة',
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

              // ── Send to All Switch Card ─────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                decoration: BoxDecoration(
                  color: _sendToAll
                      ? const Color(0xFFFF9500).withValues(
                          alpha: isDark ? 0.12 : 0.08,
                        )
                      : searchBgColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _sendToAll
                        ? const Color(0xFFFF9500).withValues(alpha: 0.4)
                        : borderColor,
                  ),
                ),
                child: SwitchListTile.adaptive(
                  value: _sendToAll,
                  onChanged: (val) {
                    setState(() {
                      _sendToAll = val;
                    });
                  },
                  activeColor: const Color(0xFFFF9500),
                  title: const Text(
                    'إرسال إلى الجميع (كافة الأقسام والموظفين)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'عند تفعيل هذا الخيار تصل الرسالة للجميع. أغلقه لتحديد أقسام أو أشخاص بعينهم.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ),
              ),

              // ── Tab Bar & Search Section (Visible when not sending to all) ──
              if (!_sendToAll) ...[
                // Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Container(
                    height: 38,
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
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        prefixIconColor:
                            isDark ? Colors.white54 : Colors.black45,
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
                          vertical: 9,
                          horizontal: 12,
                        ),
                      ),
                    ),
                  ),
                ),

                // Tabs Header
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                    unselectedLabelColor:
                        isDark ? Colors.white54 : Colors.black54,
                    labelStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.corporate_fare_rounded, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'الأقسام (${_selectedDepartmentIds.isNotEmpty ? "${_selectedDepartmentIds.length}/" : ""}${filteredDepartments.length})',
                            ),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.person_search_rounded, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'الموظفين والزملاء (${_selectedUserIds.isNotEmpty ? "${_selectedUserIds.length}/" : ""}${filteredUsers.length})',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Departments
                      _buildDepartmentsTab(
                        filteredDepartments,
                        isDark,
                        borderColor,
                      ),

                      // Tab 2: Users
                      _buildUsersTab(
                        filteredUsers,
                        departmentsById,
                        isDark,
                        borderColor,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // When Send to All is enabled
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF9500)
                                  .withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.public_rounded,
                              color: Color(0xFFFF9500),
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'الإرسال العام مفعل للجميع',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'هذه الرسالة ستصل إلى كافة منسوبي المؤسسة وجميع الأقسام دون حجب.\nيمكنك تعطيل الخيار بالأعلى لاختيار أقسام أو أشخاص محددين.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? Colors.white60 : Colors.black54,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // ── Bottom Summary & Action Bar ─────────────────────────────
              _buildBottomBar(context, isDark, borderColor, canConfirm),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab 1: Departments List ─────────────────────────────────────────────
  Widget _buildDepartmentsTab(
    List<DepartmentSummary> departments,
    bool isDark,
    Color borderColor,
  ) {
    if (departments.isEmpty) {
      return Center(
        child: Text(
          'لا توجد أقسام مطابقة للبحث',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      );
    }

    final allFilteredSelected = departments.every(
      (dept) => _selectedDepartmentIds.contains(dept.id),
    );

    return Column(
      children: [
        // Select All row for departments
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                'اختر قسماً أو أكثر لاستلام البث:',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (allFilteredSelected) {
                      for (final d in departments) {
                        _selectedDepartmentIds.remove(d.id);
                      }
                    } else {
                      for (final d in departments) {
                        _selectedDepartmentIds.add(d.id);
                      }
                    }
                  });
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  allFilteredSelected ? 'إلغاء تحديد الأقسام' : 'تحديد كل الأقسام',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            itemCount: departments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final dept = departments[index];
              final isSelected = _selectedDepartmentIds.contains(dept.id);

              return InkWell(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedDepartmentIds.remove(dept.id);
                    } else {
                      _selectedDepartmentIds.add(dept.id);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFF9500)
                            .withValues(alpha: isDark ? 0.14 : 0.08)
                        : (isDark
                            ? const Color(0xFF252528)
                            : const Color(0xFFF9F9FB)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFF9500)
                          : borderColor,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF34C759)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.corporate_fare_rounded,
                          color: Color(0xFF34C759),
                          size: 19,
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
                                    dept.name,
                                    style: const TextStyle(
                                      fontSize: 13,
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
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dept.description.isNotEmpty
                                  ? dept.description
                                  : 'كود: ${dept.code} • ${dept.membersCount} أعضاء',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isSelected
                            ? const Color(0xFFFF9500)
                            : (isDark ? Colors.white38 : Colors.black38),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Tab 2: Users List ───────────────────────────────────────────────────
  Widget _buildUsersTab(
    List<ChatDirectoryUser> users,
    Map<String, DepartmentSummary> departmentsById,
    bool isDark,
    Color borderColor,
  ) {
    if (users.isEmpty) {
      return Center(
        child: Text(
          'لا يوجد موظفون مطابقون للبحث',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      );
    }

    final allFilteredSelected =
        users.every((u) => _selectedUserIds.contains(u.id));

    return Column(
      children: [
        // Select All row for users
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                'اختر موظفين محددين لاستلام البث:',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (allFilteredSelected) {
                      for (final u in users) {
                        _selectedUserIds.remove(u.id);
                      }
                    } else {
                      for (final u in users) {
                        _selectedUserIds.add(u.id);
                      }
                    }
                  });
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  allFilteredSelected ? 'إلغاء تحديد الموظفين' : 'تحديد كل المعروضين',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final user = users[index];
              final isSelected = _selectedUserIds.contains(user.id);
              final deptName =
                  departmentsById[user.departmentId]?.name ?? '';
              final subtitle = deptName.isNotEmpty
                  ? '$deptName • ${user.branchCode}'
                  : '@${user.username} • ${user.branchCode}';

              return InkWell(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedUserIds.remove(user.id);
                    } else {
                      _selectedUserIds.add(user.id);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFF9500)
                            .withValues(alpha: isDark ? 0.14 : 0.08)
                        : (isDark
                            ? const Color(0xFF252528)
                            : const Color(0xFFF9F9FB)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFF9500)
                          : borderColor,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          SafeNetworkAvatar(
                            radius: 17,
                            backgroundColor: isDark
                                ? const Color(0xFF2C3E50)
                                : const Color(0xFFDCE6F2),
                            imageUrl: user.avatarUrl,
                            httpHeaders: _authHeaders,
                            fallbackText: user.displayName.isNotEmpty
                                ? user.displayName[0].toUpperCase()
                                : '?',
                            fallbackTextStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF24415C),
                            ),
                          ),
                          if (user.isOnline)
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
                                    color: isDark
                                        ? const Color(0xFF1C1C1E)
                                        : Colors.white,
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
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    user.displayName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF2C2C2E)
                                        : const Color(0xFFF2F2F7),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    '@${user.username}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.black54,
                                    ),
                                  ),
                                ),
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
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isSelected
                            ? const Color(0xFFFF9500)
                            : (isDark ? Colors.white38 : Colors.black38),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Bottom Action Bar ───────────────────────────────────────────────────
  Widget _buildBottomBar(
    BuildContext context,
    bool isDark,
    Color borderColor,
    bool canConfirm,
  ) {
    String summaryText;
    if (_sendToAll) {
      summaryText = 'الإرسال إلى: جميع الأقسام والموظفين';
    } else {
      final parts = <String>[];
      if (_selectedDepartmentIds.isNotEmpty) {
        parts.add('${_selectedDepartmentIds.length} قسم');
      }
      if (_selectedUserIds.isNotEmpty) {
        parts.add('${_selectedUserIds.length} موظف');
      }
      summaryText = parts.isEmpty
          ? 'يرجى اختيار جهة واحدة على الأقل'
          : 'المحدد: ${parts.join(' و ')}';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E20) : const Color(0xFFF9F9FB),
        border: Border(top: BorderSide(color: borderColor, width: 0.8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    summaryText,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _sendToAll || canConfirm
                          ? (isDark ? Colors.white : Colors.black87)
                          : Colors.redAccent,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!_sendToAll &&
                    (_selectedDepartmentIds.isNotEmpty ||
                        _selectedUserIds.isNotEmpty)) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedDepartmentIds.clear();
                        _selectedUserIds.clear();
                      });
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.redAccent,
                    ),
                    child: const Text('مسح', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
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
          FilledButton.icon(
            onPressed: canConfirm
                ? () {
                    final selectedDepartments = _sendToAll
                        ? const <DepartmentSummary>[]
                        : widget.departments
                            .where((entry) =>
                                _selectedDepartmentIds.contains(entry.id))
                            .toList();

                    final selectedUsers = _sendToAll
                        ? const <ChatDirectoryUser>[]
                        : widget.users
                            .where((entry) =>
                                _selectedUserIds.contains(entry.id))
                            .toList();

                    final payload = {
                      'broadcastTargets': {
                        'departmentIds': _sendToAll
                            ? const <String>[]
                            : selectedDepartments
                                .map((e) => e.id.trim())
                                .where((e) => e.isNotEmpty)
                                .toList(),
                        'departmentCodes': _sendToAll
                            ? const <String>[]
                            : selectedDepartments
                                .map((e) => e.code.trim().toUpperCase())
                                .where((e) => e.isNotEmpty)
                                .toList(),
                        'departmentNames': _sendToAll
                            ? const <String>[]
                            : selectedDepartments
                                .map((e) => e.name.trim())
                                .where((e) => e.isNotEmpty)
                                .toList(),
                        'userIds': _sendToAll
                            ? const <String>[]
                            : selectedUsers
                                .map((e) => e.id.trim())
                                .where((e) => e.isNotEmpty)
                                .toList(),
                        'userNames': _sendToAll
                            ? const <String>[]
                            : selectedUsers
                                .map((e) => e.displayName.trim())
                                .where((e) => e.isNotEmpty)
                                .toList(),
                        'sentToAllDepartments': _sendToAll,
                      },
                    };

                    Navigator.of(context).pop(payload);
                  }
                : null,
            icon: const Icon(Icons.send_rounded, size: 15),
            label: const Text(
              'تأكيد الإرسال',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF9500),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}
