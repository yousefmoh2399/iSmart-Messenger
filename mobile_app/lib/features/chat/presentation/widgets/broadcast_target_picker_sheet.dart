import 'package:flutter/material.dart';

import '../../models/chat_models.dart';
import 'chat_avatar.dart';

class BroadcastTargetPickerSheet extends StatefulWidget {
  const BroadcastTargetPickerSheet({
    super.key,
    required this.departments,
    required this.users,
    required this.currentUserId,
    this.initialSendToAll = true,
    this.initialDepartmentIds = const {},
    this.initialUserIds = const {},
  });

  final List<DepartmentSummary> departments;
  final List<ChatDirectoryUser> users;
  final String currentUserId;
  final bool initialSendToAll;
  final Set<String> initialDepartmentIds;
  final Set<String> initialUserIds;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required List<DepartmentSummary> departments,
    required List<ChatDirectoryUser> users,
    required String currentUserId,
    bool initialSendToAll = true,
    Set<String> initialDepartmentIds = const {},
    Set<String> initialUserIds = const {},
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BroadcastTargetPickerSheet(
        departments: departments,
        users: users,
        currentUserId: currentUserId,
        initialSendToAll: initialSendToAll,
        initialDepartmentIds: initialDepartmentIds,
        initialUserIds: initialUserIds,
      ),
    );
  }

  @override
  State<BroadcastTargetPickerSheet> createState() =>
      _BroadcastTargetPickerSheetState();
}

class _BroadcastTargetPickerSheetState extends State<BroadcastTargetPickerSheet>
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
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
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

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
    });
  }

  void _confirmSelection() {
    final departmentsById = {
      for (final dept in widget.departments) dept.id: dept,
    };
    final usersById = {for (final user in widget.users) user.id: user};

    final selectedDepartments = _selectedDepartmentIds
        .map((id) => departmentsById[id])
        .whereType<DepartmentSummary>()
        .toList();

    final selectedUsers = _selectedUserIds
        .map((id) => usersById[id])
        .whereType<ChatDirectoryUser>()
        .toList();

    final payload = <String, dynamic>{
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final sheetBgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
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
      final jobTitle = user.jobTitle.toLowerCase();
      final deptName =
          (departmentsById[user.departmentId]?.name ?? '').toLowerCase();
      return name.contains(query) ||
          username.contains(query) ||
          branch.contains(query) ||
          jobTitle.contains(query) ||
          deptName.contains(query);
    }).toList();

    final canConfirm = _sendToAll ||
        _selectedDepartmentIds.isNotEmpty ||
        _selectedUserIds.isNotEmpty;

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
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9500).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
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
                            'اختر الأقسام أو الموظفين المستهدفين بالرسالة',
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

              // ── All Departments Switch ──────────────────────────────────
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _sendToAll
                      ? const Color(0xFFFF9500).withValues(alpha: 0.1)
                      : (isDark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFFF2F2F7)),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _sendToAll
                        ? const Color(0xFFFF9500).withValues(alpha: 0.35)
                        : borderColor,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.groups_rounded,
                      size: 22,
                      color: _sendToAll
                          ? const Color(0xFFFF9500)
                          : (isDark ? Colors.white54 : Colors.black45),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إرسال إلى جميع الأقسام والموظفين',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _sendToAll
                                  ? const Color(0xFFFF9500)
                                  : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _sendToAll
                                ? 'الرسالة ستصل لجميع أعضاء القناة بلا استثناء'
                                : 'محدد: أقسام أو زملاء معينين فقط',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _sendToAll,
                      activeColor: const Color(0xFFFF9500),
                      onChanged: (val) {
                        setState(() {
                          _sendToAll = val;
                        });
                      },
                    ),
                  ],
                ),
              ),

              // ── Search Input ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: searchBgColor,
                      hintText: _tabController.index == 0
                          ? 'بحث في الأقسام...'
                          : 'بحث بالاسم، الكود، القسم أو الفرع...',
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
                              onPressed: _clearSearch,
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
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(2.5),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
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
                  labelColor:
                      isDark ? Colors.white : const Color(0xFF1C1C1E),
                  unselectedLabelColor:
                      isDark ? Colors.white54 : Colors.black54,
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.apartment_rounded, size: 16),
                          const SizedBox(width: 6),
                          const Text('الأقسام'),
                          if (!_sendToAll && _selectedDepartmentIds.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9500),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_selectedDepartmentIds.length}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.people_alt_rounded, size: 16),
                          const SizedBox(width: 6),
                          const Text('الموظفين'),
                          if (!_sendToAll && _selectedUserIds.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9500),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_selectedUserIds.length}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
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
                    // Tab 1: Departments
                    _buildDepartmentsTab(
                      filteredDepartments: filteredDepartments,
                      isDark: isDark,
                      borderColor: borderColor,
                    ),

                    // Tab 2: Users
                    _buildUsersTab(
                      filteredUsers: filteredUsers,
                      departmentsById: departmentsById,
                      isDark: isDark,
                      borderColor: borderColor,
                    ),
                  ],
                ),
              ),

              // ── Footer Bar ──────────────────────────────────────────────
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
                            _sendToAll
                                ? 'سيصل لجميع الأقسام والموظفين'
                                : (_selectedDepartmentIds.isEmpty &&
                                        _selectedUserIds.isEmpty)
                                    ? 'يرجى اختيار قسم أو موظف واحد على الأقل'
                                    : 'محدد: ${_selectedDepartmentIds.length} قسم • ${_selectedUserIds.length} موظف',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _sendToAll
                                  ? const Color(0xFFFF9500)
                                  : (_selectedDepartmentIds.isEmpty &&
                                          _selectedUserIds.isEmpty
                                      ? (isDark
                                          ? Colors.white38
                                          : Colors.black38)
                                      : (isDark
                                          ? Colors.white
                                          : Colors.black87)),
                            ),
                          ),
                          if (!_sendToAll &&
                              (_selectedDepartmentIds.isNotEmpty ||
                                  _selectedUserIds.isNotEmpty)) ...[
                            const SizedBox(height: 2),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedDepartmentIds.clear();
                                  _selectedUserIds.clear();
                                });
                              },
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
                      onPressed: canConfirm ? _confirmSelection : null,
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text(
                        'تأكيد الوجهة',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9500),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
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

  Widget _buildDepartmentsTab({
    required List<DepartmentSummary> filteredDepartments,
    required bool isDark,
    required Color borderColor,
  }) {
    if (filteredDepartments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 40,
              color: isDark ? Colors.white30 : Colors.black26,
            ),
            const SizedBox(height: 8),
            Text(
              'لا توجد أقسام مطابقة للبحث',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Quick Actions Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                'الأقسام المتاحة (${filteredDepartments.length})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _sendToAll = false;
                    for (final d in filteredDepartments) {
                      _selectedDepartmentIds.add(d.id);
                    }
                  });
                },
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('تحديد الكل', style: TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _sendToAll = false;
                    for (final d in filteredDepartments) {
                      _selectedDepartmentIds.remove(d.id);
                    }
                  });
                },
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('إلغاء التحديد', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filteredDepartments.length,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemBuilder: (context, index) {
              final dept = filteredDepartments[index];
              final isChecked =
                  _sendToAll || _selectedDepartmentIds.contains(dept.id);

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: isChecked && !_sendToAll
                      ? const Color(0xFFFF9500).withValues(alpha: 0.08)
                      : (isDark
                          ? const Color(0xFF242426)
                          : const Color(0xFFF8F9FA)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isChecked && !_sendToAll
                        ? const Color(0xFFFF9500).withValues(alpha: 0.3)
                        : borderColor,
                  ),
                ),
                child: CheckboxListTile(
                  value: isChecked,
                  onChanged: (val) {
                    setState(() {
                      if (_sendToAll) {
                        _sendToAll = false;
                        _selectedDepartmentIds.clear();
                        _selectedUserIds.clear();
                        _selectedDepartmentIds.add(dept.id);
                      } else {
                        if (val == true) {
                          _selectedDepartmentIds.add(dept.id);
                        } else {
                          _selectedDepartmentIds.remove(dept.id);
                        }
                      }
                    });
                  },
                  activeColor: const Color(0xFFFF9500),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  secondary: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9500).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        dept.code.isNotEmpty ? dept.code : 'قسم',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFF9500),
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    dept.name,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    dept.description.isNotEmpty
                        ? dept.description
                        : 'قسم ${dept.code} • ${dept.membersCount} عضو',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUsersTab({
    required List<ChatDirectoryUser> filteredUsers,
    required Map<String, DepartmentSummary> departmentsById,
    required bool isDark,
    required Color borderColor,
  }) {
    if (filteredUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_search_rounded,
              size: 40,
              color: isDark ? Colors.white30 : Colors.black26,
            ),
            const SizedBox(height: 8),
            Text(
              'لا يوجد موظفون مطابقون للبحث',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Quick Actions Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                'الموظفين المتاحين (${filteredUsers.length})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _sendToAll = false;
                    for (final u in filteredUsers) {
                      _selectedUserIds.add(u.id);
                    }
                  });
                },
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('تحديد الكل', style: TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _sendToAll = false;
                    for (final u in filteredUsers) {
                      _selectedUserIds.remove(u.id);
                    }
                  });
                },
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('إلغاء التحديد', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filteredUsers.length,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemBuilder: (context, index) {
              final user = filteredUsers[index];
              final isChecked =
                  _sendToAll || _selectedUserIds.contains(user.id);
              final deptName = departmentsById[user.departmentId]?.name ?? '';
              final isOnline = user.isOnline || user.presenceStatus == 'online';

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: isChecked && !_sendToAll
                      ? const Color(0xFFFF9500).withValues(alpha: 0.08)
                      : (isDark
                          ? const Color(0xFF242426)
                          : const Color(0xFFF8F9FA)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isChecked && !_sendToAll
                        ? const Color(0xFFFF9500).withValues(alpha: 0.3)
                        : borderColor,
                  ),
                ),
                child: CheckboxListTile(
                  value: isChecked,
                  onChanged: (val) {
                    setState(() {
                      if (_sendToAll) {
                        _sendToAll = false;
                        _selectedDepartmentIds.clear();
                        _selectedUserIds.clear();
                        _selectedUserIds.add(user.id);
                      } else {
                        if (val == true) {
                          _selectedUserIds.add(user.id);
                        } else {
                          _selectedUserIds.remove(user.id);
                        }
                      }
                    });
                  },
                  activeColor: const Color(0xFFFF9500),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  secondary: Stack(
                    children: [
                      ChatAvatar(
                        radius: 19,
                        backgroundColor: const Color(0xFFFF9500)
                            .withValues(alpha: 0.15),
                        avatarUrl: user.avatarUrl,
                        fallback: Text(
                          user.displayName.isNotEmpty
                              ? user.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFFFF9500),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: isOnline
                                ? const Color(0xFF34C759)
                                : Colors.grey,
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
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (user.branchCode.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF3A3A3C)
                                : const Color(0xFFE5E5EA),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            user.branchCode,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    [
                      if (user.jobTitle.isNotEmpty) user.jobTitle,
                      if (deptName.isNotEmpty) deptName,
                      '@${user.username}',
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
