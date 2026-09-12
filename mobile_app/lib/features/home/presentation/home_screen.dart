import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/admin_announcement.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/announcements_skeleton_strip.dart';
import '../../chat/presentation/chat_admin_management_screen.dart';
import '../../files/presentation/my_files_screen.dart';
import '../../files/presentation/pending_uploads_screen.dart';
import '../../it_assets/presentation/mobile_it_asset_scanner_screen.dart';
import '../../printers/presentation/printer_monitoring_screen.dart';
import '../../scanner/presentation/scanner_session_screen.dart';
import '../../tickets/presentation/tickets_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final draftState = ref.watch(scanSessionControllerProvider);
    final announcementsState = ref.watch(announcementsControllerProvider);
    final themeMode =
        ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.light;
    final syncBanner = ref.watch(syncBannerStateProvider);

    final user = authState.valueOrNull;
    final hasDraft = (draftState.valueOrNull?.pages.length ?? 0) > 0;
    final isAdmin = user?.isAdmin == true;
    final canManageChat = user?.canManageChat == true;
    final canViewPrinters = user?.canViewPrinterModule == true;
    final canViewItAssets =
        user?.canScanItAssets == true ||
        user?.canScanItSpareParts == true ||
        user?.canScanItInventory == true;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.appThemePalette;

    final printersColor = isDark
        ? const Color(0xFF0F766E)
        : const Color(0xFF0D9488);
    final ticketsColor = isDark
        ? const Color(0xFF5B21B6)
        : const Color(0xFF6D28D9);

    return Scaffold(
      appBar: AppBar(
        title: const Text('اسكان الملفات'),
        actions: [
          IconButton(
            tooltip: 'تبديل الثيم',
            onPressed: () =>
                ref.read(themeModeControllerProvider.notifier).cycleThemeMode(),
            icon: Icon(switch (themeMode) {
              ThemeMode.dark => Icons.dark_mode_outlined,
              ThemeMode.system => Icons.light_mode_outlined,
              ThemeMode.light => Icons.light_mode_outlined,
            }),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compactCards = constraints.maxWidth < 400;

          // Resolve first letter of the user name for avatar
          final avatarLetter = user?.fullName.trim().isNotEmpty == true
              ? user!.fullName.trim()[0].toUpperCase()
              : (user?.username.trim().isNotEmpty == true
                    ? user!.username.trim()[0].toUpperCase()
                    : 'U');

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // 1. Profile Welcome Header Card
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFFF2F2F7),
                    ),
                    child: Center(
                      child: Text(
                        avatarLetter,
                        style: TextStyle(
                          color: palette.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مرحباً، ${user?.fullName ?? user?.username ?? 'أيها المستخدم'}',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          isAdmin ? 'مسؤول النظام (Admin)' : 'حساب موظف',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 2. Sync Offline Banners
              if (syncBanner.isOffline || syncBanner.isSyncing) ...[
                _SyncStatusBanner(state: syncBanner),
                const SizedBox(height: 12),
              ],

              // 3. System Announcements Strip
              _AnnouncementsStrip(announcementsState: announcementsState),

              // 4. Saved Draft Notice Banner
              if (hasDraft && !isAdmin) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.restore_page_rounded,
                          color: Color(0xFFD97706),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'مسودة محفوظة غير مكتملة',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFB45309),
                                    fontSize: 14,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'تحتوي على ${draftState.valueOrNull!.pages.length} صفحات تنتظر الحفظ.',
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(
                                  0xFFB45309,
                                ).withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ScannerSessionScreen(),
                            ),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD97706),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          minimumSize: const Size(0, 38),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'استكمال',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 5. Quick Actions Heading
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'الإجراءات السريعة',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ),

              // 6. Hero Scanning Card (For Staff Only)
              if (!isAdmin) ...[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ScannerSessionScreen(),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: palette.accent.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: palette.accent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.document_scanner_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'مسح مستند جديد',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: palette.accent,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 18,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'التقط الصفحات وأنشئ ملفات PDF احترافية ونظيفة بسرعة.',
                                    style: TextStyle(
                                      color: palette.accent.withValues(
                                        alpha: 0.8,
                                      ),
                                      fontSize: 12,
                                      height: 1.3,
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
                ),
                const SizedBox(height: 14),
              ],

              // 7. Grid of Secondary Actions
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _ActionListTile(
                      title: 'ملفاتي السحابية',
                      subtitle: isAdmin
                          ? 'إدارة ومراجعة ملفات النظام بالكامل'
                          : 'استعرض ملفاتك المرفوعة والمشتركة',
                      icon: Icons.cloud_done_rounded,
                      iconColor: palette.accent,
                      showTopDivider: false,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MyFilesScreen(),
                          ),
                        );
                      },
                    ),
                    if (!isAdmin)
                      _ActionListTile(
                        title: 'ملفاتي المحلية',
                        subtitle: 'الملفات الممسوحة والمحفوظة على الموبايل',
                        icon: Icons.folder_copy_rounded,
                        iconColor: palette.warning,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PendingUploadsScreen(),
                            ),
                          );
                        },
                      ),
                    if (canManageChat)
                      _ActionListTile(
                        title: 'إدارة الشات',
                        subtitle: 'تحكم في المستخدمين والغرف والغرف النشطة',
                        icon: Icons.admin_panel_settings_rounded,
                        iconColor: palette.success,
                        showTopDivider: isAdmin,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ChatAdminManagementScreen(),
                            ),
                          );
                        },
                      ),
                    if (canViewPrinters)
                      _ActionListTile(
                        title: 'مراقبة الطابعات',
                        subtitle: 'متابعة الفروع وحساب استهلاك الورق',
                        icon: Icons.print_rounded,
                        iconColor: printersColor,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const MobilePrinterMonitoringScreen(),
                            ),
                          );
                        },
                      ),
                    if (canViewItAssets)
                      _ActionListTile(
                        title: 'ماسح أصول IT',
                        subtitle: user?.canManageItInventory == true
                            ? 'مسح QR لعرض الأجهزة أو تسجيل الجرد الفعلي'
                            : 'مسح QR وعرض بيانات الجهاز وسجل حركته',
                        icon: Icons.qr_code_scanner_rounded,
                        iconColor: const Color(0xFF2563EB),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const MobileItAssetScannerScreen(),
                            ),
                          );
                        },
                      ),
                    _ActionListTile(
                      title: 'تذاكر الدعم',
                      subtitle: 'تابع طلباتك وحالة التذاكر المفتوحة',
                      icon: Icons.confirmation_number_rounded,
                      iconColor: ticketsColor,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TicketsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ActionListTile extends StatelessWidget {
  const _ActionListTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.showTopDivider = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final bool showTopDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            if (showTopDivider)
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 64,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: iconColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
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
}

class _SyncStatusBanner extends StatelessWidget {
  const _SyncStatusBanner({required this.state});

  final SyncBannerState state;

  @override
  Widget build(BuildContext context) {
    final color = state.isOffline
        ? const Color(0xFFB45309)
        : const Color(0xFF166534);
    final icon = state.isOffline ? Icons.cloud_off_rounded : Icons.sync_rounded;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementsStrip extends StatefulWidget {
  const _AnnouncementsStrip({required this.announcementsState});

  final AsyncValue<List<AdminAnnouncement>> announcementsState;

  @override
  State<_AnnouncementsStrip> createState() => _AnnouncementsStripState();
}

class _AnnouncementsStripState extends State<_AnnouncementsStrip> {
  final PageController _pageController = PageController(viewportFraction: 0.93);
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Color _toneColor(BuildContext context, String tone) {
    final scheme = Theme.of(context).colorScheme;
    return switch (tone) {
      'success' => const Color(0xFF10B981),
      'warning' => const Color(0xFFF59E0B),
      'critical' => scheme.error,
      _ => scheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return widget.announcementsState.when(
      loading: () => const AnnouncementsSkeletonStrip(),
      error: (_, __) => const SizedBox.shrink(),
      data: (announcements) {
        if (announcements.isEmpty) {
          return const SizedBox.shrink();
        }

        final visible = announcements
            .where((announcement) => announcement.isActive)
            .take(3)
            .toList();
        if (visible.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          children: [
            SizedBox(
              height: 120,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final announcement = visible[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _toneColor(
                          context,
                          announcement.tone,
                        ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _toneColor(
                            context,
                            announcement.tone,
                          ).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHigh
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: isDark ? 0.1 : 0.03,
                                  ),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              announcement.isPinned
                                  ? Icons.push_pin_outlined
                                  : Icons.campaign_outlined,
                              color: _toneColor(context, announcement.tone),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  announcement.title,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: Text(
                                    announcement.message,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.color
                                              ?.withValues(alpha: 0.8),
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (visible.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(visible.length, (index) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 6,
                      width: _currentPage == index ? 16 : 6,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
          ],
        );
      },
    );
  }
}
