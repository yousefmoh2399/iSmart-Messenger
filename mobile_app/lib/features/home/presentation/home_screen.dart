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
    final remoteDocsState = ref.watch(remoteDocumentsControllerProvider);
    final localDocsState = ref.watch(pendingUploadsControllerProvider);
    final themeMode =
        ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.light;
    final syncBanner = ref.watch(syncBannerStateProvider);

    final user = authState.valueOrNull;
    final draftPagesCount = draftState.valueOrNull?.pages.length ?? 0;
    final hasDraft = draftPagesCount > 0;
    final cloudFilesCount = remoteDocsState.valueOrNull?.length ?? 0;
    final localFilesCount = localDocsState.valueOrNull?.length ?? 0;

    final isAdmin = user?.isAdmin == true;
    final canManageChat = user?.canManageChat == true;
    final canViewPrinters = user?.canViewPrinterModule == true;
    final canViewItAssets =
        user?.canScanItAssets == true ||
        user?.canScanItSpareParts == true ||
        user?.canScanItInventory == true;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.appThemePalette;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    final printersColor = isDark
        ? const Color(0xFF14B8A6)
        : const Color(0xFF0D9488);
    final ticketsColor = isDark
        ? const Color(0xFF8B5CF6)
        : const Color(0xFF6D28D9);

    final avatarLetter = user?.fullName.trim().isNotEmpty == true
        ? user!.fullName.trim()[0].toUpperCase()
        : (user?.username.trim().isNotEmpty == true
              ? user!.username.trim()[0].toUpperCase()
              : 'U');

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text(
          'مركز المستندات والعمليات',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث البيانات',
            onPressed: () {
              ref.read(remoteDocumentsControllerProvider.notifier).refresh();
              ref.read(pendingUploadsControllerProvider.notifier).refresh();
              ref.read(announcementsControllerProvider.notifier).refresh();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
        children: [
          // 1. Apple iOS Bento Profile & Live Counters Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: borderCol),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            palette.accent,
                            palette.accent.withValues(alpha: 0.72),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          avatarLetter,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
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
                            'مرحباً، ${user?.fullName ?? user?.username ?? 'مستخدم النظام'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
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
                                  horizontal: 9,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.accent.withValues(alpha: 0.13),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isAdmin ? 'مسؤول النظام (Admin)' : 'حساب موظف',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: palette.accent,
                                  ),
                                ),
                              ),
                              if ((user?.branchCode ?? '').isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.07)
                                        : const Color(0xFFF2F2F7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'فرع ${user!.branchCode}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
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
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _BentoQuickStat(
                        label: 'الملفات السحابية',
                        value: '$cloudFilesCount',
                        icon: Icons.cloud_done_rounded,
                        color: const Color(0xFF007AFF),
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _BentoQuickStat(
                        label: 'الملفات المحلية',
                        value: '$localFilesCount',
                        icon: Icons.folder_special_rounded,
                        color: const Color(0xFFF59E0B),
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _BentoQuickStat(
                        label: 'صفحات المسودة',
                        value: '$draftPagesCount',
                        icon: Icons.document_scanner_rounded,
                        color: const Color(0xFF10B981),
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Sync Offline / Progress Banner
          if (syncBanner.isOffline || syncBanner.isSyncing) ...[
            _SyncStatusBanner(state: syncBanner),
            const SizedBox(height: 12),
          ],

          // 3. System Announcements Strip
          _AnnouncementsStrip(announcementsState: announcementsState),

          // 4. Saved Draft Notice Banner
          if (hasDraft) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.restore_page_rounded,
                      color: Color(0xFFD97706),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'مسودة مسح محفوظة غير مكتملة',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB45309),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'تحتوي على $draftPagesCount صفحات جاهزة للاستكمال والحفظ.',
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
                      padding: const EdgeInsets.symmetric(horizontal: 14),
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

          // 5. Section Header: الماسح الضوئي والمستندات
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10, right: 4),
            child: Text(
              'الماسح الضوئي والمستندات',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
          ),

          // 6. Hero Gradient Card: مسح مستند جديد (Visible for ALL users)
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
              borderRadius: BorderRadius.circular(22),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF007AFF), Color(0xFF2563EB)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(18),
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
                            const Text(
                              'مسح مستند جديد بالكاميرا',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 17.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'التقط الصفحات مع قص تلقائي للحواف وتحويل فوري إلى PDF عالي الدقة.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.camera_alt_rounded,
                                    size: 15,
                                    color: Color(0xFF007AFF),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'ابدأ المسح الضوئي الآن',
                                    style: TextStyle(
                                      color: Color(0xFF007AFF),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
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
          const SizedBox(height: 12),

          // 7. 2-Column Bento Grid: ملفاتي السحابية + ملفاتي المحلية
          Row(
            children: [
              Expanded(
                child: _BentoFeatureCard(
                  title: 'ملفاتي السحابية',
                  subtitle: 'المرفوعة والمشتركة والمجلدات',
                  badgeText: '$cloudFilesCount ملف',
                  icon: Icons.cloud_done_rounded,
                  accentColor: const Color(0xFF007AFF),
                  cardBg: cardBg,
                  borderCol: borderCol,
                  isDark: isDark,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MyFilesScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BentoFeatureCard(
                  title: 'ملفاتي المحلية',
                  subtitle: 'الممسوحة والمحفوظة بالهاتف',
                  badgeText: '$localFilesCount ملف',
                  icon: Icons.folder_special_rounded,
                  accentColor: const Color(0xFFF59E0B),
                  cardBg: cardBg,
                  borderCol: borderCol,
                  isDark: isDark,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PendingUploadsScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 8. Quick Action Card: إرسال ملف مباشرة للكمبيوتر
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderCol),
            ),
            child: _ActionListTile(
              title: 'إرسال ملف مباشر للكمبيوتر أو الطابعة',
              subtitle:
                  'اختر ملفاً من جهازك لإرساله فوراً لسطح المكتب أو طباعته عن بعد',
              icon: Icons.desktop_windows_rounded,
              iconColor: const Color(0xFF0EA5E9),
              showTopDivider: false,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MyFilesScreen(
                      launchDesktopSendPickerOnOpen: true,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // 9. Section Header: العمليات والإدارة
          Padding(
            padding: const EdgeInsets.only(bottom: 10, right: 4),
            child: Text(
              'العمليات والإدارة',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
          ),

          // 10. Bento Group for Operations & Admin
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderCol),
            ),
            child: Column(
              children: [
                if (canManageChat)
                  _ActionListTile(
                    title: 'إدارة الشات والغرف والمجموعات',
                    subtitle:
                        'التحكم في الموظفين، الأقسام، المجموعات، وقنوات البث',
                    icon: Icons.admin_panel_settings_rounded,
                    iconColor: palette.success,
                    showTopDivider: false,
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
                    title: 'مراقبة الطابعات والأحبار',
                    subtitle: 'متابعة حالة الطابعات بالفروع واستهلاك الورق',
                    icon: Icons.print_rounded,
                    iconColor: printersColor,
                    showTopDivider: canManageChat,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MobilePrinterMonitoringScreen(),
                        ),
                      );
                    },
                  ),
                if (canViewItAssets)
                  _ActionListTile(
                    title: 'ماسح أصول ومخزون IT',
                    subtitle: user?.canManageItInventory == true
                        ? 'مسح QR لعرض الأجهزة أو تسجيل الجرد الفعلي'
                        : 'مسح QR وعرض بيانات الجهاز وسجل حركته',
                    icon: Icons.qr_code_scanner_rounded,
                    iconColor: const Color(0xFF2563EB),
                    showTopDivider: canManageChat || canViewPrinters,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MobileItAssetScannerScreen(),
                        ),
                      );
                    },
                  ),
                _ActionListTile(
                  title: 'تذاكر الدعم الفني',
                  subtitle: 'متابعة طلبات الصيانة والدعم وحالة التذاكر المفتوحة',
                  icon: Icons.confirmation_number_rounded,
                  iconColor: ticketsColor,
                  showTopDivider:
                      canManageChat || canViewPrinters || canViewItAssets,
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
      ),
    );
  }
}

class _BentoQuickStat extends StatelessWidget {
  const _BentoQuickStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _BentoFeatureCard extends StatelessWidget {
  const _BentoFeatureCard({
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.icon,
    required this.accentColor,
    required this.cardBg,
    required this.borderCol,
    required this.isDark,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String badgeText;
  final IconData icon;
  final Color accentColor;
  final Color cardBg;
  final Color borderCol;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
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
                      color: accentColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: accentColor, size: 22),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: accentColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
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
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? Colors.white60 : Colors.black54,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 21),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.45,
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
