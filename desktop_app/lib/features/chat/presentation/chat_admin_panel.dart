import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/admin_announcement.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/managed_user.dart';
import '../../../shared/models/remote_document.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/button_loading_indicator.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../admin/presentation/backup_screen.dart';
import '../../admin/presentation/update_management_screen.dart';
import '../../admin/presentation/server_settings_screen.dart';
import '../../reports/presentation/report_templates_screen.dart';
import '../models/chat_models.dart';

class ChatAdminPanel extends ConsumerStatefulWidget {
  const ChatAdminPanel({
    super.key,
    required this.departments,
    required this.branches,
    required this.manageableConversations,
    required this.users,
    required this.roles,
    required this.usersState,
    required this.currentUser,
    this.initialTabIndex = 0,
    this.onTabChanged,
  });

  final List<DepartmentSummary> departments;
  final List<BranchSummary> branches;
  final List<ChatConversation> manageableConversations;
  final List<ChatDirectoryUser> users;
  final List<ChatRole> roles;
  final AsyncValue<List<ManagedUser>> usersState;
  final AppUser currentUser;
  final int initialTabIndex;
  final ValueChanged<int>? onTabChanged;

  @override
  ConsumerState<ChatAdminPanel> createState() => _ChatAdminPanelState();
}

class _ChatAdminPanelState extends ConsumerState<ChatAdminPanel>
    with SingleTickerProviderStateMixin {
  late Future<_AdminLoadResult<ChatAuditLog>> _auditLogsFuture;
  late Future<_AdminLoadResult<ChatSystemError>> _systemErrorsFuture;
  late TabController _tabController;
  List<String> _visibleTabKeys = const <String>[];

  @override
  void initState() {
    super.initState();
    _rebuildTabController(preferredIndex: widget.initialTabIndex);
    _reloadLogs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureUsersLoaded();
    });
  }

  Future<void> _ensureUsersLoaded() async {
    if (!mounted) return;
    if (!widget.currentUser.isAdmin &&
        !widget.currentUser.can('canCreateUsers')) {
      return;
    }
    final usersState = ref.read(usersControllerProvider);
    if (usersState.hasError ||
        usersState.isLoading ||
        usersState.valueOrNull == null) {
      await ref.read(usersControllerProvider.notifier).refresh();
    }
  }

  @override
  void didUpdateWidget(covariant ChatAdminPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextTabs = _allowedTabKeys();
    if (_visibleTabKeys.length != nextTabs.length ||
        !_sameTabLabels(_visibleTabKeys, nextTabs)) {
      _rebuildTabController();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reloadLogs() {
    final controller = ref.read(chatOverviewControllerProvider.notifier);
    _auditLogsFuture = _safeLoad(
      () => controller.fetchAuditLogs(limit: 200),
      emptyMessage: 'لا توجد أحداث إدارية مسجلة',
    );
    _systemErrorsFuture = _safeLoad(
      () => controller.fetchSystemErrors(limit: 200),
      emptyMessage: 'لا توجد أخطاء نظامية مسجلة',
    );
  }

  Future<_AdminLoadResult<T>> _safeLoad<T>(
    Future<List<T>> Function() loader, {
    required String emptyMessage,
  }) async {
    try {
      final items = await loader();
      return _AdminLoadResult(items: items, emptyMessage: emptyMessage);
    } catch (error) {
      return _AdminLoadResult(
        items: const [],
        emptyMessage: emptyMessage,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> _refreshAll() async {
    if (!mounted) return;
    final overviewController = ref.read(chatOverviewControllerProvider.notifier);
    final usersController = ref.read(usersControllerProvider.notifier);
    final adminAnnouncementsController = ref.read(
      adminAnnouncementsControllerProvider.notifier,
    );
    final adminDocumentsController = ref.read(
      adminDocumentsControllerProvider.notifier,
    );
    await overviewController.refresh();
    await usersController.refresh();
    await adminAnnouncementsController.refresh();
    await adminDocumentsController.refresh();
    if (mounted) {
      setState(_reloadLogs);
    }
  }

  bool _can(String permission) =>
      widget.currentUser.isAdmin || widget.currentUser.can(permission);

  bool _sameTabLabels(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  List<String> _allowedTabKeys() {
    final tabs = <String>[
      if (_can('canManageAnnouncements')) 'announcements',
      if (_can('canCreateUsers')) 'users',
      if (_can('canManageFiles')) 'files',
      if (_can('canCreateDepartments')) 'departments',
      if (_can('canManageBranches')) 'branches',
      if (_can('canCreateRooms') || _can('canSendBroadcast')) 'rooms',
      if (_can('canManageRoles')) 'roles',
      if (_can('canViewDepartmentLogs')) 'audit',
      if (_can('canManageSystem')) 'errors',
      if (_can('canManageSystem')) 'server',
      if (_can('canManageUpdates')) 'updates',
      if (_can('canManageBackups')) 'backups',
      if (widget.currentUser.isAdmin) 'reports',
    ];
    return tabs.isEmpty ? const <String>['blocked'] : tabs;
  }

  List<_AdminPanelTabData> _buildVisibleTabs({
    required AsyncValue<List<AdminAnnouncement>> announcementsState,
    required AsyncValue<List<RemoteDocument>> documentsState,
  }) {
    final tabs = <_AdminPanelTabData>[
      if (_visibleTabKeys.contains('announcements'))
        _AdminPanelTabData(
          label: 'الإعلانات',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: Text('الإعلانات'),
          ),
          mobileTab: const Tab(text: 'الإعلانات'),
          child: _AnnouncementsAdminTab(announcementsState: announcementsState),
        ),
      if (_visibleTabKeys.contains('users'))
        _AdminPanelTabData(
          label: 'المستخدمون',
          destination: const NavigationRailDestination(
            icon: Icon(Iconsax.people),
            selectedIcon: Icon(Iconsax.people5),
            label: Text('المستخدمون'),
          ),
          mobileTab: const Tab(text: 'المستخدمون'),
          child: _UsersAdminTab(
            departments: widget.departments,
            branches: widget.branches,
            usersState: widget.usersState,
          ),
        ),
      if (_visibleTabKeys.contains('files'))
        _AdminPanelTabData(
          label: 'الملفات',
          destination: const NavigationRailDestination(
            icon: Icon(Iconsax.folder),
            selectedIcon: Icon(Iconsax.folder5),
            label: Text('الملفات'),
          ),
          mobileTab: const Tab(text: 'الملفات'),
          child: _AdminDocumentsTab(documentsState: documentsState),
        ),
      if (_visibleTabKeys.contains('departments'))
        _AdminPanelTabData(
          label: 'الأقسام',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.domain_add),
            selectedIcon: Icon(Icons.domain_add_outlined),
            label: Text('الأقسام'),
          ),
          mobileTab: const Tab(text: 'الأقسام'),
          child: _DepartmentsAdminTab(
            departments: widget.departments,
            users: widget.users,
          ),
        ),
      if (_visibleTabKeys.contains('branches'))
        _AdminPanelTabData(
          label: 'الفروع',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree),
            label: Text('الفروع'),
          ),
          mobileTab: const Tab(text: 'الفروع'),
          child: _BranchesAdminTab(branches: widget.branches),
        ),
      if (_visibleTabKeys.contains('rooms'))
        _AdminPanelTabData(
          label: 'الغرف',
          destination: const NavigationRailDestination(
            icon: Icon(Iconsax.message),
            selectedIcon: Icon(Iconsax.message5),
            label: Text('الغرف'),
          ),
          mobileTab: const Tab(text: 'الغرف'),
          child: _RoomsAdminTab(
            conversations: widget.manageableConversations,
            users: widget.users,
            departments: widget.departments,
          ),
        ),
      if (_visibleTabKeys.contains('roles'))
        _AdminPanelTabData(
          label: 'الصلاحيات',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings),
            label: Text('الصلاحيات'),
          ),
          mobileTab: const Tab(text: 'الصلاحيات'),
          child: _RolesAdminTab(roles: widget.roles),
        ),
      if (_visibleTabKeys.contains('audit'))
        _AdminPanelTabData(
          label: 'السجل',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: Text('السجل'),
          ),
          mobileTab: const Tab(text: 'السجل'),
          child: _AuditLogsTab(logsFuture: _auditLogsFuture),
        ),
      if (_visibleTabKeys.contains('errors'))
        _AdminPanelTabData(
          label: 'الأخطاء',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.error_outline),
            selectedIcon: Icon(Icons.error),
            label: Text('الأخطاء'),
          ),
          mobileTab: const Tab(text: 'الأخطاء'),
          child: _SystemErrorsTab(errorsFuture: _systemErrorsFuture),
        ),
      if (_visibleTabKeys.contains('server'))
        _AdminPanelTabData(
          label: 'الخادم',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.settings_ethernet_outlined),
            selectedIcon: Icon(Icons.settings_ethernet),
            label: Text('الخادم'),
          ),
          mobileTab: const Tab(text: 'الخادم'),
          child: const ServerSettingsScreen(),
        ),
      if (_visibleTabKeys.contains('updates'))
        _AdminPanelTabData(
          label: 'التحديث',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.update_outlined),
            selectedIcon: Icon(Icons.update),
            label: Text('التحديث'),
          ),
          mobileTab: const Tab(text: 'التحديث'),
          child: const UpdateManagementScreen(),
        ),
      if (_visibleTabKeys.contains('backups'))
        _AdminPanelTabData(
          label: 'النسخ الاحتياطي',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.backup_outlined),
            selectedIcon: Icon(Icons.backup),
            label: Text('النسخ الاحتياطي'),
          ),
          mobileTab: const Tab(text: 'نسخ احتياطي'),
          child: const BackupScreen(),
        ),
      if (_visibleTabKeys.contains('reports'))
        _AdminPanelTabData(
          label: 'قوالب التقارير',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.table_view_outlined),
            selectedIcon: Icon(Icons.table_view),
            label: Text('قوالب التقارير'),
          ),
          mobileTab: const Tab(text: 'قوالب التقارير'),
          child: const ReportTemplatesScreen(),
        ),
    ];

    if (tabs.isNotEmpty) {
      return tabs;
    }

    return const <_AdminPanelTabData>[
      _AdminPanelTabData(
        label: 'غير متاح',
        destination: NavigationRailDestination(
          icon: Icon(Icons.block_outlined),
          selectedIcon: Icon(Icons.block),
          label: Text('غير متاح'),
        ),
        mobileTab: Tab(text: 'غير متاح'),
        child: _PermissionDeniedTab(),
      ),
    ];
  }

  void _handleTabChanged() {
    if (!_tabController.indexIsChanging) {
      widget.onTabChanged?.call(_tabController.index);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _rebuildTabController({int? preferredIndex}) {
    final nextTabs = _allowedTabKeys();
    final nextIndex = (preferredIndex ?? _tabControllerOrNull?.index ?? 0)
        .clamp(0, nextTabs.length - 1);
    final previous = _tabControllerOrNull;
    previous?.removeListener(_handleTabChanged);
    _tabController = TabController(
      length: nextTabs.length,
      vsync: this,
      initialIndex: nextIndex,
    );
    _tabController.addListener(_handleTabChanged);
    _visibleTabKeys = nextTabs;
    previous?.dispose();
  }

  TabController? get _tabControllerOrNull {
    try {
      return _tabController;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 1100;
    final isTablet = size.width >= 800;
    final visibleTabs = _buildVisibleTabs(
      announcementsState: ref.watch(adminAnnouncementsControllerProvider),
      documentsState: ref.watch(adminDocumentsControllerProvider),
    );
    final navDestinations = visibleTabs
        .map((entry) => entry.destination)
        .toList();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Row(
        children: [
          if (isTablet)
            NavigationRail(
              extended: isDesktop,
              selectedIndex: _tabController.index,
              onDestinationSelected: (index) => _tabController.animateTo(index),
              destinations: navDestinations,
              backgroundColor: theme.colorScheme.surfaceContainerLow,
              selectedLabelTextStyle: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelTextStyle: theme.textTheme.labelLarge,
            ),
          if (isTablet)
            VerticalDivider(
              thickness: 1,
              width: 1,
              color: theme.dividerColor.withOpacity(0.2),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    border: Border(
                      bottom: BorderSide(
                        color: theme.dividerColor.withOpacity(0.2),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (!isTablet)
                        Expanded(
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            dividerColor: Colors.transparent,
                            tabs: visibleTabs
                                .map((entry) => entry.mobileTab)
                                .toList(),
                          ),
                        )
                      else
                        Expanded(
                          child: Text(
                            (navDestinations[_tabController.index].label
                                        as Text)
                                    .data ??
                                'لوحة الإدارة',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      const SizedBox(width: 16),
                      FilledButton.tonalIcon(
                        onPressed: _refreshAll,
                        icon: const Icon(Iconsax.refresh),
                        label: const Text('تحديث'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: isTablet
                        ? const NeverScrollableScrollPhysics()
                        : const ScrollPhysics(),
                    children: visibleTabs.map((entry) => entry.child).toList(),
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

class _AdminLoadResult<T> {
  const _AdminLoadResult({
    required this.items,
    required this.emptyMessage,
    this.errorMessage,
  });

  final List<T> items;
  final String emptyMessage;
  final String? errorMessage;

  bool get hasError => errorMessage != null && errorMessage!.trim().isNotEmpty;
}

class _AdminPanelTabData {
  const _AdminPanelTabData({
    required this.label,
    required this.destination,
    required this.mobileTab,
    required this.child,
  });

  final String label;
  final NavigationRailDestination destination;
  final Tab mobileTab;
  final Widget child;
}

class _PermissionDeniedTab extends StatelessWidget {
  const _PermissionDeniedTab();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('ليس لديك صلاحية لفتح هذه الصفحة'));
  }
}

// ---------------- Helper for consistent TextFields in Dialogs ----------------
InputDecoration _dialogInputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    filled: true,
  );
}

// ─── Apple Minimalist Admin Dialog Components for Desktop ─────────────────────

class _AppleAdminDialog extends StatelessWidget {
  const _AppleAdminDialog({
    required this.badgeIcon,
    required this.badgeColor,
    required this.title,
    this.subtitle,
    required this.content,
    required this.actions,
    this.maxWidth = 520,
  });

  final IconData badgeIcon;
  final Color badgeColor;
  final String title;
  final String? subtitle;
  final Widget content;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E222A) : Colors.white;

    return Dialog(
      backgroundColor: bg,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 18, 16),
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
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
    final bg = isDark ? const Color(0xFF1E222A) : Colors.white;

    return Dialog(
      backgroundColor: bg,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
          padding: const EdgeInsets.all(24),
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
                      ? const Color(0xFF2C323D)
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
    final fill = isDark ? const Color(0xFF282D37) : const Color(0xFFF8FAFC);
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
            fontSize: 13.5,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
            ),
            filled: true,
            fillColor: enabled
                ? fill
                : (isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
            prefixIcon: prefixIcon != null
                ? Icon(
                    prefixIcon,
                    size: 18,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  )
                : null,
            suffixIcon: suffix,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
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
    final fill = isDark ? const Color(0xFF282D37) : const Color(0xFFF8FAFC);
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
            fontSize: 13.5,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          dropdownColor: isDark ? const Color(0xFF232832) : Colors.white,
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
                    size: 18,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
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

class _PermissionToggleCard extends StatelessWidget {
  const _PermissionToggleCard({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.color,
    this.disabled = false,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color color;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = color.withValues(alpha: isDark ? 0.18 : 0.1);
    final inactiveBg = isDark ? const Color(0xFF282D37) : const Color(0xFFF8FAFC);
    final activeBorder = color.withValues(alpha: 0.45);
    final inactiveBorder = isDark ? Colors.white10 : const Color(0xFFE2E8F0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : () => onChanged?.call(!value),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: value ? activeBg : inactiveBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: value ? activeBorder : inactiveBorder,
              width: value ? 1.2 : 0.8,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: value ? FontWeight.w700 : FontWeight.w500,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: value,
                  activeColor: color,
                  onChanged: disabled ? null : onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Admin Documents Tab ----------------

class _AdminDocumentsTab extends ConsumerStatefulWidget {
  const _AdminDocumentsTab({required this.documentsState});

  final AsyncValue<List<RemoteDocument>> documentsState;

  @override
  ConsumerState<_AdminDocumentsTab> createState() => _AdminDocumentsTabState();
}

class _AdminDocumentsTabState extends ConsumerState<_AdminDocumentsTab> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final query = _searchController.text.trim();
      ref.read(adminDocumentsControllerProvider.notifier).setSearch(
            query.isEmpty ? null : query,
          );
    });
    setState(() {});
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
        subtitle: 'تعديل اسم الملف المعروض في قائمة المستندات',
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty || !mounted) return;
    try {
      final docRepository = ref.read(documentRepositoryProvider);
      final adminDocsController = ref.read(
        adminDocumentsControllerProvider.notifier,
      );
      await docRepository.renameDocument(document.id, result);
      await adminDocsController.refresh();
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
                'هل أنت متأكد من حذف "${document.fileName}"؟ لن يتمكن الموظفون من الوصول إليه بعد الحذف.',
            onConfirm: () => Navigator.pop(context, true),
          ),
        ) ??
        false;

    if (!shouldDelete || !mounted) return;

    try {
      final docRepository = ref.read(documentRepositoryProvider);
      final adminDocsController = ref.read(
        adminDocumentsControllerProvider.notifier,
      );
      await docRepository.deleteDocument(document.id);
      await adminDocsController.refresh();
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
    final docsState = ref.watch(adminDocumentsControllerProvider);
    final docsNotifier = ref.watch(adminDocumentsControllerProvider.notifier);
    final hasMore = docsNotifier.hasMore;
    final isLoadingMore = docsNotifier.isLoadingMore;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: _dialogInputDecoration(
                    'ابحث باسم الملف أو صاحبه',
                  ).copyWith(
                    prefixIcon: const Icon(Iconsax.search_normal),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: () => ref
                    .read(adminDocumentsControllerProvider.notifier)
                    .refresh(),
                icon: const Icon(Iconsax.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: docsState.when(
              loading: () => const _AdminTableLoadingShimmer(),
              error: (error, stackTrace) =>
                  Center(child: Text(error.toString())),
              data: (documents) {
                final filtered = _filter(documents);
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Iconsax.document_text_1,
                          size: 48,
                          color: Theme.of(context).disabledColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _searchController.text.isNotEmpty
                              ? 'لا توجد ملفات تطابق بحثك'
                              : 'لا توجد ملفات حالياً',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).hintColor,
                              ),
                        ),
                      ],
                    ),
                  );
                }
                return Card(
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(0.5),
                    ),
                  ),
                  child: ListView.separated(
                    itemCount: filtered.length + (hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Theme.of(context).dividerColor.withOpacity(0.3),
                    ),
                    itemBuilder: (context, index) {
                      if (index == filtered.length) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: isLoadingMore
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                )
                              : OutlinedButton.icon(
                                  onPressed: () => ref
                                      .read(
                                        adminDocumentsControllerProvider
                                            .notifier,
                                      )
                                      .loadMore(),
                                  icon: const Icon(Icons.expand_more_rounded),
                                  label: const Text('تحميل المزيد'),
                                ),
                        );
                      }
                      final document = filtered[index];
                      final owner =
                          document.ownerFullName?.trim().isNotEmpty == true
                          ? document.ownerFullName!
                          : (document.ownerUsername ?? 'غير معروف');
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Text(
                          document.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$owner • ${document.pageCount} صفحة • ${formatFileSize(document.fileSize)} • ${formatDate(document.createdAt)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'فتح',
                              onPressed: () => _downloadAndOpen(document),
                              icon: const Icon(Iconsax.folder_open5),
                            ),
                            IconButton(
                              tooltip: 'إعادة تسمية',
                              onPressed: () => _renameDocument(document),
                              icon: const Icon(Iconsax.edit),
                            ),
                            IconButton(
                              tooltip: 'حذف',
                              onPressed: () => _deleteDocument(document),
                              icon: Icon(
                                Iconsax.note_remove5,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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

// ---------------- Users Admin Tab ----------------

String _departmentName(List<DepartmentSummary> departments, String? id) {
  if (id == null) return 'بدون قسم';
  return departments
          .where((department) => department.id == id)
          .map((department) => department.name)
          .firstOrNull ??
      'بدون قسم';
}

List<String> _managedUserDepartmentIds(ManagedUser user) {
  if (user.departmentIds.isNotEmpty) {
    return user.departmentIds;
  }
  return [if (user.departmentId != null) user.departmentId!];
}

String _managedUserDepartmentNames(
  List<DepartmentSummary> departments,
  ManagedUser user,
) {
  final ids = _managedUserDepartmentIds(user);
  if (ids.isEmpty) {
    return _departmentName(departments, null);
  }
  final names = ids
      .map((id) => _departmentName(departments, id))
      .where((name) => name.trim().isNotEmpty)
      .toSet()
      .toList();
  return names.isEmpty ? _departmentName(departments, null) : names.join('، ');
}

String _branchName(List<BranchSummary> branches, String? id) {
  if (id == null) return 'بدون فرع';
  return branches
          .where((branch) => branch.id == id)
          .map((branch) => branch.name)
          .firstOrNull ??
      'بدون فرع';
}

class _UsersAdminTab extends ConsumerStatefulWidget {
  const _UsersAdminTab({
    required this.departments,
    required this.branches,
    required this.usersState,
  });

  final List<DepartmentSummary> departments;
  final List<BranchSummary> branches;
  final AsyncValue<List<ManagedUser>> usersState;

  @override
  ConsumerState<_UsersAdminTab> createState() => _UsersAdminTabState();
}

class _UsersAdminTabState extends ConsumerState<_UsersAdminTab> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;
  String? _departmentFilter;
  String? _branchFilter;
  String? _roleFilter;
  String _statusFilter = 'all';

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _applyFilters();
    });
    setState(() {});
  }

  void _applyFilters() {
    if (!mounted) return;
    final query = _searchController.text.trim();
    ref.read(usersControllerProvider.notifier).setFilters(
          search: query.isEmpty ? null : query,
          departmentId: _departmentFilter,
          branchId: _branchFilter,
          role: _roleFilter,
          status: _statusFilter == 'all' ? null : _statusFilter,
        );
  }

  List<ManagedUser> _filterUsers(List<ManagedUser> users) {
    final query = _searchController.text.trim().toLowerCase();
    return users.where((user) {
      final departmentName = _managedUserDepartmentNames(
        widget.departments,
        user,
      ).toLowerCase();
      final branchName = _branchName(
        widget.branches,
        user.branchId,
      ).toLowerCase();
      final searchable =
          '${user.username} ${user.fullName} ${user.branchCode} $departmentName $branchName'
              .toLowerCase();
      if (query.isNotEmpty && !searchable.contains(query)) return false;
      if (_departmentFilter != null &&
          !_managedUserDepartmentIds(user).contains(_departmentFilter)) {
        return false;
      }
      if (_branchFilter != null && user.branchId != _branchFilter) {
        return false;
      }
      if (_roleFilter != null && user.role != _roleFilter) return false;
      if (_statusFilter == 'active' && !user.isActive) return false;
      if (_statusFilter == 'inactive' && user.isActive) return false;
      return true;
    }).toList();
  }

  Future<void> _deleteUser(BuildContext context, ManagedUser user) async {
    final displayName = user.fullName.isEmpty ? user.username : user.fullName;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => _AppleDangerDialog(
        title: 'حذف المستخدم نهائياً',
        subtitle: 'إزالة حساب $displayName من قاعدة البيانات',
        message:
            'هل أنت متأكد من حذف الحساب؟ سيتم إلغاء وصول الموظف وإزالة كافة الجلسات المرتبطة به.',
        onConfirm: () => Navigator.pop(context, true),
      ),
    );
    if (approved != true || !mounted) return;
    try {
      final userRepository = ref.read(userManagementRepositoryProvider);
      final usersController = ref.read(usersControllerProvider.notifier);
      final overviewController = ref.read(
        chatOverviewControllerProvider.notifier,
      );
      await userRepository.deleteUser(user.id);
      await usersController.refresh();
      await overviewController.refresh();
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('تم حذف المستخدم بنجاح')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _forceLogoutAll(BuildContext context, ManagedUser user) async {
    final displayName = user.fullName.isEmpty ? user.username : user.fullName;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => _AppleDangerDialog(
        title: 'تسجيل خروج من كل الأجهزة',
        subtitle: 'إنهاء الجلسات النشطة لـ $displayName',
        confirmLabel: 'تسجيل الخروج',
        message:
            'سيتم إبطال كافة مفاتيح الدخول الفعالة للمستخدم عبر كل أجهزة الكمبيوتر والهواتف فوراً.',
        onConfirm: () => Navigator.pop(context, true),
      ),
    );
    if (approved != true || !mounted) return;
    try {
      final userRepository = ref.read(userManagementRepositoryProvider);
      final usersController = ref.read(usersControllerProvider.notifier);
      await userRepository.forceLogoutAllDevices(user.id);
      await usersController.refresh();
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل خروج المستخدم من جميع الأجهزة بنجاح'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

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
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return _AppleAdminDialog(
            badgeIcon: Icons.key_rounded,
            badgeColor: const Color(0xFFF59E0B),
            title: 'إعادة تعيين كلمة المرور',
            subtitle: 'تغيير رمز المرور لحساب: $displayName',
            maxWidth: 460,
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
                  'سيتم إلزام المستخدم باستخدام كلمة المرور الجديدة لتسجيل الدخول التالي.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
              ),
            ],
          );
        },
      ),
    );
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
    final maxAttachmentSizeMBController = TextEditingController(
      text: user?.maxAttachmentSizeMB.toString() ?? '20',
    );
    final permissions = Map<String, bool>.from(user?.permissions ?? const {});
    var obscurePassword = true;

    const permissionLabels = <String, String>{
      'canCreateUsers': 'إدارة المستخدمين',
      'canCreateDepartments': 'إدارة الأقسام',
      'canManageBranches': 'إدارة الفروع',
      'canCreateRooms': 'إنشاء غرف',
      'canSendBroadcast': 'إرسال بث',
      'canDeleteMessages': 'حذف رسائل',
      'canUploadFiles': 'رفع ملفات',
      'canModerateDepartment': 'إدارة محادثات القسم',
      'canViewDepartmentLogs': 'عرض السجل',
      'canManageAnnouncements': 'إدارة الإعلانات',
      'canManageFiles': 'إدارة الملفات',
      'canManageRoles': 'إدارة الصلاحيات',
      'canManageSystem': 'إعدادات الخادم',
      'canManageUpdates': 'إدارة التحديثات',
      'canManageBackups': 'النسخ الاحتياطي',
      'canManageTickets': 'إدارة التذاكر',
      'canViewPrinters': 'عرض صفحة الطابعات',
      'canManagePrinters': 'إدارة فروع الطابعات',
      'canSyncPrinters': 'مزامنة الطابعات',
      'canExportPrinterReports': 'تصدير تقارير الطابعات',
      'canViewSnipeit': 'عرض صفحة Snipe-IT',
      'canViewSystemMonitor': 'مراقبة النظام',
    };

    final permissionCategories = [
      (
        title: 'صلاحيات المحادثات والملفات',
        icon: Icons.chat_bubble_outline_rounded,
        color: const Color(0xFF007AFF),
        keys: [
          'canCreateRooms',
          'canSendBroadcast',
          'canDeleteMessages',
          'canUploadFiles',
          'canModerateDepartment',
          'canViewDepartmentLogs',
          'canManageAnnouncements',
          'canManageFiles',
        ],
      ),
      (
        title: 'صلاحيات الطابعات والتقارير',
        icon: Icons.print_outlined,
        color: const Color(0xFF34C759),
        keys: [
          'canViewPrinters',
          'canManagePrinters',
          'canSyncPrinters',
          'canExportPrinterReports',
        ],
      ),
      (
        title: 'صلاحيات التذاكر والأصول والنظام',
        icon: Icons.confirmation_number_outlined,
        color: const Color(0xFFF59E0B),
        keys: [
          'canManageTickets',
          'canViewSnipeit',
          'canViewSystemMonitor',
        ],
      ),
      (
        title: 'صلاحيات الإدارة والتحكم الكامل',
        icon: Icons.admin_panel_settings_outlined,
        color: const Color(0xFF9333EA),
        keys: [
          'canCreateUsers',
          'canCreateDepartments',
          'canManageBranches',
          'canManageRoles',
          'canManageSystem',
          'canManageUpdates',
          'canManageBackups',
        ],
      ),
    ];

    Map<String, bool> resolvePermissionsForRole() {
      if (role != 'admin') {
        return permissions;
      }
      return {for (final key in permissionLabels.keys) key: true};
    }

    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final isAdminRole = role == 'admin';

          return _AppleAdminDialog(
            badgeIcon: user == null ? Icons.person_add_rounded : Icons.manage_accounts_rounded,
            badgeColor: const Color(0xFF0284C7),
            title: user == null ? 'إضافة مستخدم جديد' : 'تعديل بيانات المستخدم',
            subtitle: user == null
                ? 'إنشاء حساب موظف جديد وتعيين الدور والصلاحيات المخصصة'
                : 'تحديث بيانات الحساب وكلمة المرور وصلاحيات المنظومة',
            maxWidth: 720,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Two Column Form Layout
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
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
                            label: 'الاسم الكامل',
                            hint: 'الاسم الكامل باللغة العربية',
                            prefixIcon: Icons.badge_outlined,
                          ),
                          const SizedBox(height: 12),
                          _AppleDropdown<String>(
                            value: role,
                            label: 'الدور (Role)',
                            prefixIcon: Icons.shield_outlined,
                            enabled: !isSaving,
                            items: const [
                              DropdownMenuItem(value: 'user', child: Text('مستخدم عادي (User)')),
                              DropdownMenuItem(value: 'manager', child: Text('مدير قسم (Manager)')),
                              DropdownMenuItem(value: 'admin', child: Text('مسؤول نظام (Admin)')),
                            ],
                            onChanged: (val) => setLocalState(() {
                              role = val ?? role;
                              if (role == 'admin') {
                                for (final key in permissionLabels.keys) {
                                  permissions[key] = true;
                                }
                              }
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: [
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
                              ...widget.departments.map(
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
                              ...widget.branches.map(
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
                            label: user == null ? 'كلمة المرور' : 'كلمة مرور جديدة (اختياري)',
                            hint: user == null ? 'افتراضي 123456 أو 6 أحرف' : 'اتركها فارغة لعدم التغيير',
                            prefixIcon: Icons.lock_outline_rounded,
                            suffix: IconButton(
                              icon: Icon(
                                obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                size: 19,
                              ),
                              onPressed: () => setLocalState(() => obscurePassword = !obscurePassword),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: maxAttachmentSizeMBController,
                  enabled: !isSaving,
                  label: 'الحد الأقصى لحجم المرفقات (بالميجابايت)',
                  hint: 'القيمة الافتراضية 20 ميجابايت',
                  prefixIcon: Icons.attachment_rounded,
                ),
                const SizedBox(height: 18),

                // ── Permissions Header & Notice ──
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 18, color: Color(0xFF007AFF)),
                    const SizedBox(width: 8),
                    const Text(
                      'صلاحيات المستخدم المخصصة في النظام',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    if (isAdminRole)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'مسؤول النظام يمتلك كافة الصلاحيات تلقائياً',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEA580C)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Categorized Grid of Toggle Cards ──
                ...permissionCategories.map((category) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF232832) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(category.icon, size: 16, color: category.color),
                            const SizedBox(width: 8),
                            Text(
                              category.title,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: category.color,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            mainAxisExtent: 44,
                          ),
                          itemCount: category.keys.length,
                          itemBuilder: (ctx, idx) {
                            final key = category.keys[idx];
                            final label = permissionLabels[key] ?? key;
                            final isEnabled = isAdminRole ? true : (permissions[key] == true);

                            return _PermissionToggleCard(
                              title: label,
                              value: isEnabled,
                              color: category.color,
                              disabled: isSaving || isAdminRole,
                              onChanged: (val) {
                                setLocalState(() => permissions[key] = val);
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  );
                }),

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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                          setLocalState(() => errorText = 'اسم المستخدم مطلوب.');
                          return;
                        }
                        if (fullName.isEmpty) {
                          setLocalState(() => errorText = 'الاسم الكامل مطلوب.');
                          return;
                        }
                        if (password.isNotEmpty && password.length < 6) {
                          setLocalState(
                            () => errorText =
                                'كلمة المرور يجب أن تكون 6 أحرف على الأقل.',
                          );
                          return;
                        }
                        setLocalState(() {
                          isSaving = true;
                          errorText = null;
                        });
                        try {
                          final effectivePermissions =
                              resolvePermissionsForRole();
                          final maxAttachmentSizeMB = int.tryParse(maxAttachmentSizeMBController.text.trim()) ?? 20;
                          if (user == null) {
                            await userRepository.createUser(
                              username: username,
                              fullName: fullName,
                              password: password.isEmpty ? '123456' : password,
                              role: role,
                              departmentId: departmentId,
                              branchId: branchId,
                              maxAttachmentSizeMB: maxAttachmentSizeMB,
                              permissions: effectivePermissions,
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
                              maxAttachmentSizeMB: maxAttachmentSizeMB,
                              permissions: effectivePermissions,
                            );
                          }
                          if (context.mounted) Navigator.pop(context, true);
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
                    : Text(user == null ? 'إنشاء المستخدم' : 'حفظ التعديلات'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
              ),
            ],
          );
        },
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
  Widget build(BuildContext context) {
    final usersState = ref.watch(usersControllerProvider);
    final usersNotifier = ref.watch(usersControllerProvider.notifier);
    final hasMore = usersNotifier.hasMore;
    final isLoadingMore = usersNotifier.isLoadingMore;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => _showUserDialog(context, ref),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('إضافة مستخدم'),
              ),
              const Spacer(),
              IconButton.filledTonal(
                onPressed: () =>
                    ref.read(usersControllerProvider.notifier).refresh(),
                icon: const Icon(Iconsax.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: _dialogInputDecoration(
                    'بحث بالاسم أو الفرع أو القسم أو اسم المستخدم',
                  ).copyWith(
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _departmentFilter,
                  decoration: _dialogInputDecoration('القسم'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('كل الأقسام'),
                    ),
                    ...widget.departments.map(
                      (department) => DropdownMenuItem<String?>(
                        value: department.id,
                        child: Text(department.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _departmentFilter = value);
                    _applyFilters();
                  },
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _branchFilter,
                  decoration: _dialogInputDecoration('الفرع'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('كل الفروع'),
                    ),
                    ...widget.branches.map(
                      (branch) => DropdownMenuItem<String?>(
                        value: branch.id,
                        child: Text(branch.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _branchFilter = value);
                    _applyFilters();
                  },
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _roleFilter,
                  decoration: _dialogInputDecoration('الدور'),
                  items: const [
                    DropdownMenuItem<String?>(value: null, child: Text('الكل')),
                    DropdownMenuItem(value: 'admin', child: Text('admin')),
                    DropdownMenuItem(value: 'manager', child: Text('manager')),
                    DropdownMenuItem(value: 'user', child: Text('user')),
                  ],
                  onChanged: (value) {
                    setState(() => _roleFilter = value);
                    _applyFilters();
                  },
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _statusFilter,
                  decoration: _dialogInputDecoration('الحالة'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('الكل')),
                    DropdownMenuItem(value: 'active', child: Text('نشط')),
                    DropdownMenuItem(value: 'inactive', child: Text('موقوف')),
                  ],
                  onChanged: (value) {
                    setState(() => _statusFilter = value ?? 'all');
                    _applyFilters();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: usersState.when(
              loading: () => const _AdminTableLoadingShimmer(),
              error: (error, stackTrace) =>
                  Center(child: Text(error.toString())),
              data: (users) {
                final filteredUsers = _filterUsers(users);
                if (filteredUsers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Iconsax.user_remove,
                          size: 48,
                          color: Theme.of(context).disabledColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _searchController.text.isNotEmpty ||
                                  _departmentFilter != null ||
                                  _branchFilter != null ||
                                  _roleFilter != null ||
                                  _statusFilter != 'all'
                              ? 'لا توجد نتائج تطابق معايير البحث'
                              : 'لا يوجد مستخدمون حالياً',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).hintColor,
                              ),
                        ),
                      ],
                    ),
                  );
                }
                return Card(
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(0.5),
                    ),
                  ),
                  child: ListView.separated(
                    itemCount: filteredUsers.length + (hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Theme.of(context).dividerColor.withOpacity(0.3),
                    ),
                    itemBuilder: (context, index) {
                      if (index == filteredUsers.length) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: isLoadingMore
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                )
                              : OutlinedButton.icon(
                                  onPressed: () => ref
                                      .read(usersControllerProvider.notifier)
                                      .loadMore(),
                                  icon: const Icon(Icons.expand_more_rounded),
                                  label: const Text('تحميل المزيد'),
                                ),
                        );
                      }
                      final user = filteredUsers[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Text(
                          user.fullName.isEmpty ? user.username : user.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${user.username} • ${user.role} • ${_managedUserDepartmentNames(widget.departments, user)} • ${_branchName(widget.branches, user.branchId)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        leading: Chip(
                          label: Text(user.isActive ? 'نشط' : 'موقوف'),
                          backgroundColor: user.isActive
                              ? Colors.green.withOpacity(0.1)
                              : Theme.of(
                                  context,
                                ).colorScheme.error.withOpacity(0.1),
                        ),
                        trailing: SizedBox(
                          width: 270,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: 'فرض تسجيل خروج من كل الأجهزة',
                                color: const Color(0xFFDC2626),
                                onPressed: () => _forceLogoutAll(context, user),
                                icon: const Icon(Icons.phonelink_erase_rounded),
                              ),
                              IconButton(
                                tooltip: 'إعادة تعيين كلمة المرور',
                                onPressed: () => _showResetPasswordDialog(
                                  context,
                                  ref,
                                  user,
                                ),
                                icon: const Icon(Iconsax.lock4),
                              ),
                              IconButton(
                                tooltip: 'تعديل',
                                onPressed: () =>
                                    _showUserDialog(context, ref, user: user),
                                icon: const Icon(Iconsax.edit),
                              ),
                              IconButton(
                                tooltip: 'حذف المستخدم',
                                color: Theme.of(context).colorScheme.error,
                                onPressed: () => _deleteUser(context, user),
                                icon: const Icon(Icons.delete_outline),
                              ),
                              _ManagedUserStatusSwitch(
                                userId: user.id,
                                isActive: user.isActive,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
    if (!mounted) return;
    final previousValue = _isActive;
    final userRepository = ref.read(userManagementRepositoryProvider);
    final usersController = ref.read(usersControllerProvider.notifier);
    final overviewController = ref.read(
      chatOverviewControllerProvider.notifier,
    );
    setState(() {
      _isSaving = true;
      _isActive = value;
    });
    try {
      await userRepository.updateUserStatus(
        userId: widget.userId,
        isActive: value,
      );
      await usersController.refresh();
      await overviewController.refresh();
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
      setState(() => _isActive = previousValue);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
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

// ---------------- Branches Admin Tab ----------------

class _BranchesAdminTab extends ConsumerStatefulWidget {
  const _BranchesAdminTab({required this.branches});

  final List<BranchSummary> branches;

  @override
  ConsumerState<_BranchesAdminTab> createState() => _BranchesAdminTabState();
}

class _BranchesAdminTabState extends ConsumerState<_BranchesAdminTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BranchSummary> _filteredBranches() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.branches;
    }
    return widget.branches.where((branch) {
      return branch.name.toLowerCase().contains(query) ||
          branch.code.toLowerCase().contains(query) ||
          branch.description.toLowerCase().contains(query);
    }).toList();
  }

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
        builder: (context, setLocalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final previewName = nameController.text.trim().isEmpty
              ? 'اسم الفرع يظهر هنا'
              : nameController.text.trim();
          final previewCode = codeController.text.trim().isEmpty
              ? 'CODE'
              : codeController.text.trim().toUpperCase();

          return _AppleAdminDialog(
            badgeIcon: branch == null
                ? Icons.add_location_alt_rounded
                : Icons.edit_location_alt_rounded,
            badgeColor: const Color(0xFF0EA5E9),
            title: branch == null ? 'إضافة فرع جديد' : 'تعديل بيانات الفرع',
            subtitle: branch == null
                ? 'أدخل اسم الفرع وكوده التعريفي لربط الموظفين والطابعات به'
                : 'تحديث الاسم أو الكود أو الوصف الخاص بفرع "${branch.name}"',
            maxWidth: 500,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Live Preview Pill
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF282D37)
                        : const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF0EA5E9).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: Color(0xFF0EA5E9),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              previewName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              descriptionController.text.trim().isEmpty
                                  ? 'معاينة بطاقة الفرع في النظام'
                                  : descriptionController.text.trim(),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          previewCode,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0EA5E9),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: StatefulBuilder(
                        builder: (ctx, _) => _AppleTextField(
                          controller: nameController,
                          label: 'اسم الفرع *',
                          hint: 'مثال: الفرع الرئيسي - القاهرة',
                          prefixIcon: Icons.storefront_outlined,
                          enabled: !isSaving,
                          autofocus: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _AppleTextField(
                        controller: codeController,
                        label: 'كود الفرع *',
                        hint: 'CAI-01',
                        prefixIcon: Icons.qr_code_rounded,
                        enabled: !isSaving,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _AppleTextField(
                  controller: descriptionController,
                  label: 'وصف وموقع الفرع (اختياري)',
                  hint: 'مثال: المبنى الإداري - الدور الثالث',
                  prefixIcon: Icons.notes_rounded,
                  minLines: 2,
                  maxLines: 3,
                  enabled: !isSaving,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
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
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0EA5E9),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ButtonLoadingIndicator(),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  branch == null ? 'إنشاء الفرع' : 'حفظ التعديلات',
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
            branch == null ? 'تم إنشاء الفرع بنجاح.' : 'تم تحديث الفرع بنجاح.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches = _filteredBranches();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalMembers = widget.branches.fold<int>(
      0,
      (sum, item) => sum + item.membersCount,
    );
    final pageBg = isDark ? const Color(0xFF0B0F17) : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF151C28) : Colors.white;
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.06);
    const accent = Color(0xFF0EA5E9);

    return Container(
      color: pageBg,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderCol),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.account_tree_rounded,
                        color: accent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'إدارة الفروع والمواقع الجغرافية',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'تنظيم فروع المؤسسة وأكوادها التعريفية وتوزيع الموظفين والطابعات عليها',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _AdminStatPill(
                      icon: Icons.storefront_rounded,
                      label: 'إجمالي الفروع',
                      value: '${widget.branches.length}',
                      color: accent,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 10),
                    _AdminStatPill(
                      icon: Iconsax.people,
                      label: 'إجمالي الأعضاء',
                      value: '$totalMembers',
                      color: const Color(0xFF10B981),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => _showBranchDialog(context, ref),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Iconsax.add, size: 18),
                      label: const Text(
                        'إضافة فرع جديد',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'ابحث باسم الفرع أو الكود أو الوصف...',
                    prefixIcon: const Icon(Iconsax.search_normal_1, size: 18),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          )
                        : null,
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF2F2F7),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: branches.isEmpty
                ? _AdminEmptyBentoState(
                    icon: Icons.account_tree_outlined,
                    title: 'لا توجد فروع مطابقة',
                    subtitle:
                        'اضغط على "إضافة فرع جديد" لإضافة فروع المؤسسة وربط الموظفين بها.',
                    isDark: isDark,
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 430,
                          mainAxisExtent: 176,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                    itemCount: branches.length,
                    itemBuilder: (context, index) {
                      final branch = branches[index];
                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderCol),
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
                                    color: accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.storefront_rounded,
                                    color: accent,
                                    size: 21,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        branch.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          branch.code,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: accent,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'تعديل الفرع',
                                  onPressed: () => _showBranchDialog(
                                    context,
                                    ref,
                                    branch: branch,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.black.withValues(alpha: 0.04),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(Iconsax.edit_2, size: 17),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: 'حذف الفرع',
                                  onPressed: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => _AppleDangerDialog(
                                        title: 'حذف الفرع',
                                        subtitle: 'تأكيد إزالة الفرع من النظام',
                                        message:
                                            'هل أنت متأكد من حذف فرع "${branch.name}" (${branch.code})؟ لن يتم حذف الأجهزة أو الموظفين.',
                                        onConfirm: () =>
                                            Navigator.pop(ctx, true),
                                      ),
                                    );
                                    if (confirmed != true ||
                                        !context.mounted ||
                                        !mounted) {
                                      return;
                                    }
                                    try {
                                      await ref
                                          .read(
                                            chatOverviewControllerProvider
                                                .notifier,
                                          )
                                          .deleteBranch(branch.id);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('تم حذف الفرع بنجاح'),
                                        ),
                                      );
                                    } catch (error) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(error.toString()),
                                        ),
                                      );
                                    }
                                  },
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(
                                      0xFFFF3B30,
                                    ).withValues(alpha: 0.1),
                                    foregroundColor: const Color(0xFFFF3B30),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(Iconsax.trash, size: 17),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: Text(
                                branch.description.trim().isEmpty
                                    ? 'لا يوجد وصف إضافي مسجل لهذا الفرع.'
                                    : branch.description,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Divider(height: 16, color: borderCol),
                            Row(
                              children: [
                                Icon(
                                  Iconsax.people,
                                  size: 15,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${branch.membersCount} موظف مسجل في هذا الفرع',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                ),
                              ],
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

// ---------------- Announcements Tab ----------------

class _AnnouncementsAdminTab extends ConsumerStatefulWidget {
  const _AnnouncementsAdminTab({required this.announcementsState});
  final AsyncValue<List<AdminAnnouncement>> announcementsState;

  @override
  ConsumerState<_AnnouncementsAdminTab> createState() =>
      _AnnouncementsAdminTabState();
}

class _AnnouncementsAdminTabState
    extends ConsumerState<_AnnouncementsAdminTab> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedToneFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _toneColor(BuildContext context, String tone) {
    return switch (tone) {
      'success' => const Color(0xFF10B981),
      'warning' => const Color(0xFFF59E0B),
      'critical' => const Color(0xFFEF4444),
      _ => const Color(0xFF007AFF),
    };
  }

  IconData _toneIcon(String tone) {
    return switch (tone) {
      'success' => Iconsax.tick_circle,
      'warning' => Iconsax.warning_2,
      'critical' => Iconsax.danger,
      _ => Iconsax.info_circle,
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
          final activeToneColor = _toneColor(context, tone);
          final previewTitle = titleController.text.trim().isEmpty
              ? 'عنوان الإعلان سيظهر هنا'
              : titleController.text.trim();
          final previewMsg = messageController.text.trim().isEmpty
              ? 'نص الإعلان سيظهر هنا لجميع الموظفين في الشريط العلوي...'
              : messageController.text.trim();

          Widget toneOptionCard({
            required String value,
            required String label,
            required IconData icon,
            required Color color,
          }) {
            final selected = tone == value;
            return Expanded(
              child: InkWell(
                onTap: isSaving
                    ? null
                    : () => setLocalState(() => tone = value),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.15)
                        : (isDark
                              ? const Color(0xFF282D37)
                              : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? color
                          : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                      width: selected ? 1.5 : 0.8,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        icon,
                        color: selected
                            ? color
                            : (isDark ? Colors.white54 : Colors.black45),
                        size: 20,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: selected
                              ? color
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return _AppleAdminDialog(
            badgeIcon: Icons.campaign_rounded,
            badgeColor: activeToneColor,
            title: announcement == null
                ? 'نشر إعلان إداري جديد'
                : 'تعديل الإعلان الإداري',
            subtitle:
                'يظهر الإعلان بشكل فوري لجميع الموظفين في أعلى شاشة المحادثات',
            maxWidth: 580,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Live Announcement Preview Banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: activeToneColor.withValues(
                      alpha: isDark ? 0.14 : 0.08,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: activeToneColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: activeToneColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _toneIcon(tone),
                          color: activeToneColor,
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
                                Expanded(
                                  child: Text(
                                    previewTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: activeToneColor.withValues(
                                      alpha: 0.18,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _toneLabel(tone),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: activeToneColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              previewMsg,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _AppleTextField(
                  controller: titleController,
                  label: 'عنوان الإعلان *',
                  hint: 'مثال: تحديث مواعيد العمل الرسمية',
                  prefixIcon: Icons.title_rounded,
                  enabled: !isSaving,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: messageController,
                  label: 'تفاصيل ونص الإعلان *',
                  hint: 'اكتب تفاصيل الإعلان بوضوح هنا...',
                  prefixIcon: Icons.subject_rounded,
                  minLines: 3,
                  maxLines: 5,
                  enabled: !isSaving,
                ),
                const SizedBox(height: 16),
                Text(
                  'مستوى ونوع الإعلان',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    toneOptionCard(
                      value: 'info',
                      label: 'معلومة',
                      icon: Iconsax.info_circle,
                      color: const Color(0xFF007AFF),
                    ),
                    const SizedBox(width: 8),
                    toneOptionCard(
                      value: 'success',
                      label: 'نجاح',
                      icon: Iconsax.tick_circle,
                      color: const Color(0xFF10B981),
                    ),
                    const SizedBox(width: 8),
                    toneOptionCard(
                      value: 'warning',
                      label: 'تنبيه',
                      icon: Iconsax.warning_2,
                      color: const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 8),
                    toneOptionCard(
                      value: 'critical',
                      label: 'عاجل',
                      icon: Iconsax.danger,
                      color: const Color(0xFFEF4444),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _PermissionToggleCard(
                        title: 'تثبيت في المقدمة 📌',
                        value: isPinned,
                        color: const Color(0xFFF59E0B),
                        disabled: isSaving,
                        onChanged: (v) => setLocalState(() => isPinned = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PermissionToggleCard(
                        title: 'إعلان نشط ومفعل ✅',
                        value: isActive,
                        color: const Color(0xFF10B981),
                        disabled: isSaving,
                        onChanged: (v) => setLocalState(() => isActive = v),
                      ),
                    ),
                  ],
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
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
                          setLocalState(
                            () => errorText =
                                'العنوان يجب أن يكون حرفين على الأقل.',
                          );
                          return;
                        }
                        if (message.length < 4) {
                          setLocalState(
                            () => errorText = 'نص الإعلان قصير جدًا.',
                          );
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
                style: FilledButton.styleFrom(
                  backgroundColor: activeToneColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ButtonLoadingIndicator(),
                      )
                    : const Icon(Icons.send_rounded, size: 17),
                label: Text(
                  announcement == null ? 'نشر الإعلان' : 'حفظ التعديلات',
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF0B0F17) : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF151C28) : Colors.white;
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.06);
    const accent = Color(0xFF007AFF);

    final allAnnouncements =
        widget.announcementsState.valueOrNull ?? const <AdminAnnouncement>[];
    final activeCount = allAnnouncements.where((a) => a.isActive).length;
    final pinnedCount = allAnnouncements.where((a) => a.isPinned).length;

    return Container(
      color: pageBg,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Header & Filter Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderCol),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.campaign_rounded,
                        color: accent,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'الإعلانات والتنبيهات العامة',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'بث التنبيهات العاجلة والتعاميم الإدارية في أعلى شاشة المحادثات لجميع الموظفين',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _AdminStatPill(
                      icon: Icons.campaign_outlined,
                      label: 'الإجمالي',
                      value: '${allAnnouncements.length}',
                      color: accent,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _AdminStatPill(
                      icon: Iconsax.tick_circle,
                      label: 'النشطة',
                      value: '$activeCount',
                      color: const Color(0xFF10B981),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _AdminStatPill(
                      icon: Icons.push_pin_rounded,
                      label: 'المثبتة',
                      value: '$pinnedCount',
                      color: const Color(0xFFF59E0B),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed: () => ref
                          .read(adminAnnouncementsControllerProvider.notifier)
                          .refresh(),
                      tooltip: 'تحديث القائمة',
                      style: IconButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Iconsax.refresh, size: 18),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: () => _showAnnouncementDialog(context, ref),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Iconsax.add_circle, size: 18),
                      label: const Text(
                        'نشر إعلان جديد',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'بحث في عنوان أو محتوى الإعلانات...',
                          prefixIcon: const Icon(
                            Iconsax.search_normal_1,
                            size: 18,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                )
                              : null,
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : const Color(0xFFF2F2F7),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final item in const [
                          ('all', 'الكل'),
                          ('info', 'معلومة'),
                          ('success', 'نجاح'),
                          ('warning', 'تنبيه'),
                          ('critical', 'عاجل'),
                        ])
                          ChoiceChip(
                            label: Text(item.$2),
                            selected: _selectedToneFilter == item.$1,
                            onSelected: (_) =>
                                setState(() => _selectedToneFilter = item.$1),
                            selectedColor: accent.withValues(alpha: 0.16),
                            labelStyle: TextStyle(
                              fontWeight: _selectedToneFilter == item.$1
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: 12,
                              color: _selectedToneFilter == item.$1
                                  ? accent
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            side: BorderSide(
                              color: _selectedToneFilter == item.$1
                                  ? accent
                                  : borderCol,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: widget.announcementsState.when(
              loading: () => const _AdminTableLoadingShimmer(),
              error: (error, stackTrace) =>
                  Center(child: Text(error.toString())),
              data: (announcements) {
                final query = _searchController.text.trim().toLowerCase();
                final filtered = announcements.where((a) {
                  if (_selectedToneFilter != 'all' &&
                      a.tone != _selectedToneFilter) {
                    return false;
                  }
                  if (query.isEmpty) return true;
                  return a.title.toLowerCase().contains(query) ||
                      a.message.toLowerCase().contains(query);
                }).toList();

                if (filtered.isEmpty) {
                  return _AdminEmptyBentoState(
                    icon: Icons.campaign_outlined,
                    title: 'لا توجد إعلانات لعرضها',
                    subtitle:
                        'اضغط على "نشر إعلان جديد" لإرسال تنبيه أو تعميم إداري للموظفين.',
                    isDark: isDark,
                  );
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final announcement = filtered[index];
                    final toneCol = _toneColor(context, announcement.tone);

                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: announcement.isPinned
                              ? toneCol.withValues(alpha: 0.45)
                              : borderCol,
                          width: announcement.isPinned ? 1.3 : 1,
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
                                  color: toneCol.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _toneIcon(announcement.tone),
                                  color: toneCol,
                                  size: 21,
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
                                            announcement.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: toneCol.withValues(
                                              alpha: 0.14,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            _toneLabel(announcement.tone),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: toneCol,
                                            ),
                                          ),
                                        ),
                                        if (announcement.isPinned) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(
                                                0xFFF59E0B,
                                              ).withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.push_pin_rounded,
                                                  size: 12,
                                                  color: Color(0xFFF59E0B),
                                                ),
                                                SizedBox(width: 3),
                                                Text(
                                                  'مثبت',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFFF59E0B),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'آخر تحديث: ${formatEgyptDateTime(announcement.updatedAt, separator: ' • ')}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: (announcement.isActive
                                          ? const Color(0xFF10B981)
                                          : Colors.grey)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  announcement.isActive ? 'نشط' : 'متوقف',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: announcement.isActive
                                        ? const Color(0xFF10B981)
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Switch(
                                value: announcement.isActive,
                                activeColor: const Color(0xFF10B981),
                                onChanged: (value) async {
                                  if (!mounted) return;
                                  final announcementRepository = ref.read(
                                    announcementRepositoryProvider,
                                  );
                                  final adminAnnouncementsController = ref.read(
                                    adminAnnouncementsControllerProvider
                                        .notifier,
                                  );
                                  final announcementsController = ref.read(
                                    announcementsControllerProvider.notifier,
                                  );
                                  await announcementRepository
                                      .updateAnnouncementStatus(
                                        announcementId: announcement.id,
                                        isActive: value,
                                      );
                                  await adminAnnouncementsController.refresh();
                                  await announcementsController.refresh();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.03)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderCol),
                            ),
                            child: Text(
                              announcement.message,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.5,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () => _showAnnouncementDialog(
                                  context,
                                  ref,
                                  announcement: announcement,
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: isDark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.black.withValues(alpha: 0.05),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(Iconsax.edit_2, size: 16),
                                label: const Text('تعديل الإعلان'),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFFF3B30),
                                  backgroundColor: const Color(
                                    0xFFFF3B30,
                                  ).withValues(alpha: 0.08),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
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
                                  if (confirmed != true ||
                                      !context.mounted ||
                                      !mounted) {
                                    return;
                                  }
                                  final announcementRepository = ref.read(
                                    announcementRepositoryProvider,
                                  );
                                  final adminAnnouncementsController = ref.read(
                                    adminAnnouncementsControllerProvider
                                        .notifier,
                                  );
                                  final announcementsController = ref.read(
                                    announcementsControllerProvider.notifier,
                                  );
                                  await announcementRepository
                                      .deleteAnnouncement(announcement.id);
                                  await adminAnnouncementsController.refresh();
                                  await announcementsController.refresh();
                                },
                                icon: const Icon(Iconsax.trash, size: 16),
                                label: const Text('حذف'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Departments Admin Tab ----------------

class _DepartmentsAdminTab extends ConsumerStatefulWidget {
  const _DepartmentsAdminTab({required this.departments, required this.users});
  final List<DepartmentSummary> departments;
  final List<ChatDirectoryUser> users;

  @override
  ConsumerState<_DepartmentsAdminTab> createState() =>
      _DepartmentsAdminTabState();
}

class _DepartmentsAdminTabState extends ConsumerState<_DepartmentsAdminTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DepartmentSummary> _filteredDepartments() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.departments;
    }
    return widget.departments.where((department) {
      return department.name.toLowerCase().contains(query) ||
          department.code.toLowerCase().contains(query) ||
          department.description.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _showDepartmentDialog(
    BuildContext context,
    WidgetRef ref, {
    DepartmentSummary? department,
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final overviewController = container.read(
      chatOverviewControllerProvider.notifier,
    );

    final nameController = TextEditingController(text: department?.name ?? '');
    final codeController = TextEditingController(text: department?.code ?? '');
    final descriptionController = TextEditingController(
      text: department?.description ?? '',
    );
    final managerSearchController = TextEditingController();
    final selectedManagers = <String>{
      ...department?.managers ?? const <String>[],
    };
    var isSaving = false;
    String? errorText;

    final eligibleManagers = widget.users
        .where((entry) => entry.role == 'manager' || entry.role == 'admin')
        .toList();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final mQuery = managerSearchController.text.trim().toLowerCase();
          final filteredManagers = eligibleManagers.where((u) {
            if (mQuery.isEmpty) return true;
            return u.displayName.toLowerCase().contains(mQuery) ||
                u.username.toLowerCase().contains(mQuery);
          }).toList();

          return _AppleAdminDialog(
            badgeIcon: department == null
                ? Icons.add_business_rounded
                : Icons.domain_verification_rounded,
            badgeColor: const Color(0xFF6366F1),
            title: department == null
                ? 'إضافة قسم إداري جديد'
                : 'تعديل بيانات القسم',
            subtitle: department == null
                ? 'إنشاء قسم جديد في الهيكل التنظيمي وتعيين المديرين المسؤولين عنه'
                : 'تحديث بيانات ومديري قسم "${department.name}"',
            maxWidth: 560,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _AppleTextField(
                        controller: nameController,
                        label: 'اسم القسم *',
                        hint: 'مثال: قسم تكنولوجيا المعلومات',
                        prefixIcon: Icons.domain_rounded,
                        enabled: !isSaving,
                        autofocus: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _AppleTextField(
                        controller: codeController,
                        label: 'كود القسم *',
                        hint: 'IT-DEP',
                        prefixIcon: Icons.tag_rounded,
                        enabled: !isSaving,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: descriptionController,
                  label: 'وصف ومهام القسم (اختياري)',
                  hint: 'اكتب نبذة مختصرة عن اختصاصات القسم...',
                  prefixIcon: Icons.notes_rounded,
                  minLines: 2,
                  maxLines: 3,
                  enabled: !isSaving,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.manage_accounts_rounded,
                      size: 18,
                      color: Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'مديرو ومشرفو القسم',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'تم اختيار ${selectedManagers.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: managerSearchController,
                  enabled: !isSaving,
                  onChanged: (_) => setLocalState(() {}),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن مدير بالاسم أو اسم المستخدم...',
                    prefixIcon: const Icon(Iconsax.search_normal_1, size: 17),
                    isDense: true,
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF282D37)
                        : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide(
                        color: isDark
                            ? Colors.white10
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide(
                        color: isDark
                            ? Colors.white10
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 210),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF232832)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: filteredManagers.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: Text(
                              'لا يوجد مديرون مطابقون للبحث',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(8),
                          itemCount: filteredManagers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, idx) {
                            final manager = filteredManagers[idx];
                            final selected = selectedManagers.contains(
                              manager.id,
                            );
                            return InkWell(
                              onTap: isSaving
                                  ? null
                                  : () {
                                      setLocalState(() {
                                        if (selected) {
                                          selectedManagers.remove(manager.id);
                                        } else {
                                          selectedManagers.add(manager.id);
                                        }
                                      });
                                    },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? const Color(
                                          0xFF6366F1,
                                        ).withValues(alpha: 0.14)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 15,
                                      backgroundColor: const Color(
                                        0xFF6366F1,
                                      ).withValues(alpha: 0.18),
                                      child: Text(
                                        manager.displayName.isNotEmpty
                                            ? manager.displayName[0]
                                                  .toUpperCase()
                                            : 'M',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF6366F1),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            manager.displayName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            '@${manager.username} • ${manager.role == 'admin' ? 'مسؤول نظام' : 'مدير'}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      selected
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      color: selected
                                          ? const Color(0xFF6366F1)
                                          : Colors.grey,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
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
                          setLocalState(() => errorText = 'اسم القسم مطلوب.');
                          return;
                        }
                        if (code.isEmpty) {
                          setLocalState(() => errorText = 'كود القسم مطلوب.');
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
                              managers: selectedManagers.toList(),
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
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (error) {
                          setLocalState(() {
                            isSaving = false;
                            errorText = error.toString();
                          });
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ButtonLoadingIndicator(),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  department == null ? 'إنشاء القسم' : 'حفظ التعديلات',
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
  Widget build(BuildContext context) {
    final departments = _filteredDepartments();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF0B0F17) : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF151C28) : Colors.white;
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.06);
    const accent = Color(0xFF6366F1);

    final totalMembers = widget.departments.fold<int>(
      0,
      (sum, d) => sum + d.membersCount,
    );
    final userById = {for (final u in widget.users) u.id: u};

    return Container(
      color: pageBg,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderCol),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.domain_rounded,
                        color: accent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'إدارة الأقسام والهيكل الإداري',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'إدارة أقسام المؤسسة وتعيين مديري الأقسام ومتابعة توزيع الأعضاء',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _AdminStatPill(
                      icon: Icons.domain_rounded,
                      label: 'إجمالي الأقسام',
                      value: '${widget.departments.length}',
                      color: accent,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 10),
                    _AdminStatPill(
                      icon: Iconsax.people,
                      label: 'إجمالي الأعضاء',
                      value: '$totalMembers',
                      color: const Color(0xFF10B981),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => _showDepartmentDialog(context, ref),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.add_business_rounded, size: 18),
                      label: const Text(
                        'إضافة قسم جديد',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'ابحث باسم القسم أو الكود أو الوصف...',
                    prefixIcon: const Icon(Iconsax.search_normal_1, size: 18),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          )
                        : null,
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF2F2F7),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: departments.isEmpty
                ? _AdminEmptyBentoState(
                    icon: Icons.domain_disabled_rounded,
                    title: 'لا توجد أقسام مطابقة',
                    subtitle:
                        'اضغط على "إضافة قسم جديد" لإنشاء قسم في الهيكل التنظيمي.',
                    isDark: isDark,
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 450,
                          mainAxisExtent: 205,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                    itemCount: departments.length,
                    itemBuilder: (context, index) {
                      final department = departments[index];
                      final managerNames = department.managers
                          .map((id) => userById[id]?.displayName)
                          .whereType<String>()
                          .toList();

                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderCol),
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
                                    color: accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.domain_rounded,
                                    color: accent,
                                    size: 21,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        department.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          department.code,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: accent,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'تعديل القسم',
                                  onPressed: () => _showDepartmentDialog(
                                    context,
                                    ref,
                                    department: department,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.black.withValues(alpha: 0.04),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(Iconsax.edit_2, size: 17),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: 'حذف القسم',
                                  onPressed: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => _AppleDangerDialog(
                                        title: 'حذف القسم',
                                        subtitle:
                                            'تأكيد إزالة القسم من الهيكل الإداري',
                                        message:
                                            'هل أنت متأكد من حذف قسم "${department.name}" (${department.code})؟ لن يتم حذف الموظفين.',
                                        onConfirm: () =>
                                            Navigator.pop(ctx, true),
                                      ),
                                    );
                                    if (confirmed != true ||
                                        !context.mounted ||
                                        !mounted) {
                                      return;
                                    }
                                    try {
                                      await ref
                                          .read(
                                            chatOverviewControllerProvider
                                                .notifier,
                                          )
                                          .deleteDepartment(department.id);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('تم حذف القسم بنجاح'),
                                        ),
                                      );
                                    } catch (error) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(error.toString()),
                                        ),
                                      );
                                    }
                                  },
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(
                                      0xFFFF3B30,
                                    ).withValues(alpha: 0.1),
                                    foregroundColor: const Color(0xFFFF3B30),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(Iconsax.trash, size: 17),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: Text(
                                department.description.trim().isEmpty
                                    ? 'لا يوجد وصف مسجل لهذا القسم.'
                                    : department.description,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Divider(height: 16, color: borderCol),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Iconsax.people,
                                        size: 14,
                                        color: Color(0xFF10B981),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        '${department.membersCount} عضو',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF10B981),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    managerNames.isEmpty
                                        ? 'بدون مدير معين'
                                        : 'المدير: ${managerNames.join('، ')}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
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

// ---------------- Shared Bento Stat & Empty Helpers ----------------

class _AdminStatPill extends StatelessWidget {
  const _AdminStatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminEmptyBentoState extends StatelessWidget {
  const _AdminEmptyBentoState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF151C28) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: const Color(0xFF007AFF)),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white54 : Colors.black54,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Rooms Admin Tab ----------------

class _RoomsAdminTab extends ConsumerStatefulWidget {
  const _RoomsAdminTab({
    required this.conversations,
    required this.users,
    this.departments = const <DepartmentSummary>[],
  });

  final List<ChatConversation> conversations;
  final List<ChatDirectoryUser> users;
  final List<DepartmentSummary> departments;

  @override
  ConsumerState<_RoomsAdminTab> createState() => _RoomsAdminTabState();
}

class _RoomsAdminTabState extends ConsumerState<_RoomsAdminTab> {
  final TextEditingController _searchController = TextEditingController();
  String _typeFilter = 'all'; // all, group, department, broadcast, archived
  List<ChatConversation> _fetchedRooms = const <ChatConversation>[];
  bool _isLoadingRooms = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reloadRooms);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reloadRooms() async {
    if (!mounted || _isLoadingRooms) return;
    setState(() => _isLoadingRooms = true);
    try {
      final repo = ref.read(chatRepositoryProvider);
      final results = await Future.wait<List<ChatConversation>>([
        repo.fetchManageableConversations().catchError(
          (_) => const <ChatConversation>[],
        ),
        repo.fetchConversations().catchError(
          (_) => const <ChatConversation>[],
        ),
      ]);
      final merged = <String, ChatConversation>{};
      for (final list in results) {
        for (final conv in list) {
          if (conv.type != 'direct' && conv.id.isNotEmpty) {
            merged[conv.id] = conv;
          }
        }
      }
      final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
      final depts = widget.departments.isNotEmpty
          ? widget.departments
          : (overview?.departments ?? const <DepartmentSummary>[]);
      for (final dept in depts) {
        final convId = dept.defaultConversationId;
        if (convId != null && convId.isNotEmpty && !merged.containsKey(convId)) {
          try {
            final conv = await repo.fetchConversation(convId);
            if (conv.id.isNotEmpty) {
              merged[conv.id] = conv;
            }
          } catch (_) {
            // Synthesize department room entry if individual fetch fails
            merged[convId] = ChatConversation(
              id: convId,
              type: 'department',
              name: 'غرفة ${dept.name}',
              description: dept.description,
              departmentId: dept.id,
              createdBy: null,
              members: widget.users
                  .where(
                    (u) =>
                        u.departmentId == dept.id ||
                        u.departmentIds.contains(dept.id),
                  )
                  .toList(),
              admins: widget.users
                  .where((u) => dept.managers.contains(u.id))
                  .toList(),
              broadcastPublisherIds: const [],
              blockedMemberIds: const [],
              pinnedMessage: null,
              lastMessage: null,
              unreadCount: 0,
              isArchived: false,
              isMuted: false,
              isPinned: false,
              isFavorite: false,
              isActive: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _fetchedRooms = merged.values.toList();
        _isLoadingRooms = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingRooms = false);
      }
    }
  }

  List<ChatConversation> _mergedRooms(ChatOverviewData? overview) {
    final map = <String, ChatConversation>{};
    for (final c
        in overview?.manageableConversations ?? const <ChatConversation>[]) {
      if (c.type != 'direct' && c.id.isNotEmpty) {
        map[c.id] = c;
      }
    }
    for (final c in overview?.conversations ?? const <ChatConversation>[]) {
      if (c.type != 'direct' && c.id.isNotEmpty) {
        map[c.id] = c;
      }
    }
    for (final c in widget.conversations) {
      if (c.type != 'direct' && c.id.isNotEmpty) {
        map[c.id] = c;
      }
    }
    for (final c in _fetchedRooms) {
      if (c.type != 'direct' && c.id.isNotEmpty) {
        map[c.id] = c;
      }
    }
    final depts = widget.departments.isNotEmpty
        ? widget.departments
        : (overview?.departments ?? const <DepartmentSummary>[]);
    for (final dept in depts) {
      final convId = dept.defaultConversationId;
      if (convId != null && convId.isNotEmpty && !map.containsKey(convId)) {
        map[convId] = ChatConversation(
          id: convId,
          type: 'department',
          name: 'غرفة ${dept.name}',
          description: dept.description,
          departmentId: dept.id,
          createdBy: null,
          members: widget.users
              .where(
                (u) =>
                    u.departmentId == dept.id ||
                    u.departmentIds.contains(dept.id),
              )
              .toList(),
          admins: widget.users
              .where((u) => dept.managers.contains(u.id))
              .toList(),
          broadcastPublisherIds: const [],
          blockedMemberIds: const [],
          pinnedMessage: null,
          lastMessage: null,
          unreadCount: 0,
          isArchived: false,
          isMuted: false,
          isPinned: false,
          isFavorite: false,
          isActive: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  String _roomTypeLabel(String type) {
    return switch (type) {
      'broadcast' => 'قناة بث 📢',
      'department' => 'غرفة قسم 🏢',
      'group' => 'مجموعة عمل 👥',
      _ => type,
    };
  }

  Color _roomTypeColor(String type) {
    return switch (type) {
      'broadcast' => const Color(0xFFF59E0B),
      'department' => const Color(0xFF8B5CF6),
      _ => const Color(0xFF007AFF),
    };
  }

  IconData _roomTypeIcon(String type) {
    return switch (type) {
      'broadcast' => Icons.campaign_rounded,
      'department' => Icons.domain_rounded,
      _ => Iconsax.people,
    };
  }

  Future<void> _showCreateRoomDialog(
    BuildContext context,
    WidgetRef ref, {
    String initialType = 'group',
  }) async {
    final overviewController = ref.read(
      chatOverviewControllerProvider.notifier,
    );
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final searchController = TextEditingController();
    var selectedType = initialType; // 'group', 'department', 'broadcast'
    String? selectedDepartmentId = widget.departments.isNotEmpty
        ? widget.departments.first.id
        : null;
    final selectedMembers = <String>{};
    final selectedAdmins = <String>{};
    var isSaving = false;
    String? errorText;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final isBroadcast = selectedType == 'broadcast';
          final accentColor = _roomTypeColor(selectedType);
          final query = searchController.text.trim().toLowerCase();
          final visibleUsers = widget.users.where((u) {
            if (query.isEmpty) return true;
            return u.displayName.toLowerCase().contains(query) ||
                u.username.toLowerCase().contains(query);
          }).toList();

          Widget typeChoice({
            required String type,
            required String title,
            required IconData icon,
            required Color color,
          }) {
            final selected = selectedType == type;
            return Expanded(
              child: InkWell(
                onTap: isSaving
                    ? null
                    : () => setLocalState(() => selectedType = type),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.15)
                        : (isDark
                              ? const Color(0xFF282D37)
                              : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? color
                          : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                      width: selected ? 1.5 : 0.8,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        icon,
                        color: selected
                            ? color
                            : (isDark ? Colors.white54 : Colors.black45),
                        size: 20,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: selected
                              ? color
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return _AppleAdminDialog(
            badgeIcon: _roomTypeIcon(selectedType),
            badgeColor: accentColor,
            title: isBroadcast
                ? 'إنشاء قناة بث جديدة'
                : (selectedType == 'department'
                      ? 'إنشاء غرفة قسم جديدة'
                      : 'إنشاء مجموعة عمل جديدة'),
            subtitle: isBroadcast
                ? 'قناة رسمية لإرسال التعاميم والإعلانات للأقسام والموظفين'
                : 'مساحة تواصل جماعية للموظفين والمشرفين مع صلاحيات كاملة',
            maxWidth: 600,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'نوع الغرفة أو القناة',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    typeChoice(
                      type: 'group',
                      title: 'مجموعة عمل',
                      icon: Iconsax.people,
                      color: const Color(0xFF007AFF),
                    ),
                    const SizedBox(width: 8),
                    typeChoice(
                      type: 'department',
                      title: 'غرفة قسم',
                      icon: Icons.domain_rounded,
                      color: const Color(0xFF8B5CF6),
                    ),
                    const SizedBox(width: 8),
                    typeChoice(
                      type: 'broadcast',
                      title: 'قناة بث',
                      icon: Icons.campaign_rounded,
                      color: const Color(0xFFF59E0B),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _AppleTextField(
                  controller: nameController,
                  label: isBroadcast ? 'اسم قناة البث *' : 'اسم الغرفة *',
                  hint: isBroadcast
                      ? 'مثال: التعاميم الإدارية العاجلة'
                      : 'مثال: فريق الدعم الفني والمبيعات',
                  prefixIcon: _roomTypeIcon(selectedType),
                  enabled: !isSaving,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                if (selectedType == 'department' &&
                    widget.departments.isNotEmpty) ...[
                  _AppleDropdown<String>(
                    value: selectedDepartmentId ?? widget.departments.first.id,
                    label: 'القسم المرتبط بالغرفة *',
                    prefixIcon: Icons.domain_rounded,
                    enabled: !isSaving,
                    items: widget.departments
                        .map(
                          (d) => DropdownMenuItem<String>(
                            value: d.id,
                            child: Text('${d.name} (${d.code})'),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setLocalState(() => selectedDepartmentId = val),
                  ),
                  const SizedBox(height: 12),
                ],
                _AppleTextField(
                  controller: descriptionController,
                  label: 'وصف الغرفة والغرض منها (اختياري)',
                  hint: 'اكتب وصفاً مختصراً لأعضاء الغرفة...',
                  prefixIcon: Icons.notes_rounded,
                  minLines: 2,
                  maxLines: 3,
                  enabled: !isSaving,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Iconsax.people, size: 17, color: accentColor),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        isBroadcast
                            ? 'المخولون بالإرسال في القناة (المرسلون)'
                            : 'أعضاء الغرفة',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: isSaving
                          ? null
                          : () {
                              setLocalState(() {
                                if (selectedMembers.length ==
                                    widget.users.length) {
                                  selectedMembers.clear();
                                  selectedAdmins.clear();
                                } else {
                                  selectedMembers.addAll(
                                    widget.users.map((u) => u.id),
                                  );
                                }
                              });
                            },
                      child: Text(
                        selectedMembers.length == widget.users.length
                            ? 'إلغاء تحديد الكل'
                            : 'تحديد الكل (${widget.users.length})',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: searchController,
                  enabled: !isSaving,
                  onChanged: (_) => setLocalState(() {}),
                  decoration: InputDecoration(
                    hintText: 'بحث عن موظف بالاسم أو اسم المستخدم...',
                    prefixIcon: const Icon(Iconsax.search_normal_1, size: 17),
                    isDense: true,
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF282D37)
                        : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide(
                        color: isDark
                            ? Colors.white10
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF232832)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: visibleUsers.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: Center(child: Text('لا توجد نتائج مطابقة')),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(6),
                          itemCount: visibleUsers.length,
                          itemBuilder: (context, idx) {
                            final user = visibleUsers[idx];
                            final isMember = selectedMembers.contains(user.id);
                            final isAdmin = selectedAdmins.contains(user.id);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isMember
                                    ? accentColor.withValues(alpha: 0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isMember,
                                    activeColor: accentColor,
                                    onChanged: isSaving
                                        ? null
                                        : (val) {
                                            setLocalState(() {
                                              if (val == true) {
                                                selectedMembers.add(user.id);
                                              } else {
                                                selectedMembers.remove(user.id);
                                                selectedAdmins.remove(user.id);
                                              }
                                            });
                                          },
                                  ),
                                  Expanded(
                                    child: InkWell(
                                      onTap: isSaving
                                          ? null
                                          : () {
                                              setLocalState(() {
                                                if (isMember) {
                                                  selectedMembers.remove(
                                                    user.id,
                                                  );
                                                  selectedAdmins.remove(
                                                    user.id,
                                                  );
                                                } else {
                                                  selectedMembers.add(user.id);
                                                }
                                              });
                                            },
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user.displayName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            '@${user.username}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (isMember)
                                    FilterChip(
                                      selected: isAdmin,
                                      label: const Text('مشرف'),
                                      selectedColor: const Color(
                                        0xFF10B981,
                                      ).withValues(alpha: 0.2),
                                      labelStyle: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isAdmin
                                            ? const Color(0xFF10B981)
                                            : (isDark
                                                  ? Colors.white60
                                                  : Colors.black54),
                                      ),
                                      onSelected: isSaving
                                          ? null
                                          : (v) {
                                              setLocalState(() {
                                                if (v) {
                                                  selectedAdmins.add(user.id);
                                                } else {
                                                  selectedAdmins.remove(
                                                    user.id,
                                                  );
                                                }
                                              });
                                            },
                                    ),
                                ],
                              ),
                            );
                          },
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                child: const Text('إلغاء'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        final name = nameController.text.trim();
                        if (name.isEmpty) {
                          setLocalState(
                            () => errorText = 'يرجى إدخال اسم الغرفة أو القناة.',
                          );
                          return;
                        }
                        setLocalState(() {
                          isSaving = true;
                          errorText = null;
                        });
                        try {
                          await overviewController.createConversation(
                            type: selectedType,
                            name: name,
                            description: descriptionController.text.trim(),
                            memberIds: selectedMembers.toList(),
                            adminIds: selectedAdmins.toList(),
                            departmentId: selectedType == 'department'
                                ? selectedDepartmentId
                                : null,
                          );
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (error) {
                          setLocalState(() {
                            isSaving = false;
                            errorText = error.toString();
                          });
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ButtonLoadingIndicator(),
                      )
                    : const Icon(Icons.add_task_rounded, size: 18),
                label: Text(
                  isBroadcast ? 'إنشاء قناة البث' : 'إنشاء الغرفة الآن',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (created == true && context.mounted) {
      await overviewController.refresh();
      await _reloadRooms();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء الغرفة بنجاح.')),
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
    final nameController = TextEditingController(
      text: conversation.displayTitle(''),
    );
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
    final memberSearchController = TextEditingController();
    var isArchived = conversation.isArchived;
    var isActive = conversation.isActive;
    var isSaving = false;
    String? errorText;

    final accentColor = _roomTypeColor(conversation.type);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final mQuery = memberSearchController.text.trim().toLowerCase();
          final visibleUsers = widget.users.where((u) {
            if (mQuery.isEmpty) return true;
            return u.displayName.toLowerCase().contains(mQuery) ||
                u.username.toLowerCase().contains(mQuery);
          }).toList();

          return _AppleAdminDialog(
            badgeIcon: _roomTypeIcon(conversation.type),
            badgeColor: accentColor,
            title: 'إدارة وتعديل "${conversation.displayTitle('')}"',
            subtitle:
                '${_roomTypeLabel(conversation.type)} • تحكم في الاسم والحالة والأعضاء والمشرفين',
            maxWidth: 600,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AppleTextField(
                  controller: nameController,
                  label: 'اسم الغرفة / القناة *',
                  prefixIcon: _roomTypeIcon(conversation.type),
                  enabled: !isSaving,
                ),
                const SizedBox(height: 12),
                _AppleTextField(
                  controller: descriptionController,
                  label: 'الوصف',
                  prefixIcon: Icons.notes_rounded,
                  minLines: 2,
                  maxLines: 3,
                  enabled: !isSaving,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _PermissionToggleCard(
                        title: 'الغرفة نشطة ومفعلة ✅',
                        value: isActive,
                        color: const Color(0xFF10B981),
                        disabled: isSaving,
                        onChanged: (v) => setLocalState(() => isActive = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PermissionToggleCard(
                        title: 'أرشفة الغرفة 📦',
                        value: isArchived,
                        color: const Color(0xFFF59E0B),
                        disabled: isSaving,
                        onChanged: (v) => setLocalState(() => isArchived = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Iconsax.people, size: 17, color: accentColor),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        isBroadcast
                            ? 'المرسلون (${selectedMembers.length}) ومشرفو البث (${selectedAdmins.length})'
                            : 'الأعضاء (${selectedMembers.length}) والمشرفون (${selectedAdmins.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: memberSearchController,
                  enabled: !isSaving,
                  onChanged: (_) => setLocalState(() {}),
                  decoration: InputDecoration(
                    hintText: 'بحث عن عضو أو مشرف بالاسم أو اسم المستخدم...',
                    prefixIcon: const Icon(Iconsax.search_normal_1, size: 17),
                    isDense: true,
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF282D37)
                        : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide(
                        color: isDark
                            ? Colors.white10
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF232832)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: visibleUsers.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: Center(child: Text('لا توجد نتائج مطابقة')),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(6),
                          itemCount: visibleUsers.length,
                          itemBuilder: (context, idx) {
                            final user = visibleUsers[idx];
                            final isMember = selectedMembers.contains(user.id);
                            final isAdmin = selectedAdmins.contains(user.id);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isMember
                                    ? accentColor.withValues(alpha: 0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isMember,
                                    activeColor: accentColor,
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
                                  Expanded(
                                    child: InkWell(
                                      onTap: isSaving
                                          ? null
                                          : () {
                                              setLocalState(() {
                                                if (isMember) {
                                                  selectedMembers.remove(
                                                    user.id,
                                                  );
                                                  selectedAdmins.remove(
                                                    user.id,
                                                  );
                                                } else {
                                                  selectedMembers.add(user.id);
                                                }
                                              });
                                            },
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user.displayName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            '@${user.username}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (isMember)
                                    FilterChip(
                                      selected: isAdmin,
                                      label: Text(
                                        isBroadcast ? 'مشرف بث' : 'مشرف',
                                      ),
                                      selectedColor: const Color(
                                        0xFF10B981,
                                      ).withValues(alpha: 0.2),
                                      labelStyle: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isAdmin
                                            ? const Color(0xFF10B981)
                                            : (isDark
                                                  ? Colors.white60
                                                  : Colors.black54),
                                      ),
                                      onSelected: isSaving
                                          ? null
                                          : (v) {
                                              setLocalState(() {
                                                if (v) {
                                                  selectedAdmins.add(user.id);
                                                } else {
                                                  selectedAdmins.remove(
                                                    user.id,
                                                  );
                                                }
                                              });
                                            },
                                    ),
                                ],
                              ),
                            );
                          },
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                child: const Text('إلغاء'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (nameController.text.trim().isEmpty) {
                          setLocalState(() => errorText = 'اسم الغرفة مطلوب.');
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
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (error) {
                          setLocalState(() {
                            isSaving = false;
                            errorText = error.toString();
                          });
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ButtonLoadingIndicator(),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text(
                  'حفظ التعديلات',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (saved == true && context.mounted) {
      await overviewController.refresh();
      await _reloadRooms();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF0B0F17) : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF151C28) : Colors.white;
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.06);

    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final canCreateRooms =
        authUser?.role == 'admin' || authUser?.can('canCreateRooms') == true;
    final canSendBroadcast =
        authUser?.role == 'admin' || authUser?.can('canSendBroadcast') == true;

    final overview = ref.watch(chatOverviewControllerProvider).valueOrNull;
    final allRooms = _mergedRooms(overview);

    final groupsCount = allRooms.where((c) => c.type == 'group').length;
    final deptRoomsCount = allRooms.where((c) => c.type == 'department').length;
    final broadcastsCount = allRooms.where((c) => c.type == 'broadcast').length;

    final query = _searchController.text.trim().toLowerCase();
    final filteredRooms = allRooms.where((room) {
      if (_typeFilter == 'archived') {
        if (!room.isArchived) return false;
      } else if (_typeFilter != 'all' && room.type != _typeFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final title = room.displayTitle('').toLowerCase();
      final desc = room.description.toLowerCase();
      return title.contains(query) || desc.contains(query);
    }).toList();

    return Container(
      color: pageBg,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderCol),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Iconsax.messages_2,
                        color: Color(0xFF007AFF),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'إدارة الغرف والقنوات ومجموعات العمل',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'إنشاء وإدارة المجموعات وغرف الأقسام وقنوات البث وتحديد المشرفين والأعضاء',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _AdminStatPill(
                      icon: Iconsax.messages_3,
                      label: 'الإجمالي',
                      value: '${allRooms.length}',
                      color: const Color(0xFF007AFF),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _AdminStatPill(
                      icon: Iconsax.people,
                      label: 'المجموعات',
                      value: '$groupsCount',
                      color: const Color(0xFF10B981),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _AdminStatPill(
                      icon: Icons.domain_rounded,
                      label: 'غرف الأقسام',
                      value: '$deptRoomsCount',
                      color: const Color(0xFF8B5CF6),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _AdminStatPill(
                      icon: Icons.campaign_rounded,
                      label: 'قنوات البث',
                      value: '$broadcastsCount',
                      color: const Color(0xFFF59E0B),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'تحديث قائمة الغرف والمجموعات',
                      onPressed: _isLoadingRooms
                          ? null
                          : () async {
                              await _reloadRooms();
                              if (mounted) {
                                await ref
                                    .read(chatOverviewControllerProvider.notifier)
                                    .refresh();
                              }
                            },
                      icon: _isLoadingRooms
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: ButtonLoadingIndicator(),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                    ),
                    const SizedBox(width: 10),
                    if (canCreateRooms) ...[
                      FilledButton.icon(
                        onPressed: () => _showCreateRoomDialog(
                          context,
                          ref,
                          initialType: 'group',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF007AFF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Iconsax.add_circle, size: 18),
                        label: const Text(
                          'إنشاء غرفة / مجموعة',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (canSendBroadcast)
                      FilledButton.tonalIcon(
                        onPressed: () => _showCreateRoomDialog(
                          context,
                          ref,
                          initialType: 'broadcast',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(
                            0xFFF59E0B,
                          ).withValues(alpha: 0.14),
                          foregroundColor: const Color(0xFFF59E0B),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.campaign_rounded, size: 18),
                        label: const Text(
                          'إنشاء قناة بث',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'ابحث باسم الغرفة أو القناة أو الوصف...',
                          prefixIcon: const Icon(
                            Iconsax.search_normal_1,
                            size: 18,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                )
                              : null,
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : const Color(0xFFF2F2F7),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final item in const [
                          ('all', 'الكل'),
                          ('group', 'المجموعات 👥'),
                          ('department', 'غرف الأقسام 🏢'),
                          ('broadcast', 'قنوات البث 📢'),
                          ('archived', 'المؤرشفة 📦'),
                        ])
                          ChoiceChip(
                            label: Text(item.$2),
                            selected: _typeFilter == item.$1,
                            onSelected: (_) =>
                                setState(() => _typeFilter = item.$1),
                            selectedColor: const Color(
                              0xFF007AFF,
                            ).withValues(alpha: 0.16),
                            labelStyle: TextStyle(
                              fontWeight: _typeFilter == item.$1
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: 12,
                              color: _typeFilter == item.$1
                                  ? const Color(0xFF007AFF)
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            side: BorderSide(
                              color: _typeFilter == item.$1
                                  ? const Color(0xFF007AFF)
                                  : borderCol,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filteredRooms.isEmpty
                ? _AdminEmptyBentoState(
                    icon: Iconsax.messages_2,
                    title: 'لا توجد غرف أو قنوات مطابقة',
                    subtitle:
                        'اضغط على "إنشاء غرفة / مجموعة" أو "إنشاء قناة بث" لإضافة غرفة جديدة.',
                    isDark: isDark,
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 460,
                          mainAxisExtent: 210,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                    itemCount: filteredRooms.length,
                    itemBuilder: (context, index) {
                      final room = filteredRooms[index];
                      final typeCol = _roomTypeColor(room.type);
                      final title = room.displayTitle('').trim().isEmpty
                          ? 'غرفة بدون اسم'
                          : room.displayTitle('');

                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderCol),
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
                                    color: typeCol.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(
                                    _roomTypeIcon(room.type),
                                    color: typeCol,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: typeCol.withValues(
                                                alpha: 0.13,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              _roomTypeLabel(room.type),
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w800,
                                                color: typeCol,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: (room.isActive
                                                      ? const Color(0xFF10B981)
                                                      : const Color(0xFFEF4444))
                                                  .withValues(alpha: 0.13),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              room.isActive ? 'نشطة' : 'معطلة',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w800,
                                                color: room.isActive
                                                    ? const Color(0xFF10B981)
                                                    : const Color(0xFFEF4444),
                                              ),
                                            ),
                                          ),
                                          if (room.isArchived)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFFF59E0B,
                                                ).withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'مؤرشفة',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFFF59E0B),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: Text(
                                room.description.trim().isEmpty
                                    ? 'لا يوجد وصف مسجل لهذه الغرفة.'
                                    : room.description,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Divider(height: 16, color: borderCol),
                            Row(
                              children: [
                                Icon(
                                  Iconsax.people,
                                  size: 15,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '${room.members.length} عضو',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(
                                  Iconsax.shield_tick,
                                  size: 15,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '${room.admins.length} مشرف',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                FilledButton.tonalIcon(
                                  onPressed: () => _showRoomDialog(
                                    context,
                                    ref,
                                    conversation: room,
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: typeCol.withValues(
                                      alpha: 0.12,
                                    ),
                                    foregroundColor: typeCol,
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(Iconsax.setting_2, size: 15),
                                  label: const Text(
                                    'إدارة',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: 'حذف الغرفة',
                                  onPressed: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => _AppleDangerDialog(
                                        title: 'حذف الغرفة نهائياً',
                                        subtitle:
                                            'تأكيد إزالة الغرفة وجميع محادثاتها',
                                        message:
                                            'هل أنت متأكد من حذف غرفة "$title"؟ لا يمكن التراجع عن هذا الإجراء.',
                                        onConfirm: () =>
                                            Navigator.pop(ctx, true),
                                      ),
                                    );
                                    if (confirmed != true ||
                                        !context.mounted ||
                                        !mounted) {
                                      return;
                                    }
                                    try {
                                      await ref
                                          .read(
                                            chatOverviewControllerProvider
                                                .notifier,
                                          )
                                          .deleteManagedConversation(room.id);
                                      if (mounted) {
                                        setState(() {
                                          _fetchedRooms = _fetchedRooms
                                              .where((r) => r.id != room.id)
                                              .toList();
                                        });
                                        await _reloadRooms();
                                      }
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'تم حذف الغرفة بنجاح.',
                                          ),
                                        ),
                                      );
                                    } catch (error) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(error.toString()),
                                        ),
                                      );
                                    }
                                  },
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(
                                      0xFFFF3B30,
                                    ).withValues(alpha: 0.1),
                                    foregroundColor: const Color(0xFFFF3B30),
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(Iconsax.trash, size: 16),
                                ),
                              ],
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

// ---------------- Roles Admin Tab ----------------

class _RolesAdminTab extends ConsumerStatefulWidget {
  const _RolesAdminTab({required this.roles});
  final List<ChatRole> roles;
  @override
  ConsumerState<_RolesAdminTab> createState() => _RolesAdminTabState();
}

class _RolesAdminTabState extends ConsumerState<_RolesAdminTab> {
  late Map<String, ChatPermissionSet> _draftPermissions;
  String? _selectedRoleId;
  bool _savingRole = false;

  bool _samePermissions(ChatPermissionSet a, ChatPermissionSet b) {
    return a.canCreateUsers == b.canCreateUsers &&
        a.canCreateDepartments == b.canCreateDepartments &&
        a.canCreateRooms == b.canCreateRooms &&
        a.canSendBroadcast == b.canSendBroadcast &&
        a.canDeleteMessages == b.canDeleteMessages &&
        a.canUploadFiles == b.canUploadFiles &&
        a.canModerateDepartment == b.canModerateDepartment &&
        a.canViewDepartmentLogs == b.canViewDepartmentLogs &&
        a.canManageAnnouncements == b.canManageAnnouncements &&
        a.canManageFiles == b.canManageFiles &&
        a.canManageBranches == b.canManageBranches &&
        a.canManageRoles == b.canManageRoles &&
        a.canManageSystem == b.canManageSystem &&
        a.canManageUpdates == b.canManageUpdates &&
        a.canManageBackups == b.canManageBackups &&
        a.canManageTickets == b.canManageTickets &&
        a.canViewPrinters == b.canViewPrinters &&
        a.canManagePrinters == b.canManagePrinters &&
        a.canSyncPrinters == b.canSyncPrinters &&
        a.canExportPrinterReports == b.canExportPrinterReports &&
        a.canViewSnipeit == b.canViewSnipeit &&
        a.canViewSystemMonitor == b.canViewSystemMonitor;
  }

  bool _hasServerRolesChanged(List<ChatRole> previous, List<ChatRole> next) {
    if (identical(previous, next)) {
      return false;
    }
    if (previous.length != next.length) {
      return true;
    }
    for (var i = 0; i < previous.length; i++) {
      final before = previous[i];
      final after = next[i];
      if (before.id != after.id ||
          before.roleName != after.roleName ||
          !_samePermissions(before.permissions, after.permissions)) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _draftPermissions = {
      for (final role in widget.roles) role.id: role.permissions,
    };
    if (widget.roles.isNotEmpty) {
      _selectedRoleId = widget.roles.first.id;
    }
  }

  @override
  void didUpdateWidget(covariant _RolesAdminTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasServerRolesChanged(oldWidget.roles, widget.roles)) {
      return;
    }
    _draftPermissions = {
      for (final role in widget.roles) role.id: role.permissions,
    };
    if (_selectedRoleId == null ||
        !widget.roles.any((r) => r.id == _selectedRoleId)) {
      _selectedRoleId = widget.roles.isNotEmpty ? widget.roles.first.id : null;
    }
  }

  String _roleArabicTitle(String roleName) {
    return switch (roleName.toLowerCase()) {
      'admin' => 'مسؤول النظام (Admin)',
      'manager' => 'مدير قسم (Manager)',
      'user' => 'موظف (User)',
      _ => roleName,
    };
  }

  String _roleArabicSubtitle(String roleName) {
    return switch (roleName.toLowerCase()) {
      'admin' => 'صلاحيات الإدارة العليا والتحكم الكامل في النظام والخادم',
      'manager' => 'صلاحيات الإشراف على الأقسام والغرف ومتابعة سير العمل',
      'user' => 'الصلاحيات الأساسية للموظفين في المراسلة والملفات والطابعات',
      _ => 'تخصيص الصلاحيات الافتراضية لهذا الدور الوظيفي',
    };
  }

  Color _roleColor(String roleName) {
    return switch (roleName.toLowerCase()) {
      'admin' => const Color(0xFFEF4444),
      'manager' => const Color(0xFF8B5CF6),
      _ => const Color(0xFF007AFF),
    };
  }

  IconData _roleIcon(String roleName) {
    return switch (roleName.toLowerCase()) {
      'admin' => Iconsax.shield_security,
      'manager' => Iconsax.user_octagon,
      _ => Iconsax.user,
    };
  }

  int _enabledCount(ChatPermissionSet p) {
    final values = [
      p.canCreateUsers,
      p.canCreateDepartments,
      p.canCreateRooms,
      p.canSendBroadcast,
      p.canDeleteMessages,
      p.canUploadFiles,
      p.canModerateDepartment,
      p.canViewDepartmentLogs,
      p.canManageAnnouncements,
      p.canManageFiles,
      p.canManageBranches,
      p.canManageRoles,
      p.canManageSystem,
      p.canManageUpdates,
      p.canManageBackups,
      p.canManageTickets,
      p.canViewPrinters,
      p.canManagePrinters,
      p.canSyncPrinters,
      p.canExportPrinterReports,
      p.canViewSnipeit,
      p.canViewSystemMonitor,
    ];
    return values.where((v) => v).length;
  }

  ChatPermissionSet _setAllPermissions(bool value) {
    return ChatPermissionSet(
      canCreateUsers: value,
      canCreateDepartments: value,
      canCreateRooms: value,
      canSendBroadcast: value,
      canDeleteMessages: value,
      canUploadFiles: value,
      canModerateDepartment: value,
      canViewDepartmentLogs: value,
      canManageAnnouncements: value,
      canManageFiles: value,
      canManageBranches: value,
      canManageRoles: value,
      canManageSystem: value,
      canManageUpdates: value,
      canManageBackups: value,
      canManageTickets: value,
      canViewPrinters: value,
      canManagePrinters: value,
      canSyncPrinters: value,
      canExportPrinterReports: value,
      canViewSnipeit: value,
      canViewSystemMonitor: value,
    );
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
      canViewSnipeit: key == 'canViewSnipeit' ? value : source.canViewSnipeit,
      canViewSystemMonitor: key == 'canViewSystemMonitor'
          ? value
          : source.canViewSystemMonitor,
    );
  }

  Widget _buildPermissionCategoryCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required ChatRole role,
    required ChatPermissionSet draft,
    required List<(String, String, bool)> items,
    required bool isDark,
  }) {
    final cardBg = isDark ? const Color(0xFF151C28) : Colors.white;
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.06);
    final activeInGroup = items.where((e) => e.$3).length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$activeInGroup / ${items.length} مفعلة',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth > 760
                  ? 3
                  : (constraints.maxWidth > 480 ? 2 : 1);
              final itemWidth =
                  (constraints.maxWidth - ((cols - 1) * 10)) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: items
                    .map(
                      (item) => SizedBox(
                        width: itemWidth,
                        child: _PermissionToggleCard(
                          title: item.$2,
                          value: item.$3,
                          color: color,
                          disabled: _savingRole,
                          onChanged: (value) {
                            setState(() {
                              _draftPermissions[role.id] = _updatePermission(
                                draft,
                                item.$1,
                                value,
                              );
                            });
                          },
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF0B0F17) : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF151C28) : Colors.white;
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.06);

    if (widget.roles.isEmpty) {
      return Container(
        color: pageBg,
        child: _AdminEmptyBentoState(
          icon: Icons.admin_panel_settings_outlined,
          title: 'لا توجد أدوار وظيفية مسجلة',
          subtitle: 'قم بتحديث الصفحة لتحميل الأدوار والصلاحيات.',
          isDark: isDark,
        ),
      );
    }

    final selectedRole = widget.roles.firstWhere(
      (r) => r.id == _selectedRoleId,
      orElse: () => widget.roles.first,
    );
    final draft =
        _draftPermissions[selectedRole.id] ?? selectedRole.permissions;
    final hasUnsavedChanges = !_samePermissions(
      draft,
      selectedRole.permissions,
    );
    final roleAccent = _roleColor(selectedRole.roleName);

    return Container(
      color: pageBg,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Role Selector Cards
          Row(
            children: widget.roles.map((role) {
              final isSelected = role.id == selectedRole.id;
              final rColor = _roleColor(role.roleName);
              final rDraft = _draftPermissions[role.id] ?? role.permissions;
              final count = _enabledCount(rDraft);
              final dirty = !_samePermissions(rDraft, role.permissions);

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: role == widget.roles.last ? 0 : 12,
                  ),
                  child: InkWell(
                    onTap: () => setState(() => _selectedRoleId = role.id),
                    borderRadius: BorderRadius.circular(18),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? rColor.withValues(alpha: isDark ? 0.16 : 0.08)
                            : cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected ? rColor : borderCol,
                          width: isSelected ? 1.6 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: rColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              _roleIcon(role.roleName),
                              color: rColor,
                              size: 22,
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
                                        _roleArabicTitle(role.roleName),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (dirty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFF59E0B),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$count من 22 صلاحية مفعلة',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? rColor
                                        : (isDark
                                              ? Colors.white54
                                              : Colors.black54),
                                  ),
                                ),
                              ],
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

          // Active Role Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderCol),
            ),
            child: Row(
              children: [
                Icon(
                  _roleIcon(selectedRole.roleName),
                  color: roleAccent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'تخصيص صلاحيات: ${_roleArabicTitle(selectedRole.roleName)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                          if (hasUnsavedChanges) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFF59E0B,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'تعديلات غير محفوظة',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFF59E0B),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        _roleArabicSubtitle(selectedRole.roleName),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _savingRole
                      ? null
                      : () {
                          setState(() {
                            _draftPermissions[selectedRole.id] =
                                _setAllPermissions(true);
                          });
                        },
                  icon: const Icon(Icons.done_all_rounded, size: 17),
                  label: const Text('تفعيل الكل'),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _savingRole
                      ? null
                      : () {
                          setState(() {
                            _draftPermissions[selectedRole.id] =
                                _setAllPermissions(false);
                          });
                        },
                  icon: const Icon(Icons.deselect_rounded, size: 17),
                  label: const Text('إلغاء الكل'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _savingRole
                      ? null
                      : () async {
                          setState(() => _savingRole = true);
                          try {
                            await ref
                                .read(chatOverviewControllerProvider.notifier)
                                .updateRole(
                                  roleId: selectedRole.id,
                                  permissions:
                                      _draftPermissions[selectedRole.id] ??
                                      selectedRole.permissions,
                                );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تم حفظ صلاحيات "${_roleArabicTitle(selectedRole.roleName)}" بنجاح.',
                                ),
                              ),
                            );
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error.toString())),
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _savingRole = false);
                            }
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: roleAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _savingRole
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: ButtonLoadingIndicator(),
                        )
                      : const Icon(Iconsax.tick_circle, size: 18),
                  label: Text(
                    _savingRole ? 'جارٍ الحفظ...' : 'حفظ صلاحيات الدور',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Categorized Permission Cards
          Expanded(
            child: ListView(
              children: [
                _buildPermissionCategoryCard(
                  context: context,
                  title: 'صلاحيات المستخدمين والهيكل التنظيمي',
                  subtitle:
                      'إضافة وتعديل حسابات الموظفين والأقسام والفروع والأدوار الوظيفية',
                  icon: Iconsax.people,
                  color: const Color(0xFF007AFF),
                  role: selectedRole,
                  draft: draft,
                  isDark: isDark,
                  items: [
                    (
                      'canCreateUsers',
                      'إنشاء وإدارة المستخدمين',
                      draft.canCreateUsers,
                    ),
                    (
                      'canCreateDepartments',
                      'إنشاء وإدارة الأقسام',
                      draft.canCreateDepartments,
                    ),
                    (
                      'canManageBranches',
                      'إدارة الفروع والمواقع',
                      draft.canManageBranches,
                    ),
                    (
                      'canManageRoles',
                      'إدارة الأدوار والصلاحيات',
                      draft.canManageRoles,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildPermissionCategoryCard(
                  context: context,
                  title: 'صلاحيات المحادثات والغرف والمحتوى',
                  subtitle:
                      'إنشاء الغرف وقنوات البث وإدارة الرسائل والملفات والإعلانات',
                  icon: Iconsax.messages_2,
                  color: const Color(0xFF10B981),
                  role: selectedRole,
                  draft: draft,
                  isDark: isDark,
                  items: [
                    (
                      'canCreateRooms',
                      'إنشاء وإدارة الغرف والمجموعات',
                      draft.canCreateRooms,
                    ),
                    (
                      'canSendBroadcast',
                      'إنشاء وإرسال قنوات البث',
                      draft.canSendBroadcast,
                    ),
                    (
                      'canModerateDepartment',
                      'الإشراف على محادثات القسم',
                      draft.canModerateDepartment,
                    ),
                    (
                      'canDeleteMessages',
                      'حذف وتعديل الرسائل',
                      draft.canDeleteMessages,
                    ),
                    (
                      'canUploadFiles',
                      'رفع وإرسال المرفقات والملفات',
                      draft.canUploadFiles,
                    ),
                    (
                      'canManageFiles',
                      'إدارة مستندات وملفات النظام',
                      draft.canManageFiles,
                    ),
                    (
                      'canManageAnnouncements',
                      'إدارة ونشر الإعلانات العامة',
                      draft.canManageAnnouncements,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildPermissionCategoryCard(
                  context: context,
                  title: 'صلاحيات الطابعات والتذاكر والأصول',
                  subtitle:
                      'مراقبة طابعات الفروع وإدارة التذاكر الفنية ونظام الأصول Snipe-IT',
                  icon: Iconsax.printer,
                  color: const Color(0xFF8B5CF6),
                  role: selectedRole,
                  draft: draft,
                  isDark: isDark,
                  items: [
                    (
                      'canManageTickets',
                      'إدارة التذاكر والدعم الفني',
                      draft.canManageTickets,
                    ),
                    (
                      'canViewPrinters',
                      'عرض لوحة مراقبة الطابعات',
                      draft.canViewPrinters,
                    ),
                    (
                      'canManagePrinters',
                      'إدارة الطابعات وفروعها',
                      draft.canManagePrinters,
                    ),
                    (
                      'canSyncPrinters',
                      'مزامنة وفحص الطابعات',
                      draft.canSyncPrinters,
                    ),
                    (
                      'canExportPrinterReports',
                      'تصدير تقارير الطابعات',
                      draft.canExportPrinterReports,
                    ),
                    (
                      'canViewSnipeit',
                      'عرض نظام الأصول (Snipe-IT)',
                      draft.canViewSnipeit,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildPermissionCategoryCard(
                  context: context,
                  title: 'صلاحيات النظام والخادم والنسخ الاحتياطي',
                  subtitle:
                      'إعدادات الخادم ومراقبة الأداء والسجل الإداري والتحديثات والنسخ الاحتياطي',
                  icon: Iconsax.setting_2,
                  color: const Color(0xFFF59E0B),
                  role: selectedRole,
                  draft: draft,
                  isDark: isDark,
                  items: [
                    (
                      'canViewDepartmentLogs',
                      'عرض السجل الإداري (Audit Logs)',
                      draft.canViewDepartmentLogs,
                    ),
                    (
                      'canViewSystemMonitor',
                      'مراقبة موارد وأداء النظام',
                      draft.canViewSystemMonitor,
                    ),
                    (
                      'canManageSystem',
                      'إدارة إعدادات الخادم والأخطاء',
                      draft.canManageSystem,
                    ),
                    (
                      'canManageUpdates',
                      'إدارة إصدارات وتحديثات التطبيق',
                      draft.canManageUpdates,
                    ),
                    (
                      'canManageBackups',
                      'إدارة النسخ الاحتياطي للنظام',
                      draft.canManageBackups,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Audit Logs Tab ----------------

class _AuditLogsTab extends StatelessWidget {
  const _AuditLogsTab({required this.logsFuture});
  final Future<_AdminLoadResult<ChatAuditLog>> logsFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminLoadResult<ChatAuditLog>>(
      future: logsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState != ConnectionState.done) {
          return const _AdminTableLoadingShimmer();
        }
        final result = snapshot.data;
        if (result == null) {
          return const Center(child: Text('تعذر تحميل السجل الآن'));
        }
        if (result.hasError) {
          return _AdminLoadErrorState(
            message: result.errorMessage!,
            hint: 'يمكنك تحديث اللوحة لاحقًا.',
          );
        }
        final logs = result.items;
        if (logs.isEmpty) return Center(child: Text(result.emptyMessage));

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final log = logs[index];
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).dividerColor.withOpacity(0.3),
                ),
              ),
              child: ListTile(
                title: Text(
                  log.action,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('${log.entityType} • ${log.entityId}'),
                trailing: Text(formatEgyptDateTime(log.createdAt)),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------- System Errors Tab ----------------

class _SystemErrorsTab extends StatelessWidget {
  const _SystemErrorsTab({required this.errorsFuture});
  final Future<_AdminLoadResult<ChatSystemError>> errorsFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminLoadResult<ChatSystemError>>(
      future: errorsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState != ConnectionState.done) {
          return const _AdminTableLoadingShimmer();
        }
        final result = snapshot.data;
        if (result == null) {
          return const Center(child: Text('تعذر تحميل الأخطاء الآن'));
        }
        if (result.hasError) {
          return _AdminLoadErrorState(
            message: result.errorMessage!,
            hint: 'الخادم بطيء أو سجل الأخطاء كبير جدًا.',
          );
        }
        final errors = result.items;
        if (errors.isEmpty) return Center(child: Text(result.emptyMessage));

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: errors.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final error = errors[index];
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.error.withOpacity(0.5),
                ),
              ),
              child: ExpansionTile(
                title: Text(
                  '${error.statusCode} • ${error.errorName}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(error.path),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(error.message),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${error.method} • ${formatEgyptDateTime(error.createdAt)}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                  if (error.stack != null && error.stack!.isNotEmpty) ...[
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
                      child: SelectableText(error.stack!),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------- Admin Load Error State ----------------

class _AdminLoadErrorState extends StatelessWidget {
  const _AdminLoadErrorState({required this.message, required this.hint});
  final String message;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: scheme.error.withOpacity(0.18)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: scheme.error, size: 36),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminTableLoadingShimmer extends StatelessWidget {
  const _AdminTableLoadingShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: const [
        ShimmerSkeleton(height: 48, borderRadius: 12),
        SizedBox(height: 10),
        ShimmerSkeleton(height: 64, borderRadius: 12),
        SizedBox(height: 8),
        ShimmerSkeleton(height: 64, borderRadius: 12),
        SizedBox(height: 8),
        ShimmerSkeleton(height: 64, borderRadius: 12),
      ],
    );
  }
}
