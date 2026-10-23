import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
                  child: Material(
                    color: Colors.transparent,
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
                  title: 'الغرف والقنوات',
                  icon: Icons.forum_rounded,
                  color: Colors.teal,
                  screen: _RoomsTab(
                    conversations: overview.manageableConversations,
                    users: overview.users,
                    departments: overview.departments,
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
                  title: 'الصلاحيات والأدوار (Roles)',
                  icon: Icons.admin_panel_settings_rounded,
                  color: Colors.red,
                  screen: _RolesTab(roles: overview.roles),
                ),
              ]),
              const SizedBox(height: 8),
              buildSection('النظام', [
                buildItem(
                  title: 'إعدادات الخادم والشبكة',
                  icon: Icons.dns_rounded,
                  color: const Color(0xFF007AFF),
                  screen: const _MobileServerSettingsTab(),
                ),
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
    this.onChanged,
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
  final ValueChanged<String>? onChanged;

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
          onChanged: onChanged,
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
                        child: Material(
                          color: Colors.transparent,
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
                child: Material(
                  color: Colors.transparent,
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

// ─── Redesigned Apple Minimalist Admin Tabs (Mobile) ─────────────────────────

class _AnnouncementsTab extends ConsumerStatefulWidget {
  const _AnnouncementsTab({required this.announcementsState});

  final AsyncValue<List<AdminAnnouncement>> announcementsState;

  @override
  ConsumerState<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends ConsumerState<_AnnouncementsTab> {
  String _searchQuery = '';
  String _toneFilter = 'all';

  Color _toneColor(String tone) {
    return switch (tone) {
      'success' => const Color(0xFF16A34A),
      'warning' => const Color(0xFFD97706),
      'critical' => const Color(0xFFDC2626),
      _ => const Color(0xFF007AFF),
    };
  }

  IconData _safeToneIcon(String tone) {
    return switch (tone) {
      'success' => Icons.check_circle_rounded,
      'warning' => Icons.warning_amber_rounded,
      'critical' => Icons.error_rounded,
      _ => Icons.info_rounded,
    };
  }

  String _toneLabel(String tone) {
    return switch (tone) {
      'success' => 'نجاح / تحديث',
      'warning' => 'تنبيه هام',
      'critical' => 'عاجل وحرج',
      _ => 'معلومة عامة',
    };
  }

  Future<void> _showAnnouncementDialog(
    BuildContext context, {
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
          final activeToneColor = _toneColor(tone);
          final previewTitle = titleController.text.trim().isEmpty
              ? 'عنوان الإعلان سيظهر هنا...'
              : titleController.text.trim();
          final previewMsg = messageController.text.trim().isEmpty
              ? 'معاينة حية لنص الإعلان كما سيظهر للموظفين في أعلى الشاشة...'
              : messageController.text.trim();

          return _AppleAdminDialog(
            badgeIcon: Icons.campaign_rounded,
            badgeColor: activeToneColor,
            title: announcement == null ? 'إضافة إعلان جديد' : 'تعديل الإعلان',
            subtitle: announcement == null
                ? 'نشر تعميم إداري فوري لجميع مستخدمي المنظومة'
                : 'تحديث بيانات الإعلان المنشور وإعدادات ظهوره',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Live Preview Banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        activeToneColor.withValues(alpha: isDark ? 0.22 : 0.12),
                        activeToneColor.withValues(alpha: isDark ? 0.08 : 0.04),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: activeToneColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: activeToneColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              _safeToneIcon(tone),
                              size: 16,
                              color: activeToneColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              previewTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          if (isPinned)
                            Icon(
                              Icons.push_pin_rounded,
                              size: 15,
                              color: activeToneColor,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        previewMsg,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'نبرة الإعلان وأولويته',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.6,
                  children: [
                    for (final item in const [
                      ('info', 'معلومة عامة', Icons.info_rounded),
                      ('success', 'نجاح / تحديث', Icons.check_circle_rounded),
                      ('warning', 'تنبيه هام', Icons.warning_amber_rounded),
                      ('critical', 'عاجل وحرج', Icons.error_rounded),
                    ])
                      Builder(
                        builder: (context) {
                          final selected = tone == item.$1;
                          final color = _toneColor(item.$1);
                          return InkWell(
                            onTap: isSaving
                                ? null
                                : () => setLocalState(() => tone = item.$1),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? color.withValues(
                                        alpha: isDark ? 0.22 : 0.12,
                                      )
                                    : (isDark
                                          ? Colors.white.withValues(alpha: 0.04)
                                          : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? color
                                      : (isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.08,
                                              )
                                            : const Color(0xFFE2E8F0)),
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(item.$3, size: 18, color: color),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      item.$2,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: selected
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: selected
                                            ? color
                                            : (isDark
                                                  ? Colors.white70
                                                  : const Color(0xFF334155)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _AppleTextField(
                  controller: titleController,
                  enabled: !isSaving,
                  label: 'عنوان الإعلان',
                  hint: 'أدخل عنواناً موجزاً وواضحاً...',
                  prefixIcon: Icons.title_rounded,
                  onChanged: (_) => setLocalState(() {}),
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
                  onChanged: (_) => setLocalState(() {}),
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        value: isPinned,
                        onChanged: isSaving
                            ? null
                            : (value) =>
                                  setLocalState(() => isPinned = value),
                        secondary: const Icon(
                          Icons.push_pin_rounded,
                          color: Color(0xFFEA580C),
                        ),
                        title: const Text(
                          'تثبيت في أعلى التطبيق',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: const Text(
                          'يضمن ظهور الإعلان كشريط بارز دائماً',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFE2E8F0),
                      ),
                      SwitchListTile.adaptive(
                        value: isActive,
                        onChanged: isSaving
                            ? null
                            : (value) =>
                                  setLocalState(() => isActive = value),
                        secondary: const Icon(
                          Icons.visibility_rounded,
                          color: Color(0xFF16A34A),
                        ),
                        title: const Text(
                          'تفعيل ونشر الإعلان فوراً',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: const Text(
                          'إظهار الإعلان لجميع المستخدمين النشطين',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
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
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: activeToneColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        final title = titleController.text.trim();
                        final message = messageController.text.trim();
                        if (title.isEmpty || message.isEmpty) {
                          setLocalState(() {
                            errorText = 'يرجى إدخال عنوان ونص الإعلان.';
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
                          await adminAnnouncementsController.refresh();
                          await announcementsController.refresh();
                          if (context.mounted) {
                            Navigator.of(context).pop(true);
                          }
                        } catch (error) {
                          setLocalState(() {
                            isSaving = false;
                            errorText = error.toString();
                          });
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ButtonLoadingIndicator(),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  announcement == null ? 'نشر الإعلان' : 'حفظ التغييرات',
                ),
              ),
            ],
          );
        },
      ),
    );
    titleController.dispose();
    messageController.dispose();
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            announcement == null
                ? 'تم نشر الإعلان بنجاح'
                : 'تم تحديث الإعلان بنجاح',
          ),
        ),
      );
    }
  }

  Future<void> _deleteAnnouncement(
    BuildContext context,
    AdminAnnouncement item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _AppleDangerDialog(
        title: 'حذف الإعلان',
        subtitle: 'إزالة الإعلان من شريط التنبيهات الفوري',
        message: 'هل أنت متأكد من حذف الإعلان "${item.title}" نهائياً؟',
        confirmLabel: 'حذف الإعلان',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(announcementRepositoryProvider)
        .deleteAnnouncement(item.id);
    await ref.read(adminAnnouncementsControllerProvider.notifier).refresh();
    await ref.read(announcementsControllerProvider.notifier).refresh();
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
      child: widget.announcementsState.when(
        loading: () => const Center(child: AppLoadingIndicator(size: 28)),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (items) {
          final activeCount = items.where((e) => e.isActive).length;
          final pinnedCount = items.where((e) => e.isPinned).length;
          final filtered = items.where((item) {
            if (_toneFilter != 'all' && item.tone != _toneFilter) return false;
            if (_searchQuery.trim().isNotEmpty) {
              final q = _searchQuery.trim().toLowerCase();
              return item.title.toLowerCase().contains(q) ||
                  item.message.toLowerCase().contains(q);
            }
            return true;
          }).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFEA580C,
                            ).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                            Icons.campaign_rounded,
                            color: Color(0xFFEA580C),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'التعميمات والإعلانات الإدارية',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'إرسال تنبيهات فورية ومثبتة لجميع الموظفين',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () => _showAnnouncementDialog(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFEA580C),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('إعلان جديد'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _MobileBentoStatChip(
                          label: 'الإجمالي',
                          value: '${items.length}',
                          color: const Color(0xFF007AFF),
                        ),
                        const SizedBox(width: 8),
                        _MobileBentoStatChip(
                          label: 'النشطة',
                          value: '$activeCount',
                          color: const Color(0xFF16A34A),
                        ),
                        const SizedBox(width: 8),
                        _MobileBentoStatChip(
                          label: 'المثبتة',
                          value: '$pinnedCount',
                          color: const Color(0xFFEA580C),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'بحث في عناوين ونصوص الإعلانات...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: cardBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final chip in const [
                      ('all', 'الكل'),
                      ('info', 'معلومة'),
                      ('success', 'نجاح'),
                      ('warning', 'تنبيه'),
                      ('critical', 'عاجل'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text(chip.$2),
                          selected: _toneFilter == chip.$1,
                          onSelected: (_) =>
                              setState(() => _toneFilter = chip.$1),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.campaign_outlined,
                        size: 44,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'لا توجد إعلانات مطابقة حالياً',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                )
              else
                ...filtered.map((item) {
                  final color = _toneColor(item.tone);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: item.isPinned
                            ? color.withValues(alpha: 0.45)
                            : (isDark
                                  ? Colors.white.withValues(alpha: 0.07)
                                  : Colors.black.withValues(alpha: 0.05)),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  _safeToneIcon(item.tone),
                                  size: 18,
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        _MobileBadgePill(
                                          label: _toneLabel(item.tone),
                                          color: color,
                                        ),
                                        _MobileBadgePill(
                                          label: item.isActive
                                              ? 'نشط'
                                              : 'مخفي',
                                          color: item.isActive
                                              ? const Color(0xFF16A34A)
                                              : Colors.grey,
                                        ),
                                        if (item.isPinned)
                                          const _MobileBadgePill(
                                            label: 'مثبت 📌',
                                            color: Color(0xFFEA580C),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => _showAnnouncementDialog(
                                  context,
                                  announcement: item,
                                ),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                tooltip: 'تعديل',
                              ),
                              IconButton(
                                onPressed: () =>
                                    _deleteAnnouncement(context, item),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 20,
                                  color: Colors.redAccent,
                                ),
                                tooltip: 'حذف',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            item.message,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : const Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _DepartmentsTab extends ConsumerStatefulWidget {
  const _DepartmentsTab({required this.departments, required this.users});

  final List<DepartmentSummary> departments;
  final List<ChatDirectoryUser> users;

  @override
  ConsumerState<_DepartmentsTab> createState() => _DepartmentsTabState();
}

class _DepartmentsTabState extends ConsumerState<_DepartmentsTab> {
  String _searchQuery = '';

  Future<void> _showDepartmentDialog({DepartmentSummary? department}) async {
    final nameController = TextEditingController(text: department?.name ?? '');
    final codeController = TextEditingController(text: department?.code ?? '');
    final descriptionController = TextEditingController(
      text: department?.description ?? '',
    );
    var selectedManagers = <String>{...(department?.managers ?? const [])};
    var managerSearch = '';
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
          final filteredUsers = widget.users.where((u) {
            if (managerSearch.trim().isEmpty) return true;
            final q = managerSearch.trim().toLowerCase();
            return u.displayName.toLowerCase().contains(q) ||
                u.username.toLowerCase().contains(q);
          }).toList();

          return _AppleAdminDialog(
            badgeIcon: department == null
                ? Icons.add_business_rounded
                : Icons.business_rounded,
            badgeColor: const Color(0xFF4F46E5),
            title: department == null
                ? 'إضافة قسم إداري جديد'
                : 'تعديل بيانات القسم',
            subtitle: department == null
                ? 'إنشاء قسم تنظيمي جديد مع غرفة محادثة تلقائية'
                : 'تحديث اسم القسم، الكود التعريفي، ومديري القسم',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AppleTextField(
                  controller: nameController,
                  enabled: !isSaving,
                  label: 'اسم القسم',
                  hint: 'مثال: الموارد البشرية، تقنية المعلومات...',
                  prefixIcon: Icons.business_rounded,
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: codeController,
                  enabled: !isSaving,
                  label: 'كود القسم المختصر',
                  hint: 'مثال: HR, IT, FIN',
                  prefixIcon: Icons.tag_rounded,
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: descriptionController,
                  enabled: !isSaving,
                  label: 'وصف ومهام القسم',
                  hint: 'اختياري: نبذة مختصرة عن اختصاصات القسم...',
                  prefixIcon: Icons.notes_rounded,
                  minLines: 2,
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.manage_accounts_rounded,
                      size: 16,
                      color: Color(0xFF4F46E5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'مديرو القسم (${selectedManagers.length})',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (v) => setDialogState(() => managerSearch = v),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن موظف لتعيينه كمدير قسم...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 190),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: filteredUsers.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              'لا يوجد موظفون مطابقون للبحث',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        )
                      : Material(
                          color: Colors.transparent,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredUsers.length,
                            itemBuilder: (context, idx) {
                              final user = filteredUsers[idx];
                              final isSelected = selectedManagers.contains(
                                user.id,
                              );
                              return CheckboxListTile(
                                dense: true,
                                value: isSelected,
                                onChanged: isSaving
                                    ? null
                                    : (checked) {
                                        setDialogState(() {
                                          if (checked == true) {
                                            selectedManagers.add(user.id);
                                          } else {
                                            selectedManagers.remove(user.id);
                                          }
                                        });
                                      },
                                title: Text(
                                  user.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  '@${user.username} • ${user.role}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              );
                            },
                          ),
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
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        final name = nameController.text.trim();
                        final code = codeController.text.trim();
                        final description = descriptionController.text.trim();
                        if (name.isEmpty || code.isEmpty) {
                          setDialogState(() {
                            errorText = 'اسم القسم والكود المختصر مطلوبان.';
                          });
                          return;
                        }
                        setDialogState(() {
                          isSaving = true;
                          errorText = null;
                        });
                        try {
                          final notifier = ref.read(
                            chatOverviewControllerProvider.notifier,
                          );
                          if (department == null) {
                            await notifier.createDepartment(
                              name: name,
                              code: code,
                              description: description,
                              managers: selectedManagers.toList(),
                            );
                          } else {
                            await notifier.updateDepartment(
                              departmentId: department.id,
                              name: name,
                              code: code,
                              description: description,
                              managers: selectedManagers.toList(),
                            );
                          }
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        } catch (error) {
                          setDialogState(() {
                            isSaving = false;
                            errorText = error.toString();
                          });
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ButtonLoadingIndicator(),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(department == null ? 'إنشاء القسم' : 'حفظ التعديلات'),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
    codeController.dispose();
    descriptionController.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            department == null
                ? 'تم إنشاء القسم بنجاح'
                : 'تم تحديث بيانات القسم بنجاح',
          ),
        ),
      );
    }
  }

  Future<void> _deleteDepartment(DepartmentSummary department) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _AppleDangerDialog(
        title: 'حذف القسم الإداري',
        subtitle: 'إزالة القسم والغرفة الافتراضية المرتبطة به',
        message:
            'هل أنت متأكد من حذف قسم "${department.name}"؟ سيتم أرشفة الغرفة المرتبطة به.',
        confirmLabel: 'حذف القسم',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(chatOverviewControllerProvider.notifier)
        .deleteDepartment(department.id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final usersById = {for (final u in widget.users) u.id: u};

    final filtered = widget.departments.where((dept) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      return dept.name.toLowerCase().contains(q) ||
          dept.code.toLowerCase().contains(q) ||
          dept.description.toLowerCase().contains(q);
    }).toList();

    final totalMembers = widget.departments.fold<int>(
      0,
      (sum, d) => sum + d.membersCount,
    );

    return Container(
      color: scaffoldBg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.business_rounded,
                        color: Color(0xFF4F46E5),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الأقسام والهيكل التنظيمي',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'إدارة الأقسام، الأكواد التعريفية، ومديري الأقسام',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showDepartmentDialog(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('إضافة قسم'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _MobileBentoStatChip(
                      label: 'إجمالي الأقسام',
                      value: '${widget.departments.length}',
                      color: const Color(0xFF4F46E5),
                    ),
                    const SizedBox(width: 8),
                    _MobileBentoStatChip(
                      label: 'إجمالي الأعضاء',
                      value: '$totalMembers',
                      color: const Color(0xFF007AFF),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'بحث باسم القسم أو الكود...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: cardBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: Text(
                  'لا توجد أقسام مطابقة للبحث',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            )
          else
            ...filtered.map((dept) {
              final managerNames = dept.managers
                  .map((id) => usersById[id]?.displayName ?? id)
                  .toList();
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF4F46E5,
                            ).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            dept.code,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                              color: Color(0xFF4F46E5),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            dept.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              _showDepartmentDialog(department: dept),
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'تعديل القسم',
                        ),
                        IconButton(
                          onPressed: () => _deleteDepartment(dept),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'حذف القسم',
                        ),
                      ],
                    ),
                    if (dept.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        dept.description,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF475569),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _MobileBadgePill(
                          label: '${dept.membersCount} عضو',
                          color: const Color(0xFF007AFF),
                        ),
                        _MobileBadgePill(
                          label: managerNames.isEmpty
                              ? 'بدون مدير معين'
                              : 'المديرون: ${managerNames.join('، ')}',
                          color: const Color(0xFF16A34A),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _BranchesTab extends ConsumerStatefulWidget {
  const _BranchesTab({required this.branches});

  final List<BranchSummary> branches;

  @override
  ConsumerState<_BranchesTab> createState() => _BranchesTabState();
}

class _BranchesTabState extends ConsumerState<_BranchesTab> {
  String _searchQuery = '';

  Future<void> _showBranchDialog({BranchSummary? branch}) async {
    final nameController = TextEditingController(text: branch?.name ?? '');
    final codeController = TextEditingController(text: branch?.code ?? '');
    final descriptionController = TextEditingController(
      text: branch?.description ?? '',
    );
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
          final previewName = nameController.text.trim().isEmpty
              ? 'اسم الفرع'
              : nameController.text.trim();
          final previewCode = codeController.text.trim().isEmpty
              ? 'BR-01'
              : codeController.text.trim().toUpperCase();

          return _AppleAdminDialog(
            badgeIcon: branch == null
                ? Icons.add_location_alt_rounded
                : Icons.location_on_rounded,
            badgeColor: const Color(0xFF9333EA),
            title: branch == null ? 'إضافة فرع جديد' : 'تعديل بيانات الفرع',
            subtitle: branch == null
                ? 'تسجيل موقع جغرافي أو فرع تشغيلي جديد في المنظومة'
                : 'تحديث بيانات الفرع والكود التعريفي الخاص به',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFFAF5FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF9333EA).withValues(alpha: 0.28),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9333EA),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          previewCode,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          previewName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _AppleTextField(
                  controller: nameController,
                  enabled: !isSaving,
                  label: 'اسم الفرع',
                  hint: 'مثال: الفرع الرئيسي - القاهرة',
                  prefixIcon: Icons.storefront_rounded,
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: codeController,
                  enabled: !isSaving,
                  label: 'كود الفرع المختصر',
                  hint: 'مثال: CAI-01',
                  prefixIcon: Icons.qr_code_rounded,
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: descriptionController,
                  enabled: !isSaving,
                  label: 'العنوان أو الوصف',
                  hint: 'اختياري: تفاصيل الموقع أو الهاتف الداخلي...',
                  prefixIcon: Icons.map_outlined,
                  minLines: 2,
                  maxLines: 3,
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  _AppleErrorBanner(error: errorText!),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9333EA),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        final name = nameController.text.trim();
                        final code = codeController.text.trim();
                        final description = descriptionController.text.trim();
                        if (name.isEmpty || code.isEmpty) {
                          setDialogState(() {
                            errorText = 'اسم الفرع والكود المختصر مطلوبان.';
                          });
                          return;
                        }
                        setDialogState(() {
                          isSaving = true;
                          errorText = null;
                        });
                        try {
                          final notifier = ref.read(
                            chatOverviewControllerProvider.notifier,
                          );
                          if (branch == null) {
                            await notifier.createBranch(
                              name: name,
                              code: code,
                              description: description,
                            );
                          } else {
                            await notifier.updateBranch(
                              branchId: branch.id,
                              name: name,
                              code: code,
                              description: description,
                            );
                          }
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        } catch (error) {
                          setDialogState(() {
                            isSaving = false;
                            errorText = error.toString();
                          });
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ButtonLoadingIndicator(),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(branch == null ? 'إضافة الفرع' : 'حفظ التعديلات'),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
    codeController.dispose();
    descriptionController.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            branch == null
                ? 'تمت إضافة الفرع بنجاح'
                : 'تم تحديث بيانات الفرع بنجاح',
          ),
        ),
      );
    }
  }

  Future<void> _deleteBranch(BranchSummary branch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _AppleDangerDialog(
        title: 'حذف الفرع',
        subtitle: 'إزالة الفرع من قائمة الفروع التشغيلية',
        message: 'هل أنت متأكد من حذف فرع "${branch.name}" نهائياً؟',
        confirmLabel: 'حذف الفرع',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(chatOverviewControllerProvider.notifier)
        .deleteBranch(branch.id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    final filtered = widget.branches.where((b) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      return b.name.toLowerCase().contains(q) ||
          b.code.toLowerCase().contains(q) ||
          b.description.toLowerCase().contains(q);
    }).toList();

    final totalMembers = widget.branches.fold<int>(
      0,
      (sum, b) => sum + b.membersCount,
    );

    return Container(
      color: scaffoldBg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF9333EA).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFF9333EA),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الفروع والمواقع التشغيلية',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'إدارة فروع المؤسسة وتوزيع الموظفين والطابعات',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showBranchDialog(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF9333EA),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('إضافة فرع'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _MobileBentoStatChip(
                      label: 'إجمالي الفروع',
                      value: '${widget.branches.length}',
                      color: const Color(0xFF9333EA),
                    ),
                    const SizedBox(width: 8),
                    _MobileBentoStatChip(
                      label: 'الموظفون بالفروع',
                      value: '$totalMembers',
                      color: const Color(0xFF007AFF),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'بحث باسم الفرع أو الكود...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: cardBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: Text(
                  'لا توجد فروع مطابقة للبحث',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            )
          else
            ...filtered.map((branch) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF9333EA,
                            ).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            branch.code,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                              color: Color(0xFF9333EA),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            branch.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showBranchDialog(branch: branch),
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'تعديل الفرع',
                        ),
                        IconButton(
                          onPressed: () => _deleteBranch(branch),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'حذف الفرع',
                        ),
                      ],
                    ),
                    if (branch.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        branch.description,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF475569),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _MobileBadgePill(
                      label: '${branch.membersCount} موظف مسجل بالفرع',
                      color: const Color(0xFF9333EA),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _RoomsTab extends ConsumerStatefulWidget {
  const _RoomsTab({
    required this.conversations,
    required this.users,
    this.departments = const [],
  });

  final List<ChatConversation> conversations;
  final List<ChatDirectoryUser> users;
  final List<DepartmentSummary> departments;

  @override
  ConsumerState<_RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends ConsumerState<_RoomsTab> {
  String _searchQuery = '';
  String _typeFilter = 'all';

  List<ChatConversation> _resolveAllRooms(
    List<ChatConversation>? liveManageable,
    List<ChatConversation>? liveAll,
  ) {
    final map = <String, ChatConversation>{};
    for (final c in widget.conversations) {
      if (c.type != 'direct') {
        map[c.id] = c;
      }
    }
    if (liveManageable != null) {
      for (final c in liveManageable) {
        if (c.type != 'direct') {
          map[c.id] = c;
        }
      }
    }
    if (liveAll != null) {
      for (final c in liveAll) {
        if (c.type != 'direct') {
          map.putIfAbsent(c.id, () => c);
        }
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Color _roomColor(String type) {
    return switch (type) {
      'broadcast' => const Color(0xFFEA580C),
      'department' => const Color(0xFF4F46E5),
      _ => const Color(0xFF0D9488),
    };
  }

  IconData _roomIcon(String type) {
    return switch (type) {
      'broadcast' => Icons.campaign_rounded,
      'department' => Icons.business_rounded,
      _ => Icons.groups_rounded,
    };
  }

  String _roomTypeLabel(String type) {
    return switch (type) {
      'broadcast' => 'قناة بث إداري 📢',
      'department' => 'غرفة قسم 🏢',
      _ => 'مجموعة عمل 👥',
    };
  }

  String _departmentName(String? deptId) {
    if (deptId == null || deptId.isEmpty) return '';
    for (final d in widget.departments) {
      if (d.id == deptId || d.name == deptId) return d.name;
    }
    return '';
  }

  Future<void> _showCreateRoomDialog({String initialType = 'group'}) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    var selectedType = initialType;
    String? selectedDepartmentId = widget.departments.isNotEmpty
        ? widget.departments.first.id
        : null;
    final selectedMembers = <String>{};
    final selectedAdmins = <String>{};
    var memberSearch = '';
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
          final badgeColor = _roomColor(selectedType);
          final filteredUsers = widget.users.where((u) {
            if (memberSearch.trim().isEmpty) return true;
            final q = memberSearch.trim().toLowerCase();
            return u.displayName.toLowerCase().contains(q) ||
                u.username.toLowerCase().contains(q);
          }).toList();

          return _AppleAdminDialog(
            badgeIcon: _roomIcon(selectedType),
            badgeColor: badgeColor,
            title: selectedType == 'broadcast'
                ? 'إنشاء قناة بث إدارية'
                : 'إنشاء غرفة أو مجموعة جديدة',
            subtitle:
                'حدد نوع الغرفة، الأعضاء المشاركين، والمشرفين المسؤولين عنها',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    for (final item in const [
                      ('group', 'مجموعة عمل', Icons.groups_rounded),
                      ('department', 'غرفة قسم', Icons.business_rounded),
                      ('broadcast', 'قناة بث', Icons.campaign_rounded),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: InkWell(
                            onTap: isSaving
                                ? null
                                : () => setDialogState(() {
                                    selectedType = item.$1;
                                  }),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 6,
                              ),
                              decoration: BoxDecoration(
                                color: selectedType == item.$1
                                    ? _roomColor(
                                        item.$1,
                                      ).withValues(alpha: 0.15)
                                    : (isDark
                                          ? Colors.white.withValues(alpha: 0.04)
                                          : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selectedType == item.$1
                                      ? _roomColor(item.$1)
                                      : (isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.08,
                                              )
                                            : const Color(0xFFE2E8F0)),
                                  width: selectedType == item.$1 ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    item.$3,
                                    size: 18,
                                    color: _roomColor(item.$1),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.$2,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: selectedType == item.$1
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _AppleTextField(
                  controller: titleController,
                  enabled: !isSaving,
                  label: 'اسم الغرفة أو القناة',
                  hint: 'مثال: غرفة عمليات الفروع، قناة التعميمات...',
                  prefixIcon: Icons.forum_rounded,
                ),
                const SizedBox(height: 12),
                if (selectedType == 'department' &&
                    widget.departments.isNotEmpty) ...[
                  _AppleDropdown<String?>(
                    value: selectedDepartmentId,
                    label: 'القسم المرتبط بالغرفة',
                    prefixIcon: Icons.business_rounded,
                    items: widget.departments
                        .map(
                          (d) => DropdownMenuItem<String?>(
                            value: d.id,
                            child: Text('${d.name} (${d.code})'),
                          ),
                        )
                        .toList(),
                    onChanged: isSaving
                        ? null
                        : (v) => setDialogState(() => selectedDepartmentId = v),
                  ),
                  const SizedBox(height: 12),
                ],
                _AppleTextField(
                  controller: descriptionController,
                  enabled: !isSaving,
                  label: 'وصف الغرفة',
                  hint: 'اختياري: الهدف من الغرفة أو قواعد النشر...',
                  prefixIcon: Icons.notes_rounded,
                  minLines: 2,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Text(
                  'الأعضاء والمشرفون (${selectedMembers.length} عضو • ${selectedAdmins.length} مشرف)',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  onChanged: (v) => setDialogState(() => memberSearch = v),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن موظف لإضافته للغرفة...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, idx) {
                        final user = filteredUsers[idx];
                        final isMember = selectedMembers.contains(user.id);
                        final isAdmin = selectedAdmins.contains(user.id);
                        return ListTile(
                          dense: true,
                          leading: Checkbox(
                            value: isMember,
                            onChanged: isSaving
                                ? null
                                : (checked) {
                                    setDialogState(() {
                                      if (checked == true) {
                                        selectedMembers.add(user.id);
                                      } else {
                                        selectedMembers.remove(user.id);
                                        selectedAdmins.remove(user.id);
                                      }
                                    });
                                  },
                          ),
                          title: Text(
                            user.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            '@${user.username} • ${user.role}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: IconButton(
                            tooltip: 'تعيين كمشرف للغرفة',
                            onPressed: isSaving
                                ? null
                                : () {
                                    setDialogState(() {
                                      if (isAdmin) {
                                        selectedAdmins.remove(user.id);
                                      } else {
                                        selectedMembers.add(user.id);
                                        selectedAdmins.add(user.id);
                                      }
                                    });
                                  },
                            icon: Icon(
                              isAdmin
                                  ? Icons.verified_user_rounded
                                  : Icons.shield_outlined,
                              size: 18,
                              color: isAdmin
                                  ? const Color(0xFF0D9488)
                                  : Colors.grey,
                            ),
                          ),
                        );
                      },
                    ),
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
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: badgeColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        final name = titleController.text.trim();
                        if (name.isEmpty) {
                          setDialogState(() {
                            errorText = 'يرجى إدخال اسم الغرفة أو القناة.';
                          });
                          return;
                        }
                        setDialogState(() {
                          isSaving = true;
                          errorText = null;
                        });
                        try {
                          await ref
                              .read(chatOverviewControllerProvider.notifier)
                              .createConversation(
                                type: selectedType,
                                name: name,
                                description: descriptionController.text.trim(),
                                memberIds: selectedMembers.toList(),
                                adminIds: selectedAdmins.toList(),
                                departmentId: selectedType == 'department'
                                    ? selectedDepartmentId
                                    : null,
                              );
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        } catch (error) {
                          setDialogState(() {
                            isSaving = false;
                            errorText = error.toString();
                          });
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ButtonLoadingIndicator(),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('إنشاء الآن'),
              ),
            ],
          );
        },
      ),
    );
    titleController.dispose();
    descriptionController.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء الغرفة بنجاح')),
      );
    }
  }

  Future<void> _showEditRoomDialog(ChatConversation room) async {
    final titleController = TextEditingController(text: room.name);
    final descriptionController = TextEditingController(text: room.description);
    final selectedMembers = <String>{...room.members.map((p) => p.id)};
    final selectedAdmins = <String>{...room.admins.map((m) => m.id)};
    var isArchived = room.isArchived;
    var isActive = room.isActive;
    var memberSearch = '';
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
          final badgeColor = _roomColor(room.type);
          final filteredUsers = widget.users.where((u) {
            if (memberSearch.trim().isEmpty) return true;
            final q = memberSearch.trim().toLowerCase();
            return u.displayName.toLowerCase().contains(q) ||
                u.username.toLowerCase().contains(q);
          }).toList();

          return _AppleAdminDialog(
            badgeIcon: _roomIcon(room.type),
            badgeColor: badgeColor,
            title: 'إدارة وتعديل الغرفة',
            subtitle: '${_roomTypeLabel(room.type)} • ${room.name}',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AppleTextField(
                  controller: titleController,
                  enabled: !isSaving,
                  label: 'اسم الغرفة أو القناة',
                  hint: 'أدخل اسم الغرفة...',
                  prefixIcon: Icons.forum_rounded,
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: descriptionController,
                  enabled: !isSaving,
                  label: 'وصف الغرفة',
                  hint: 'وصف الغرفة أو التعليمات...',
                  prefixIcon: Icons.notes_rounded,
                  minLines: 2,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          dense: true,
                          value: isActive,
                          onChanged: isSaving
                              ? null
                              : (v) => setDialogState(() => isActive = v),
                          title: const Text(
                            'الغرفة نشطة ومفعلة للمحادثات',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SwitchListTile.adaptive(
                          dense: true,
                          value: isArchived,
                          onChanged: isSaving
                              ? null
                              : (v) => setDialogState(() => isArchived = v),
                          title: const Text(
                            'أرشفة الغرفة وإخفاؤها من القائمة النشطة',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'الأعضاء والمشرفون (${selectedMembers.length} عضو • ${selectedAdmins.length} مشرف)',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  onChanged: (v) => setDialogState(() => memberSearch = v),
                  decoration: InputDecoration(
                    hintText: 'ابحث في الأعضاء...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, idx) {
                        final user = filteredUsers[idx];
                        final isMember = selectedMembers.contains(user.id);
                        final isAdmin = selectedAdmins.contains(user.id);
                        return ListTile(
                          dense: true,
                          leading: Checkbox(
                            value: isMember,
                            onChanged: isSaving
                                ? null
                                : (checked) {
                                    setDialogState(() {
                                      if (checked == true) {
                                        selectedMembers.add(user.id);
                                      } else {
                                        selectedMembers.remove(user.id);
                                        selectedAdmins.remove(user.id);
                                      }
                                    });
                                  },
                          ),
                          title: Text(
                            user.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            '@${user.username} • ${user.role}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: IconButton(
                            tooltip: 'تعيين كمشرف للغرفة',
                            onPressed: isSaving
                                ? null
                                : () {
                                    setDialogState(() {
                                      if (isAdmin) {
                                        selectedAdmins.remove(user.id);
                                      } else {
                                        selectedMembers.add(user.id);
                                        selectedAdmins.add(user.id);
                                      }
                                    });
                                  },
                            icon: Icon(
                              isAdmin
                                  ? Icons.verified_user_rounded
                                  : Icons.shield_outlined,
                              size: 18,
                              color: isAdmin
                                  ? const Color(0xFF0D9488)
                                  : Colors.grey,
                            ),
                          ),
                        );
                      },
                    ),
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
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: badgeColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        final name = titleController.text.trim();
                        if (name.isEmpty) {
                          setDialogState(() {
                            errorText = 'اسم الغرفة لا يمكن أن يكون فارغاً.';
                          });
                          return;
                        }
                        setDialogState(() {
                          isSaving = true;
                          errorText = null;
                        });
                        try {
                          await ref
                              .read(chatOverviewControllerProvider.notifier)
                              .updateManagedConversation(
                                conversationId: room.id,
                                name: name,
                                description: descriptionController.text.trim(),
                                memberIds: selectedMembers.toList(),
                                adminIds: selectedAdmins.toList(),
                                isArchived: isArchived,
                                isActive: isActive,
                              );
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        } catch (error) {
                          setDialogState(() {
                            isSaving = false;
                            errorText = error.toString();
                          });
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ButtonLoadingIndicator(),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('حفظ التغييرات'),
              ),
            ],
          );
        },
      ),
    );
    titleController.dispose();
    descriptionController.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث إعدادات الغرفة بنجاح')),
      );
    }
  }

  Future<void> _deleteRoom(ChatConversation room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _AppleDangerDialog(
        title: 'حذف الغرفة نهائياً',
        subtitle: 'إزالة الغرفة وجميع الرسائل المرتبطة بها',
        message:
            'هل أنت متأكد من حذف "${room.name}"؟ سيتم إزالة جميع الرسائل والمحادثات المرتبطة بها.',
        confirmLabel: 'حذف الغرفة',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(chatOverviewControllerProvider.notifier)
        .deleteManagedConversation(room.id);
  }

  @override
  Widget build(BuildContext context) {
    final liveOverview = ref.watch(chatOverviewControllerProvider).valueOrNull;
    final allRooms = _resolveAllRooms(
      liveOverview?.manageableConversations,
      liveOverview?.conversations,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    final groupsCount = allRooms.where((r) => r.type == 'group').length;
    final deptRoomsCount = allRooms.where((r) => r.type == 'department').length;
    final broadcastCount = allRooms.where((r) => r.type == 'broadcast').length;

    final filtered = allRooms.where((room) {
      if (_typeFilter == 'archived') {
        if (!room.isArchived) return false;
      } else if (_typeFilter != 'all') {
        if (room.type != _typeFilter) return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final deptName = _departmentName(room.departmentId).toLowerCase();
        return room.name.toLowerCase().contains(q) ||
            room.description.toLowerCase().contains(q) ||
            deptName.contains(q);
      }
      return true;
    }).toList();

    return Container(
      color: scaffoldBg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D9488).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.forum_rounded,
                        color: Color(0xFF0D9488),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إدارة الغرف والقنوات والمجموعات',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'تحكم كامل في مجموعات العمل، غرف الأقسام، وقنوات البث',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            _showCreateRoomDialog(initialType: 'group'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0D9488),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.group_add_rounded, size: 18),
                        label: const Text('إنشاء غرفة'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            _showCreateRoomDialog(initialType: 'broadcast'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEA580C),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.campaign_rounded, size: 18),
                        label: const Text('إنشاء قناة بث'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _MobileBentoStatChip(
                      label: 'الإجمالي',
                      value: '${allRooms.length}',
                      color: const Color(0xFF007AFF),
                    ),
                    const SizedBox(width: 6),
                    _MobileBentoStatChip(
                      label: 'مجموعات',
                      value: '$groupsCount',
                      color: const Color(0xFF0D9488),
                    ),
                    const SizedBox(width: 6),
                    _MobileBentoStatChip(
                      label: 'أقسام',
                      value: '$deptRoomsCount',
                      color: const Color(0xFF4F46E5),
                    ),
                    const SizedBox(width: 6),
                    _MobileBentoStatChip(
                      label: 'بث',
                      value: '$broadcastCount',
                      color: const Color(0xFFEA580C),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'ابحث باسم الغرفة أو القسم...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: cardBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final chip in const [
                  ('all', 'الكل'),
                  ('group', 'المجموعات 👥'),
                  ('department', 'غرف الأقسام 🏢'),
                  ('broadcast', 'قنوات البث 📢'),
                  ('archived', 'المؤرشفة 📦'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(chip.$2),
                      selected: _typeFilter == chip.$1,
                      onSelected: (_) =>
                          setState(() => _typeFilter = chip.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                children: [
                  Icon(Icons.forum_outlined, size: 42, color: Colors.grey),
                  SizedBox(height: 10),
                  Text(
                    'لا توجد غرف أو قنوات مطابقة للفلتر الحالي',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            )
          else
            ...filtered.map((room) {
              final color = _roomColor(room.type);
              final deptLabel = _departmentName(room.departmentId);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _roomIcon(room.type),
                            color: color,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                room.name.trim().isEmpty
                                    ? 'غرفة بدون اسم'
                                    : room.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _MobileBadgePill(
                                    label: _roomTypeLabel(room.type),
                                    color: color,
                                  ),
                                  if (deptLabel.isNotEmpty)
                                    _MobileBadgePill(
                                      label: deptLabel,
                                      color: const Color(0xFF4F46E5),
                                    ),
                                  if (room.isArchived)
                                    const _MobileBadgePill(
                                      label: 'مؤرشفة 📦',
                                      color: Colors.grey,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showEditRoomDialog(room),
                          icon: const Icon(Icons.tune_rounded, size: 20),
                          tooltip: 'إعدادات الغرفة والأعضاء',
                        ),
                        IconButton(
                          onPressed: () => _deleteRoom(room),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'حذف الغرفة',
                        ),
                      ],
                    ),
                    if (room.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        room.description,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF475569),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _MobileBadgePill(
                          label: '${room.members.length} عضو',
                          color: const Color(0xFF007AFF),
                        ),
                        _MobileBadgePill(
                          label: '${room.admins.length} مشرف',
                          color: const Color(0xFF0D9488),
                        ),
                        _MobileBadgePill(
                          label: room.isActive ? 'نشطة 🟢' : 'متوقفة ⏸️',
                          color: room.isActive
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFD97706),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
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
  final Map<String, ChatPermissionSet> _draftPermissions = {};
  String? _selectedRoleId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _syncDrafts();
  }

  @override
  void didUpdateWidget(covariant _RolesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDrafts();
  }

  void _syncDrafts() {
    for (final role in widget.roles) {
      _draftPermissions[role.id] = role.permissions;
    }
    if (_selectedRoleId == null && widget.roles.isNotEmpty) {
      _selectedRoleId = widget.roles.first.id;
    }
  }

  ChatPermissionSet _togglePermission(
    ChatPermissionSet current,
    String key,
    bool value,
  ) {
    final map = Map<String, dynamic>.from(current.toJson());
    map[key] = value;
    return ChatPermissionSet.fromJson(map);
  }

  ChatPermissionSet _setAllPermissions(ChatPermissionSet current, bool value) {
    final map = Map<String, dynamic>.from(current.toJson());
    for (final k in map.keys) {
      map[k] = value;
    }
    return ChatPermissionSet.fromJson(map);
  }

  int _countEnabled(ChatPermissionSet perms) {
    return perms.toJson().values.where((v) => v == true).length;
  }

  Color _roleColor(String roleName) {
    return switch (roleName.toLowerCase()) {
      'admin' => const Color(0xFFDC2626),
      'manager' => const Color(0xFF4F46E5),
      _ => const Color(0xFF0D9488),
    };
  }

  IconData _roleIcon(String roleName) {
    return switch (roleName.toLowerCase()) {
      'admin' => Icons.shield_rounded,
      'manager' => Icons.manage_accounts_rounded,
      _ => Icons.person_rounded,
    };
  }

  String _roleArabicTitle(String roleName) {
    return switch (roleName.toLowerCase()) {
      'admin' => 'مسؤول النظام (Admin)',
      'manager' => 'مدير قسم (Manager)',
      _ => 'موظف (User)',
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    if (widget.roles.isEmpty) {
      return Container(
        color: scaffoldBg,
        child: const Center(child: Text('لا توجد أدوار متاحة حالياً')),
      );
    }

    final activeRole = widget.roles.firstWhere(
      (r) => r.id == _selectedRoleId,
      orElse: () => widget.roles.first,
    );
    final draft = _draftPermissions[activeRole.id] ?? activeRole.permissions;
    final draftJson = draft.toJson();
    final enabledCount = _countEnabled(draft);
    final roleAccent = _roleColor(activeRole.roleName);

    const categories = [
      (
        title: 'المحادثات والغرف والتواصل',
        icon: Icons.forum_rounded,
        color: Color(0xFF007AFF),
        items: [
          (
            'canCreateRooms',
            'إنشاء وإدارة الغرف',
            'إنشاء مجموعات العمل وغرف الأقسام وتعديلها',
            Icons.group_add_rounded,
          ),
          (
            'canSendBroadcast',
            'النشر في قنوات البث',
            'إرسال تعميمات ورسائل جماعية في قنوات البث',
            Icons.campaign_rounded,
          ),
          (
            'canDeleteMessages',
            'حذف الرسائل',
            'حذف الرسائل المخالفة داخل الغرف والمحادثات',
            Icons.delete_sweep_rounded,
          ),
          (
            'canUploadFiles',
            'رفع ومشاركة المرفقات',
            'إرفاق الصور والملفات والمستندات في المحادثات',
            Icons.attach_file_rounded,
          ),
          (
            'canModerateDepartment',
            'الإشراف على غرفة القسم',
            'إدارة الأعضاء والرسائل داخل القسم التابع له',
            Icons.verified_user_rounded,
          ),
          (
            'canViewDepartmentLogs',
            'عرض سجلات نشاط القسم',
            'الاطلاع على سجل العمليات الخاص بالقسم',
            Icons.history_edu_rounded,
          ),
        ],
      ),
      (
        title: 'الهيكلة الإدارية والمستخدمون',
        icon: Icons.admin_panel_settings_rounded,
        color: Color(0xFF4F46E5),
        items: [
          (
            'canCreateUsers',
            'إنشاء وإدارة المستخدمين',
            'إضافة حسابات الموظفين وتعديل بياناتهم',
            Icons.person_add_alt_1_rounded,
          ),
          (
            'canCreateDepartments',
            'إنشاء وإدارة الأقسام',
            'إضافة الأقسام التنظيمية وتعيين مديريها',
            Icons.business_rounded,
          ),
          (
            'canManageBranches',
            'إدارة الفروع والمواقع',
            'إضافة وتعديل فروع المؤسسة وأكوادها',
            Icons.location_on_rounded,
          ),
          (
            'canManageRoles',
            'إدارة الأدوار والصلاحيات',
            'تعديل مصفوفة الصلاحيات للأدوار الوظيفية',
            Icons.security_rounded,
          ),
          (
            'canManageAnnouncements',
            'إدارة الإعلانات والتعميمات',
            'نشر وتثبيت الإعلانات الإدارية العامة',
            Icons.campaign_outlined,
          ),
        ],
      ),
      (
        title: 'المستندات، التذاكر، والنسخ الاحتياطي',
        icon: Icons.folder_copy_rounded,
        color: Color(0xFF0D9488),
        items: [
          (
            'canManageFiles',
            'إدارة أرشيف الملفات',
            'التحكم الكامل في المستندات المرفوعة وتعديلها',
            Icons.folder_open_rounded,
          ),
          (
            'canManageTickets',
            'إدارة ومعالجة التذاكر',
            'استلام تذاكر الدعم الفني وتغيير حالتها وإغلاقها',
            Icons.confirmation_number_rounded,
          ),
          (
            'canManageBackups',
            'إدارة النسخ الاحتياطي',
            'إنشاء واستعادة النسخ الاحتياطية لقاعدة البيانات',
            Icons.backup_rounded,
          ),
          (
            'canManageUpdates',
            'إدارة تحديثات المنظومة',
            'رفع ونشر إصدارات التحديث للتطبيقات',
            Icons.system_update_alt_rounded,
          ),
        ],
      ),
      (
        title: 'الطابعات، الأصول، ومراقبة النظام',
        icon: Icons.print_rounded,
        color: Color(0xFFEA580C),
        items: [
          (
            'canViewPrinters',
            'عرض شاشة الطابعات',
            'الاطلاع على حالة طابعات الفروع والأحبار',
            Icons.print_rounded,
          ),
          (
            'canManagePrinters',
            'إدارة تعريفات الطابعات',
            'إضافة وتعديل وحذف الطابعات وتعيين الفروع',
            Icons.build_circle_rounded,
          ),
          (
            'canSyncPrinters',
            'مزامنة بيانات الطابعات',
            'تشغيل الفحص والمزامنة اللحظية للطابعات',
            Icons.sync_rounded,
          ),
          (
            'canExportPrinterReports',
            'تصدير تقارير الطباعة',
            'تصدير سجلات الاستهلاك وأعطال الطابعات',
            Icons.receipt_long_rounded,
          ),
          (
            'canViewSnipeit',
            'إدارة عهد وأصول IT (Snipe-IT)',
            'عرض وإدارة أجهزة وعهد الموظفين التقنية',
            Icons.devices_rounded,
          ),
          (
            'canViewSystemMonitor',
            'مراقبة السيرفرات والشبكة',
            'الاطلاع على حالة الخوادم والمنافذ الحية',
            Icons.monitor_heart_rounded,
          ),
          (
            'canManageSystem',
            'إعدادات النظام المتقدمة',
            'إدارة إعدادات الخادم وسجلات التدقيق والأخطاء',
            Icons.dns_rounded,
          ),
        ],
      ),
    ];

    return Container(
      color: scaffoldBg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'مصفوفة الأدوار والصلاحيات (22 صلاحية)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'اختر الدور الوظيفي لتخصيص صلاحياته بدقة وحفظها فوراً',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 14),
                Row(
                  children: widget.roles.map((role) {
                    final selected = role.id == activeRole.id;
                    final color = _roleColor(role.roleName);
                    final roleDraft =
                        _draftPermissions[role.id] ?? role.permissions;
                    final count = _countEnabled(roleDraft);
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: InkWell(
                          onTap: () =>
                              setState(() => _selectedRoleId = role.id),
                          borderRadius: BorderRadius.circular(14),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? color.withValues(
                                      alpha: isDark ? 0.22 : 0.12,
                                    )
                                  : (isDark
                                        ? Colors.white.withValues(alpha: 0.04)
                                        : const Color(0xFFF8FAFC)),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? color
                                    : (isDark
                                          ? Colors.white.withValues(alpha: 0.08)
                                          : const Color(0xFFE2E8F0)),
                                width: selected ? 1.6 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  _roleIcon(role.roleName),
                                  color: color,
                                  size: 22,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _roleArabicTitle(role.roleName),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11.5,
                                    color: selected ? color : null,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$count / 22 مفعلة',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _MobileBadgePill(
                      label: 'المفعلة: $enabledCount من 22',
                      color: roleAccent,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _draftPermissions[activeRole.id] = _setAllPermissions(
                            draft,
                            true,
                          );
                        });
                      },
                      child: const Text('تفعيل الكل'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _draftPermissions[activeRole.id] = _setAllPermissions(
                            draft,
                            false,
                          );
                        });
                      },
                      child: const Text('إلغاء الكل'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (final category in categories) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.07)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: category.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          category.icon,
                          color: category.color,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          category.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final perm in category.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MobilePermissionCard(
                        icon: perm.$4,
                        accentColor: category.color,
                        title: perm.$2,
                        subtitle: perm.$3,
                        value: draftJson[perm.$1] == true,
                        onChanged: (next) {
                          setState(() {
                            _draftPermissions[activeRole.id] =
                                _togglePermission(draft, perm.$1, next);
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: roleAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _isSaving
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final roleTitle = _roleArabicTitle(activeRole.roleName);
                      setState(() => _isSaving = true);
                      try {
                        await ref
                            .read(chatOverviewControllerProvider.notifier)
                            .updateRole(
                              roleId: activeRole.id,
                              permissions:
                                  _draftPermissions[activeRole.id] ??
                                  activeRole.permissions,
                            );
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم حفظ صلاحيات دور "$roleTitle" بنجاح',
                              ),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isSaving = false);
                        }
                      }
                    },
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: ButtonLoadingIndicator(),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(
                'حفظ صلاحيات ${_roleArabicTitle(activeRole.roleName)}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePermissionCard extends StatelessWidget {
  const _MobilePermissionCard({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value
              ? accentColor.withValues(alpha: isDark ? 0.16 : 0.08)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value
                ? accentColor.withValues(alpha: 0.45)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.07)
                      : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: value
                    ? accentColor.withValues(alpha: 0.18)
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: value ? accentColor : Colors.grey,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? Colors.white60
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            CupertinoSwitch(
              value: value,
              activeTrackColor: accentColor,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileServerTargetDraft {
  _MobileServerTargetDraft({
    required this.id,
    String title = '',
    String baseUrl = '',
    String portsText = '',
  }) : titleController = TextEditingController(text: title),
       baseUrlController = TextEditingController(text: baseUrl),
       portsController = TextEditingController(text: portsText);

  final String id;
  final TextEditingController titleController;
  final TextEditingController baseUrlController;
  final TextEditingController portsController;

  List<int> get parsedPorts {
    return portsController.text
        .split(RegExp(r'[,،\s]+'))
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .where((p) => p > 0 && p <= 65535)
        .toSet()
        .toList();
  }

  void dispose() {
    titleController.dispose();
    baseUrlController.dispose();
    portsController.dispose();
  }
}

class _MobileServerSettingsTab extends ConsumerStatefulWidget {
  const _MobileServerSettingsTab();

  @override
  ConsumerState<_MobileServerSettingsTab> createState() =>
      _MobileServerSettingsTabState();
}

class _MobileServerSettingsTabState
    extends ConsumerState<_MobileServerSettingsTab> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _desktopUrlController = TextEditingController();
  final _mobileUrlController = TextEditingController();
  final _snipeitUrlController = TextEditingController();
  bool _showServersShortcut = true;
  final List<_MobileServerTargetDraft> _targets = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _desktopUrlController.dispose();
    _mobileUrlController.dispose();
    _snipeitUrlController.dispose();
    for (final t in _targets) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get<Map<String, dynamic>>(
        '/api/app-settings',
        options: Options(extra: {'requiresAuth': false}),
      );
      final settings =
          (response.data?['settings'] as Map<String, dynamic>?) ?? const {};
      _desktopUrlController.text =
          settings['desktopBaseUrl']?.toString() ?? '';
      _mobileUrlController.text = settings['mobileBaseUrl']?.toString() ?? '';
      _snipeitUrlController.text = settings['snipeitUrl']?.toString() ?? '';
      _showServersShortcut = settings['showServersShortcut'] != false;

      for (final t in _targets) {
        t.dispose();
      }
      _targets.clear();
      final rawTargets = settings['serverTargets'];
      if (rawTargets is List) {
        var idx = 0;
        for (final entry in rawTargets) {
          if (entry is Map) {
            final ports = (entry['ports'] is List)
                ? (entry['ports'] as List).map((e) => e.toString()).join(', ')
                : '';
            _targets.add(
              _MobileServerTargetDraft(
                id: entry['id']?.toString() ?? 'srv_${idx++}',
                title: entry['title']?.toString() ?? '',
                baseUrl: entry['baseUrl']?.toString() ?? '',
                portsText: ports,
              ),
            );
          }
        }
      }
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final apiClient = ref.read(apiClientProvider);
      final targetsPayload = _targets
          .where(
            (t) =>
                t.titleController.text.trim().isNotEmpty &&
                t.baseUrlController.text.trim().isNotEmpty,
          )
          .map(
            (t) => {
              'id': t.id,
              'title': t.titleController.text.trim(),
              'baseUrl': t.baseUrlController.text.trim(),
              'ports': t.parsedPorts,
            },
          )
          .toList();

      await apiClient.dio.put<Map<String, dynamic>>(
        '/api/admin/app-settings',
        data: {
          'desktopBaseUrl': _desktopUrlController.text.trim(),
          'mobileBaseUrl': _mobileUrlController.text.trim(),
          'snipeitUrl': _snipeitUrlController.text.trim(),
          'showServersShortcut': _showServersShortcut,
          'serverTargets': targetsPayload,
        },
        options: Options(extra: {'requiresAuth': true}),
      );
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ إعدادات الخادم بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    if (_loading) {
      return Container(
        color: scaffoldBg,
        child: const Center(child: AppLoadingIndicator(size: 28)),
      );
    }

    final totalPorts = _targets.fold<int>(
      0,
      (sum, t) => sum + t.parsedPorts.length,
    );

    return Container(
      color: scaffoldBg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.dns_rounded,
                        color: Color(0xFF007AFF),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إعدادات الخادم والربط الشبكي',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'عناوين السيرفر الافتراضية ومراقبة المنافذ الحية',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _loading || _saving ? null : _loadSettings,
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'تحديث',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _MobileBentoStatChip(
                      label: 'السيرفرات المضافة',
                      value: '${_targets.length}',
                      color: const Color(0xFF007AFF),
                    ),
                    const SizedBox(width: 8),
                    _MobileBentoStatChip(
                      label: 'المنافذ المراقبة',
                      value: '$totalPorts',
                      color: const Color(0xFF0D9488),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_error != null) ...[
            _AppleErrorBanner(error: _error!),
            const SizedBox(height: 14),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'نقاط الاتصال الأساسية (Core Endpoints)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: _desktopUrlController,
                  label: 'رابط خادم تطبيق الكمبيوتر (Desktop Base URL)',
                  hint: 'https://chat.ismart.live',
                  prefixIcon: Icons.desktop_windows_rounded,
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: _mobileUrlController,
                  label: 'رابط خادم تطبيق الموبايل (Mobile Base URL)',
                  hint: 'https://chat.ismart.live',
                  prefixIcon: Icons.phone_iphone_rounded,
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: _snipeitUrlController,
                  label: 'رابط منظومة الأصول والعهد (Snipe-IT URL)',
                  hint: 'https://assets.ismart.live',
                  prefixIcon: Icons.inventory_2_outlined,
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _showServersShortcut,
                  onChanged: (v) => setState(() => _showServersShortcut = v),
                  title: const Text(
                    'إظهار اختصار مراقبة السيرفرات في الشريط الجانبي',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'قائمة السيرفرات والمنافذ المراقبة',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _targets.add(
                            _MobileServerTargetDraft(
                              id: 'srv_${DateTime.now().millisecondsSinceEpoch}',
                              portsText: '80, 443',
                            ),
                          );
                        });
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('إضافة سيرفر'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_targets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'لا توجد سيرفرات مضافة للمراقبة حالياً',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ..._targets.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    final ports = item.parsedPorts;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _MobileBadgePill(
                                label: 'سيرفر #${idx + 1}',
                                color: const Color(0xFF007AFF),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    item.dispose();
                                    _targets.removeAt(idx);
                                  });
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _AppleTextField(
                            controller: item.titleController,
                            label: 'اسم السيرفر',
                            hint: 'مثال: سيرفر قاعدة البيانات الرئيسي',
                            prefixIcon: Icons.label_outline_rounded,
                          ),
                          const SizedBox(height: 10),
                          _AppleTextField(
                            controller: item.baseUrlController,
                            label: 'عنوان IP أو النطاق',
                            hint: '192.168.1.10 أو https://server.local',
                            prefixIcon: Icons.lan_outlined,
                          ),
                          const SizedBox(height: 10),
                          _AppleTextField(
                            controller: item.portsController,
                            label: 'المنافذ (مفصولة بفاصلة)',
                            hint: '80, 443, 3000, 27017',
                            prefixIcon: Icons.settings_ethernet_rounded,
                            onChanged: (_) => setState(() {}),
                          ),
                          if (ports.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: ports
                                  .map(
                                    (p) => _MobileBadgePill(
                                      label: ':$p',
                                      color: const Color(0xFF0D9488),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _saving ? null : _saveSettings,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: ButtonLoadingIndicator(),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text('حفظ جميع إعدادات الخادم'),
          ),
        ],
      ),
    );
  }
}

class _MobileBentoStatChip extends StatelessWidget {
  const _MobileBentoStatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileBadgePill extends StatelessWidget {
  const _MobileBadgePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
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
                child: Material(
                  color: Colors.transparent,
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
                child: Material(
                  color: Colors.transparent,
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
