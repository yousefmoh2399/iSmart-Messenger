import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/safe_network_avatar.dart';
import '../models/chat_models.dart';

class GroupManagementDialog extends ConsumerStatefulWidget {
  const GroupManagementDialog({super.key, required this.conversation});

  final ChatConversation conversation;

  @override
  ConsumerState<GroupManagementDialog> createState() =>
      _GroupManagementDialogState();
}

class _GroupManagementDialogState
    extends ConsumerState<GroupManagementDialog>
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
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم المجموعة',
                  hintText: 'أدخل اسم المجموعة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'الوصف',
                  hintText: 'اكتب وصفاً مختصراً للمجموعة',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
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
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'اكتب رسالة تظهر لجميع أعضاء المجموعة',
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

  Future<void> _clearPinnedMessage() async {
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

    final primaryColor = theme.colorScheme.primary;
    final surfaceCardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final surfaceBgColor =
        isDark ? const Color(0xFF121214) : const Color(0xFFF2F2F7);
    final dividerColor = isDark ? Colors.white12 : const Color(0xFFE5E5EA);

    return Dialog(
      backgroundColor: surfaceBgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: SizedBox(
        width: 820,
        height: 720,
        child: !canManage
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'غير مصرح لك بإدارة هذه المجموعة.\nيمكن فقط لمالك المجموعة ومشرفيها إدارتها.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              )
            : Stack(
                children: [
                  Column(
                    children: [
                      // ── Top Bar ──────────────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
                        decoration: BoxDecoration(
                          color: surfaceCardColor,
                          border: Border(
                            bottom: BorderSide(
                              color: dividerColor,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _conversation.type == 'broadcast'
                                    ? CupertinoIcons.radiowaves_right
                                    : CupertinoIcons.person_3_fill,
                                color: primaryColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _conversation.type == 'broadcast'
                                      ? 'إدارة قناة البث'
                                      : 'إدارة المجموعة',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? const Color(0xFFE2E8F0)
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  '${_conversation.members.length} أعضاء',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(CupertinoIcons.xmark_circle_fill),
                              color: isDark ? Colors.white38 : Colors.black26,
                              iconSize: 24,
                              onPressed: () =>
                                  Navigator.pop(context, _conversation),
                            ),
                          ],
                        ),
                      ),

                      // ── Group Header Card (Avatar + Info) ────────────────────
                      Container(
                        margin: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surfaceCardColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                  alpha: isDark ? 0.2 : 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // ── Avatar with Camera Overlay ───
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                SafeNetworkAvatar(
                                  radius: 40,
                                  imageUrl: _conversation.avatarUrl,
                                  fallbackIcon: _conversation.type ==
                                          'broadcast'
                                      ? CupertinoIcons.radiowaves_right
                                      : CupertinoIcons.person_3_fill,
                                  fallbackIconSize: 32,
                                  fallbackIconColor: primaryColor,
                                  backgroundColor:
                                      primaryColor.withValues(alpha: 0.12),
                                ),
                                if (_uploadingAvatar)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
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
                                      onTap: _uploadingAvatar
                                          ? null
                                          : _pickAndUploadAvatar,
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
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
                            const SizedBox(width: 18),

                            // ── Name & Description ───
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _conversation.name.isNotEmpty
                                              ? _conversation.name
                                              : 'مجموعة بدون اسم',
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? const Color(0xFFE2E8F0)
                                                : const Color(0xFF0F172A),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          CupertinoIcons.pencil,
                                          size: 18,
                                        ),
                                        tooltip: 'تعديل الاسم والوصف',
                                        onPressed: _editGroupInfo,
                                      ),
                                      if (_conversation.avatarUrl != null)
                                        IconButton(
                                          icon: const Icon(
                                            CupertinoIcons.trash,
                                            size: 18,
                                            color: Colors.redAccent,
                                          ),
                                          tooltip: 'إزالة الصورة',
                                          onPressed: _removeAvatar,
                                        ),
                                    ],
                                  ),
                                  if (_conversation
                                      .description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _conversation.description,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.black54,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      _buildStatusBadge(
                                        isDark: isDark,
                                        text: _conversation.type == 'broadcast'
                                            ? 'قناة بث'
                                            : 'مجموعة خاصة',
                                        color: primaryColor,
                                      ),
                                      const SizedBox(width: 8),
                                      _buildStatusBadge(
                                        isDark: isDark,
                                        text:
                                            '${_conversation.admins.length} مشرفين',
                                        color: Colors.indigo,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Apple Style Segmented TabBar ─────────────────────────
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
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
                          labelColor: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                          unselectedLabelColor:
                              isDark ? Colors.white54 : Colors.black45,
                          labelStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          tabs: [
                            Tab(text: 'الأعضاء (${_conversation.members.length})'),
                            const Tab(text: 'إضافة أعضاء'),
                            const Tab(text: 'الرسالة المثبتة'),
                            Tab(text: 'المحظورون (${blockedUsers.length})'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Tab Views ────────────────────────────────────────────
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // ── TAB 1: Members ───
                            _buildMembersTab(
                              context: context,
                              members: filteredMembers,
                              ownerId: ownerId,
                              currentUserId: currentUserId,
                              isDark: isDark,
                              surfaceCardColor: surfaceCardColor,
                              dividerColor: dividerColor,
                              primaryColor: primaryColor,
                            ),

                            // ── TAB 2: Add Members ───
                            _buildAddMembersTab(
                              context: context,
                              addableUsers: addableUsers,
                              isDark: isDark,
                              surfaceCardColor: surfaceCardColor,
                              dividerColor: dividerColor,
                              primaryColor: primaryColor,
                            ),

                            // ── TAB 3: Pinned Message ───
                            _buildPinnedMessageTab(
                              context: context,
                              isDark: isDark,
                              surfaceCardColor: surfaceCardColor,
                              dividerColor: dividerColor,
                              primaryColor: primaryColor,
                            ),

                            // ── TAB 4: Blocked Members ───
                            _buildBlockedMembersTab(
                              context: context,
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
  // Sub-widgets & Tab Builders
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildStatusBadge({
    required bool isDark,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildMembersTab({
    required BuildContext context,
    required List<ChatDirectoryUser> members,
    required String? ownerId,
    required String? currentUserId,
    required bool isDark,
    required Color surfaceCardColor,
    required Color dividerColor,
    required Color primaryColor,
  }) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
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
        const SizedBox(height: 6),

        Expanded(
          child: members.isEmpty
              ? Center(
                  child: Text(
                    'لا يوجد أعضاء مطابقين للبحث',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                )
              : Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  decoration: BoxDecoration(
                    color: surfaceCardColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: members.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 0.5,
                      indent: 68,
                      endIndent: 16,
                      color: dividerColor,
                    ),
                    itemBuilder: (context, index) {
                      final member = members[index];
                      final isMemberOwner = member.id == ownerId;
                      final isMemberAdmin = _isAdmin(member.id);
                      final isMe = member.id == currentUserId;

                      return ListTile(
                        leading: SafeNetworkAvatar(
                          radius: 20,
                          backgroundColor: primaryColor.withValues(alpha: 0.12),
                          imageUrl: member.avatarUrl,
                          fallbackText: member.displayName.isNotEmpty
                              ? member.displayName.substring(0, 1)
                              : '?',
                        ),
                        title: Row(
                          children: [
                            Text(
                              member.displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: isDark
                                    ? const Color(0xFFE2E8F0)
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            if (isMe)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  '(أنت)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            const Spacer(),
                            if (isMemberOwner)
                              _buildStatusBadge(
                                isDark: isDark,
                                text: 'مالك',
                                color: Colors.amber.shade800,
                              )
                            else if (isMemberAdmin)
                              _buildStatusBadge(
                                isDark: isDark,
                                text: 'مشرف',
                                color: primaryColor,
                              )
                            else
                              _buildStatusBadge(
                                isDark: isDark,
                                text: 'عضو',
                                color: Colors.grey,
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
                                icon: const Icon(
                                  CupertinoIcons.ellipsis_circle,
                                  size: 20,
                                ),
                                tooltip: 'إجراءات العضو',
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
                                itemBuilder: (ctx) => [
                                  PopupMenuItem(
                                    value: 'toggle_admin',
                                    child: Row(
                                      children: [
                                        Icon(
                                          isMemberAdmin
                                              ? CupertinoIcons
                                                  .person_badge_minus
                                              : CupertinoIcons
                                                  .person_badge_plus,
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
                                          CupertinoIcons.person_crop_circle_badge_minus,
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
        ),
      ],
    );
  }

  Widget _buildAddMembersTab({
    required BuildContext context,
    required List<ChatDirectoryUser> addableUsers,
    required bool isDark,
    required Color surfaceCardColor,
    required Color dividerColor,
    required Color primaryColor,
  }) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
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
        const SizedBox(height: 6),

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
              : Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: surfaceCardColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
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
                        checkboxShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        secondary: SafeNetworkAvatar(
                          radius: 20,
                          backgroundColor: primaryColor.withValues(alpha: 0.12),
                          imageUrl: user.avatarUrl,
                          fallbackText: user.displayName.isNotEmpty
                              ? user.displayName.substring(0, 1)
                              : '?',
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
        ),

        // Bottom action bar
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(
            children: [
              Text(
                'تم تحديد ${_selectedToAdd.length} من جهات الاتصال',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                icon: const Icon(CupertinoIcons.person_badge_plus, size: 18),
                label: Text('إضافة المحددين (${_selectedToAdd.length})'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPinnedMessageTab({
    required BuildContext context,
    required bool isDark,
    required Color surfaceCardColor,
    required Color dividerColor,
    required Color primaryColor,
  }) {
    final pinned = _conversation.pinnedMessage;
    final hasPinned = pinned != null && pinned.content.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
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
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        CupertinoIcons.pin_fill,
                        color: primaryColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'الرسالة المثبتة للمجموعة',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  hasPinned
                      ? pinned.content
                      : 'لا توجد رسالة مثبتة حالياً. يمكنك تثبيت رسالة هامة لتظهر في أعلى المحادثة لجميع الأعضاء.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: hasPinned
                        ? (isDark ? Colors.white : Colors.black87)
                        : (isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
                if (hasPinned && pinned.setByName.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'تم التثبيت بواسطة: ${pinned.setByName}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () => _upsertPinnedMessage(edit: hasPinned),
                icon: Icon(
                  hasPinned
                      ? CupertinoIcons.pencil
                      : CupertinoIcons.pin_fill,
                  size: 18,
                ),
                label: Text(hasPinned ? 'تعديل الرسالة' : 'تثبيت رسالة جديدة'),
              ),
              if (hasPinned) ...[
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  onPressed: _clearPinnedMessage,
                  icon: const Icon(CupertinoIcons.trash, size: 18),
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
    required BuildContext context,
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
              'لا يوجد أعضاء محظورون في هذه المجموعة',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      decoration: BoxDecoration(
        color: surfaceCardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
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
            leading: SafeNetworkAvatar(
              radius: 20,
              backgroundColor: Colors.grey.withValues(alpha: 0.18),
              imageUrl: user.avatarUrl,
              fallbackText: user.displayName.isNotEmpty
                  ? user.displayName.substring(0, 1)
                  : '?',
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
              '@${user.username}',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
            trailing: FilledButton.tonal(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
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
      ),
    );
  }
}
