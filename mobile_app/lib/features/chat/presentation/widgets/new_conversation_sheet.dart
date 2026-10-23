import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/providers/providers.dart';
import '../../models/chat_models.dart';
import 'chat_avatar.dart';

enum _NewChatMode { direct, group, department, broadcast }

class NewConversationSheet extends ConsumerStatefulWidget {
  const NewConversationSheet({
    super.key,
    required this.currentUser,
  });

  final AppUser currentUser;

  static Future<ChatConversation?> show(
    BuildContext context, {
    required AppUser currentUser,
  }) {
    return showModalBottomSheet<ChatConversation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => NewConversationSheet(currentUser: currentUser),
    );
  }

  @override
  ConsumerState<NewConversationSheet> createState() =>
      _NewConversationSheetState();
}

class _NewConversationSheetState extends ConsumerState<NewConversationSheet> {
  _NewChatMode _mode = _NewChatMode.direct;
  int _groupStep = 1; // 1: Select members, 2: Group info & details

  final _searchController = TextEditingController();
  final _groupNameController = TextEditingController();
  final _groupDescController = TextEditingController();

  final _selectedMemberIds = <String>{};
  final _selectedAdminIds = <String>{};

  String? _filterDepartmentId;
  String? _departmentRoomDeptId;
  String _searchQuery = '';
  bool _isCreating = false;
  XFile? _pickedAvatarFile;
  Uint8List? _pickedAvatarBytes;

  @override
  void initState() {
    super.initState();
    _departmentRoomDeptId = widget.currentUser.departmentId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatOverviewControllerProvider.notifier).ensureAllUsersLoaded();
    });
  }


  Future<void> _pickAvatar() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _pickedAvatarFile = picked;
        _pickedAvatarBytes = bytes;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل اختيار الصورة: $e')),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _groupNameController.dispose();
    _groupDescController.dispose();
    super.dispose();
  }

  void _onContactTapped(ChatDirectoryUser user) {
    HapticFeedback.lightImpact();
    if (_mode == _NewChatMode.direct) {
      _startDirectChat(user);
    } else {
      _toggleMember(user.id);
    }
  }

  void _toggleMember(String userId) {
    setState(() {
      if (_selectedMemberIds.contains(userId)) {
        _selectedMemberIds.remove(userId);
        _selectedAdminIds.remove(userId);
      } else {
        _selectedMemberIds.add(userId);
      }
    });
  }

  void _toggleAllInDepartment(List<ChatDirectoryUser> deptUsers) {
    HapticFeedback.mediumImpact();
    setState(() {
      final deptUserIds = deptUsers.map((u) => u.id).toSet();
      final allSelected = deptUserIds.every(_selectedMemberIds.contains);

      if (allSelected) {
        _selectedMemberIds.removeAll(deptUserIds);
        _selectedAdminIds.removeAll(deptUserIds);
      } else {
        _selectedMemberIds.addAll(deptUserIds);
      }
    });
  }

  Future<void> _startDirectChat(ChatDirectoryUser targetUser) async {
    if (_isCreating) return;
    setState(() => _isCreating = true);
    try {
      final conv = await ref
          .read(chatOverviewControllerProvider.notifier)
          .createDirectConversation(targetUser.id);

      if (_pickedAvatarFile != null) {
        try {
          await ref
              .read(chatOverviewControllerProvider.notifier)
              .uploadConversationAvatar(
                conversationId: conv.id,
                filePath: _pickedAvatarFile!.path,
                fileBytes: _pickedAvatarBytes,
                fileName: _pickedAvatarFile!.name,
              );
        } catch (_) {}
      }

      if (mounted) {
        Navigator.of(context).pop(conv);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل بدء المحادثة: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _createGroup() async {
    final name = _groupNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال اسم المجموعة أولاً'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_isCreating) return;
    setState(() => _isCreating = true);
    try {
      final conv = await ref
          .read(chatOverviewControllerProvider.notifier)
          .createConversation(
            type: 'group',
            name: name,
            description: _groupDescController.text.trim(),
            memberIds: _selectedMemberIds.toList(),
            adminIds: _selectedAdminIds.toList(),
          );
      if (mounted) {
        Navigator.of(context).pop(conv);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء المجموعة: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _createDepartmentRoom(List<DepartmentSummary> depts) async {
    if (_departmentRoomDeptId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار القسم أولاً'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final dept = depts.firstWhere(
      (d) => d.id == _departmentRoomDeptId,
      orElse: () => depts.first,
    );

    final name = _groupNameController.text.trim().isNotEmpty
        ? _groupNameController.text.trim()
        : 'غرفة ${dept.name}';

    if (_isCreating) return;
    setState(() => _isCreating = true);
    try {
      final conv = await ref
          .read(chatOverviewControllerProvider.notifier)
          .createConversation(
            type: 'department',
            name: name,
            description: _groupDescController.text.trim(),
            departmentId: _departmentRoomDeptId,
          );
      if (mounted) {
        Navigator.of(context).pop(conv);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء غرفة القسم: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _createBroadcast() async {
    final name = _groupNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال اسم قناة البث'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_selectedMemberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار عضو واحد على الأقل للاستقبال'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_isCreating) return;
    setState(() => _isCreating = true);
    try {
      final conv = await ref
          .read(chatOverviewControllerProvider.notifier)
          .createConversation(
            type: 'broadcast',
            name: name,
            description: _groupDescController.text.trim(),
            memberIds: _selectedMemberIds.toList(),
            adminIds: _selectedAdminIds.toList(),
          );
      if (mounted) {
        Navigator.of(context).pop(conv);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء قناة البث: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final overview =
        ref.watch(chatOverviewControllerProvider).valueOrNull ??
        ChatOverviewData(
          conversations: const [],
          manageableConversations: const [],
          users: const [],
          departments: const [],
          branches: const [],
          roles: const [],
        );

    final canCreateRooms =
        widget.currentUser.role == 'admin' ||
        widget.currentUser.can('canCreateRooms');
    final canSendBroadcast =
        widget.currentUser.role == 'admin' ||
        widget.currentUser.can('canSendBroadcast');

    // All available colleagues excluding current user
    final allUsers = overview.users
        .where((u) => u.id != widget.currentUser.id && u.isActive)
        .toList();

    // Filter by department (matching both departmentId and departmentIds)
    final departmentUsers = _filterDepartmentId == null
        ? allUsers
        : allUsers.where((u) =>
            u.departmentId == _filterDepartmentId ||
            u.departmentIds.contains(_filterDepartmentId)).toList();

    // Filter by search query (including branch and department names)
    final filteredUsers = departmentUsers.where((u) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      final name = u.displayName.toLowerCase();
      final username = u.username.toLowerCase();
      final job = u.jobTitle.toLowerCase();
      final branch = u.branchCode.toLowerCase();
      final branchName = overview.branches
          .where((b) =>
              b.id == u.branchId ||
              (b.code.isNotEmpty &&
                  b.code.toUpperCase() == u.branchCode.toUpperCase()))
          .firstOrNull
          ?.name ??
          '';
      final deptName = overview.departments
          .where((d) => d.id == u.departmentId || u.departmentIds.contains(d.id))
          .firstOrNull
          ?.name ??
          '';
      return name.contains(query) ||
          username.contains(query) ||
          job.contains(query) ||
          branch.contains(query) ||
          branchName.toLowerCase().contains(query) ||
          deptName.toLowerCase().contains(query);
    }).toList();

    final sheetBg = isDark
        ? const Color(0xFF161C24)
        : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF212B36) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.90,
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header Navigation Bar
          _buildHeader(theme, isDark),

          const Divider(height: 1, thickness: 0.8),

          // Body Content (Switching between Direct, Group Step 1/2, Dept, Broadcast)
          Expanded(
            child: _buildBody(
              allUsers: allUsers,
              departmentUsers: departmentUsers,
              filteredUsers: filteredUsers,
              departments: overview.departments,
              canCreateRooms: canCreateRooms,
              canSendBroadcast: canSendBroadcast,
              cardBg: cardBg,
              borderColor: borderColor,
              isDark: isDark,
            ),
          ),

          // Bottom Bar for Group/Broadcast modes
          if (_mode == _NewChatMode.group && _groupStep == 1)
            _buildGroupSelectionBottomBar(isDark),

          if (_mode == _NewChatMode.broadcast)
            _buildBroadcastBottomBar(isDark),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Header Navigation Bar
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHeader(ThemeData theme, bool isDark) {
    String title;
    String? subtitle;
    Widget? leading;
    Widget? trailing;

    if (_mode == _NewChatMode.direct) {
      title = 'رسالة جديدة';
      subtitle = 'اختر زميلاً أو أنشئ محادثة جماعية';
      trailing = IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'إغلاق',
        onPressed: () => Navigator.of(context).pop(),
      );
    } else if (_mode == _NewChatMode.group) {
      if (_groupStep == 1) {
        title = 'مجموعة جديدة';
        subtitle = _selectedMemberIds.isEmpty
            ? 'اختر أعضاء المجموعة'
            : 'تم اختيار ${_selectedMemberIds.length} من الأعضاء';
        leading = IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          tooltip: 'رجوع',
          onPressed: () {
            setState(() {
              _mode = _NewChatMode.direct;
              _selectedMemberIds.clear();
            });
          },
        );
        trailing = TextButton(
          onPressed: _selectedMemberIds.isNotEmpty
              ? () => setState(() => _groupStep = 2)
              : null,
          child: Text(
            'التالي',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: _selectedMemberIds.isNotEmpty
                  ? const Color(0xFF00A884)
                  : (isDark ? Colors.white30 : Colors.black26),
            ),
          ),
        );
      } else {
        title = 'بيانات المجموعة';
        subtitle = 'أدخل اسم ووصف المجموعة';
        leading = IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          tooltip: 'رجوع',
          onPressed: () => setState(() => _groupStep = 1),
        );
        trailing = FilledButton.tonal(
          onPressed: _isCreating ? null : _createGroup,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF00A884),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          ),
          child: _isCreating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'إنشاء',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
        );
      }
    } else if (_mode == _NewChatMode.department) {
      title = 'غرفة قسم جديدة';
      subtitle = 'محادثة تلقائية لجميع أفراد القسم';
      leading = IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        tooltip: 'رجوع',
        onPressed: () => setState(() => _mode = _NewChatMode.direct),
      );
    } else {
      title = 'قناة بث جديدة';
      subtitle = 'إرسال تعليمات وتوجيهات للأعضاء';
      leading = IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        tooltip: 'رجوع',
        onPressed: () => setState(() => _mode = _NewChatMode.direct),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          if (leading != null) leading,
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Main Body
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBody({
    required List<ChatDirectoryUser> allUsers,
    required List<ChatDirectoryUser> departmentUsers,
    required List<ChatDirectoryUser> filteredUsers,
    required List<DepartmentSummary> departments,
    required bool canCreateRooms,
    required bool canSendBroadcast,
    required Color cardBg,
    required Color borderColor,
    required bool isDark,
  }) {
    if (_mode == _NewChatMode.group && _groupStep == 2) {
      return _buildGroupDetailsStep(allUsers, isDark);
    }

    if (_mode == _NewChatMode.department) {
      return _buildDepartmentRoomForm(departments, isDark);
    }

    return Column(
      children: [
        // 1. Search Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: _SearchInputField(
            controller: _searchController,
            isDark: isDark,
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
          ),
        ),

        // 2. Department Horizontal Filter Pills
        _DepartmentFilterPills(
          departments: departments,
          selectedDepartmentId: _filterDepartmentId,
          isDark: isDark,
          onSelected: (deptId) {
            HapticFeedback.selectionClick();
            setState(() => _filterDepartmentId = deptId);
          },
        ),

        // 3. Select All in Department Banner (when in Group Mode)
        if (_mode == _NewChatMode.group && departmentUsers.isNotEmpty)
          _buildDepartmentBatchSelectBanner(departmentUsers, isDark),

        // 4. Selected Members Horizontal Tray (when 1+ members selected in Group Mode)
        if (_mode == _NewChatMode.group && _selectedMemberIds.isNotEmpty)
          _buildSelectedMembersTray(allUsers, isDark),

        // 5. Action Tiles (New Group / Department / Broadcast) - only in Direct Mode
        if (_mode == _NewChatMode.direct && _searchQuery.isEmpty)
          _buildQuickActionTiles(canCreateRooms, canSendBroadcast, isDark),

        // 6. Section Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Text(
                _mode == _NewChatMode.group
                    ? 'جهات الاتصال المتاحة'
                    : 'جميع الزملاء',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${filteredUsers.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 7. Users List
        Expanded(
          child: filteredUsers.isEmpty
              ? _buildEmptyState(isDark)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  itemCount: filteredUsers.length,
                  itemBuilder: (context, index) {
                    final user = filteredUsers[index];
                    final isSelected = _selectedMemberIds.contains(user.id);
                    final deptName = departments.where((d) => d.id == user.departmentId).firstOrNull?.name ?? '';

                    return _ContactListItem(
                      user: user,
                      departmentName: deptName,
                      isSelected: isSelected,
                      isGroupMode: _mode == _NewChatMode.group ||
                          _mode == _NewChatMode.broadcast,
                      isDark: isDark,
                      onTap: () => _onContactTapped(user),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WhatsApp Style Quick Action Options (New Group, Room, Broadcast)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildQuickActionTiles(
    bool canCreateRooms,
    bool canSendBroadcast,
    bool isDark,
  ) {
    return Column(
      children: [
        _ActionTile(
          icon: Icons.group_add_rounded,
          iconBg: const Color(0xFF00A884),
          title: 'مجموعة جديدة',
          subtitle: 'إنشاء محادثة جماعية مع اختيار الأعضاء والأقسام',
          isDark: isDark,
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              _mode = _NewChatMode.group;
              _groupStep = 1;
            });
          },
        ),
        if (canCreateRooms)
          _ActionTile(
            icon: Icons.apartment_rounded,
            iconBg: const Color(0xFF007AFF),
            title: 'غرفة قسم',
            subtitle: 'إنشاء قناة محادثة مخصصة لجميع موظفي القسم',
            isDark: isDark,
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _mode = _NewChatMode.department);
            },
          ),
        if (canSendBroadcast)
          _ActionTile(
            icon: Icons.campaign_rounded,
            iconBg: const Color(0xFFF59E0B),
            title: 'قناة بث جديدة',
            subtitle: 'إرسال توجيهات وتعليمات للموظفين في قناة واحدة',
            isDark: isDark,
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _mode = _NewChatMode.broadcast);
            },
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Divider(height: 1, thickness: 0.6),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Department Batch Select Banner ("Select All in Department")
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDepartmentBatchSelectBanner(
    List<ChatDirectoryUser> deptUsers,
    bool isDark,
  ) {
    final deptUserIds = deptUsers.map((u) => u.id).toSet();
    final allSelected = deptUserIds.every(_selectedMemberIds.contains);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF00A884).withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00A884).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            allSelected
                ? Icons.remove_done_rounded
                : Icons.done_all_rounded,
            color: const Color(0xFF00A884),
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              allSelected
                  ? 'إلغاء تحديد كل أعضاء القسم المعروض (${deptUsers.length})'
                  : 'تحديد جميع أعضاء القسم المعروض بنقرة واحدة (${deptUsers.length})',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Color(0xFF00A884),
              ),
            ),
          ),
          InkWell(
            onTap: () => _toggleAllInDepartment(deptUsers),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF00A884),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                allSelected ? 'إلغاء' : 'تحديد الكل',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Horizontal Tray of Selected Members
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSelectedMembersTray(
    List<ChatDirectoryUser> allUsers,
    bool isDark,
  ) {
    final selectedUsers =
        allUsers.where((u) => _selectedMemberIds.contains(u.id)).toList();

    return Container(
      height: 78,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: selectedUsers.length,
        itemBuilder: (context, index) {
          final user = selectedUsers[index];
          final firstName = user.displayName.split(' ').first;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ChatAvatar(
                      radius: 23,
                      backgroundColor: const Color(0xFF00A884),
                      avatarUrl: user.avatarUrl,
                      fallback: Text(
                        user.displayName.isNotEmpty
                            ? user.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Positioned(
                      top: -2,
                      right: -2,
                      child: GestureDetector(
                        onTap: () => _toggleMember(user.id),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                SizedBox(
                  width: 54,
                  child: Text(
                    firstName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Group Step 2: Group Info & Details
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildGroupDetailsStep(
    List<ChatDirectoryUser> allUsers,
    bool isDark,
  ) {
    final selectedUsers =
        allUsers.where((u) => _selectedMemberIds.contains(u.id)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Group Avatar Picker
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                    image: _pickedAvatarBytes != null
                        ? DecorationImage(
                            image: MemoryImage(_pickedAvatarBytes!),
                            fit: BoxFit.cover,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00A884).withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _pickedAvatarBytes == null
                      ? const Icon(
                          Icons.camera_alt_rounded,
                          color: Color(0xFF00A884),
                          size: 34,
                        )
                      : null,
                ),
              ),
              Positioned(
                bottom: -2,
                left: -2,
                child: Material(
                  color: const Color(0xFF00A884),
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _pickAvatar,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.edit_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
              if (_pickedAvatarBytes != null)
                Positioned(
                  top: -2,
                  right: -2,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _pickedAvatarBytes = null;
                      _pickedAvatarFile = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Group Name Input
        TextField(
          controller: _groupNameController,
          autofocus: true,
          maxLength: 50,
          decoration: InputDecoration(
            labelText: 'اسم المجموعة (مطلوب)',
            hintText: 'مثال: فريق مشروع التطوير',
            prefixIcon: const Icon(Icons.group_rounded),
            filled: true,
            fillColor: isDark ? const Color(0xFF212B36) : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Group Description Input
        TextField(
          controller: _groupDescController,
          maxLines: 2,
          maxLength: 150,
          decoration: InputDecoration(
            labelText: 'وصف المجموعة (اختياري)',
            hintText: 'الهدف من المجموعة أو التوجيهات...',
            prefixIcon: const Icon(Icons.description_outlined),
            filled: true,
            fillColor: isDark ? const Color(0xFF212B36) : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Participants Summary
        Text(
          'الأعضاء المختارون (${selectedUsers.length})',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        const SizedBox(height: 10),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: selectedUsers.map((u) {
            return Chip(
              avatar: ChatAvatar(
                radius: 12,
                backgroundColor: const Color(0xFF00A884),
                avatarUrl: u.avatarUrl,
                fallback: Text(
                  u.displayName.isNotEmpty ? u.displayName[0] : '?',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
              label: Text(u.displayName),
              onDeleted: () => _toggleMember(u.id),
              deleteIconColor: Colors.red,
            );
          }).toList(),
        ),

        const SizedBox(height: 28),

        FilledButton.icon(
          onPressed: _isCreating ? null : _createGroup,
          icon: _isCreating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded),
          label: const Text(
            'إنشاء المجموعة الآن',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF00A884),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Department Room Form
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDepartmentRoomForm(
    List<DepartmentSummary> departments,
    bool isDark,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        DropdownButtonFormField<String>(
          value: _departmentRoomDeptId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'اختر القسم',
            prefixIcon: const Icon(Icons.apartment_rounded),
            filled: true,
            fillColor: isDark ? const Color(0xFF212B36) : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          items: departments.map((d) {
            return DropdownMenuItem<String>(
              value: d.id,
              child: Text('${d.name} (${d.membersCount} موظف)'),
            );
          }).toList(),
          onChanged: (val) => setState(() => _departmentRoomDeptId = val),
        ),

        const SizedBox(height: 14),

        TextField(
          controller: _groupNameController,
          decoration: InputDecoration(
            labelText: 'اسم الغرفة (اختياري)',
            hintText: 'يترك فارغاً للاسم الافتراضي: غرفة [القسم]',
            prefixIcon: const Icon(Icons.meeting_room_rounded),
            filled: true,
            fillColor: isDark ? const Color(0xFF212B36) : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),

        const SizedBox(height: 14),

        TextField(
          controller: _groupDescController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'الوصف (اختياري)',
            prefixIcon: const Icon(Icons.description_outlined),
            filled: true,
            fillColor: isDark ? const Color(0xFF212B36) : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),

        const SizedBox(height: 24),

        FilledButton.icon(
          onPressed: _isCreating ? null : () => _createDepartmentRoom(departments),
          icon: _isCreating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.add_rounded),
          label: const Text(
            'إنشاء غرفة القسم',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF007AFF),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bottom Action Bar for Group Selection
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildGroupSelectionBottomBar(bool isDark) {
    final count = _selectedMemberIds.length;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B222C) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 0.8,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count == 0
                      ? 'لم يتم تحديد أي عضو'
                      : '$count أعضاء تم اختيارهم',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: count == 0
                        ? (isDark ? Colors.white54 : Colors.black54)
                        : const Color(0xFF00A884),
                  ),
                ),
                Text(
                  'انقر التالي لإكمال إنشاء المجموعة',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: count > 0 ? () => setState(() => _groupStep = 2) : null,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text(
              'التالي',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00A884),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bottom Action Bar for Broadcast Creation
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBroadcastBottomBar(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B222C) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 0.8,
          ),
        ),
      ),
      child: FilledButton.icon(
        onPressed: _isCreating ? null : _createBroadcast,
        icon: _isCreating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.campaign_rounded),
        label: Text(
          'إنشاء قناة البث (${_selectedMemberIds.length} مستلم)',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFF59E0B),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Empty State
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_search_rounded,
            size: 54,
            color: isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 10),
          Text(
            'لا يوجد زملاء مطابقين للبحث',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contact List Item (Apple / WhatsApp Style)
// ─────────────────────────────────────────────────────────────────────────────
class _ContactListItem extends StatelessWidget {
  const _ContactListItem({
    required this.user,
    required this.departmentName,
    required this.isSelected,
    required this.isGroupMode,
    required this.isDark,
    required this.onTap,
  });

  final ChatDirectoryUser user;
  final String departmentName;
  final bool isSelected;
  final bool isGroupMode;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF00A884).withValues(alpha: isDark ? 0.16 : 0.08)
            : (isDark ? const Color(0xFF1E2632) : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF00A884).withValues(alpha: 0.5)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
          width: isSelected ? 1.4 : 0.8,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            ChatAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF00A884),
              avatarUrl: user.avatarUrl,
              fallback: Text(
                user.displayName.isNotEmpty
                    ? user.displayName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            // Online Green Dot Badge
            if (user.isOnline)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF1E2632) : Colors.white,
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
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            if (departmentName.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF00A884).withValues(alpha: 0.18)
                      : const Color(0xFF00A884).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  departmentName,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF00A884),
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Row(
          children: [
            if (user.jobTitle.isNotEmpty)
              Text(
                user.jobTitle,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            if (user.jobTitle.isNotEmpty && user.branchCode.isNotEmpty)
              Text(
                ' • ',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            if (user.branchCode.isNotEmpty)
              Text(
                user.branchCode,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
          ],
        ),
        trailing: isGroupMode
            ? AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF00A884)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF00A884)
                        : (isDark ? Colors.white38 : Colors.black38),
                    width: isSelected ? 2 : 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 16,
                      )
                    : null,
              )
            : const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 19,
                color: Color(0xFF00A884),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action Tile (New Group, Room, Broadcast)
// ─────────────────────────────────────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: iconBg.withValues(alpha: isDark ? 0.20 : 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconBg, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 11.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Department Filter Pills (Horizontal Scroll)
// ─────────────────────────────────────────────────────────────────────────────
class _DepartmentFilterPills extends StatelessWidget {
  const _DepartmentFilterPills({
    required this.departments,
    required this.selectedDepartmentId,
    required this.isDark,
    required this.onSelected,
  });

  final List<DepartmentSummary> departments;
  final String? selectedDepartmentId;
  final bool isDark;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: departments.length + 1,
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final dept = isAll ? null : departments[index - 1];
          final isSelected = isAll
              ? selectedDepartmentId == null
              : selectedDepartmentId == dept?.id;

          final label = isAll ? 'كل الأقسام' : dept!.name;

          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              selected: isSelected,
              showCheckmark: false,
              label: Text(label),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
              backgroundColor:
                  isDark ? const Color(0xFF1E2632) : const Color(0xFFEAEFF5),
              selectedColor: const Color(0xFF00A884),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFF00A884)
                      : Colors.transparent,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onSelected: (_) => onSelected(dept?.id),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search Input Field
// ─────────────────────────────────────────────────────────────────────────────
class _SearchInputField extends StatelessWidget {
  const _SearchInputField({
    required this.controller,
    required this.isDark,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool isDark;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF212B36) : const Color(0xFFEAEFF5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13.5),
        decoration: InputDecoration(
          hintText: 'ابحث بالاسم، المسمى، أو الفرع...',
          hintStyle: TextStyle(
            fontSize: 12.5,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    controller.clear();
                    onChanged('');
                  },
                  child: const Icon(Icons.close_rounded, size: 18),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}
