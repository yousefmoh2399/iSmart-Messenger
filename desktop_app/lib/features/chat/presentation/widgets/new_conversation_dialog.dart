import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/providers/providers.dart';
import '../../../../shared/widgets/safe_network_avatar.dart';
import '../../models/chat_models.dart';

class NewConversationDialog extends ConsumerStatefulWidget {
  const NewConversationDialog({
    super.key,
    required this.currentUser,
    required this.overview,
  });

  final AppUser currentUser;
  final ChatOverviewData overview;

  @override
  ConsumerState<NewConversationDialog> createState() =>
      _NewConversationDialogState();
}

class _NewConversationDialogState
    extends ConsumerState<NewConversationDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  final _filterScrollController = ScrollController();

  final _selectedMembers = <String>{};
  final _selectedAdmins = <String>{};

  late String _selectedType; // 'direct', 'group', 'department', 'broadcast'
  ChatDirectoryUser? _selectedDirectUser;
  String _filterCategory = 'department'; // 'department' or 'branch'
  String? _filterDepartmentId;
  String? _filterBranchId;
  String? _departmentRoomDeptId;
  String _searchQuery = '';
  bool _isCreating = false;
  Uint8List? _pickedAvatarBytes;
  String? _pickedAvatarPath;
  String? _pickedAvatarName;

  late List<String> _availableTypes;

  @override
  void initState() {
    super.initState();
    _departmentRoomDeptId = widget.currentUser.departmentId;

    final canCreateRooms = widget.currentUser.role == 'admin' ||
        widget.currentUser.can('canCreateRooms');
    final canSendBroadcast = widget.currentUser.role == 'admin' ||
        widget.currentUser.can('canSendBroadcast');

    _availableTypes = <String>[
      'direct',
      'group',
      if (canCreateRooms) 'department',
      if (canSendBroadcast) 'broadcast',
    ];
    _selectedType = _availableTypes.first;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatOverviewControllerProvider.notifier).ensureAllUsersLoaded();
    });
  }


  Future<void> _pickAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      final picked = result?.files.single;
      if (picked == null) return;

      Uint8List? bytes = picked.bytes;
      if (bytes == null && picked.path != null && picked.path!.isNotEmpty) {
        final file = File(picked.path!);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
        }
      }

      setState(() {
        _pickedAvatarBytes = bytes;
        _pickedAvatarPath = picked.path;
        _pickedAvatarName = picked.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل اختيار الصورة: $e')),
      );
    }
  }

  Widget _buildAvatarPicker(bool isDark) {
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: _pickAvatar,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                image: _pickedAvatarBytes != null
                    ? DecorationImage(
                        image: MemoryImage(_pickedAvatarBytes!),
                        fit: BoxFit.cover,
                      )
                    : null,
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 1.5,
                ),
              ),
              child: _pickedAvatarBytes == null
                  ? Icon(
                      _selectedType == 'broadcast'
                          ? Icons.campaign_rounded
                          : Icons.group_rounded,
                      size: 36,
                      color: isDark ? Colors.white38 : Colors.black38,
                    )
                  : null,
            ),
          ),
          Positioned(
            bottom: -2,
            left: -2,
            child: Material(
              color: Theme.of(context).colorScheme.primary,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _pickAvatar,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
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
                  _pickedAvatarPath = null;
                  _pickedAvatarName = null;
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
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    _filterScrollController.dispose();
    super.dispose();
  }

  void _toggleMember(String userId) {
    setState(() {
      if (_selectedMembers.contains(userId)) {
        _selectedMembers.remove(userId);
        _selectedAdmins.remove(userId);
      } else {
        _selectedMembers.add(userId);
      }
    });
  }

  void _toggleAllInDepartment(List<ChatDirectoryUser> deptUsers) {
    setState(() {
      final deptUserIds = deptUsers.map((u) => u.id).toSet();
      final allSelected = deptUserIds.every(_selectedMembers.contains);

      if (allSelected) {
        _selectedMembers.removeAll(deptUserIds);
        _selectedAdmins.removeAll(deptUserIds);
      } else {
        _selectedMembers.addAll(deptUserIds);
      }
    });
  }

  Future<void> _createConversation() async {
    final controller = ref.read(chatOverviewControllerProvider.notifier);
    if (_isCreating) return;

    setState(() => _isCreating = true);
    try {
      ChatConversation conversation;
      if (_selectedType == 'direct') {
        if (_selectedDirectUser == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى اختيار زميل لبدء المحادثة')),
          );
          setState(() => _isCreating = false);
          return;
        }
        conversation = await controller.createDirectConversation(
          _selectedDirectUser!.id,
        );
      } else if (_selectedType == 'group') {
        final name = _nameController.text.trim();
        if (name.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى إدخال اسم المجموعة')),
          );
          setState(() => _isCreating = false);
          return;
        }
        conversation = await controller.createConversation(
          type: 'group',
          name: name,
          description: _descriptionController.text.trim(),
          memberIds: _selectedMembers.toList(),
          adminIds: _selectedAdmins.toList(),
        );
      } else if (_selectedType == 'department') {
        if (_departmentRoomDeptId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى اختيار القسم')),
          );
          setState(() => _isCreating = false);
          return;
        }
        final dept = widget.overview.departments.firstWhere(
          (d) => d.id == _departmentRoomDeptId,
          orElse: () => widget.overview.departments.first,
        );
        final name = _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : 'غرفة ${dept.name}';
        conversation = await controller.createConversation(
          type: 'department',
          name: name,
          description: _descriptionController.text.trim(),
          departmentId: _departmentRoomDeptId,
        );
      } else {
        // Broadcast
        final name = _nameController.text.trim();
        if (name.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى إدخال اسم قناة البث')),
          );
          setState(() => _isCreating = false);
          return;
        }
        conversation = await controller.createConversation(
          type: 'broadcast',
          name: name,
          description: _descriptionController.text.trim(),
          memberIds: _selectedMembers.toList(),
          adminIds: _selectedAdmins.toList(),
        );
      }


      if (_pickedAvatarBytes != null ||
          (_pickedAvatarPath != null && _pickedAvatarPath!.isNotEmpty)) {
        try {
          conversation = await controller.uploadConversationAvatar(
            conversationId: conversation.id,
            filePath: _pickedAvatarPath,
            fileBytes: _pickedAvatarBytes,
            fileName: _pickedAvatarName ?? 'avatar.jpg',
          );
        } catch (_) {}
      }

      if (mounted) {
        Navigator.of(context).pop(conversation);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشلت العملية: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final currentOverview =
        ref.watch(chatOverviewControllerProvider).valueOrNull ??
        widget.overview;

    final allUsers = currentOverview.users
        .where((u) => u.id != widget.currentUser.id && u.isActive)
        .toList();

    // Filter by branch
    final branchFilteredUsers = _filterBranchId == null
        ? allUsers
        : allUsers.where((u) {
            final b = currentOverview.branches.firstWhere(
              (branch) => branch.id == _filterBranchId,
              orElse: () => BranchSummary(
                id: _filterBranchId!,
                name: '',
                code: '',
                description: '',
                membersCount: 0,
              ),
            );
            return u.branchId == _filterBranchId ||
                (b.code.isNotEmpty &&
                    u.branchCode.toUpperCase() == b.code.toUpperCase());
          }).toList();

    // Filter by department (matching both departmentId and departmentIds)
    final departmentUsers = _filterDepartmentId == null
        ? branchFilteredUsers
        : branchFilteredUsers.where((u) {
            return u.departmentId == _filterDepartmentId ||
                u.departmentIds.contains(_filterDepartmentId);
          }).toList();

    final filteredUsers = departmentUsers.where((u) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final branchName = currentOverview.branches
          .where((b) =>
              b.id == u.branchId ||
              (b.code.isNotEmpty &&
                  b.code.toUpperCase() == u.branchCode.toUpperCase()))
          .firstOrNull
          ?.name ??
          '';
      final deptName = currentOverview.departments
          .where((d) =>
              d.id == u.departmentId ||
              u.departmentIds.contains(d.id))
          .firstOrNull
          ?.name ??
          '';
      return u.displayName.toLowerCase().contains(q) ||
          u.username.toLowerCase().contains(q) ||
          u.jobTitle.toLowerCase().contains(q) ||
          u.branchCode.toLowerCase().contains(q) ||
          branchName.toLowerCase().contains(q) ||
          deptName.toLowerCase().contains(q);
    }).toList();

    final dialogBg = isDark ? const Color(0xFF161C24) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1F2732) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 820,
          maxHeight: 640,
        ),
        child: Column(
          children: [
            // Top Window Bar (Header + Segmented Switcher + Close)
            _buildTopBar(isDark),

            const Divider(height: 1, thickness: 0.8),

            // Two-Column Main Content
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Right Column (Directory & Contacts)
                  Expanded(
                    flex: 55,
                    child: _buildDirectoryColumn(
                      departmentUsers: departmentUsers,
                      filteredUsers: filteredUsers,
                      departments: currentOverview.departments,
                      branches: currentOverview.branches,
                      cardBg: cardBg,
                      borderColor: borderColor,
                      isDark: isDark,
                    ),
                  ),

                  VerticalDivider(
                    width: 1,
                    thickness: 0.8,
                    color: borderColor,
                  ),

                  // Left Column (Details & Actions)
                  Expanded(
                    flex: 45,
                    child: _buildDetailsColumn(
                      allUsers: allUsers,
                      departments: currentOverview.departments,
                      branches: currentOverview.branches,
                      cardBg: cardBg,
                      borderColor: borderColor,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Top Header Bar
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildTopBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF00A884).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.edit_square,
              color: Color(0xFF00A884),
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'رسالة جديدة',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 20),

          // Mode Segmented Buttons
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _availableTypes.map((type) {
                  final isSelected = _selectedType == type;
                  final (icon, label) = switch (type) {
                    'direct' => (Icons.chat_bubble_outline_rounded, 'مباشرة'),
                    'group' => (Icons.group_rounded, 'مجموعة'),
                    'department' => (Icons.apartment_rounded, 'غرفة قسم'),
                    _ => (Icons.campaign_rounded, 'قناة بث'),
                  };

                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedType = type;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF00A884)
                              : (isDark
                                  ? const Color(0xFF222C38)
                                  : const Color(0xFFEAEFF5)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              size: 15,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark
                                        ? Colors.white70
                                        : Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: 'إغلاق',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Right Column: Directory & Contacts List
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDirectoryColumn({
    required List<ChatDirectoryUser> departmentUsers,
    required List<ChatDirectoryUser> filteredUsers,
    required List<DepartmentSummary> departments,
    required List<BranchSummary> branches,
    required Color cardBg,
    required Color borderColor,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search Input
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF212B36) : const Color(0xFFEAEFF5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'بحث بالاسم، المسمى، الفرع، القسم...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _searchController.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        child: const Icon(Icons.close_rounded, size: 16),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
              ),
            ),
          ),
        ),

        // Filter Category Switcher: [📁 الأقسام] [🏢 الفروع] + Reset Button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _buildCategoryTab(
                label: '📁 الأقسام',
                isSelected: _filterCategory == 'department',
                isDark: isDark,
                onTap: () {
                  setState(() {
                    _filterCategory = 'department';
                    _filterBranchId = null;
                  });
                },
              ),
              const SizedBox(width: 6),
              _buildCategoryTab(
                label: '🏢 الفروع',
                isSelected: _filterCategory == 'branch',
                isDark: isDark,
                onTap: () {
                  setState(() {
                    _filterCategory = 'branch';
                    _filterDepartmentId = null;
                  });
                },
              ),
              const Spacer(),
              if (_filterDepartmentId != null || _filterBranchId != null)
                InkWell(
                  onTap: () {
                    setState(() {
                      _filterDepartmentId = null;
                      _filterBranchId = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.clear_rounded, size: 12, color: Colors.red),
                        SizedBox(width: 3),
                        Text(
                          'إعادة ضبط',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Horizontal Filter Pills with Mouse-Drag + Mouse-Wheel + Chevrons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            height: 32,
            child: Row(
              children: [
                _buildScrollButton(
                  icon: Icons.chevron_right_rounded,
                  isDark: isDark,
                  onTap: () {
                    if (_filterScrollController.hasClients) {
                      _filterScrollController.animateTo(
                        (_filterScrollController.offset - 140).clamp(
                          0.0,
                          _filterScrollController.position.maxScrollExtent,
                        ),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Listener(
                    onPointerSignal: (pointerSignal) {
                      if (pointerSignal is PointerScrollEvent &&
                          _filterScrollController.hasClients) {
                        final delta = pointerSignal.scrollDelta.dy != 0
                            ? pointerSignal.scrollDelta.dy
                            : pointerSignal.scrollDelta.dx;
                        if (delta != 0) {
                          final target = (_filterScrollController.offset + delta).clamp(
                            0.0,
                            _filterScrollController.position.maxScrollExtent,
                          );
                          _filterScrollController.jumpTo(target);
                        }
                      }
                    },
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                          PointerDeviceKind.stylus,
                        },
                      ),
                      child: ListView.builder(
                        controller: _filterScrollController,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        itemCount: _filterCategory == 'department'
                            ? departments.length + 1
                            : branches.length + 1,
                        itemBuilder: (context, index) {
                          if (_filterCategory == 'department') {
                            final isAll = index == 0;
                            final dept = isAll ? null : departments[index - 1];
                            final isSelected = isAll
                                ? _filterDepartmentId == null
                                : _filterDepartmentId == dept?.id;
                            final count = isAll
                                ? null
                                : departmentUsers
                                    .where((u) =>
                                        u.departmentId == dept?.id ||
                                        u.departmentIds.contains(dept?.id))
                                    .length;
                            final label = isAll
                                ? 'كل الأقسام'
                                : (count != null && count > 0
                                    ? '${dept!.name} ($count)'
                                    : dept!.name);

                            return _buildFilterPill(
                              label: label,
                              isSelected: isSelected,
                              isDark: isDark,
                              onTap: () => setState(() => _filterDepartmentId = dept?.id),
                            );
                          } else {
                            final isAll = index == 0;
                            final branch = isAll ? null : branches[index - 1];
                            final isSelected = isAll
                                ? _filterBranchId == null
                                : _filterBranchId == branch?.id;
                            final count = isAll
                                ? null
                                : departmentUsers
                                    .where((u) =>
                                        u.branchId == branch?.id ||
                                        (branch != null &&
                                            branch.code.isNotEmpty &&
                                            u.branchCode.toUpperCase() ==
                                                branch.code.toUpperCase()))
                                    .length;
                            final branchTitle = isAll
                                ? 'كل الفروع'
                                : (branch!.name.isNotEmpty
                                    ? branch.name
                                    : branch.code);
                            final label = isAll
                                ? branchTitle
                                : (count != null && count > 0
                                    ? '$branchTitle ($count)'
                                    : branchTitle);

                            return _buildFilterPill(
                              label: label,
                              isSelected: isSelected,
                              isDark: isDark,
                              onTap: () => setState(() => _filterBranchId = branch?.id),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _buildScrollButton(
                  icon: Icons.chevron_left_rounded,
                  isDark: isDark,
                  onTap: () {
                    if (_filterScrollController.hasClients) {
                      _filterScrollController.animateTo(
                        (_filterScrollController.offset + 140).clamp(
                          0.0,
                          _filterScrollController.position.maxScrollExtent,
                        ),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),

        // Batch Select All In Department/Branch Banner (in group / broadcast mode)
        if ((_selectedType == 'group' || _selectedType == 'broadcast') &&
            departmentUsers.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildDepartmentBatchBanner(departmentUsers, isDark),
          ),
        ],

        const SizedBox(height: 8),

        // Contacts List
        Expanded(
          child: filteredUsers.isEmpty
              ? Center(
                  child: Text(
                    'لا يوجد زملاء مطابقين للبحث',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredUsers.length,
                  itemBuilder: (context, index) {
                    final user = filteredUsers[index];
                    final isDirect = _selectedType == 'direct';
                    final isSelected = isDirect
                        ? _selectedDirectUser?.id == user.id
                        : _selectedMembers.contains(user.id);
                    final deptName = departments
                        .where((d) => d.id == user.departmentId || user.departmentIds.contains(d.id))
                        .firstOrNull
                        ?.name;
                    final branch = branches.firstWhere(
                      (b) =>
                          b.id == user.branchId ||
                          (b.code.isNotEmpty &&
                              b.code.toUpperCase() ==
                                  user.branchCode.toUpperCase()),
                      orElse: () => BranchSummary(
                        id: '',
                        name: user.branchCode,
                        code: user.branchCode,
                        description: '',
                        membersCount: 0,
                      ),
                    );
                    final branchDisplayName = branch.name.isNotEmpty
                        ? branch.name
                        : user.branchCode;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF00A884).withValues(
                                alpha: isDark ? 0.20 : 0.08,
                              )
                            : (isDark ? const Color(0xFF1B232D) : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF00A884)
                              : borderColor,
                          width: isSelected ? 1.5 : 0.8,
                        ),
                      ),
                      child: ListTile(
                        onTap: () {
                          if (isDirect) {
                            setState(() => _selectedDirectUser = user);
                          } else {
                            _toggleMember(user.id);
                          }
                        },
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            SafeNetworkAvatar(
                              radius: 19,
                              backgroundColor: const Color(0xFF00A884),
                              imageUrl: user.avatarUrl,
                              fallbackText: user.displayName.isNotEmpty
                                  ? user.displayName[0].toUpperCase()
                                  : '?',
                              fallbackTextStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (user.isOnline)
                              Positioned(
                                bottom: -1,
                                right: -1,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF22C55E),
                                    shape: BoxShape.circle,
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
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (user.role == 'admin') ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'مسؤول',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: Colors.amber,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ] else if (user.role == 'manager') ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'مدير',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: Color(0xFF3B82F6),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                            if (deptName != null && deptName.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00A884).withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  deptName,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF00A884),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Text(
                                [
                                  if (user.jobTitle.isNotEmpty) user.jobTitle,
                                  if (branchDisplayName.isNotEmpty) '🏢 $branchDisplayName',
                                ].join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white54 : Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: isDirect
                            ? Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.arrow_forward_ios_rounded,
                                size: 16,
                                color: isSelected
                                    ? const Color(0xFF00A884)
                                    : (isDark ? Colors.white30 : Colors.black26),
                              )
                            : Checkbox(
                                value: isSelected,
                                activeColor: const Color(0xFF00A884),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                onChanged: (_) => _toggleMember(user.id),
                              ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCategoryTab({
    required String label,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF2E3B4B) : const Color(0xFFDCE4ED))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00A884)
                : (isDark ? Colors.white10 : Colors.black12),
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? (isDark ? Colors.white : const Color(0xFF0F172A))
                : (isDark ? Colors.white54 : Colors.black54),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required String label,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A884)
                : (isDark
                    ? const Color(0xFF222C38)
                    : const Color(0xFFEAEFF5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollButton({
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 24,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF222C38) : const Color(0xFFEAEFF5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Department Batch Select Banner
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDepartmentBatchBanner(
    List<ChatDirectoryUser> deptUsers,
    bool isDark,
  ) {
    final deptUserIds = deptUsers.map((u) => u.id).toSet();
    final allSelected = deptUserIds.every(_selectedMembers.contains);
    final count = deptUsers.length;
    final title = _filterBranchId != null
        ? (allSelected ? 'إلغاء تحديد أعضاء الفرع ($count)' : 'تحديد جميع أعضاء الفرع ($count)')
        : _filterDepartmentId != null
            ? (allSelected ? 'إلغاء تحديد أعضاء القسم ($count)' : 'تحديد جميع أعضاء القسم ($count)')
            : (allSelected ? 'إلغاء تحديد جميع الزملاء المعروضين ($count)' : 'تحديد جميع الزملاء المعروضين ($count)');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF00A884).withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF00A884).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            allSelected ? Icons.remove_done_rounded : Icons.done_all_rounded,
            color: const Color(0xFF00A884),
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                color: Color(0xFF00A884),
              ),
            ),
          ),
          InkWell(
            onTap: () => _toggleAllInDepartment(deptUsers),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00A884),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                allSelected ? 'إلغاء' : 'تحديد الكل',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Left Column: Details & Action Configuration
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDetailsColumn({
    required List<ChatDirectoryUser> allUsers,
    required List<DepartmentSummary> departments,
    required List<BranchSummary> branches,
    required Color cardBg,
    required Color borderColor,
    required bool isDark,
  }) {
    if (_selectedType == 'direct') {
      return _buildDirectDetailsPane(departments, branches, isDark);
    }

    if (_selectedType == 'department') {
      return _buildDepartmentRoomPane(departments, isDark);
    }

    if (_selectedType == 'broadcast') {
      return _buildBroadcastPane(allUsers, isDark);
    }

    // Default: Group Mode
    return _buildGroupDetailsPane(allUsers, isDark);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Direct Chat Pane (Selected User Card & Start Chat Action)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDirectDetailsPane(
    List<DepartmentSummary> departments,
    List<BranchSummary> branches,
    bool isDark,
  ) {
    if (_selectedDirectUser == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 34,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'اختر جهة اتصال',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'انقر على أي زميل في القائمة لبدء المحادثة المباشرة معه فوراً',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final user = _selectedDirectUser!;
    final deptName = departments
        .where((d) => d.id == user.departmentId || user.departmentIds.contains(d.id))
        .firstOrNull
        ?.name;
    final branch = branches.firstWhere(
      (b) =>
          b.id == user.branchId ||
          (b.code.isNotEmpty &&
              b.code.toUpperCase() == user.branchCode.toUpperCase()),
      orElse: () => BranchSummary(
        id: '',
        name: user.branchCode,
        code: user.branchCode,
        description: '',
        membersCount: 0,
      ),
    );
    final branchDisplayName =
        branch.name.isNotEmpty ? branch.name : user.branchCode;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Large Avatar
          SafeNetworkAvatar(
            radius: 38,
            backgroundColor: const Color(0xFF00A884),
            imageUrl: user.avatarUrl,
            fallbackText: user.displayName.isNotEmpty
                ? user.displayName[0].toUpperCase()
                : '?',
            fallbackTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            user.displayName,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          Text(
            '@${user.username}',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),

          const SizedBox(height: 14),

          // User details pills
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1B232D) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildInfoRow('الحالة', user.isOnline ? 'متصل الآن 🟢' : 'غير متصل', isDark),
                if (user.jobTitle.isNotEmpty)
                  _buildInfoRow('المسمى الوظيفي', user.jobTitle, isDark),
                if (deptName != null)
                  _buildInfoRow('القسم', deptName, isDark),
                if (branchDisplayName.isNotEmpty)
                  _buildInfoRow('الفرع', branchDisplayName, isDark),
              ],
            ),
          ),

          const Spacer(),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isCreating ? null : _createConversation,
              icon: _isCreating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.chat_bubble_rounded),
              label: Text(
                'بدء المحادثة مع ${user.displayName.split(' ').first}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00A884),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Group Mode Details Pane
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildGroupDetailsPane(
    List<ChatDirectoryUser> allUsers,
    bool isDark,
  ) {
    final selectedUsers =
        allUsers.where((u) => _selectedMembers.contains(u.id)).toList();

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAvatarPicker(isDark),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'اسم المجموعة (مطلوب)',
              prefixIcon: const Icon(Icons.group_rounded, size: 20),
              filled: true,
              fillColor: isDark ? const Color(0xFF1B232D) : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descriptionController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'الوصف (اختياري)',
              prefixIcon: const Icon(Icons.description_outlined, size: 20),
              filled: true,
              fillColor: isDark ? const Color(0xFF1B232D) : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Selected Members Counter & Clear
          Row(
            children: [
              Text(
                'الأعضاء المختارون (${selectedUsers.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (selectedUsers.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _selectedMembers.clear()),
                  child: const Text(
                    'مسح الكل',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Selected Members Chips Box
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B232D) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.black12,
                ),
              ),
              child: selectedUsers.isEmpty
                  ? Center(
                      child: Text(
                        'حدد الأعضاء من القائمة المقابلة',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: selectedUsers.map((u) {
                          return Chip(
                            avatar: SafeNetworkAvatar(
                              radius: 10,
                              backgroundColor: const Color(0xFF00A884),
                              imageUrl: u.avatarUrl,
                              fallbackText: u.displayName.isNotEmpty
                                  ? u.displayName[0]
                                  : '?',
                              fallbackTextStyle: const TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                              ),
                            ),
                            label: Text(
                              u.displayName,
                              style: const TextStyle(fontSize: 11),
                            ),
                            onDeleted: () => _toggleMember(u.id),
                            deleteIconColor: Colors.red,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 12),

          FilledButton.icon(
            onPressed: _isCreating || selectedUsers.isEmpty
                ? null
                : _createConversation,
            icon: _isCreating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              selectedUsers.isEmpty
                  ? 'اختر عضواً واحداً على الأقل'
                  : 'إنشاء المجموعة (${selectedUsers.length} أعضاء)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00A884),
              padding: const EdgeInsets.symmetric(vertical: 12),
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
  // Department Room Pane
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDepartmentRoomPane(
    List<DepartmentSummary> departments,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: _departmentRoomDeptId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'اختر القسم',
              prefixIcon: const Icon(Icons.apartment_rounded),
              filled: true,
              fillColor: isDark ? const Color(0xFF1B232D) : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
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

          const SizedBox(height: 12),

          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'اسم الغرفة (اختياري)',
              hintText: 'يترك فارغاً للاسم التلقائي: غرفة [القسم]',
              prefixIcon: const Icon(Icons.meeting_room_rounded),
              filled: true,
              fillColor: isDark ? const Color(0xFF1B232D) : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 12),

          TextField(
            controller: _descriptionController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'الوصف (اختياري)',
              prefixIcon: const Icon(Icons.description_outlined),
              filled: true,
              fillColor: isDark ? const Color(0xFF1B232D) : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const Spacer(),

          FilledButton.icon(
            onPressed: _isCreating ? null : _createConversation,
            icon: _isCreating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add_rounded),
            label: const Text(
              'إنشاء غرفة القسم',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              padding: const EdgeInsets.symmetric(vertical: 12),
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
  // Broadcast Pane
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBroadcastPane(
    List<ChatDirectoryUser> allUsers,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAvatarPicker(isDark),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'اسم قناة البث (مطلوب)',
              prefixIcon: const Icon(Icons.campaign_rounded),
              filled: true,
              fillColor: isDark ? const Color(0xFF1B232D) : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 12),

          TextField(
            controller: _descriptionController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'وصف القناة (اختياري)',
              prefixIcon: const Icon(Icons.description_outlined),
              filled: true,
              fillColor: isDark ? const Color(0xFF1B232D) : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 14),

          Text(
            'المستلمون المحددون: ${_selectedMembers.length} زميل',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),

          const Spacer(),

          FilledButton.icon(
            onPressed: _isCreating || _selectedMembers.isEmpty
                ? null
                : _createConversation,
            icon: _isCreating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.campaign_rounded),
            label: Text(
              'إنشاء قناة البث (${_selectedMembers.length} مستلم)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
