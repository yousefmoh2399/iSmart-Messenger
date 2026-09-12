import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/chat/presentation/chat_dashboard_screen.dart';
import '../features/files/presentation/files_dashboard_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/printers/presentation/printer_monitoring_screen.dart';
import '../features/servers/presentation/servers_screen.dart';
import '../features/it_assets/presentation/it_assets_screen.dart';
import '../features/updates/presentation/update_center_screen.dart';
import '../features/purchasing/presentation/screens/purchase_requests_screen.dart';
import '../features/snipeit/presentation/snipeit_screen.dart';
import '../shared/providers/providers.dart';
import '../shared/widgets/desktop_workspace_sidebar.dart';

class DesktopWorkspaceShell extends ConsumerStatefulWidget {
  const DesktopWorkspaceShell({super.key});

  @override
  ConsumerState<DesktopWorkspaceShell> createState() =>
      _DesktopWorkspaceShellState();
}

class _DesktopWorkspaceShellState extends ConsumerState<DesktopWorkspaceShell> {
  DesktopWorkspaceSection _activeSection = DesktopWorkspaceSection.chat;

  void _navigateTo(DesktopWorkspaceSection section) {
    if (_activeSection == section) {
      if (section == DesktopWorkspaceSection.snipeit) {
        ref
            .read(snipeitRefreshEventProvider.notifier)
            .update((state) => state + 1);
      }
      return;
    }
    setState(() {
      _activeSection = section;
    });
    ref.read(chatSectionVisibleProvider.notifier).state =
        section == DesktopWorkspaceSection.chat;
  }

  int _stackIndexForSection(DesktopWorkspaceSection section) {
    switch (section) {
      case DesktopWorkspaceSection.chat:
      case DesktopWorkspaceSection.admin:
      case DesktopWorkspaceSection.tickets:
        return 0;
      case DesktopWorkspaceSection.printers:
        return 4;
      case DesktopWorkspaceSection.itAssets:
        return 5;
      case DesktopWorkspaceSection.purchaseRequests:
        return 6;
      case DesktopWorkspaceSection.files:
        return 1;
      case DesktopWorkspaceSection.servers:
        return 2;
      case DesktopWorkspaceSection.profile:
        return 3;
      case DesktopWorkspaceSection.snipeit:
        return 7;
    }
  }

  Future<void> _confirmAndLogout() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد تسجيل الخروج'),
        content: const Text(
          'سيتم تسجيل خروجك من هذا الجهاز. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
    if (approved == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final themeMode =
        ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.light;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return auth.when(
      loading: () => const Scaffold(body: SizedBox.expand()),
      error: (_, __) => const Scaffold(body: SizedBox.expand()),
      data: (user) {
        if (user == null) return const Scaffold(body: SizedBox.expand());

        final canOpenAdmin = user.canManageChat;
        final appServerDefaults = ref
            .watch(appServerDefaultsProvider)
            .valueOrNull;
        final cachedAppServerDefaults = ref
            .watch(cachedAppServerDefaultsProvider)
            .valueOrNull;
        final showServersShortcut =
            (appServerDefaults ?? cachedAppServerDefaults)
                ?.showServersShortcut ??
            false;
        if (!showServersShortcut &&
            _activeSection == DesktopWorkspaceSection.servers) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _activeSection == DesktopWorkspaceSection.servers) {
              _navigateTo(DesktopWorkspaceSection.chat);
            }
          });
        }

        return Scaffold(
          body: Row(
            children: [
              Expanded(
                child: IndexedStack(
                  index: _stackIndexForSection(_activeSection),
                  children: [
                    ChatDashboardScreen(
                      isWrapped: true,
                      activeSection: _activeSection,
                      onSectionChanged: _navigateTo,
                    ),
                    const FilesDashboardScreen(isWrapped: true),
                    const ServersScreen(isWrapped: true),
                    const ProfileScreen(isWrapped: true),
                    const PrinterMonitoringScreen(isWrapped: true),
                    const ItAssetsScreen(isWrapped: true),
                    const PurchaseRequestsScreen(),
                    const SnipeitScreen(isWrapped: true),
                  ],
                ),
              ),
              DesktopWorkspaceSidebar(
                user: user,
                activeSection: _activeSection,
                currentThemeMode: themeMode,
                isDark: isDark,
                accentColor: Theme.of(context).colorScheme.primary,
                onOpenChat: () => _navigateTo(DesktopWorkspaceSection.chat),
                onRefresh: () =>
                    ref.read(chatOverviewControllerProvider.notifier).refresh(),
                onOpenFiles: () => _navigateTo(DesktopWorkspaceSection.files),
                showServersShortcut: showServersShortcut,
                onOpenServers: () =>
                    _navigateTo(DesktopWorkspaceSection.servers),
                onOpenProfile: () =>
                    _navigateTo(DesktopWorkspaceSection.profile),
                onOpenUpdates: () {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) => const UpdateCenterScreen(),
                        ),
                      )
                      .then((_) {
                        if (mounted) {
                          ref.read(chatSectionVisibleProvider.notifier).state =
                              _activeSection == DesktopWorkspaceSection.chat;
                        }
                      });
                },
                onToggleTheme: () => ref
                    .read(themeModeControllerProvider.notifier)
                    .cycleThemeMode(),
                onOpenTickets: () =>
                    _navigateTo(DesktopWorkspaceSection.tickets),
                onOpenPrinters: user.canViewPrinterModule
                    ? () => _navigateTo(DesktopWorkspaceSection.printers)
                    : null,
                onOpenItAssets: user.canViewItAssets
                    ? () => _navigateTo(DesktopWorkspaceSection.itAssets)
                    : null,
                onOpenPurchaseRequests:
                    user.permissions['canViewPurchaseRequests'] == true ||
                        user.role == 'admin'
                    ? () =>
                          _navigateTo(DesktopWorkspaceSection.purchaseRequests)
                    : null,
                onOpenSnipeit: user.canViewSnipeit
                    ? () => _navigateTo(DesktopWorkspaceSection.snipeit)
                    : null,
                onCreateConversation: () =>
                    _navigateTo(DesktopWorkspaceSection.chat),
                onOpenAdmin: canOpenAdmin
                    ? () => _navigateTo(DesktopWorkspaceSection.admin)
                    : null,
                onLogout: () {
                  _confirmAndLogout();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
