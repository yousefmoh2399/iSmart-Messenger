import 'dart:math' as math;
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
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
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

// ─── Apple Minimalist Admin Dialog Components ─────────────────────────────────

class _AppleAdminDialog extends StatelessWidget {
  const _AppleAdminDialog({
    required this.badgeIcon,
    required this.badgeColor,
    required this.title,
    this.subtitle,
    required this.content,
    required this.actions,
  });

  final IconData badgeIcon;
  final Color badgeColor;
  final String title;
  final String? subtitle;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Dialog(
      backgroundColor: bg,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Icon(badgeIcon, color: badgeColor, size: 24),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? const Color(0xFFF8FAFC)
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark
                                  ? Colors.white60
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 0.7,
              color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
            ),
            // Body Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: content,
              ),
            ),
            // Actions
            Divider(
              height: 1,
              thickness: 0.7,
              color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppleDangerDialog extends StatelessWidget {
  const _AppleDangerDialog({
    required this.title,
    required this.subtitle,
    required this.message,
    this.confirmLabel = 'تأكيد الحذف',
    required this.onConfirm,
  });

  final String title;
  final String subtitle;
  final String message;
  final String confirmLabel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Dialog(
      backgroundColor: bg,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFEF4444),
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? const Color(0xFFF8FAFC)
                      : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white24
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Text(
                        'إلغاء',
                        style: TextStyle(
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onConfirm,
                      icon: const Icon(Icons.delete_forever_rounded, size: 18),
                      label: Text(
                        confirmLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppleTextField extends StatelessWidget {
  const _AppleTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.enabled = true,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool enabled;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF8FAFC);
    final border = isDark ? Colors.white10 : const Color(0xFFE2E8F0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscureText,
          maxLines: maxLines,
          minLines: minLines,
                    autofocus: autofocus,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
            ),
            filled: true,
            fillColor: enabled
                ? fill
                : (isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
            prefixIcon: prefixIcon != null
                ? Icon(
                    prefixIcon,
                    size: 19,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  )
                : null,
            suffixIcon: suffix,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: border, width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: border, width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF0284C7),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AppleDropdown<T> extends StatelessWidget {
  const _AppleDropdown({
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
    this.prefixIcon,
    this.enabled = true,
  });

  final T value;
  final String label;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final IconData? prefixIcon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF8FAFC);
    final border = isDark ? Colors.white10 : const Color(0xFFE2E8F0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<T>(
          value: value,
          items: items,
          onChanged: enabled ? onChanged : null,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: enabled
                ? fill
                : (isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
            prefixIcon: prefixIcon != null
                ? Icon(
                    prefixIcon,
                    size: 19,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: border, width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: border, width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF0284C7),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AppleErrorBanner extends StatelessWidget {
  const _AppleErrorBanner({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFEF4444),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFFB91C1C),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
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
      builder: (context) => _AppleAdminDialog(
        badgeIcon: Icons.edit_note_rounded,
        badgeColor: const Color(0xFF0284C7),
        title: 'إعادة تسمية الملف',
        subtitle: 'تعديل اسم الملف المعروض في المستندات الإدارية',
        content: _AppleTextField(
          controller: controller,
          label: 'اسم الملف الجديد',
          hint: 'اكتب اسم الملف...',
          prefixIcon: Icons.description_outlined,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('إلغاء'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('حفظ التعديل'),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
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
          builder: (context) => _AppleDangerDialog(
            title: 'حذف الملف نهائياً',
            subtitle: 'تأكيد إزالة المستند من الخادم',
            message:
                'هل أنت متأكد من رغبتك في حذف "${document.fileName}"؟ لن يتمكن الموظفون من تنزيله بعد الحذف.',
            onConfirm: () => Navigator.pop(context, true),
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
    var obscure = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          final displayName =
              user.fullName.isEmpty ? user.username : user.fullName;
          return _AppleAdminDialog(
            badgeIcon: Icons.key_rounded,
            badgeColor: const Color(0xFFF59E0B),
            title: 'إعادة تعيين كلمة المرور',
            subtitle: 'تغيير رمز المرور لحساب: $displayName',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AppleTextField(
                  controller: passwordController,
                  enabled: !isSaving,
                  obscureText: obscure,
                  label: 'كلمة المرور الجديدة',
                  hint: 'أدخل 6 أحرف أو أرقام على الأقل',
                  prefixIcon: Icons.lock_outline_rounded,
                  suffix: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'توليد كلمة مرور عشوائية',
                        icon: const Icon(Icons.shuffle_rounded, size: 20),
                        onPressed: isSaving
                            ? null
                            : () {
                                final rnd = 100000 + math.Random().nextInt(900000);
                                setLocalState(() {
                                  passwordController.text = '$rnd';
                                });
                              },
                      ),
                      IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                        onPressed: () => setLocalState(() => obscure = !obscure),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'سيتم إلزام المستخدم باستخدام كلمة المرور هذه لتسجيل الدخول القادم.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white54
                        : const Color(0xFF64748B),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  _AppleErrorBanner(error: errorText!),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text('إلغاء'),
              ),
              const SizedBox(width: 8),
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
                icon: isSaving ? null : const Icon(Icons.check_rounded, size: 18),
                label: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: ButtonLoadingIndicator(),
                      )
                    : const Text('تعيين كلمة المرور'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteUser(
    BuildContext context,
    WidgetRef ref,
    ManagedUser user,
  ) async {
    final displayName = user.fullName.isEmpty ? user.username : user.fullName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _AppleDangerDialog(
        title: 'حذف حساب المستخدم',
        subtitle: 'إزالة المستخدم $displayName من النظام',
        message:
            'هل أنت متأكد من حذف الحساب نهائياً؟ سيتم إلغاء وصوله وإزالة المحادثات المرتبطة به.',
        onConfirm: () => Navigator.pop(context, true),
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
    final displayName = user.fullName.isEmpty ? user.username : user.fullName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _AppleDangerDialog(
        title: 'إنهاء جميع الجلسات',
        subtitle: 'تسجيل خروج إجباري لـ $displayName',
        confirmLabel: 'تسجيل الخروج',
        message:
            'سيتم قطع الاتصال الفوري وإبطال جميع جلسات الدخول للمستخدم عبر كافة الأجهزة والهواتف والكمبيوتر.',
        onConfirm: () => Navigator.pop(context, true),
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
    var obscurePassword = true;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => _AppleAdminDialog(
          badgeIcon: user == null ? Icons.person_add_rounded : Icons.manage_accounts_rounded,
          badgeColor: const Color(0xFF0284C7),
          title: user == null ? 'إضافة مستخدم جديد' : 'تعديل بيانات المستخدم',
          subtitle: user == null
              ? 'إنشاء حساب موظف جديد وتعيين الصلاحيات والقسم'
              : 'تحديث بيانات الحساب أو كلمة المرور أو القسم',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AppleTextField(
                controller: usernameController,
                enabled: !isSaving,
                label: 'اسم المستخدم (Username)',
                hint: 'مثال: ahmed_ali',
                prefixIcon: Icons.alternate_email_rounded,
              ),
              const SizedBox(height: 12),
              _AppleTextField(
                controller: fullNameController,
                enabled: !isSaving,
                label: 'الاسم الكامل الثلاثي أو الثنائي',
                hint: 'مثال: أحمد علي حسن',
                prefixIcon: Icons.badge_outlined,
              ),
              const SizedBox(height: 12),
              _AppleDropdown<String>(
                value: role,
                label: 'صلاحيات الدور (Role)',
                prefixIcon: Icons.shield_outlined,
                enabled: !isSaving,
                items: const [
                  DropdownMenuItem(value: 'user', child: Text('مستخدم عادي (User)')),
                  DropdownMenuItem(value: 'manager', child: Text('مدير قسم (Manager)')),
                  DropdownMenuItem(value: 'admin', child: Text('مسؤول نظام (Admin)')),
                ],
                onChanged: (val) => setLocalState(() => role = val ?? role),
              ),
              const SizedBox(height: 12),
              _AppleDropdown<String?>(
                value: departmentId,
                label: 'القسم التابع له',
                prefixIcon: Icons.business_outlined,
                enabled: !isSaving,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('بدون قسم'),
                  ),
                  ...departments.map(
                    (dept) => DropdownMenuItem<String?>(
                      value: dept.id,
                      child: Text(dept.name),
                    ),
                  ),
                ],
                onChanged: (val) => setLocalState(() => departmentId = val),
              ),
              const SizedBox(height: 12),
              _AppleDropdown<String?>(
                value: branchId,
                label: 'الفرع التابع له',
                prefixIcon: Icons.storefront_outlined,
                enabled: !isSaving,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('بدون فرع'),
                  ),
                  ...branches.map(
                    (br) => DropdownMenuItem<String?>(
                      value: br.id,
                      child: Text(br.name),
                    ),
                  ),
                ],
                onChanged: (val) => setLocalState(() => branchId = val),
              ),
              const SizedBox(height: 12),
              _AppleTextField(
                controller: passwordController,
                enabled: !isSaving,
                obscureText: obscurePassword,
                label: user == null
                    ? 'كلمة المرور'
                    : 'كلمة مرور جديدة (اختياري)',
                hint: user == null
                    ? 'اتركها فارغة لاستخدام 123456 أو أدخل 6 أحرف'
                    : 'اتركها فارغة للإبقاء على كلمة المرور الحالية',
                prefixIcon: Icons.lock_outline_rounded,
                suffix: IconButton(
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () =>
                      setLocalState(() => obscurePassword = !obscurePassword),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 14),
                _AppleErrorBanner(error: errorText!),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: const Text('إلغاء'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
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
              icon: isSaving ? null : const Icon(Icons.check_rounded, size: 18),
              label: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : Text(user == null ? 'إنشاء الحساب' : 'حفظ التعديلات'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
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
        builder: (context, setLocalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return _AppleAdminDialog(
            badgeIcon: Icons.campaign_rounded,
            badgeColor: const Color(0xFFEA580C),
            title: announcement == null ? 'إضافة إعلان جديد' : 'تعديل الإعلان',
            subtitle: announcement == null
                ? 'نشر إشعار إداري لجميع مستخدمي المنظومة'
                : 'تحديث تفاصيل وبيانات الإعلان المنشور',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AppleTextField(
                  controller: titleController,
                  enabled: !isSaving,
                  label: 'عنوان الإعلان',
                  hint: 'أدخل عنواناً موجزاً وواضحاً...',
                  prefixIcon: Icons.title_rounded,
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: messageController,
                  enabled: !isSaving,
                  label: 'نص الإعلان والتفاصيل',
                  hint: 'اكتب نص الإعلان والتعليمات المطلوب تعميمها...',
                  prefixIcon: Icons.article_outlined,
                  minLines: 3,
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                _AppleDropdown<String>(
                  value: tone,
                  label: 'نوع الإعلان وأهميته',
                  prefixIcon: Icons.palette_outlined,
                  enabled: !isSaving,
                  items: const [
                    DropdownMenuItem(value: 'info', child: Text('معلومة عامة (أزرق)')),
                    DropdownMenuItem(value: 'success', child: Text('إشعار نجاح (أخضر)')),
                    DropdownMenuItem(value: 'warning', child: Text('تنبيه هام (برتقالي)')),
                    DropdownMenuItem(value: 'critical', child: Text('عاجل وضروري (أحمر)')),
                  ],
                  onChanged: (val) => setLocalState(() => tone = val ?? tone),
                ),
                const SizedBox(height: 14),
                // Apple-style Card with Switches
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: isPinned,
                        onChanged: isSaving
                            ? null
                            : (val) => setLocalState(() => isPinned = val),
                        title: const Text(
                          'تثبيت في البداية',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'إبقاء الإعلان مثبتاً في أعلى قائمة إعلانات الموظفين',
                          style: TextStyle(fontSize: 11.5),
                        ),
                        secondary: const Icon(Icons.push_pin_outlined, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      ),
                      Divider(
                        height: 1,
                        thickness: 0.6,
                        indent: 48,
                        color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                      ),
                      SwitchListTile(
                        value: isActive,
                        onChanged: isSaving
                            ? null
                            : (val) => setLocalState(() => isActive = val),
                        title: const Text(
                          'إعلان نشط',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'ظهور الإعلان فوراً للموظفين في الشاشات',
                          style: TextStyle(fontSize: 11.5),
                        ),
                        secondary: const Icon(Icons.visibility_outlined, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      ),
                    ],
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 14),
                  _AppleErrorBanner(error: errorText!),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text('إلغاء'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
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
                icon: isSaving ? null : const Icon(Icons.campaign_rounded, size: 18),
                label: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: ButtonLoadingIndicator(),
                      )
                    : Text(announcement == null ? 'نشر الإعلان' : 'حفظ التعديلات'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEA580C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
              ),
            ],
          );
        },
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
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => _AppleDangerDialog(
                                          title: 'حذف الإعلان',
                                          subtitle: 'تأكيد إزالة الإعلان من النظام',
                                          message:
                                              'هل أنت متأكد من حذف إعلان "${announcement.title}" نهائياً؟',
                                          onConfirm: () => Navigator.pop(ctx, true),
                                        ),
                                      );
                                      if (confirmed != true || !context.mounted) return;
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
        builder: (context, setLocalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final candidates = users
              .where(
                (entry) =>
                    entry.role == 'manager' || entry.role == 'admin',
              )
              .toList();

          return _AppleAdminDialog(
            badgeIcon: Icons.corporate_fare_rounded,
            badgeColor: const Color(0xFF4F46E5),
            title: department == null ? 'إضافة قسم جديد' : 'تعديل بيانات القسم',
            subtitle: department == null
                ? 'إنشاء قسم جديد في الهيكل الإداري وتحديد المديرين'
                : 'تحديث اسم القسم أو كوده أو المديرين المسؤولين',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AppleTextField(
                  controller: nameController,
                  enabled: !isSaving,
                  label: 'اسم القسم',
                  hint: 'مثال: المبيعات، الحسابات، الدعم الفني',
                  prefixIcon: Icons.business_center_rounded,
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: codeController,
                  enabled: !isSaving,
                  label: 'كود القسم',
                  hint: 'مثال: SAL, ACC, TECH',
                  prefixIcon: Icons.tag_rounded,
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: descriptionController,
                  enabled: !isSaving,
                  label: 'الوصف أو الملاحظات (اختياري)',
                  hint: 'وصف مهام واختصاصات القسم',
                  prefixIcon: Icons.notes_rounded,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.supervisor_account_rounded,
                      size: 18,
                      color: Color(0xFF4F46E5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'المديرون المسؤولون عن القسم',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFFF1F5F9)
                            : const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                      width: 0.8,
                    ),
                  ),
                  child: candidates.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              'لا يوجد مستخدمون برتبة مدير أو أدمن بعد',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: candidates.length,
                          separatorBuilder: (ctx, idx) => Divider(
                            height: 1,
                            thickness: 0.6,
                            indent: 52,
                            color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                          ),
                          itemBuilder: (ctx, idx) {
                            final entry = candidates[idx];
                            final isSelected = selectedManagers.contains(entry.id);
                            return CheckboxListTile(
                              value: isSelected,
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                              secondary: CircleAvatar(
                                radius: 16,
                                backgroundColor: const Color(0xFF4F46E5)
                                    .withValues(alpha: isSelected ? 0.2 : 0.1),
                                child: Text(
                                  entry.displayName.isNotEmpty
                                      ? entry.displayName.substring(0, 1).toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF4F46E5),
                                  ),
                                ),
                              ),
                              title: Text(
                                entry.displayName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '@${entry.username} (${entry.role})',
                                style: const TextStyle(fontSize: 11),
                              ),
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
                            );
                          },
                        ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 14),
                  _AppleErrorBanner(error: errorText!),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text('إلغاء'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
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
                icon: isSaving ? null : const Icon(Icons.check_rounded, size: 18),
                label: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: ButtonLoadingIndicator(),
                      )
                    : Text(department == null ? 'إنشاء القسم' : 'حفظ التعديلات'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
              ),
            ],
          );
        },
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
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => _AppleDangerDialog(
                                  title: 'حذف القسم',
                                  subtitle: 'تأكيد إزالة القسم من الهيكل الإداري',
                                  message:
                                      'هل أنت متأكد من حذف قسم "${department.name}" (${department.code})؟ لن يتم حذف الموظفين لكنهم سيصبحون بدون قسم.',
                                  onConfirm: () => Navigator.pop(ctx, true),
                                ),
                              );
                              if (confirmed != true || !context.mounted) return;
                              try {
                                await ref
                                    .read(
                                      chatOverviewControllerProvider.notifier,
                                    )
                                    .deleteDepartment(department.id);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم حذف القسم بنجاح'),
                                  ),
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
        builder: (context, setLocalState) => _AppleAdminDialog(
          badgeIcon: Icons.storefront_rounded,
          badgeColor: const Color(0xFF9333EA),
          title: branch == null ? 'إضافة فرع جديد' : 'تعديل بيانات الفرع',
          subtitle: branch == null
              ? 'تسجيل موقع أو فرع عمل جديد في النظام'
              : 'تعديل بيانات الفرع والكود والرمز الخاص به',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AppleTextField(
                controller: nameController,
                enabled: !isSaving,
                label: 'اسم الفرع',
                hint: 'مثال: فرع القاهرة، فرع الإسكندرية',
                prefixIcon: Icons.place_rounded,
              ),
              const SizedBox(height: 12),
              _AppleTextField(
                controller: codeController,
                enabled: !isSaving,
                label: 'كود الفرع',
                hint: 'مثال: CAI-01, ALX-02',
                prefixIcon: Icons.pin_drop_rounded,
              ),
              const SizedBox(height: 12),
              _AppleTextField(
                controller: descriptionController,
                enabled: !isSaving,
                label: 'العنوان أو الوصف (اختياري)',
                hint: 'تفاصيل العنوان ورقم الاتصال بالفرع',
                prefixIcon: Icons.notes_rounded,
                maxLines: 2,
              ),
              if (errorText != null) ...[
                const SizedBox(height: 14),
                _AppleErrorBanner(error: errorText!),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: const Text('إلغاء'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
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
              icon: isSaving ? null : const Icon(Icons.check_rounded, size: 18),
              label: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : Text(branch == null ? 'إنشاء الفرع' : 'حفظ التعديلات'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF9333EA),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
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
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => _AppleDangerDialog(
                                  title: 'حذف الفرع',
                                  subtitle: 'تأكيد إزالة الفرع من النظام',
                                  message:
                                      'هل أنت متأكد من حذف فرع "${branch.name}" (${branch.code})؟ لن يتم حذف الأجهزة أو الموظفين التابعين له.',
                                  onConfirm: () => Navigator.pop(ctx, true),
                                ),
                              );
                              if (confirmed != true || !context.mounted) return;
                              try {
                                await ref
                                    .read(
                                      chatOverviewControllerProvider.notifier,
                                    )
                                    .deleteBranch(branch.id);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم حذف الفرع بنجاح'),
                                  ),
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
