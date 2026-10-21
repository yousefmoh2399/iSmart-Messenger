import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/chat/presentation/chat_dashboard_screen.dart';
import '../features/files/presentation/files_dashboard_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/printers/presentation/printer_monitoring_screen.dart';
import '../features/servers/presentation/servers_screen.dart';
import '../features/updates/presentation/update_center_screen.dart';
import '../features/purchasing/presentation/screens/purchase_requests_screen.dart';
import '../features/snipeit/presentation/snipeit_screen.dart';
import '../features/admin/presentation/system_monitor_screen.dart';
import '../shared/providers/providers.dart';
import '../shared/widgets/desktop_workspace_sidebar.dart';

class DesktopWorkspaceShell extends ConsumerStatefulWidget {
  const DesktopWorkspaceShell({super.key});

  @override
  ConsumerState<DesktopWorkspaceShell> createState() =>
      _DesktopWorkspaceShellState();
}

class _DesktopWorkspaceShellState extends ConsumerState<DesktopWorkspaceShell> {
  StreamSubscription? _updateEventsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initUpdateListener();
    });
  }

  @override
  void dispose() {
    _updateEventsSub?.cancel();
    super.dispose();
  }

  void _initUpdateListener() {
    try {
      final agent = ref.read(desktopUpdateAgentProvider);
      _updateEventsSub = agent.events.listen((event) {
        if (!mounted) return;
        if (event.type == 'ready_to_restart') {
          _showUpdateReadyDialog(event.message);
        }
      });
      // Check initial state
      agent.hasPreparedUpdate();
    } catch (_) {}
  }

  Future<void> _showUpdateReadyDialog(String message) async {
    if (!mounted) return;
    final agent = ref.read(desktopUpdateAgentProvider);

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF10B981),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'اكتمل تنزيل التحديث',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            message.isNotEmpty
                ? message
                : 'تم تنزيل حزمة التحديث بنجاح وهي جاهزة للتثبيت.\nهل ترغب في تثبيت التحديث وإعادة تشغيل التطبيق الآن أم المتابعة لاحقاً؟',
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('later'),
              child: const Text('لاحقاً (متابعة العمل)'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop('now'),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('تثبيت الآن'),
            ),
          ],
        );
      },
    );

    if (action == 'now') {
      try {
        await agent.restartToApplyPreparedUpdate();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل بدء التثبيت: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }


  // Getter to read the global active section
  DesktopWorkspaceSection get _activeSection => ref.watch(activeSectionProvider);

  void _navigateTo(DesktopWorkspaceSection section) {
    final current = ref.read(activeSectionProvider);
    if (current == section) {
      if (section == DesktopWorkspaceSection.snipeit) {
        ref.read(snipeitRefreshEventProvider.notifier).update((state) => state + 1);
      }
      return;
    }
    ref.read(activeSectionProvider.notifier).state = section;
    ref.read(chatSectionVisibleProvider.notifier).state = section == DesktopWorkspaceSection.chat;
  }


  

  int _stackIndexForSection(DesktopWorkspaceSection section) {
    switch (section) {
      case DesktopWorkspaceSection.chat:
      case DesktopWorkspaceSection.admin:
      case DesktopWorkspaceSection.tickets:
        return 0;
      case DesktopWorkspaceSection.files:
        return 1;
      case DesktopWorkspaceSection.servers:
        return 2;
      case DesktopWorkspaceSection.profile:
        return 3;
      case DesktopWorkspaceSection.printers:
        return 4;
      case DesktopWorkspaceSection.purchaseRequests:
        return 5;
      case DesktopWorkspaceSection.snipeit:
        return 6;
      case DesktopWorkspaceSection.systemMonitor:
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
                    const PurchaseRequestsScreen(),
                    const SnipeitScreen(isWrapped: true),
                    const SystemMonitorScreen(isWrapped: true),
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
                onOpenSystemMonitor: user.canViewSystemMonitor
                    ? () => _navigateTo(DesktopWorkspaceSection.systemMonitor)
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
