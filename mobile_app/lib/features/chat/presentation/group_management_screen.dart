import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Avatar Management
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _showAvatarOptionsSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 12),
                width: 36,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(CupertinoIcons.camera_fill, color: Color(0xFF007AFF), size: 19),
                ),
                title: const Text('التقاط صورة بالكاميرا', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadAvatar(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(CupertinoIcons.photo_fill_on_rectangle_fill, color: Color(0xFF34C759), size: 19),
                ),
                title: const Text('اختيار من معرض الصور', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadAvatar(ImageSource.gallery);
                },
              ),
              if (_conversation.avatarUrl != null) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(CupertinoIcons.trash_fill, color: Color(0xFFFF3B30), size: 19),
                  ),
                  title: const Text(
                    'إزالة الصورة الحالية',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFFF3B30)),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeAvatar();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
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
          content: Text('تم تحديث صورة المجموعة بنجاح! 🎉'),
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
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          title: const Text('إزالة صورة المجموعة'),
          content: const Text('هل أنت متأكد من حذف صورة المجموعة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF3B30)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف الصورة'),
            ),
          ],
        );
      },
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(CupertinoIcons.pencil, color: Color(0xFF007AFF), size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  'تعديل معلومات المجموعة',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'اسم المجموعة',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF38383E) : const Color(0xFFE2E8F0),
                  width: 0.8,
                ),
              ),
              child: TextField(
                controller: nameCtrl,
                autofocus: true,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  hintText: 'اكتب اسم المجموعة...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'الوصف (اختياري)',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF38383E) : const Color(0xFFE2E8F0),
                  width: 0.8,
                ),
              ),
              child: TextField(
                controller: descCtrl,
                maxLines: 3,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 13.5,
                ),
                decoration: const InputDecoration(
                  hintText: 'أضف وصفاً يوضح أهداف المجموعة...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('حفظ التعديلات', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(CupertinoIcons.pin_fill, color: Color(0xFF007AFF), size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  edit ? 'تعديل الرسالة المثبتة' : 'تثبيت رسالة جديدة',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF38383E) : const Color(0xFFE2E8F0),
                  width: 0.8,
                ),
              ),
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  hintText: 'اكتب نص الرسالة التي ستظهر مثبتة لجميع الأعضاء...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                    child: Text(edit ? 'حفظ التعديل' : 'تثبيت الآن', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (!mounted || value == null || value.isEmpty) return;

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
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          title: const Text('حذف الرسالة المثبتة'),
          content: const Text('هل تريد بالتأكيد إلغاء تثبيت وحذف الرسالة الحالية؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF3B30)),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حذف التثبيت'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true || !mounted) return;

    await _run(
      () => ref
          .read(chatOverviewControllerProvider.notifier)
          .clearGroupPinnedMessage(conversationId: _conversation.id),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Member Actions Sheet (iOS Style)
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _showMemberActionSheet({
    required ChatDirectoryUser member,
    required bool isMemberAdmin,
    required bool canModerate,
  }) async {
    if (!canModerate) return;
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 12),
                width: 36,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),

              // Member info preview header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Row(
                  children: [
                    ChatAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFF007AFF).withValues(alpha: 0.12),
                      avatarUrl: member.avatarUrl,
                      fallback: Text(
                        member.displayName.isNotEmpty ? member.displayName[0] : '?',
                        style: const TextStyle(color: Color(0xFF007AFF), fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.displayName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            member.jobTitle.isNotEmpty
                                ? '${member.jobTitle} • @${member.username}'
                                : '@${member.username}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, indent: 16, endIndent: 16),

              // Action 1: Toggle Admin
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isMemberAdmin ? CupertinoIcons.person_badge_minus : CupertinoIcons.person_badge_plus,
                    color: const Color(0xFF007AFF),
                    size: 19,
                  ),
                ),
                title: Text(
                  isMemberAdmin ? 'إلغاء صفة المشرف' : 'تعيين كمشرف للمجموعة',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _run(() => isMemberAdmin
                      ? ref.read(chatOverviewControllerProvider.notifier).demoteGroupAdmin(
                            conversationId: _conversation.id,
                            userId: member.id,
                          )
                      : ref.read(chatOverviewControllerProvider.notifier).promoteGroupAdmin(
                            conversationId: _conversation.id,
                            userId: member.id,
                          ));
                },
              ),

              // Action 2: Remove from Group
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9500).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(CupertinoIcons.person_crop_circle_badge_minus, color: Color(0xFFFF9500), size: 19),
                ),
                title: const Text('إزالة من المجموعة', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFFF9500))),
                onTap: () {
                  Navigator.pop(ctx);
                  _run(() => ref.read(chatOverviewControllerProvider.notifier).removeGroupMember(
                        conversationId: _conversation.id,
                        userId: member.id,
                      ));
                },
              ),

              // Action 3: Block member
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(CupertinoIcons.slash_circle, color: Color(0xFFFF3B30), size: 19),
                ),
                title: const Text('حظر العضو من المجموعة', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFFF3B30))),
                onTap: () {
                  Navigator.pop(ctx);
                  _run(() => ref.read(chatOverviewControllerProvider.notifier).blockGroupMember(
                        conversationId: _conversation.id,
                        userId: member.id,
                      ));
                },
              ),
            ],
          ),
        ),
      ),
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
    final surfaceBgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final dividerColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);

    if (currentUserId == null || !canManage) {
      return Scaffold(
        backgroundColor: surfaceBgColor,
        appBar: AppBar(title: const Text('إدارة المجموعة')),
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
          elevation: 0,
          scrolledUnderElevation: 0.5,
          leading: IconButton(
            icon: const Icon(CupertinoIcons.back),
            onPressed: () => Navigator.pop(context, _conversation),
          ),
          title: Text(
            _conversation.type == 'broadcast' ? 'إدارة قناة البث' : 'إدارة المجموعة',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          actions: [
            IconButton(
              icon: const Icon(CupertinoIcons.pencil_circle_fill, size: 24),
              color: primaryColor,
              tooltip: 'تعديل اسم ووصف المجموعة',
              onPressed: _editGroupInfo,
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // ── Group Header Card (Apple Inset Profile) ──────────────
                Container(
                  width: double.infinity,
                  color: surfaceCardColor,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      // Avatar with camera badge
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GestureDetector(
                            onTap: _showAvatarOptionsSheet,
                            child: ChatAvatar(
                              radius: 44,
                              backgroundColor: primaryColor.withValues(alpha: 0.12),
                              avatarUrl: _conversation.avatarUrl,
                              fallback: Icon(
                                _conversation.type == 'broadcast'
                                    ? CupertinoIcons.radiowaves_right
                                    : CupertinoIcons.person_3_fill,
                                color: primaryColor,
                                size: 40,
                              ),
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
                            child: GestureDetector(
                              onTap: _showAvatarOptionsSheet,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: primaryColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: surfaceCardColor, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.18),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  CupertinoIcons.camera_fill,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Title & Description
                      Text(
                        _conversation.name.isNotEmpty
                            ? _conversation.name
                            : 'مجموعة بدون اسم',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_conversation.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _conversation.description,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 10),

                      // Apple Inset Status Badges
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildApplePill(
                            icon: CupertinoIcons.person_2_fill,
                            text: '${_conversation.members.length} عضو',
                            color: const Color(0xFF007AFF),
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),
                          _buildApplePill(
                            icon: CupertinoIcons.shield_fill,
                            text: '${_conversation.admins.length} مشرف',
                            color: const Color(0xFF34C759),
                            isDark: isDark,
                          ),
                          if (blockedUsers.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            _buildApplePill(
                              icon: CupertinoIcons.slash_circle,
                              text: '${blockedUsers.length} محظور',
                              color: const Color(0xFFFF9500),
                              isDark: isDark,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Apple Segmented TabBar ───────────────────────────────
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
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
                          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: isDark ? Colors.white : const Color(0xFF0F172A),
                    unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    tabs: [
                      Tab(text: 'الأعضاء (${_conversation.members.length})'),
                      const Tab(text: 'إضافة +'),
                      const Tab(text: 'المثبتة 📌'),
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
                        canManage: canManage,
                      ),

                      // TAB 2: Add Members
                      _buildAddMembersTab(
                        allUsers: allUsers,
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
  // Sub-widgets & Tabs
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildApplePill({
    required IconData icon,
    required String text,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.35 : 0.20),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
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
    required bool canManage,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: CupertinoSearchTextField(
            controller: _membersSearchController,
            placeholder: 'بحث في الأعضاء...',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 13.5,
            ),
            onChanged: (val) => setState(() => _membersSearchQuery = val),
          ),
        ),
        Expanded(
          child: filteredMembers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.person_2,
                        size: 40,
                        color: isDark ? Colors.white24 : Colors.black12,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'لا يوجد أعضاء مطابقين للبحث',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
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
                    final canModerateThisMember = canManage && !isMemberOwner && !isMe;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      onTap: canModerateThisMember
                          ? () => _showMemberActionSheet(
                                member: member,
                                isMemberAdmin: isMemberAdmin,
                                canModerate: canModerateThisMember,
                              )
                          : null,
                      leading: Stack(
                        children: [
                          ChatAvatar(
                            radius: 20,
                            backgroundColor: primaryColor.withValues(alpha: 0.12),
                            avatarUrl: member.avatarUrl,
                            fallback: Text(
                              member.displayName.isNotEmpty
                                  ? member.displayName[0]
                                  : '?',
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (member.isOnline)
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
                                    color: surfaceCardColor,
                                    width: 1.5,
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
                              member.displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isMe) ...[
                            Text(
                              '(أنت)',
                              style: TextStyle(
                                fontSize: 11,
                                color: primaryColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (isMemberOwner)
                            _buildApplePill(
                              icon: CupertinoIcons.star_fill,
                              text: 'مالك',
                              color: const Color(0xFFF59E0B),
                              isDark: isDark,
                            )
                          else if (isMemberAdmin)
                            _buildApplePill(
                              icon: CupertinoIcons.shield_fill,
                              text: 'مشرف',
                              color: primaryColor,
                              isDark: isDark,
                            ),
                        ],
                      ),
                      subtitle: Text(
                        member.jobTitle.isNotEmpty
                            ? '${member.jobTitle} • @${member.username}'
                            : '@${member.username}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                      trailing: canModerateThisMember
                          ? Icon(
                              CupertinoIcons.chevron_forward,
                              size: 14,
                              color: isDark ? Colors.white30 : Colors.black26,
                            )
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAddMembersTab({
    required List<ChatDirectoryUser> allUsers,
    required List<ChatDirectoryUser> addableUsers,
    required bool isDark,
    required Color surfaceCardColor,
    required Color dividerColor,
    required Color primaryColor,
  }) {
    // Map selected IDs to users for carousel tray
    final selectedUsers = allUsers.where((u) => _selectedToAdd.contains(u.id)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: CupertinoSearchTextField(
            controller: _addSearchController,
            placeholder: 'بحث بالاسم أو اسم المستخدم...',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 13.5,
            ),
            onChanged: (val) => setState(() => _addSearchQuery = val),
          ),
        ),

        // ── Selected Users Tray (Carousel) ───────────────────────────
        if (selectedUsers.isNotEmpty)
          Container(
            height: 78,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF242428) : const Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: dividerColor, width: 0.5)),
            ),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: selectedUsers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final user = selectedUsers[index];
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ChatAvatar(
                          radius: 20,
                          backgroundColor: primaryColor.withValues(alpha: 0.12),
                          avatarUrl: user.avatarUrl,
                          fallback: Text(
                            user.displayName.isNotEmpty ? user.displayName[0] : '?',
                            style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          width: 52,
                          child: Text(
                            user.displayName.split(' ').first,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      top: -2,
                      right: -2,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedToAdd.remove(user.id));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF3B30),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(CupertinoIcons.clear, size: 10, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

        // ── Addable Users List ───────────────────────────────────────
        Expanded(
          child: addableUsers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.person_badge_plus,
                        size: 40,
                        color: isDark ? Colors.white24 : Colors.black12,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'لا توجد جهات اتصال متاحة للإضافة',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                          fontSize: 13,
                        ),
                      ),
                    ],
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

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          if (isSelected) {
                            _selectedToAdd.remove(user.id);
                          } else {
                            _selectedToAdd.add(user.id);
                          }
                        });
                      },
                      leading: ChatAvatar(
                        radius: 20,
                        backgroundColor: primaryColor.withValues(alpha: 0.12),
                        avatarUrl: user.avatarUrl,
                        fallback: Text(
                          user.displayName.isNotEmpty ? user.displayName[0] : '?',
                          style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        user.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
                        ),
                      ),
                      subtitle: Text(
                        user.jobTitle.isNotEmpty
                            ? '${user.jobTitle} • @${user.username}'
                            : '@${user.username}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                      trailing: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isSelected ? primaryColor : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? primaryColor : (isDark ? Colors.white30 : Colors.black26),
                            width: 1.5,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(CupertinoIcons.checkmark, size: 14, color: Colors.white)
                            : null,
                      ),
                    );
                  },
                ),
        ),

        // ── Floating Action Bar ──────────────────────────────────────
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            MediaQuery.paddingOf(context).bottom + 12,
          ),
          decoration: BoxDecoration(
            color: surfaceCardColor,
            border: Border(top: BorderSide(color: dividerColor, width: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'الأعضاء المحددون',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                  Text(
                    '${_selectedToAdd.length} عضو',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تمت إضافة الأعضاء بنجاح! 🎉'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                icon: const Icon(CupertinoIcons.person_badge_plus, size: 17),
                label: Text(
                  'إضافة إلى المجموعة',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: surfaceCardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: dividerColor, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
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
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(CupertinoIcons.pin_fill, color: primaryColor, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'الرسالة المثبتة الحالية',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  hasPinned
                      ? pinned.content
                      : 'لا توجد رسالة مثبتة حالياً. يمكنك تثبيت رسالة هامة لتظهر في شريط علوي بارز لجميع أعضاء المجموعة.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: hasPinned
                        ? (isDark ? Colors.white : Colors.black87)
                        : (isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
                if (hasPinned && pinned.setByName.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(CupertinoIcons.person_crop_circle, size: 13, color: isDark ? Colors.white38 : Colors.black38),
                      const SizedBox(width: 4),
                      Text(
                        'تم التثبيت بواسطة: ${pinned.setByName}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => _upsertPinnedMessage(edit: hasPinned),
                  icon: Icon(
                    hasPinned ? CupertinoIcons.pencil : CupertinoIcons.pin_fill,
                    size: 16,
                  ),
                  label: Text(
                    hasPinned ? 'تعديل الرسالة' : 'تثبيت رسالة',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (hasPinned) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF3B30),
                      side: const BorderSide(color: Color(0xFFFF3B30), width: 0.8),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _removePinnedMessage,
                    icon: const Icon(CupertinoIcons.trash, size: 16),
                    label: const Text('إلغاء التثبيت', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
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
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7)),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.checkmark_shield_fill,
                size: 32,
                color: Color(0xFF34C759),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'لا يوجد أعضاء محظورون',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'الأعضاء المحظورون من المجموعة سيظهرون هنا ويمكنك إلغاء حظرهم.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: ChatAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFFF3B30).withValues(alpha: 0.12),
            avatarUrl: user.avatarUrl,
            fallback: Text(
              user.displayName.isNotEmpty ? user.displayName[0] : '?',
              style: const TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(
            user.displayName,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _run(
              () => ref
                  .read(chatOverviewControllerProvider.notifier)
                  .unblockGroupMember(
                    conversationId: _conversation.id,
                    userId: user.id,
                  ),
            ),
            child: const Text('إلغاء الحظر', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        );
      },
    );
  }
}
