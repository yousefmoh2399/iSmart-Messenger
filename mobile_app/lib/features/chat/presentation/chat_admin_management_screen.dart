import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/admin_announcement.dart';
import '../../../shared/models/managed_user.dart';
import '../../../shared/models/remote_document.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/button_loading_indicator.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../models/chat_models.dart';

class ChatAdminManagementScreen extends ConsumerStatefulWidget {
  const ChatAdminManagementScreen({super.key});

  @override
  ConsumerState<ChatAdminManagementScreen> createState() =>
      _ChatAdminManagementScreenState();
}

class _ChatAdminManagementScreenState
    extends ConsumerState<ChatAdminManagementScreen> {
  late Future<List<ChatAuditLog>> _auditLogsFuture;
  late Future<List<ChatSystemError>> _systemErrorsFuture;

  @override
  void initState() {
    super.initState();
    _reloadLogs();
  }

  void _reloadLogs() {
    final controller = ref.read(chatOverviewControllerProvider.notifier);
    _auditLogsFuture = controller.fetchAuditLogs(limit: 150);
    _systemErrorsFuture = controller.fetchSystemErrors(limit: 150);
  }

  Future<void> _refreshAll() async {
    await ref.read(chatOverviewControllerProvider.notifier).refresh();
    await ref.read(usersControllerProvider.notifier).refresh();
    await ref.read(adminAnnouncementsControllerProvider.notifier).refresh();
    await ref.read(adminDocumentsControllerProvider.notifier).refresh();
    if (mounted) {
      setState(_reloadLogs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overviewState = ref.watch(chatOverviewControllerProvider);
    final announcementsState = ref.watch(adminAnnouncementsControllerProvider);
    final documentsState = ref.watch(adminDocumentsControllerProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('لوحة تحكم الشات'),
        backgroundColor: scaffoldBg,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(onPressed: _refreshAll, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: overviewState.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            ShimmerSkeleton(height: 50, borderRadius: 12),
            SizedBox(height: 12),
            ShimmerSkeleton(height: 150, borderRadius: 14),
            SizedBox(height: 24),
            ShimmerSkeleton(height: 150, borderRadius: 14),
          ],
        ),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
        data: (overview) {
          Widget buildSection(String title, List<Widget> children) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: children.asMap().entries.map((entry) {
                      final isLast = entry.key == children.length - 1;
                      return Column(
                        children: [
                          entry.value,
                          if (!isLast)
                            const Divider(
                              height: 0.5,
                              thickness: 0.5,
                              indent: 56,
                            ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            );
          }

          Widget buildItem({
            required String title,
            required IconData icon,
            required Color color,
            required Widget screen,
          }) {
            return ListTile(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(title)),
                      body: screen,
                    ),
                  ),
                );
              },
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Colors.grey,
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              buildSection('المحتوى', [
                buildItem(
                  title: 'الإعلانات',
                  icon: Icons.campaign_rounded,
                  color: Colors.orange,
                  screen: _AnnouncementsTab(
                    announcementsState: announcementsState,
                  ),
                ),
                buildItem(
                  title: 'الملفات',
                  icon: Icons.folder_rounded,
                  color: Colors.blue,
                  screen: _AdminDocumentsTab(documentsState: documentsState),
                ),
              ]),
              const SizedBox(height: 8),
              buildSection('الهيكلة', [
                buildItem(
                  title: 'الأقسام',
                  icon: Icons.business_rounded,
                  color: Colors.indigo,
                  screen: _DepartmentsTab(
                    departments: overview.departments,
                    users: overview.users,
                  ),
                ),
                buildItem(
                  title: 'الفروع',
                  icon: Icons.location_on_rounded,
                  color: Colors.purple,
                  screen: _BranchesTab(branches: overview.branches),
                ),
                buildItem(
                  title: 'الغرف والمجموعات',
                  icon: Icons.forum_rounded,
                  color: Colors.teal,
                  screen: _RoomsTab(
                    conversations: overview.manageableConversations,
                    users: overview.users,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              buildSection('الإدارة والصلاحيات', [
                buildItem(
                  title: 'المستخدمون',
                  icon: Icons.people_rounded,
                  color: Colors.green,
                  screen: _UsersTab(
                    departments: overview.departments,
                    branches: overview.branches,
                  ),
                ),
                buildItem(
                  title: 'الصلاحيات (Roles)',
                  icon: Icons.admin_panel_settings_rounded,
                  color: Colors.red,
                  screen: _RolesTab(roles: overview.roles),
                ),
              ]),
              const SizedBox(height: 8),
              buildSection('النظام', [
                buildItem(
                  title: 'سجل النظام (Audit)',
                  icon: Icons.history_rounded,
                  color: Colors.blueGrey,
                  screen: _AuditLogsTab(logsFuture: _auditLogsFuture),
                ),
                buildItem(
                  title: 'الأخطاء التقنية',
                  icon: Icons.bug_report_rounded,
                  color: Colors.redAccent,
                  screen: _SystemErrorsTab(errorsFuture: _systemErrorsFuture),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}

class _AdminDocumentsTab extends ConsumerStatefulWidget {
  const _AdminDocumentsTab({required this.documentsState});

  final AsyncValue<List<RemoteDocument>> documentsState;

  @override
  ConsumerState<_AdminDocumentsTab> createState() => _AdminDocumentsTabState();
}

class _AdminDocumentsTabState extends ConsumerState<_AdminDocumentsTab> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RemoteDocument> _filter(List<RemoteDocument> documents) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return documents;
    return documents.where((document) {
      final owner =
          '${document.ownerFullName ?? ''} ${document.ownerUsername ?? ''}'
              .toLowerCase();
      return document.fileName.toLowerCase().contains(query) ||
          owner.contains(query);
    }).toList();
  }

  Future<void> _downloadAndOpen(RemoteDocument document) async {
    try {
      final localPath = await ref
          .read(documentRepositoryProvider)
          .downloadDocument(document);
      await OpenFilex.open(localPath);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _renameDocument(RemoteDocument document) async {
    final controller = TextEditingController(text: document.fileName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة تسمية الملف'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'اسم الملف'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    try {
      await ref
          .read(documentRepositoryProvider)
          .renameDocument(document.id, result);
      await ref.read(adminDocumentsControllerProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تحديث اسم الملف')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteDocument(RemoteDocument document) async {
    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حذف الملف'),
            content: Text('هل تريد حذف "${document.fileName}" نهائيًا؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete) return;

    try {
      await ref.read(documentRepositoryProvider).deleteDocument(document.id);
      await ref.read(adminDocumentsControllerProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حذف الملف')));
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
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      color: scaffoldBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'ابحث باسم الملف أو صاحب الملف',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFE5E5EA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
              ),
            ),
          ),
          Expanded(
            child: widget.documentsState.when(
              loading: () => ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  ShimmerSkeleton(height: 100, borderRadius: 12),
                  SizedBox(height: 12),
                  ShimmerSkeleton(height: 100, borderRadius: 12),
                ],
              ),
              error: (error, stackTrace) =>
                  Center(child: Text(error.toString())),
              data: (documents) {
                final filtered = _filter(documents);
                if (filtered.isEmpty) {
                  return const Center(child: Text('لا توجد ملفات'));
                }

                return RefreshIndicator(
                  onRefresh: () => ref
                      .read(adminDocumentsControllerProvider.notifier)
                      .refresh(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    children: [
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: filtered.asMap().entries.map((entry) {
                            final isLast = entry.key == filtered.length - 1;
                            final document = entry.value;
                            final ownerName =
                                document.ownerFullName?.trim().isNotEmpty ==
                                    true
                                ? document.ownerFullName!
                                : (document.ownerUsername ?? 'غير معروف');

                            return Column(
                              children: [
                                ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.folder_rounded,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  title: Text(
                                    document.fileName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '$ownerName • ${formatFileSize(document.fileSize)} • ${formatDate(document.createdAt)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded),
                                    onSelected: (action) {
                                      if (action == 'open') {
                                        _downloadAndOpen(document);
                                      }
                                      if (action == 'rename') {
                                        _renameDocument(document);
                                      }
                                      if (action == 'delete') {
                                        _deleteDocument(document);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'open',
                                        child: Row(
                                          children: [
                                            Icon(Icons.open_in_new),
                                            SizedBox(width: 8),
                                            Text('فتح وتنزيل'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'rename',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_rounded),
                                            SizedBox(width: 8),
                                            Text('إعادة تسمية'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.delete_outline_rounded,
                                              color: Colors.red,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'حذف',
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isLast)
                                  const Divider(
                                    height: 0.5,
                                    thickness: 0.5,
                                    indent: 56,
                                  ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => ref
                            .read(adminDocumentsControllerProvider.notifier)
                            .loadMore(),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('تحميل المزيد'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersTab extends ConsumerWidget {
  const _UsersTab({required this.departments, required this.branches});

  final List<DepartmentSummary> departments;
  final List<BranchSummary> branches;

  Future<void> _showResetPasswordDialog(
    BuildContext context,
    WidgetRef ref,
    ManagedUser user,
  ) async {
    final userRepository = ref.read(userManagementRepositoryProvider);
    final passwordController = TextEditingController(text: '123456');
    var isSaving = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(
            'إعادة تعيين كلمة المرور لـ ${user.fullName.isEmpty ? user.username : user.fullName}',
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: passwordController,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور الجديدة',
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Color(0xFFB91C1C)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: isSaving
                  ? null
                  : () async {
                      final password = passwordController.text.trim();
                      if (password.length < 6) {
                        setLocalState(() {
                          errorText =
                              'كلمة المرور يجب أن تكون 6 أحرف على الأقل.';
                        });
                        return;
                      }
                      setLocalState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await userRepository.resetPassword(
                          userId: user.id,
                          password: password,
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تمت إعادة تعيين كلمة المرور بنجاح'),
                          ),
                        );
                      } catch (error) {
                        setLocalState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              icon: const Icon(Icons.lock_reset_outlined),
              label: isSaving
                  ? const Text('جار الحفظ...')
                  : const Text('إعادة التعيين'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUser(
    BuildContext context,
    WidgetRef ref,
    ManagedUser user,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المستخدم'),
        content: Text(
          'هل تريد حذف المستخدم "${user.fullName.isEmpty ? user.username : user.fullName}" نهائياً؟ هذا الإجراء سيؤدي إلى حذف المحادثات والتذاكر المرتبطة به.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(usersControllerProvider.notifier).deleteUser(user.id);
      await ref.read(chatOverviewControllerProvider.notifier).refresh();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حذف المستخدم بنجاح.')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل حذف المستخدم: $error')));
    }
  }

  Future<void> _showForceLogoutDialog(
    BuildContext context,
    WidgetRef ref,
    ManagedUser user,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إنهاء جميع الجلسات'),
        content: Text(
          'هل تريد تسجيل الخروج القسري لـ "${user.fullName.isEmpty ? user.username : user.fullName}" من جميع الأجهزة والمنصات؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد تسجيل الخروج'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(usersControllerProvider.notifier).logoutUserAll(user.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنهاء جميع جلسات المستخدم بنجاح.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل إنهاء الجلسات: $error')));
    }
  }

  Future<void> _showUserDialog(
    BuildContext context,
    WidgetRef ref, {
    ManagedUser? user,
  }) async {
    final userRepository = ref.read(userManagementRepositoryProvider);
    final usersController = ref.read(usersControllerProvider.notifier);
    final overviewController = ref.read(
      chatOverviewControllerProvider.notifier,
    );
    final usernameController = TextEditingController(
      text: user?.username ?? '',
    );
    final fullNameController = TextEditingController(
      text: user?.fullName ?? '',
    );
    final passwordController = TextEditingController();
    var role = user?.role ?? 'user';
    String? departmentId = user?.departmentId;
    String? branchId = user?.branchId;
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(user == null ? 'إضافة مستخدم' : 'تعديل مستخدم'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: usernameController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: fullNameController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(
                      labelText: 'الاسم الكامل',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'الدور'),
                    items: const [
                      DropdownMenuItem(value: 'user', child: Text('user')),
                      DropdownMenuItem(
                        value: 'manager',
                        child: Text('manager'),
                      ),
                      DropdownMenuItem(value: 'admin', child: Text('admin')),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) => role = value ?? role,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: departmentId,
                    decoration: const InputDecoration(labelText: 'القسم'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('بدون قسم'),
                      ),
                      ...departments.map(
                        (department) => DropdownMenuItem<String?>(
                          value: department.id,
                          child: Text(department.name),
                        ),
                      ),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) => departmentId = value,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: branchId,
                    decoration: const InputDecoration(labelText: 'الفرع'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('بدون فرع'),
                      ),
                      ...branches.map(
                        (branch) => DropdownMenuItem<String?>(
                          value: branch.id,
                          child: Text(branch.name),
                        ),
                      ),
                    ],
                    onChanged: isSaving ? null : (value) => branchId = value,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    enabled: !isSaving,
                    decoration: InputDecoration(
                      labelText: user == null
                          ? 'كلمة المرور'
                          : 'كلمة مرور جديدة أو إعادة تعيينها',
                      helperText: user == null
                          ? 'اتركها فارغة لاستخدام 123456 أو اكتب 6 أحرف على الأقل'
                          : 'اتركها فارغة لو لن تغيّر كلمة المرور',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final username = usernameController.text.trim();
                      final fullName = fullNameController.text.trim();
                      final password = passwordController.text.trim();
                      if (username.isEmpty) {
                        setLocalState(() {
                          errorText = 'اسم المستخدم مطلوب.';
                        });
                        return;
                      }
                      if (fullName.isEmpty) {
                        setLocalState(() {
                          errorText = 'الاسم الكامل مطلوب.';
                        });
                        return;
                      }
                      if (password.isNotEmpty && password.length < 6) {
                        setLocalState(() {
                          errorText =
                              'كلمة المرور يجب أن تكون 6 أحرف على الأقل.';
                        });
                        return;
                      }
                      setLocalState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        if (user == null) {
                          await userRepository.createUser(
                            username: username,
                            fullName: fullName,
                            password: password.isEmpty ? '123456' : password,
                            role: role,
                            departmentId: departmentId,
                            branchId: branchId,
                          );
                        } else {
                          await userRepository.updateUser(
                            userId: user.id,
                            username: username,
                            fullName: fullName,
                            password: password,
                            role: role,
                            departmentId: departmentId,
                            branchId: branchId,
                          );
                        }
                        if (context.mounted) {
                          Navigator.pop(context, true);
                        }
                      } catch (error) {
                        setLocalState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && context.mounted) {
      await usersController.refresh();
      await overviewController.refresh();
      if (!context.mounted) return;
      final actionLabel = user == null
          ? 'تم إنشاء المستخدم بنجاح.'
          : 'تم تحديث المستخدم بنجاح.';
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(actionLabel)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersState = ref.watch(usersControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      color: scaffoldBg,
      child: usersState.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            ShimmerSkeleton(height: 48, borderRadius: 12),
            SizedBox(height: 12),
            ShimmerSkeleton(height: 82, borderRadius: 14),
            SizedBox(height: 10),
            ShimmerSkeleton(height: 82, borderRadius: 14),
          ],
        ),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
        data: (users) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton.icon(
              onPressed: () => _showUserDialog(context, ref),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('إضافة مستخدم'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            if (users.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.group_rounded,
                      size: 48,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'لا يوجد مستخدمين مسجلين',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: users.asMap().entries.map((entry) {
                    final isLast = entry.key == users.length - 1;
                    final user = entry.value;

                    return Column(
                      children: [
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.1),
                            child: Text(
                              user.fullName.isNotEmpty
                                  ? user.fullName[0].toUpperCase()
                                  : user.username[0].toUpperCase(),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          title: Text(
                            user.fullName.isEmpty
                                ? user.username
                                : user.fullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            '${user.username} • ${user.role} • ${_departmentName(departments, user.departmentId)} • ${_branchName(branches, user.branchId)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ManagedUserStatusSwitch(
                                userId: user.id,
                                isActive: user.isActive,
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _showUserDialog(context, ref, user: user);
                                  } else if (value == 'reset_password') {
                                    _showResetPasswordDialog(
                                      context,
                                      ref,
                                      user,
                                    );
                                  } else if (value == 'logout_all') {
                                    _showForceLogoutDialog(context, ref, user);
                                  } else if (value == 'delete') {
                                    _deleteUser(context, ref, user);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_rounded),
                                        SizedBox(width: 8),
                                        Text('تعديل البيانات'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'reset_password',
                                    child: Row(
                                      children: [
                                        Icon(Icons.lock_reset_outlined),
                                        SizedBox(width: 8),
                                        Text('إعادة تعيين كلمة المرور'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'logout_all',
                                    child: Row(
                                      children: [
                                        Icon(Icons.logout_rounded),
                                        SizedBox(width: 8),
                                        Text('إنهاء جميع الجلسات'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_outline_rounded,
                                          color: Colors.red,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'حذف المستخدم',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (!isLast)
                          const Divider(
                            height: 0.5,
                            thickness: 0.5,
                            indent: 72,
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(usersControllerProvider.notifier).loadMore(),
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text('تحميل المزيد'),
            ),
          ],
        ),
      ),
    );
  }
}

String _branchName(List<BranchSummary> branches, String? id) {
  if (id == null) return 'بدون فرع';
  return branches
          .where((branch) => branch.id == id)
          .map((branch) => branch.name)
          .firstOrNull ??
      'بدون فرع';
}

class _ManagedUserStatusSwitch extends ConsumerStatefulWidget {
  const _ManagedUserStatusSwitch({
    required this.userId,
    required this.isActive,
  });

  final String userId;
  final bool isActive;

  @override
  ConsumerState<_ManagedUserStatusSwitch> createState() =>
      _ManagedUserStatusSwitchState();
}

class _ManagedUserStatusSwitchState
    extends ConsumerState<_ManagedUserStatusSwitch> {
  late bool _isActive = widget.isActive;
  var _isSaving = false;

  @override
  void didUpdateWidget(covariant _ManagedUserStatusSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSaving && oldWidget.isActive != widget.isActive) {
      _isActive = widget.isActive;
    }
  }

  Future<void> _updateStatus(bool value) async {
    final previousValue = _isActive;
    setState(() {
      _isSaving = true;
      _isActive = value;
    });
    try {
      await ref
          .read(userManagementRepositoryProvider)
          .updateUserStatus(userId: widget.userId, isActive: value);
      await ref.read(usersControllerProvider.notifier).refresh();
      await ref.read(chatOverviewControllerProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            value ? 'تم تفعيل المستخدم بنجاح.' : 'تم إيقاف المستخدم بنجاح.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isActive = previousValue;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSaving) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: ButtonLoadingIndicator(),
        ),
      );
    }

    return Switch(value: _isActive, onChanged: _updateStatus);
  }
}

class _AnnouncementsTab extends ConsumerWidget {
  const _AnnouncementsTab({required this.announcementsState});

  final AsyncValue<List<AdminAnnouncement>> announcementsState;

  Color _toneColor(BuildContext context, String tone) {
    final scheme = Theme.of(context).colorScheme;
    return switch (tone) {
      'success' => const Color(0xFF166534),
      'warning' => const Color(0xFFD97706),
      'critical' => scheme.error,
      _ => scheme.primary,
    };
  }

  String _toneLabel(String tone) {
    return switch (tone) {
      'success' => 'نجاح',
      'warning' => 'تنبيه',
      'critical' => 'عاجل',
      _ => 'معلومة',
    };
  }

  Future<void> _showAnnouncementDialog(
    BuildContext context,
    WidgetRef ref, {
    AdminAnnouncement? announcement,
  }) async {
    final announcementRepository = ref.read(announcementRepositoryProvider);
    final adminAnnouncementsController = ref.read(
      adminAnnouncementsControllerProvider.notifier,
    );
    final announcementsController = ref.read(
      announcementsControllerProvider.notifier,
    );
    final titleController = TextEditingController(
      text: announcement?.title ?? '',
    );
    final messageController = TextEditingController(
      text: announcement?.message ?? '',
    );
    var tone = announcement?.tone ?? 'info';
    var isPinned = announcement?.isPinned == true;
    var isActive = announcement?.isActive != false;
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(announcement == null ? 'إضافة إعلان' : 'تعديل إعلان'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(labelText: 'العنوان'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: messageController,
                    enabled: !isSaving,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'نص الإعلان'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: tone,
                    decoration: const InputDecoration(labelText: 'النوع'),
                    items: const [
                      DropdownMenuItem(value: 'info', child: Text('معلومة')),
                      DropdownMenuItem(value: 'success', child: Text('نجاح')),
                      DropdownMenuItem(value: 'warning', child: Text('تنبيه')),
                      DropdownMenuItem(value: 'critical', child: Text('عاجل')),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) => tone = value ?? tone,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: isPinned,
                    onChanged: isSaving
                        ? null
                        : (value) => setLocalState(() => isPinned = value),
                    title: const Text('تثبيت في البداية'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    value: isActive,
                    onChanged: isSaving
                        ? null
                        : (value) => setLocalState(() => isActive = value),
                    title: const Text('نشط'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final title = titleController.text.trim();
                      final message = messageController.text.trim();
                      if (title.length < 2) {
                        setLocalState(() {
                          errorText = 'العنوان يجب أن يكون حرفين على الأقل.';
                        });
                        return;
                      }
                      if (message.length < 4) {
                        setLocalState(() {
                          errorText = 'نص الإعلان قصير جدًا.';
                        });
                        return;
                      }
                      setLocalState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        if (announcement == null) {
                          await announcementRepository.createAnnouncement(
                            title: title,
                            message: message,
                            tone: tone,
                            isPinned: isPinned,
                            isActive: isActive,
                          );
                        } else {
                          await announcementRepository.updateAnnouncement(
                            announcementId: announcement.id,
                            title: title,
                            message: message,
                            tone: tone,
                            isPinned: isPinned,
                            isActive: isActive,
                          );
                        }
                        if (!context.mounted) return;
                        Navigator.pop(context, true);
                      } catch (error) {
                        setLocalState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && context.mounted) {
      await adminAnnouncementsController.refresh();
      await announcementsController.refresh();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      color: scaffoldBg,
      child: announcementsState.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            ShimmerSkeleton(height: 48, borderRadius: 12),
            SizedBox(height: 12),
            ShimmerSkeleton(height: 110, borderRadius: 16),
            SizedBox(height: 10),
            ShimmerSkeleton(height: 110, borderRadius: 16),
          ],
        ),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
        data: (announcements) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton.icon(
              onPressed: () => _showAnnouncementDialog(context, ref),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('إضافة إعلان'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            if (announcements.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.campaign_rounded,
                      size: 48,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'لا توجد إعلانات',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: announcements.asMap().entries.map((entry) {
                    final isLast = entry.key == announcements.length - 1;
                    final announcement = entry.value;

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      announcement.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  Switch(
                                    value: announcement.isActive,
                                    onChanged: (value) async {
                                      final updated = await ref
                                          .read(announcementRepositoryProvider)
                                          .updateAnnouncementStatus(
                                            announcementId: announcement.id,
                                            isActive: value,
                                          );
                                      ref
                                          .read(
                                            adminAnnouncementsControllerProvider
                                                .notifier,
                                          )
                                          .applyAnnouncement(updated);
                                      ref
                                          .read(
                                            announcementsControllerProvider
                                                .notifier,
                                          )
                                          .applyAnnouncement(updated);
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                announcement.message,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Chip(
                                    label: Text(
                                      _toneLabel(announcement.tone),
                                      style: TextStyle(
                                        color: _toneColor(
                                          context,
                                          announcement.tone,
                                        ),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    backgroundColor: _toneColor(
                                      context,
                                      announcement.tone,
                                    ).withValues(alpha: 0.12),
                                    side: BorderSide.none,
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  if (announcement.isPinned)
                                    Chip(
                                      label: const Text(
                                        'مثبت',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      side: BorderSide.none,
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                      padding: EdgeInsets.zero,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      formatEgyptDateTime(
                                        announcement.updatedAt,
                                        separator: ' • ',
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 20,
                                    ),
                                    color: Colors.blue,
                                    onPressed: () => _showAnnouncementDialog(
                                      context,
                                      ref,
                                      announcement: announcement,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                    ),
                                    color: Colors.red,
                                    onPressed: () async {
                                      await ref
                                          .read(announcementRepositoryProvider)
                                          .deleteAnnouncement(announcement.id);
                                      await ref
                                          .read(
                                            adminAnnouncementsControllerProvider
                                                .notifier,
                                          )
                                          .refresh();
                                      await ref
                                          .read(
                                            announcementsControllerProvider
                                                .notifier,
                                          )
                                          .refresh();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (!isLast) const Divider(height: 0.5, thickness: 0.5),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentsTab extends ConsumerWidget {
  const _DepartmentsTab({required this.departments, required this.users});

  final List<DepartmentSummary> departments;
  final List<ChatDirectoryUser> users;

  Future<void> _showDepartmentDialog(
    BuildContext context,
    WidgetRef ref, {
    DepartmentSummary? department,
  }) async {
    final overviewController = ref.read(
      chatOverviewControllerProvider.notifier,
    );
    final nameController = TextEditingController(text: department?.name ?? '');
    final codeController = TextEditingController(text: department?.code ?? '');
    final descriptionController = TextEditingController(
      text: department?.description ?? '',
    );
    final selectedManagers = <String>{...?department?.managers};
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(department == null ? 'إضافة قسم' : 'تعديل قسم'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(labelText: 'اسم القسم'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(labelText: 'الكود'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(labelText: 'الوصف'),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'المديرون',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...users
                      .where(
                        (entry) =>
                            entry.role == 'manager' || entry.role == 'admin',
                      )
                      .map(
                        (entry) => CheckboxListTile(
                          value: selectedManagers.contains(entry.id),
                          title: Text(entry.displayName),
                          subtitle: Text(entry.username),
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  setLocalState(() {
                                    if (value == true) {
                                      selectedManagers.add(entry.id);
                                    } else {
                                      selectedManagers.remove(entry.id);
                                    }
                                  });
                                },
                        ),
                      ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final code = codeController.text.trim();
                      if (name.isEmpty) {
                        setLocalState(() {
                          errorText = 'اسم القسم مطلوب.';
                        });
                        return;
                      }
                      if (code.isEmpty) {
                        setLocalState(() {
                          errorText = 'كود القسم مطلوب.';
                        });
                        return;
                      }
                      setLocalState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        if (department == null) {
                          await overviewController.createDepartment(
                            name: name,
                            code: code,
                            description: descriptionController.text.trim(),
                          );
                        } else {
                          await overviewController.updateDepartment(
                            departmentId: department.id,
                            name: name,
                            code: code,
                            description: descriptionController.text.trim(),
                            managers: selectedManagers.toList(),
                          );
                        }
                        if (context.mounted) {
                          Navigator.pop(context, true);
                        }
                      } catch (error) {
                        setLocalState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (saved == true) {
      await overviewController.refresh();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            department == null
                ? 'تم إنشاء القسم بنجاح.'
                : 'تم تحديث القسم بنجاح.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      color: scaffoldBg,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: () => _showDepartmentDialog(context, ref),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('إضافة قسم'),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          if (departments.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.business_rounded,
                    size: 48,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'لا توجد أقسام مسجلة',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: departments.asMap().entries.map((entry) {
                  final isLast = entry.key == departments.length - 1;
                  final department = entry.value;

                  return Column(
                    children: [
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.business_rounded,
                            color: Colors.indigo,
                          ),
                        ),
                        title: Text(
                          department.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          '${department.code} • ${department.description} • عدد الأعضاء: ${department.membersCount}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded),
                          onSelected: (action) async {
                            if (action == 'edit') {
                              _showDepartmentDialog(
                                context,
                                ref,
                                department: department,
                              );
                            } else if (action == 'delete') {
                              try {
                                await ref
                                    .read(
                                      chatOverviewControllerProvider.notifier,
                                    )
                                    .deleteDepartment(department.id);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('تم حذف القسم')),
                                );
                              } catch (error) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(error.toString())),
                                );
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_rounded),
                                  SizedBox(width: 8),
                                  Text('تعديل'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'حذف',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isLast)
                        const Divider(height: 0.5, thickness: 0.5, indent: 56),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _BranchesTab extends ConsumerWidget {
  const _BranchesTab({required this.branches});

  final List<BranchSummary> branches;

  Future<void> _showBranchDialog(
    BuildContext context,
    WidgetRef ref, {
    BranchSummary? branch,
  }) async {
    final overviewController = ref.read(
      chatOverviewControllerProvider.notifier,
    );
    final nameController = TextEditingController(text: branch?.name ?? '');
    final codeController = TextEditingController(text: branch?.code ?? '');
    final descriptionController = TextEditingController(
      text: branch?.description ?? '',
    );
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(branch == null ? 'إضافة فرع' : 'تعديل فرع'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(labelText: 'اسم الفرع'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(labelText: 'كود الفرع'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(labelText: 'الوصف'),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final code = codeController.text.trim();
                      if (name.isEmpty) {
                        setLocalState(() => errorText = 'اسم الفرع مطلوب.');
                        return;
                      }
                      if (code.isEmpty) {
                        setLocalState(() => errorText = 'كود الفرع مطلوب.');
                        return;
                      }
                      setLocalState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        if (branch == null) {
                          await overviewController.createBranch(
                            name: name,
                            code: code,
                            description: descriptionController.text.trim(),
                          );
                        } else {
                          await overviewController.updateBranch(
                            branchId: branch.id,
                            name: name,
                            code: code,
                            description: descriptionController.text.trim(),
                          );
                        }
                        if (context.mounted) {
                          Navigator.pop(context, true);
                        }
                      } catch (error) {
                        setLocalState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (saved == true) {
      await overviewController.refresh();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            branch == null ? 'تم إنشاء الفرع بنجاح.' : 'تم تحديث الفرع بنجاح.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      color: scaffoldBg,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: () => _showBranchDialog(context, ref),
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('إضافة فرع'),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          if (branches.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    size: 48,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'لا توجد فروع مسجلة',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: branches.asMap().entries.map((entry) {
                  final isLast = entry.key == branches.length - 1;
                  final branch = entry.value;

                  return Column(
                    children: [
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Colors.purple,
                          ),
                        ),
                        title: Text(
                          branch.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          '${branch.code} • ${branch.description} • عدد الأعضاء: ${branch.membersCount}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded),
                          onSelected: (action) async {
                            if (action == 'edit') {
                              _showBranchDialog(context, ref, branch: branch);
                            } else if (action == 'delete') {
                              try {
                                await ref
                                    .read(
                                      chatOverviewControllerProvider.notifier,
                                    )
                                    .deleteBranch(branch.id);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('تم حذف الفرع')),
                                );
                              } catch (error) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(error.toString())),
                                );
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_rounded),
                                  SizedBox(width: 8),
                                  Text('تعديل'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'حذف',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isLast)
                        const Divider(height: 0.5, thickness: 0.5, indent: 56),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoomsTab extends ConsumerWidget {
  const _RoomsTab({required this.conversations, required this.users});

  final List<ChatConversation> conversations;
  final List<ChatDirectoryUser> users;

  Future<void> _showCreateBroadcastDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final overviewController = ref.read(
      chatOverviewControllerProvider.notifier,
    );
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final selectedPublishers = <String>{};
    final selectedAdmins = <String>{};
    var isSaving = false;
    String? errorText;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('إنشاء قناة بث'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(labelText: 'اسم القناة'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    enabled: !isSaving,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'الوصف'),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'المرسلون',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...users.map(
                    (user) => CheckboxListTile(
                      value: selectedPublishers.contains(user.id),
                      title: Text(user.displayName),
                      subtitle: Text(user.username),
                      onChanged: isSaving
                          ? null
                          : (value) {
                              setLocalState(() {
                                if (value == true) {
                                  selectedPublishers.add(user.id);
                                } else {
                                  selectedPublishers.remove(user.id);
                                  selectedAdmins.remove(user.id);
                                }
                              });
                            },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'مشرفو البث',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...users
                      .where((user) => selectedPublishers.contains(user.id))
                      .map(
                        (user) => CheckboxListTile(
                          value: selectedAdmins.contains(user.id),
                          title: Text(user.displayName),
                          subtitle: Text(user.username),
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  setLocalState(() {
                                    if (value == true) {
                                      selectedAdmins.add(user.id);
                                    } else {
                                      selectedAdmins.remove(user.id);
                                    }
                                  });
                                },
                        ),
                      ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'ملاحظة: المرسل يقدر يحدد الأقسام المستهدفة وقت إرسال كل رسالة.',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        setLocalState(() {
                          errorText = 'اسم القناة مطلوب.';
                        });
                        return;
                      }
                      setLocalState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await overviewController.createConversation(
                          type: 'broadcast',
                          name: name,
                          description: descriptionController.text.trim(),
                          memberIds: selectedPublishers.toList(),
                          adminIds: selectedAdmins.toList(),
                        );
                        if (context.mounted) {
                          Navigator.pop(context, true);
                        }
                      } catch (error) {
                        setLocalState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );

    if (created == true && context.mounted) {
      await overviewController.refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء قناة البث بنجاح')),
        );
      }
    }
  }

  Future<void> _showRoomDialog(
    BuildContext context,
    WidgetRef ref, {
    required ChatConversation conversation,
  }) async {
    final overviewController = ref.read(
      chatOverviewControllerProvider.notifier,
    );
    final nameController = TextEditingController(text: conversation.name);
    final descriptionController = TextEditingController(
      text: conversation.description,
    );
    final isBroadcast = conversation.type == 'broadcast';
    final selectedMembers = <String>{
      ...(isBroadcast
          ? conversation.broadcastPublisherIds
          : conversation.members.map((entry) => entry.id)),
    };
    final selectedAdmins = <String>{
      ...conversation.admins.map((entry) => entry.id),
    };
    var isArchived = conversation.isArchived;
    var isActive = conversation.isActive;
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('إدارة الغرفة'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(labelText: 'الاسم'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(labelText: 'الوصف'),
                  ),
                  SwitchListTile(
                    value: isArchived,
                    title: const Text('مؤرشفة'),
                    onChanged: isSaving
                        ? null
                        : (value) => setLocalState(() => isArchived = value),
                  ),
                  SwitchListTile(
                    value: isActive,
                    title: const Text('نشطة'),
                    onChanged: isSaving
                        ? null
                        : (value) => setLocalState(() => isActive = value),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      isBroadcast ? 'المرسلون' : 'الأعضاء',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...users.map(
                    (user) => CheckboxListTile(
                      value: selectedMembers.contains(user.id),
                      title: Text(user.displayName),
                      subtitle: Text(user.username),
                      onChanged: isSaving
                          ? null
                          : (value) {
                              setLocalState(() {
                                if (value == true) {
                                  selectedMembers.add(user.id);
                                } else {
                                  selectedMembers.remove(user.id);
                                  selectedAdmins.remove(user.id);
                                }
                              });
                            },
                    ),
                  ),
                  const Divider(height: 28),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      isBroadcast ? 'مشرفو البث' : 'المشرفون',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...users
                      .where((user) => selectedMembers.contains(user.id))
                      .map(
                        (user) => CheckboxListTile(
                          value: selectedAdmins.contains(user.id),
                          title: Text(user.displayName),
                          subtitle: Text(user.username),
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  setLocalState(() {
                                    if (value == true) {
                                      selectedAdmins.add(user.id);
                                    } else {
                                      selectedAdmins.remove(user.id);
                                    }
                                  });
                                },
                        ),
                      ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) {
                        setLocalState(() {
                          errorText = 'اسم الغرفة مطلوب.';
                        });
                        return;
                      }
                      setLocalState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await overviewController.updateManagedConversation(
                          conversationId: conversation.id,
                          name: nameController.text.trim(),
                          description: descriptionController.text.trim(),
                          memberIds: selectedMembers.toList(),
                          adminIds: selectedAdmins.toList(),
                          isArchived: isArchived,
                          isActive: isActive,
                        );
                        if (context.mounted) {
                          Navigator.pop(context, true);
                        }
                      } catch (error) {
                        setLocalState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && context.mounted) {
      await overviewController.refresh();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final canSendBroadcast =
        authUser?.role == 'admin' || authUser?.can('canSendBroadcast') == true;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      color: scaffoldBg,
      child: Column(
        children: [
          if (canSendBroadcast)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _showCreateBroadcastDialog(context, ref),
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('إنشاء قناة بث'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          Expanded(
            child: conversations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.forum_rounded,
                          size: 48,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد غرف قابلة للإدارة',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      canSendBroadcast ? 0 : 16,
                      16,
                      32,
                    ),
                    children: [
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: conversations.asMap().entries.map((entry) {
                            final isLast =
                                entry.key == conversations.length - 1;
                            final conversation = entry.value;

                            return Column(
                              children: [
                                ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.forum_rounded,
                                      color: Colors.teal,
                                    ),
                                  ),
                                  title: Text(
                                    conversation.displayTitle(''),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${conversation.type} • أعضاء: ${conversation.members.length} • مشرفون: ${conversation.admins.length}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded),
                                    onSelected: (action) async {
                                      if (action == 'settings') {
                                        _showRoomDialog(
                                          context,
                                          ref,
                                          conversation: conversation,
                                        );
                                      } else if (action == 'delete') {
                                        await ref
                                            .read(
                                              chatOverviewControllerProvider
                                                  .notifier,
                                            )
                                            .deleteManagedConversation(
                                              conversation.id,
                                            );
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'settings',
                                        child: Row(
                                          children: [
                                            Icon(Icons.tune_outlined),
                                            SizedBox(width: 8),
                                            Text('الإعدادات'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.delete_outline_rounded,
                                              color: Colors.red,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'حذف',
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isLast)
                                  const Divider(
                                    height: 0.5,
                                    thickness: 0.5,
                                    indent: 56,
                                  ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RolesTab extends ConsumerStatefulWidget {
  const _RolesTab({required this.roles});

  final List<ChatRole> roles;

  @override
  ConsumerState<_RolesTab> createState() => _RolesTabState();
}

class _RolesTabState extends ConsumerState<_RolesTab> {
  late Map<String, ChatPermissionSet> _draftPermissions;

  @override
  void initState() {
    super.initState();
    _draftPermissions = {
      for (final role in widget.roles) role.id: role.permissions,
    };
  }

  @override
  void didUpdateWidget(covariant _RolesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _draftPermissions = {
      for (final role in widget.roles) role.id: role.permissions,
    };
  }

  ChatPermissionSet _updatePermission(
    ChatPermissionSet source,
    String key,
    bool value,
  ) {
    return ChatPermissionSet(
      canCreateUsers: key == 'canCreateUsers' ? value : source.canCreateUsers,
      canCreateDepartments: key == 'canCreateDepartments'
          ? value
          : source.canCreateDepartments,
      canCreateRooms: key == 'canCreateRooms' ? value : source.canCreateRooms,
      canSendBroadcast: key == 'canSendBroadcast'
          ? value
          : source.canSendBroadcast,
      canDeleteMessages: key == 'canDeleteMessages'
          ? value
          : source.canDeleteMessages,
      canUploadFiles: key == 'canUploadFiles' ? value : source.canUploadFiles,
      canModerateDepartment: key == 'canModerateDepartment'
          ? value
          : source.canModerateDepartment,
      canViewDepartmentLogs: key == 'canViewDepartmentLogs'
          ? value
          : source.canViewDepartmentLogs,
      canManageAnnouncements: key == 'canManageAnnouncements'
          ? value
          : source.canManageAnnouncements,
      canManageFiles: key == 'canManageFiles' ? value : source.canManageFiles,
      canManageBranches: key == 'canManageBranches'
          ? value
          : source.canManageBranches,
      canManageRoles: key == 'canManageRoles' ? value : source.canManageRoles,
      canManageSystem: key == 'canManageSystem'
          ? value
          : source.canManageSystem,
      canManageUpdates: key == 'canManageUpdates'
          ? value
          : source.canManageUpdates,
      canManageBackups: key == 'canManageBackups'
          ? value
          : source.canManageBackups,
      canManageTickets: key == 'canManageTickets'
          ? value
          : source.canManageTickets,
      canViewPrinters: key == 'canViewPrinters'
          ? value
          : source.canViewPrinters,
      canManagePrinters: key == 'canManagePrinters'
          ? value
          : source.canManagePrinters,
      canSyncPrinters: key == 'canSyncPrinters'
          ? value
          : source.canSyncPrinters,
      canExportPrinterReports: key == 'canExportPrinterReports'
          ? value
          : source.canExportPrinterReports,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      color: scaffoldBg,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: widget.roles.asMap().entries.map((entry) {
                final isLast = entry.key == widget.roles.length - 1;
                final role = entry.value;
                final draft = _draftPermissions[role.id] ?? role.permissions;

                Widget permissionSwitch(
                  String key,
                  String label,
                  bool currentValue,
                ) {
                  return SwitchListTile(
                    title: Text(label, style: const TextStyle(fontSize: 14)),
                    value: currentValue,
                    onChanged: (value) {
                      setState(() {
                        _draftPermissions[role.id] = _updatePermission(
                          draft,
                          key,
                          value,
                        );
                      });
                    },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  );
                }

                return Column(
                  children: [
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: const Icon(
                          Icons.shield_outlined,
                          color: Colors.blueAccent,
                        ),
                        title: Text(
                          role.roleName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        children: [
                          Container(
                            color: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.1),
                            height: 1,
                          ),
                          permissionSwitch(
                            'canCreateUsers',
                            'إنشاء مستخدمين',
                            draft.canCreateUsers,
                          ),
                          permissionSwitch(
                            'canCreateDepartments',
                            'إنشاء أقسام',
                            draft.canCreateDepartments,
                          ),
                          permissionSwitch(
                            'canCreateRooms',
                            'إنشاء غرف',
                            draft.canCreateRooms,
                          ),
                          permissionSwitch(
                            'canSendBroadcast',
                            'إرسال إعلانات',
                            draft.canSendBroadcast,
                          ),
                          permissionSwitch(
                            'canDeleteMessages',
                            'حذف الرسائل',
                            draft.canDeleteMessages,
                          ),
                          permissionSwitch(
                            'canUploadFiles',
                            'رفع الملفات',
                            draft.canUploadFiles,
                          ),
                          permissionSwitch(
                            'canModerateDepartment',
                            'إدارة محادثات القسم',
                            draft.canModerateDepartment,
                          ),
                          permissionSwitch(
                            'canViewDepartmentLogs',
                            'عرض السجل الإداري',
                            draft.canViewDepartmentLogs,
                          ),
                          permissionSwitch(
                            'canManageAnnouncements',
                            'إدارة الإعلانات',
                            draft.canManageAnnouncements,
                          ),
                          permissionSwitch(
                            'canManageFiles',
                            'إدارة الملفات',
                            draft.canManageFiles,
                          ),
                          permissionSwitch(
                            'canManageBranches',
                            'إدارة الفروع',
                            draft.canManageBranches,
                          ),
                          permissionSwitch(
                            'canManageRoles',
                            'إدارة الصلاحيات',
                            draft.canManageRoles,
                          ),
                          permissionSwitch(
                            'canManageSystem',
                            'إعدادات الخادم',
                            draft.canManageSystem,
                          ),
                          permissionSwitch(
                            'canManageUpdates',
                            'إدارة التحديثات',
                            draft.canManageUpdates,
                          ),
                          permissionSwitch(
                            'canManageBackups',
                            'النسخ الاحتياطي',
                            draft.canManageBackups,
                          ),
                          permissionSwitch(
                            'canManageTickets',
                            'إدارة التذاكر',
                            draft.canManageTickets,
                          ),
                          permissionSwitch(
                            'canViewPrinters',
                            'عرض صفحة الطابعات',
                            draft.canViewPrinters,
                          ),
                          permissionSwitch(
                            'canManagePrinters',
                            'إدارة فروع الطابعات',
                            draft.canManagePrinters,
                          ),
                          permissionSwitch(
                            'canSyncPrinters',
                            'مزامنة الطابعات',
                            draft.canSyncPrinters,
                          ),
                          permissionSwitch(
                            'canExportPrinterReports',
                            'تصدير تقارير الطابعات',
                            draft.canExportPrinterReports,
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () async {
                                  await ref
                                      .read(
                                        chatOverviewControllerProvider.notifier,
                                      )
                                      .updateRole(
                                        roleId: role.id,
                                        permissions:
                                            _draftPermissions[role.id] ??
                                            role.permissions,
                                      );
                                },
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: const Text('حفظ الصلاحيات'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isLast) const Divider(height: 0.5, thickness: 0.5),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditLogsTab extends StatelessWidget {
  const _AuditLogsTab({required this.logsFuture});

  final Future<List<ChatAuditLog>> logsFuture;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      color: scaffoldBg,
      child: FutureBuilder<List<ChatAuditLog>>(
        future: logsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState != ConnectionState.done) {
            return const Center(child: AppLoadingIndicator(size: 28));
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final logs = snapshot.data ?? const <ChatAuditLog>[];
          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 48,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'لا توجد أحداث مسجلة',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: logs.asMap().entries.map((entry) {
                    final isLast = entry.key == logs.length - 1;
                    final log = entry.value;

                    return Column(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.bolt_rounded,
                            color: Colors.amber,
                          ),
                          title: Text(
                            log.action,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            '${log.entityType} • ${log.entityId}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: Text(
                            formatEgyptDateTime(log.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        if (!isLast)
                          const Divider(
                            height: 0.5,
                            thickness: 0.5,
                            indent: 56,
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SystemErrorsTab extends StatelessWidget {
  const _SystemErrorsTab({required this.errorsFuture});

  final Future<List<ChatSystemError>> errorsFuture;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      color: scaffoldBg,
      child: FutureBuilder<List<ChatSystemError>>(
        future: errorsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState != ConnectionState.done) {
            return const Center(child: AppLoadingIndicator(size: 28));
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final errors = snapshot.data ?? const <ChatSystemError>[];
          if (errors.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 48,
                    color: Colors.green.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'لا توجد أخطاء نظامية مسجلة',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: errors.asMap().entries.map((entry) {
                    final isLast = entry.key == errors.length - 1;
                    final entryItem = entry.value;

                    return Column(
                      children: [
                        Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            leading: const Icon(
                              Icons.error_outline_rounded,
                              color: Colors.red,
                            ),
                            title: Text(
                              '${entryItem.statusCode} • ${entryItem.errorName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              entryItem.path,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              16,
                            ),
                            children: [
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  entryItem.message,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '${entryItem.method} • ${formatEgyptDateTime(entryItem.createdAt)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (entryItem.stack != null &&
                                  entryItem.stack!.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: SelectableText(
                                    entryItem.stack!,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!isLast) const Divider(height: 0.5, thickness: 0.5),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _departmentName(List<DepartmentSummary> departments, String? id) {
  if (id == null) return 'بدون قسم';
  return departments
          .where((department) => department.id == id)
          .map((department) => department.name)
          .firstOrNull ??
      'بدون قسم';
}
