import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../models/chat_models.dart';
import 'widgets/chat_avatar.dart';

class GroupManagementScreen extends ConsumerStatefulWidget {
  const GroupManagementScreen({super.key, required this.conversation});

  final ChatConversation conversation;

  @override
  ConsumerState<GroupManagementScreen> createState() =>
      _GroupManagementScreenState();
}

class _GroupManagementScreenState
    extends ConsumerState<GroupManagementScreen>
    with SingleTickerProviderStateMixin {
  late ChatConversation _conversation;
  late TabController _tabController;

  final Set<String> _selectedToAdd = <String>{};
  bool _busy = false;
  bool _uploadingAvatar = false;

  String _membersSearchQuery = '';
  String _addSearchQuery = '';

  final TextEditingController _membersSearchController =
      TextEditingController();
  final TextEditingController _addSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _membersSearchController.dispose();
    _addSearchController.dispose();
    super.dispose();
  }

  bool _isAdmin(String userId) =>
      _conversation.admins.any((entry) => entry.id == userId);

  Future<void> _run(Future<ChatConversation> Function() task) async {
    setState(() => _busy = true);
    try {
      final updated = await task();
      if (!mounted) return;
      setState(() => _conversation = updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Avatar Management
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _pickAndUploadAvatar() async {
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

      setState(() => _uploadingAvatar = true);

      final updated = await ref
          .read(chatOverviewControllerProvider.notifier)
          .uploadConversationAvatar(
            conversationId: _conversation.id,
            filePath: picked.path,
            fileBytes: bytes,
            fileName: picked.name,
          );

      if (!mounted) return;
      setState(() {
        _conversation = updated;
        _uploadingAvatar = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث صورة المجموعة بنجاح'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل رفع الصورة: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _removeAvatar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إزالة صورة المجموعة'),
        content: const Text('هل أنت متأكد من حذف صورة المجموعة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف الصورة'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await _run(() => ref
        .read(chatOverviewControllerProvider.notifier)
        .removeConversationAvatar(conversationId: _conversation.id));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Group Info Editing (Name & Description)
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _editGroupInfo() async {
    final nameCtrl = TextEditingController(text: _conversation.name);
    final descCtrl = TextEditingController(text: _conversation.description);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل معلومات المجموعة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم المجموعة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'الوصف',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حفظ التعديلات'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    final newName = nameCtrl.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اسم المجموعة لا يمكن أن يكون فارغاً'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await _run(() => ref
        .read(chatOverviewControllerProvider.notifier)
        .updateGroupInfo(
          conversationId: _conversation.id,
          name: newName,
          description: descCtrl.text.trim(),
        ));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Pinned Message Management
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _upsertPinnedMessage({required bool edit}) async {
    final currentText = _conversation.pinnedMessage?.content ?? '';
    final controller = TextEditingController(text: edit ? currentText : '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(edit ? 'تعديل الرسالة المثبتة' : 'إضافة رسالة مثبتة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          decoration: const InputDecoration(
            hintText: 'اكتب الرسالة التي ستظهر لكل أعضاء المجموعة',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (!mounted || value == null || value.isEmpty) {
      return;
    }

    await _run(
      () => ref
          .read(chatOverviewControllerProvider.notifier)
          .setGroupPinnedMessage(
            conversationId: _conversation.id,
            content: value,
          ),
    );
  }

  Future<void> _removePinnedMessage() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الرسالة المثبتة'),
        content: const Text('هل تريد حذف الرسالة المثبتة الحالية؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;

    await _run(
      () => ref
          .read(chatOverviewControllerProvider.notifier)
          .clearGroupPinnedMessage(conversationId: _conversation.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final overview = ref.watch(chatOverviewControllerProvider).valueOrNull;
    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final currentUserId = authUser?.id;
    final ownerId = _conversation.createdBy;

    final isOwner = currentUserId != null && currentUserId == ownerId;
    final isGroupAdmin = currentUserId != null && _isAdmin(currentUserId);
    final isSystemAdmin = authUser?.role == 'admin';
    final canManage = isOwner || isGroupAdmin || isSystemAdmin;

    final primaryColor = const Color(0xFF007AFF);
    final surfaceCardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final surfaceBgColor =
        isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final dividerColor = isDark ? Colors.white12 : const Color(0xFFE5E5EA);

    if (currentUserId == null || !canManage) {
      return Scaffold(
        backgroundColor: surfaceBgColor,
        appBar: AppBar(
          title: const Text('إدارة المجموعة'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'غير مصرح لك بإدارة هذه المجموعة.\nيمكن فقط لمالك المجموعة أو مشرفيها إدارتها.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    final memberIds = _conversation.members.map((entry) => entry.id).toSet();
    final blockedIds = _conversation.blockedMemberIds.toSet();
    final allUsers = overview?.users ?? const <ChatDirectoryUser>[];

    final filteredMembers = _conversation.members.where((m) {
      if (_membersSearchQuery.isEmpty) return true;
      final q = _membersSearchQuery.toLowerCase();
      return m.displayName.toLowerCase().contains(q) ||
          m.username.toLowerCase().contains(q);
    }).toList();

    final addableUsers = allUsers.where((user) {
      final isEligible =
          !memberIds.contains(user.id) && !blockedIds.contains(user.id);
      if (!isEligible) return false;
      if (_addSearchQuery.isEmpty) return true;
      final q = _addSearchQuery.toLowerCase();
      return user.displayName.toLowerCase().contains(q) ||
          user.username.toLowerCase().contains(q);
    }).toList();

    final blockedUsers = _conversation.blockedMembers;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        backgroundColor: surfaceBgColor,
        appBar: AppBar(
          backgroundColor: surfaceCardColor,
          elevation: 0.5,
          leading: IconButton(
            icon: const Icon(CupertinoIcons.back),
            onPressed: () => Navigator.pop(context, _conversation),
          ),
          title: Text(
            _conversation.type == 'broadcast'
                ? 'إدارة قناة البث'
                : 'إدارة المجموعة',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          actions: [
            IconButton(
              icon: const Icon(CupertinoIcons.pencil),
              tooltip: 'تعديل اسم ووصف المجموعة',
              onPressed: _editGroupInfo,
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // ── Group Header Card (Avatar + Stats) ───────────────────
                Container(
                  width: double.infinity,
                  color: surfaceCardColor,
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  child: Column(
                    children: [
                      // Avatar with camera badge
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ChatAvatar(
                            radius: 46,
                            backgroundColor: primaryColor.withValues(alpha: 0.12),
                            avatarUrl: _conversation.avatarUrl,
                            fallback: Icon(
                              _conversation.type == 'broadcast'
                                  ? CupertinoIcons.radiowaves_right
                                  : CupertinoIcons.person_3_fill,
                              color: primaryColor,
                              size: 42,
                            ),
                          ),
                          if (_uploadingAvatar)
                            Positioned.fill(
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black45,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: AppLoadingIndicator(size: 24),
                                ),
                              ),
                            ),
                          Positioned(
                            bottom: -2,
                            left: -2,
                            child: Material(
                              color: primaryColor,
                              shape: const CircleBorder(),
                              elevation: 2,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                                child: const Padding(
                                  padding: EdgeInsets.all(7),
                                  child: Icon(
                                    CupertinoIcons.camera_fill,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Title & Description
                      Text(
                        _conversation.name.isNotEmpty
                            ? _conversation.name
                            : 'مجموعة بدون اسم',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFFE2E8F0)
                              : const Color(0xFF0F172A),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_conversation.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _conversation.description,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 10),

                      // Status Chips
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildChip(
                            text: '${_conversation.members.length} عضو',
                            color: const Color(0xFF3390EC),
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),
                          _buildChip(
                            text: '${_conversation.admins.length} مشرف',
                            color: const Color(0xFF19A974),
                            isDark: isDark,
                          ),
                          if (blockedUsers.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            _buildChip(
                              text: '${blockedUsers.length} محظور',
                              color: const Color(0xFFF59E0B),
                              isDark: isDark,
                            ),
                          ],
                          if (_conversation.avatarUrl != null) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _removeAvatar,
                              borderRadius: BorderRadius.circular(6),
                              child: _buildChip(
                                text: 'حذف الصورة',
                                color: Colors.redAccent,
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Apple Segmented TabBar ───────────────────────────────
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFE5E5EA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: surfaceCardColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: isDark ? Colors.white : const Color(0xFF0F172A),
                    unselectedLabelColor:
                        isDark ? Colors.white54 : Colors.black45,
                    labelStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: [
                      Tab(text: 'الأعضاء (${_conversation.members.length})'),
                      const Tab(text: 'إضافة'),
                      const Tab(text: 'المثبتة'),
                      Tab(text: 'المحظورون (${blockedUsers.length})'),
                    ],
                  ),
                ),

                // ── Tab Views ────────────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // TAB 1: Members
                      _buildMembersTab(
                        filteredMembers: filteredMembers,
                        ownerId: ownerId,
                        currentUserId: currentUserId,
                        isDark: isDark,
                        surfaceCardColor: surfaceCardColor,
                        dividerColor: dividerColor,
                        primaryColor: primaryColor,
                      ),

                      // TAB 2: Add Members
                      _buildAddMembersTab(
                        addableUsers: addableUsers,
                        isDark: isDark,
                        surfaceCardColor: surfaceCardColor,
                        dividerColor: dividerColor,
                        primaryColor: primaryColor,
                      ),

                      // TAB 3: Pinned Message
                      _buildPinnedMessageTab(
                        isDark: isDark,
                        surfaceCardColor: surfaceCardColor,
                        dividerColor: dividerColor,
                        primaryColor: primaryColor,
                      ),

                      // TAB 4: Blocked Members
                      _buildBlockedMembersTab(
                        blockedUsers: blockedUsers,
                        isDark: isDark,
                        surfaceCardColor: surfaceCardColor,
                        dividerColor: dividerColor,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (_busy)
              Container(
                color: Colors.black26,
                child: const Center(child: AppLoadingIndicator(size: 32)),
              ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Sub-widgets
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildChip({
    required String text,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildMembersTab({
    required List<ChatDirectoryUser> filteredMembers,
    required String? ownerId,
    required String? currentUserId,
    required bool isDark,
    required Color surfaceCardColor,
    required Color dividerColor,
    required Color primaryColor,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: CupertinoSearchTextField(
            controller: _membersSearchController,
            placeholder: 'ابحث في أعضاء المجموعة...',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 13,
            ),
            onChanged: (val) => setState(() => _membersSearchQuery = val),
          ),
        ),
        Expanded(
          child: filteredMembers.isEmpty
              ? Center(
                  child: Text(
                    'لا يوجد أعضاء مطابقين للبحث',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filteredMembers.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 0.5,
                    indent: 68,
                    endIndent: 16,
                    color: dividerColor,
                  ),
                  itemBuilder: (context, index) {
                    final member = filteredMembers[index];
                    final isMemberOwner = member.id == ownerId;
                    final isMemberAdmin = _isAdmin(member.id);
                    final isMe = member.id == currentUserId;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 2,
                      ),
                      leading: ChatAvatar(
                        radius: 20,
                        backgroundColor: primaryColor.withValues(alpha: 0.12),
                        avatarUrl: member.avatarUrl,
                        fallback: Text(
                          member.displayName.isNotEmpty
                              ? member.displayName.substring(0, 1)
                              : '?',
                          style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              member.displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: isDark
                                    ? const Color(0xFFE2E8F0)
                                    : const Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isMe)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                '(أنت)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: primaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (isMemberOwner)
                            _buildChip(
                              text: 'مالك',
                              color: Colors.amber.shade800,
                              isDark: isDark,
                            )
                          else if (isMemberAdmin)
                            _buildChip(
                              text: 'مشرف',
                              color: primaryColor,
                              isDark: isDark,
                            )
                          else
                            _buildChip(
                              text: 'عضو',
                              color: Colors.grey,
                              isDark: isDark,
                            ),
                        ],
                      ),
                      subtitle: Text(
                        member.jobTitle.isNotEmpty
                            ? '${member.jobTitle} • @${member.username}'
                            : '@${member.username}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                      trailing: isMemberOwner
                          ? null
                          : PopupMenuButton<String>(
                              icon: const Icon(CupertinoIcons.ellipsis, size: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onSelected: (action) {
                                if (action == 'toggle_admin') {
                                  _run(() => isMemberAdmin
                                      ? ref
                                          .read(
                                            chatOverviewControllerProvider
                                                .notifier,
                                          )
                                          .demoteGroupAdmin(
                                            conversationId: _conversation.id,
                                            userId: member.id,
                                          )
                                      : ref
                                          .read(
                                            chatOverviewControllerProvider
                                                .notifier,
                                          )
                                          .promoteGroupAdmin(
                                            conversationId: _conversation.id,
                                            userId: member.id,
                                          ));
                                } else if (action == 'remove') {
                                  _run(() => ref
                                      .read(
                                        chatOverviewControllerProvider
                                            .notifier,
                                      )
                                      .removeGroupMember(
                                        conversationId: _conversation.id,
                                        userId: member.id,
                                      ));
                                } else if (action == 'block') {
                                  _run(() => ref
                                      .read(
                                        chatOverviewControllerProvider
                                            .notifier,
                                      )
                                      .blockGroupMember(
                                        conversationId: _conversation.id,
                                        userId: member.id,
                                      ));
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'toggle_admin',
                                  child: Row(
                                    children: [
                                      Icon(
                                        isMemberAdmin
                                            ? CupertinoIcons.person_badge_minus
                                            : CupertinoIcons.person_badge_plus,
                                        size: 18,
                                        color: primaryColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isMemberAdmin
                                            ? 'إلغاء الإشراف'
                                            : 'تعيين كمشرف',
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons
                                            .person_crop_circle_badge_minus,
                                        size: 18,
                                        color: Colors.redAccent,
                                      ),
                                      SizedBox(width: 8),
                                      Text('إزالة من المجموعة'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'block',
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.slash_circle,
                                        size: 18,
                                        color: Colors.red,
                                      ),
                                      SizedBox(width: 8),
                                      Text('حظر العضو'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAddMembersTab({
    required List<ChatDirectoryUser> addableUsers,
    required bool isDark,
    required Color surfaceCardColor,
    required Color dividerColor,
    required Color primaryColor,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: CupertinoSearchTextField(
            controller: _addSearchController,
            placeholder: 'ابحث بالاسم أو اسم المستخدم...',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 13,
            ),
            onChanged: (val) => setState(() => _addSearchQuery = val),
          ),
        ),
        Expanded(
          child: addableUsers.isEmpty
              ? Center(
                  child: Text(
                    'لا يوجد جهات اتصال متاحة للإضافة',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: addableUsers.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 0.5,
                    indent: 68,
                    endIndent: 16,
                    color: dividerColor,
                  ),
                  itemBuilder: (context, index) {
                    final user = addableUsers[index];
                    final isSelected = _selectedToAdd.contains(user.id);

                    return CheckboxListTile(
                      value: isSelected,
                      activeColor: primaryColor,
                      secondary: ChatAvatar(
                        radius: 20,
                        backgroundColor: primaryColor.withValues(alpha: 0.12),
                        avatarUrl: user.avatarUrl,
                        fallback: Text(
                          user.displayName.isNotEmpty
                              ? user.displayName.substring(0, 1)
                              : '?',
                          style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        user.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark
                              ? const Color(0xFFE2E8F0)
                              : const Color(0xFF0F172A),
                        ),
                      ),
                      subtitle: Text(
                        user.jobTitle.isNotEmpty
                            ? '${user.jobTitle} • @${user.username}'
                            : '@${user.username}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selectedToAdd.add(user.id);
                          } else {
                            _selectedToAdd.remove(user.id);
                          }
                        });
                      },
                    );
                  },
                ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            MediaQuery.paddingOf(context).bottom + 12,
          ),
          decoration: BoxDecoration(
            color: surfaceCardColor,
            border: Border(top: BorderSide(color: dividerColor, width: 0.5)),
          ),
          child: Row(
            children: [
              Text(
                'المحدد: ${_selectedToAdd.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _selectedToAdd.isEmpty
                    ? null
                    : () async {
                        await _run(() => ref
                            .read(chatOverviewControllerProvider.notifier)
                            .addGroupMembers(
                              conversationId: _conversation.id,
                              userIds: _selectedToAdd.toList(),
                            ));
                        if (mounted) {
                          setState(() {
                            _selectedToAdd.clear();
                            _addSearchController.clear();
                            _addSearchQuery = '';
                          });
                          _tabController.animateTo(0);
                        }
                      },
                icon: const Icon(CupertinoIcons.person_badge_plus, size: 16),
                label: Text('إضافة (${_selectedToAdd.length})'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPinnedMessageTab({
    required bool isDark,
    required Color surfaceCardColor,
    required Color dividerColor,
    required Color primaryColor,
  }) {
    final pinned = _conversation.pinnedMessage;
    final hasPinned = pinned != null && pinned.content.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: surfaceCardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: dividerColor, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(CupertinoIcons.pin_fill, color: primaryColor, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'الرسالة المثبتة',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  hasPinned
                      ? pinned.content
                      : 'لا توجد رسالة مثبتة حالياً. يمكنك تثبيت رسالة هامة لتظهر في أعلى المحادثة لجميع الأعضاء.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: hasPinned
                        ? (isDark ? Colors.white : Colors.black87)
                        : (isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
                if (hasPinned && pinned.setByName.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'تم التثبيت بواسطة: ${pinned.setByName}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _upsertPinnedMessage(edit: hasPinned),
                icon: Icon(
                  hasPinned ? CupertinoIcons.pencil : CupertinoIcons.pin_fill,
                  size: 16,
                ),
                label: Text(hasPinned ? 'تعديل الرسالة' : 'تثبيت رسالة'),
              ),
              if (hasPinned) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _removePinnedMessage,
                  icon: const Icon(CupertinoIcons.trash, size: 16),
                  label: const Text('إلغاء التثبيت'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedMembersTab({
    required List<ChatDirectoryUser> blockedUsers,
    required bool isDark,
    required Color surfaceCardColor,
    required Color dividerColor,
  }) {
    if (blockedUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.checkmark_shield,
              size: 48,
              color: isDark ? Colors.white24 : Colors.black12,
            ),
            const SizedBox(height: 12),
            Text(
              'لا يوجد أعضاء محظورون',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: blockedUsers.length,
      separatorBuilder: (_, __) => Divider(
        height: 0.5,
        indent: 68,
        endIndent: 16,
        color: dividerColor,
      ),
      itemBuilder: (context, index) {
        final user = blockedUsers[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey.withValues(alpha: 0.2),
            child: Text(
              user.displayName.isNotEmpty
                  ? user.displayName.substring(0, 1)
                  : '?',
            ),
          ),
          title: Text(
            user.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text('@${user.username}'),
          trailing: FilledButton.tonal(
            onPressed: () => _run(
              () => ref
                  .read(chatOverviewControllerProvider.notifier)
                  .unblockGroupMember(
                    conversationId: _conversation.id,
                    userId: user.id,
                  ),
            ),
            child: const Text('إلغاء الحظر'),
          ),
        );
      },
    );
  }
}
