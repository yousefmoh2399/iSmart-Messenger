import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/desktop_workspace_sidebar.dart';
import '../../updates/presentation/update_center_screen.dart';
import 'chat_appearance.dart';

class ChatAppearanceScreen extends ConsumerStatefulWidget {
  const ChatAppearanceScreen({super.key});

  @override
  ConsumerState<ChatAppearanceScreen> createState() =>
      _ChatAppearanceScreenState();
}

class _ChatAppearanceScreenState extends ConsumerState<ChatAppearanceScreen> {
  int _selectedTabIndex = 0; // 0: خلفيات واتساب, 1: السمات الجاهزة, 2: تخصيص يدوي
  String _selectedCategory = 'all'; // 'all', 'whatsapp', 'gradient'
  bool? _previewIsDark; // null: follow app mode, true: force dark, false: force light

  Future<void> _save(ChatPreferences next) async {
    await ref.read(authControllerProvider.notifier).updateChatPreferences(next);
  }

  Future<void> _saveCustomTheme(
    ChatPreferences currentPrefs,
    ChatCustomTheme next, {
    String? wallpaperId,
  }) {
    return _save(
      currentPrefs.copyWith(
        themeId: 'custom',
        wallpaperId: wallpaperId ?? currentPrefs.wallpaperId,
        customTheme: next,
      ),
    );
  }

  void _resetToDefaults() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة المظهر الافتراضي'),
        content: const Text(
          'هل تريد إعادة ضبط السمة والخلفية وزخارف واتساب إلى المظهر الافتراضي القياسي؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _save(ChatPreferences.defaults);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تمت استعادة المظهر الافتراضي بنجاح'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final prefs = user?.chatPreferences ?? ChatPreferences.defaults;
    final themeMode =
        ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.light;
    final appIsDark = themeMode == ThemeMode.dark;
    final previewDark = _previewIsDark ?? appIsDark;
    final canOpenAdmin = user?.canManageChat == true;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final scaffoldBg = appIsDark
        ? const Color(0xFF0F141A)
        : const Color(0xFFF6F8FA);
    final cardBg = appIsDark ? const Color(0xFF1B222C) : Colors.white;
    final borderColor = appIsDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: SafeArea(
        child: Row(
          children: [
            // ── Main Content Area (Controls + Live Preview Mockup) ─────────
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 960;

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Controls Area (Left side in LTR, Right side in RTL)
                      Expanded(
                        flex: isWide ? 6 : 1,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: borderColor,
                                width: 1,
                              ),
                            ),
                          ),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
                            children: [
                              // Top Bar: Back button, Title & Action controls
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'رجوع للمحادثات',
                                    icon: const Icon(
                                      Icons.arrow_back_rounded,
                                      size: 22,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                    style: IconButton.styleFrom(
                                      backgroundColor: cardBg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(color: borderColor),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'استوديو مظهر المحادثات',
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'خصص خلفيات واتساب الأيقونية والسمات وزخارف الدودلز المتزامنة عبر جميع أجهزتك',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton.icon(
                                    onPressed: _resetToDefaults,
                                    icon: const Icon(
                                      Icons.restart_alt_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('استعادة الافتراضي'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

                              // WhatsApp Doodles Switcher Card
                              _WhatsAppDoodlesCard(
                                enabled: prefs.doodles,
                                cardBg: cardBg,
                                borderColor: borderColor,
                                onChanged: (val) =>
                                    _save(prefs.copyWith(doodles: val)),
                              ),

                              const SizedBox(height: 20),

                              // Modern Segmented Tab Switcher
                              _DesktopSegmentedTabs(
                                selectedIndex: _selectedTabIndex,
                                onChanged: (idx) {
                                  setState(() => _selectedTabIndex = idx);
                                },
                              ),

                              const SizedBox(height: 20),

                              // Tab View Content
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: switch (_selectedTabIndex) {
                                  0 => _DesktopWallpapersView(
                                      key: const ValueKey('wallpapers_tab'),
                                      preferences: prefs,
                                      isDark: previewDark,
                                      cardBg: cardBg,
                                      borderColor: borderColor,
                                      selectedCategory: _selectedCategory,
                                      onCategoryChanged: (cat) => setState(
                                        () => _selectedCategory = cat,
                                      ),
                                      onSave: _save,
                                    ),
                                  1 => _DesktopThemesView(
                                      key: const ValueKey('themes_tab'),
                                      preferences: prefs,
                                      isDark: previewDark,
                                      cardBg: cardBg,
                                      borderColor: borderColor,
                                      onSave: _save,
                                    ),
                                  _ => _DesktopCustomizerView(
                                      key: const ValueKey('customizer_tab'),
                                      preferences: prefs,
                                      isDark: previewDark,
                                      cardBg: cardBg,
                                      borderColor: borderColor,
                                      onSaveCustom: (custom, {wallpaperId}) =>
                                          _saveCustomTheme(
                                        prefs,
                                        custom,
                                        wallpaperId: wallpaperId,
                                      ),
                                      onSavePrefs: _save,
                                    ),
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Live Interactive Chat Preview Mockup (Right side)
                      if (isWide)
                        Expanded(
                          flex: 4,
                          child: Container(
                            color: appIsDark
                                ? const Color(0xFF0C1015)
                                : const Color(0xFFF0F4F8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 20,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Preview Header with Light/Dark Mode Toggle
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF22C55E),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'معاينة حية للمحادثة',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    const Spacer(),
                                    // Mode switcher toggle
                                    Container(
                                      decoration: BoxDecoration(
                                        color: cardBg,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: borderColor),
                                      ),
                                      padding: const EdgeInsets.all(3),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _ModeTogglePill(
                                            icon: Icons.light_mode_rounded,
                                            tooltip: 'معاينة المظهر النهاري',
                                            active: !previewDark,
                                            onTap: () => setState(
                                              () => _previewIsDark = false,
                                            ),
                                          ),
                                          _ModeTogglePill(
                                            icon: Icons.dark_mode_rounded,
                                            tooltip: 'معاينة المظهر الليلي',
                                            active: previewDark,
                                            onTap: () => setState(
                                              () => _previewIsDark = true,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),

                                // Realistic Desktop Chat Frame Mockup
                                Expanded(
                                  child: _DesktopLiveChatMockup(
                                    preferences: prefs,
                                    isDark: previewDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // ── Desktop Workspace Standard Sidebar ────────────────────────
            DesktopWorkspaceSidebar(
              user: user,
              activeSection: DesktopWorkspaceSection.chat,
              currentThemeMode: themeMode,
              isDark: appIsDark,
              accentColor: cs.primary,
              onOpenChat: () => ref.read(activeSectionProvider.notifier).state =
                  DesktopWorkspaceSection.chat,
              onRefresh: () => ref.invalidate(authControllerProvider),
              onOpenFiles: () =>
                  ref.read(activeSectionProvider.notifier).state =
                      DesktopWorkspaceSection.files,
              onOpenServers: () =>
                  ref.read(activeSectionProvider.notifier).state =
                      DesktopWorkspaceSection.servers,
              onOpenProfile: () =>
                  ref.read(activeSectionProvider.notifier).state =
                      DesktopWorkspaceSection.profile,
              onOpenUpdates: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UpdateCenterScreen()),
              ),
              onToggleTheme: () => ref
                  .read(themeModeControllerProvider.notifier)
                  .cycleThemeMode(),
              onOpenTickets: () =>
                  ref.read(activeSectionProvider.notifier).state =
                      DesktopWorkspaceSection.tickets,
              onLogout: () =>
                  ref.read(authControllerProvider.notifier).logout(),
              onCreateConversation: () => ref
                  .read(activeSectionProvider.notifier)
                  .state = DesktopWorkspaceSection.chat,
              onOpenAdmin: canOpenAdmin
                  ? () => ref.read(activeSectionProvider.notifier).state =
                      DesktopWorkspaceSection.admin
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WhatsApp Doodles Toggle Card
// ─────────────────────────────────────────────────────────────────────────────
class _WhatsAppDoodlesCard extends StatelessWidget {
  const _WhatsAppDoodlesCard({
    required this.enabled,
    required this.cardBg,
    required this.borderColor,
    required this.onChanged,
  });

  final bool enabled;
  final Color cardBg;
  final Color borderColor;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled
              ? const Color(0xFF00A884).withValues(alpha: 0.35)
              : borderColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF00A884).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.draw_rounded,
              color: Color(0xFF00A884),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'رسومات وزخارف واتساب (Doodles)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00A884).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'WhatsApp Signature',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF00A884),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'إظهار الرموز والزخارف الكلاسيكية الشفافة (الساعة، الفنجان، الكاميرا، القلب، الطائرة) المتكررة بنعومة فوق خلفية المحادثة',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: enabled,
            activeColor: const Color(0xFF00A884),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop Segmented Tab Switcher
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopSegmentedTabs extends StatelessWidget {
  const _DesktopSegmentedTabs({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B222C) : const Color(0xFFE9EEF4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _TabPill(
            title: 'خلفيات واتساب ومميزة',
            icon: Icons.wallpaper_rounded,
            selected: selectedIndex == 0,
            onTap: () => onChanged(0),
          ),
          _TabPill(
            title: 'السمات الجاهزة',
            icon: Icons.palette_outlined,
            selected: selectedIndex == 1,
            onTap: () => onChanged(1),
          ),
          _TabPill(
            title: 'تخصيص يدوي متقدم',
            icon: Icons.tune_rounded,
            selected: selectedIndex == 2,
            onTap: () => onChanged(2),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? const Color(0xFF242E3D) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.25 : 0.06,
                      ),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mode Toggle Pill
// ─────────────────────────────────────────────────────────────────────────────
class _ModeTogglePill extends StatelessWidget {
  const _ModeTogglePill({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 16,
            color: active
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop Wallpapers Tab View
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopWallpapersView extends StatelessWidget {
  const _DesktopWallpapersView({
    super.key,
    required this.preferences,
    required this.isDark,
    required this.cardBg,
    required this.borderColor,
    required this.selectedCategory,
    required this.onCategoryChanged,
    required this.onSave,
  });

  final ChatPreferences preferences;
  final bool isDark;
  final Color cardBg;
  final Color borderColor;
  final String selectedCategory;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<ChatPreferences> onSave;

  @override
  Widget build(BuildContext context) {
    final filteredWallpapers = ChatAppearanceCatalog.wallpapers.where((w) {
      if (selectedCategory == 'all') return true;
      return w.category == selectedCategory;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category Filter Chips
        Row(
          children: [
            _FilterChipPill(
              label: 'الكل (${ChatAppearanceCatalog.wallpapers.length})',
              selected: selectedCategory == 'all',
              onTap: () => onCategoryChanged('all'),
            ),
            const SizedBox(width: 8),
            _FilterChipPill(
              label: 'خلفيات واتساب الأصلية 💬',
              selected: selectedCategory == 'whatsapp',
              onTap: () => onCategoryChanged('whatsapp'),
            ),
            const SizedBox(width: 8),
            _FilterChipPill(
              label: 'تدرجات هادئة 🎨',
              selected: selectedCategory == 'gradient',
              onTap: () => onCategoryChanged('gradient'),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Wallpaper Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredWallpapers.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
          ),
          itemBuilder: (context, index) {
            final wallpaper = filteredWallpapers[index];
            final selected = preferences.wallpaperId == wallpaper.id;

            return _DesktopWallpaperCard(
              wallpaper: wallpaper,
              selected: selected,
              isDark: isDark,
              showDoodles: preferences.doodles && wallpaper.hasDoodles,
              onTap: () => onSave(preferences.copyWith(wallpaperId: wallpaper.id)),
            );
          },
        ),

        if (preferences.wallpaperId == 'custom') ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => onSave(preferences.copyWith(wallpaperId: 'wa_classic')),
              icon: const Icon(Icons.undo_rounded, size: 16),
              label: const Text('إلغاء الخلفية المخصصة والعودة لواتساب'),
            ),
          ),
        ],
      ],
    );
  }
}

class _FilterChipPill extends StatelessWidget {
  const _FilterChipPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary
              : (isDark ? const Color(0xFF1B222C) : const Color(0xFFE9EEF4)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

class _DesktopWallpaperCard extends StatelessWidget {
  const _DesktopWallpaperCard({
    required this.wallpaper,
    required this.selected,
    required this.isDark,
    required this.showDoodles,
    required this.onTap,
  });

  final ChatWallpaperOption wallpaper;
  final bool selected;
  final bool isDark;
  final bool showDoodles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = isDark ? wallpaper.darkColors : wallpaper.lightColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? const Color(0xFF00A884)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.10)),
            width: selected ? 2.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? const Color(0xFF00A884).withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: selected ? 10 : 4,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Wallpaper gradient
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors.length > 1 ? colors : [colors.first, colors.first],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),

              // Wallpaper doodles preview
              if (showDoodles)
                Positioned.fill(
                  child: CustomPaint(
                    painter: WhatsAppDoodlePainter(
                      doodleColor: isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : const Color(0xFF334155).withValues(alpha: 0.09),
                    ),
                  ),
                ),

              // Bottom Title Overlay Pill
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.black : Colors.white)
                        .withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          wallpaper.title,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selected)
                        Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00A884),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 11,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop Themes Tab View
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopThemesView extends StatelessWidget {
  const _DesktopThemesView({
    super.key,
    required this.preferences,
    required this.isDark,
    required this.cardBg,
    required this.borderColor,
    required this.onSave,
  });

  final ChatPreferences preferences;
  final bool isDark;
  final Color cardBg;
  final Color borderColor;
  final ValueChanged<ChatPreferences> onSave;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: ChatAppearanceCatalog.themes.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (context, index) {
        final themeOption = ChatAppearanceCatalog.themes[index];
        final selected = preferences.themeId == themeOption.id;

        return _DesktopThemeCard(
          themeOption: themeOption,
          selected: selected,
          isDark: isDark,
          cardBg: cardBg,
          borderColor: borderColor,
          onTap: () {
            final defaultWp = switch (themeOption.id) {
              'whatsapp' => 'wa_classic',
              'ios' => 'wa_slate',
              'classic' => 'wa_midnight',
              'mint' => 'wa_emerald',
              'sunset' => 'wa_peach',
              'mono' => 'wa_dark_oled',
              _ => preferences.wallpaperId,
            };
            onSave(
              preferences.copyWith(
                themeId: themeOption.id,
                wallpaperId: defaultWp,
              ),
            );
          },
        );
      },
    );
  }
}

class _DesktopThemeCard extends StatelessWidget {
  const _DesktopThemeCard({
    required this.themeOption,
    required this.selected,
    required this.isDark,
    required this.cardBg,
    required this.borderColor,
    required this.onTap,
  });

  final ChatThemeOption themeOption;
  final bool selected;
  final bool isDark;
  final Color cardBg;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final outColor = isDark
        ? themeOption.outgoingDarkColor
        : themeOption.outgoingLightColor;
    final inColor = isDark
        ? themeOption.incomingDarkColor
        : themeOption.incomingLightColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? themeOption.color
                : borderColor,
            width: selected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? themeOption.color.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.03),
              blurRadius: selected ? 10 : 4,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left: Text details & badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: themeOption.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          themeOption.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (themeOption.badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: themeOption.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            themeOption.badge!,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: themeOption.color,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    themeOption.description,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Right: Realistic Mini Sample Chat Bubbles
            Container(
              width: 110,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131820) : const Color(0xFFEFEFEF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Incoming mini bubble
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: inColor,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                      child: Text(
                        'مرحباً! 💬',
                        style: TextStyle(
                          fontSize: 9,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Outgoing mini bubble
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: outColor,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'أهلاً بك ✓✓',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: themeOption.id == 'ios'
                                  ? Colors.white
                                  : (isDark ? Colors.white : const Color(0xFF111B21)),
                            ),
                          ),
                        ],
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Desktop Customizer Tab View
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopCustomizerView extends StatelessWidget {
  const _DesktopCustomizerView({
    super.key,
    required this.preferences,
    required this.isDark,
    required this.cardBg,
    required this.borderColor,
    required this.onSaveCustom,
    required this.onSavePrefs,
  });

  final ChatPreferences preferences;
  final bool isDark;
  final Color cardBg;
  final Color borderColor;
  final void Function(ChatCustomTheme, {String? wallpaperId}) onSaveCustom;
  final ValueChanged<ChatPreferences> onSavePrefs;

  @override
  Widget build(BuildContext context) {
    final custom = preferences.customTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Accent Color Swatch
        _ColorPickerTile(
          title: 'لون التمييز والأزرار الرئيسي',
          subtitle: 'لون أيقونات الإرسال، البحث، والروابط داخل المحادثة',
          selectedColor: ChatAppearanceCatalog.colorFromHex(custom.accentColorHex),
          colors: ChatAppearanceCatalog.customAccentSwatches,
          cardBg: cardBg,
          borderColor: borderColor,
          onSelected: (color) => onSaveCustom(
            custom.copyWith(
              accentColorHex: ChatAppearanceCatalog.colorToHex(color),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Outgoing Bubble Gradient Start & End
        Row(
          children: [
            Expanded(
              child: _ColorPickerTile(
                title: 'بداية تدرج الرسالة الصادرة',
                subtitle: 'اللون العلوي لفقاعتك',
                selectedColor: ChatAppearanceCatalog.colorFromHex(
                  custom.outgoingBubbleColorHexes.first,
                ),
                colors: ChatAppearanceCatalog.customBubbleSwatches,
                cardBg: cardBg,
                borderColor: borderColor,
                onSelected: (color) {
                  final list = [...custom.outgoingBubbleColorHexes];
                  if (list.isEmpty) {
                    list.add(ChatAppearanceCatalog.colorToHex(color));
                  } else {
                    list[0] = ChatAppearanceCatalog.colorToHex(color);
                  }
                  if (list.length == 1) list.add(list.first);
                  onSaveCustom(custom.copyWith(outgoingBubbleColorHexes: list));
                },
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _ColorPickerTile(
                title: 'نهاية تدرج الرسالة الصادرة',
                subtitle: 'اللون السفلي لفقاعتك',
                selectedColor: ChatAppearanceCatalog.colorFromHex(
                  custom.outgoingBubbleColorHexes.length > 1
                      ? custom.outgoingBubbleColorHexes[1]
                      : custom.outgoingBubbleColorHexes.first,
                ),
                colors: ChatAppearanceCatalog.customBubbleSwatches,
                cardBg: cardBg,
                borderColor: borderColor,
                onSelected: (color) {
                  final list = [...custom.outgoingBubbleColorHexes];
                  if (list.length < 2) {
                    list.add(ChatAppearanceCatalog.colorToHex(color));
                  } else {
                    list[1] = ChatAppearanceCatalog.colorToHex(color);
                  }
                  onSaveCustom(custom.copyWith(outgoingBubbleColorHexes: list));
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Incoming Bubble Color
        _ColorPickerTile(
          title: 'لون فقاعة الرسائل الواردة',
          subtitle: 'لون خلفية رسائل الطرف الآخر',
          selectedColor:
              ChatAppearanceCatalog.colorFromHex(custom.incomingBubbleColorHex),
          colors: ChatAppearanceCatalog.customBubbleSwatches,
          cardBg: cardBg,
          borderColor: borderColor,
          onSelected: (color) => onSaveCustom(
            custom.copyWith(
              incomingBubbleColorHex: ChatAppearanceCatalog.colorToHex(color),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Custom Wallpaper Palette
        _CustomPaletteTile(
          title: 'تدرج خلفية الثيم المخصص',
          subtitle: 'اختر لوحة الألوان الخلفية المتدرجة للثيم المخصص',
          selectedColors: custom.wallpaperColorHexes
              .map(ChatAppearanceCatalog.colorFromHex)
              .toList(),
          palettes: ChatAppearanceCatalog.customWallpaperPalettes,
          cardBg: cardBg,
          borderColor: borderColor,
          onSelected: (colors) => onSaveCustom(
            custom.copyWith(
              wallpaperColorHexes:
                  colors.map(ChatAppearanceCatalog.colorToHex).toList(),
            ),
            wallpaperId: 'custom',
          ),
        ),

        const SizedBox(height: 18),

        // Action buttons
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => onSavePrefs(
                preferences.copyWith(
                  themeId: 'custom',
                  wallpaperId: 'custom',
                ),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('تفعيل الثيم المخصص الآن'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => onSaveCustom(
                ChatCustomTheme.defaults,
                wallpaperId: 'custom',
              ),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('إرجاع ألوان الثيم المخصص القياسية'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ColorPickerTile extends StatelessWidget {
  const _ColorPickerTile({
    required this.title,
    required this.subtitle,
    required this.selectedColor,
    required this.colors,
    required this.cardBg,
    required this.borderColor,
    required this.onSelected,
  });

  final String title;
  final String subtitle;
  final Color selectedColor;
  final List<Color> colors;
  final Color cardBg;
  final Color borderColor;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: selectedColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: selectedColor.withValues(alpha: 0.35),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11.5,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors.map((c) {
              final isMatch = ChatAppearanceCatalog.colorToHex(c) ==
                  ChatAppearanceCatalog.colorToHex(selectedColor);

              return InkWell(
                onTap: () => onSelected(c),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isMatch ? cs.primary : Colors.black12,
                      width: isMatch ? 2.5 : 1.0,
                    ),
                    boxShadow: isMatch
                        ? [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.35),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                  child: isMatch
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: Colors.white,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _CustomPaletteTile extends StatelessWidget {
  const _CustomPaletteTile({
    required this.title,
    required this.subtitle,
    required this.selectedColors,
    required this.palettes,
    required this.cardBg,
    required this.borderColor,
    required this.onSelected,
  });

  final String title;
  final String subtitle;
  final List<Color> selectedColors;
  final List<List<Color>> palettes;
  final Color cardBg;
  final Color borderColor;
  final ValueChanged<List<Color>> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11.5,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: palettes.map((palette) {
              final isMatch = palette.length == selectedColors.length &&
                  ChatAppearanceCatalog.colorToHex(palette.first) ==
                      ChatAppearanceCatalog.colorToHex(selectedColors.first);

              return InkWell(
                onTap: () => onSelected(palette),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 58,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: palette,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: isMatch ? cs.primary : Colors.black12,
                      width: isMatch ? 2.5 : 1.0,
                    ),
                    boxShadow: isMatch
                        ? [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.35),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                  child: isMatch
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: Colors.white,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop Realistic Live Chat Mockup (Right Pane)
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopLiveChatMockup extends StatelessWidget {
  const _DesktopLiveChatMockup({
    required this.preferences,
    required this.isDark,
  });

  final ChatPreferences preferences;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = ChatAppearanceCatalog.resolveAppearance(
      preferences: preferences,
      isDark: isDark,
      colorScheme: theme.colorScheme,
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.10),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Backdrop (Live wallpaper + authentic WhatsApp vector doodles)
          Positioned.fill(
            child: ChatBackdrop(
              preferences: preferences,
              isDark: isDark,
            ),
          ),

          // Chat Window Foreground
          Column(
            children: [
              // Mockup Window App Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: (isDark
                          ? const Color(0xFF1B222C)
                          : Colors.white)
                      .withValues(alpha: 0.90),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Mock Peer Avatar with online dot
                    Stack(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                resolved.accent,
                                resolved.accent.withValues(alpha: 0.65),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.support_agent_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF1B222C)
                                    : Colors.white,
                                width: 1.8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    // Peer Name & Status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'فريق الدعم الفني وتجربة المستخدم',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            children: [
                              Text(
                                'متصل الآن • يكتب الآن...',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: resolved.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Action Icons
                    Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.videocam_outlined,
                      size: 20,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.call_outlined,
                      size: 19,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                  ],
                ),
              ),

              // Mockup Messages Area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: ListView(
                    children: [
                      // Date separator pill
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (isDark
                                    ? const Color(0xFF1B222C)
                                    : Colors.white)
                                .withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Text(
                            'اليوم',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // 1. Incoming Message Bubble
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                          decoration: BoxDecoration(
                            color: resolved.incomingBubbleColor,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                              bottomLeft: Radius.circular(4),
                              bottomRight: Radius.circular(16),
                            ),
                            border: Border.all(
                              color: resolved.incomingBorderColor,
                              width: 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.25 : 0.05,
                                ),
                                blurRadius: 4,
                                offset: const Offset(0, 1.5),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'مرحباً بك! 👋 جرب اختيار أي خلفية أو سمة من لوحة التحكم لتشاهد التحول الفوري أمامك الآن.',
                                style: TextStyle(
                                  color: resolved.incomingTextColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: AlignmentDirectional.bottomEnd,
                                child: Text(
                                  '10:30 ص',
                                  style: TextStyle(
                                    color: resolved.incomingTextColor
                                        .withValues(alpha: 0.55),
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // 2. Outgoing Message Bubble with Reply Quote
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 330),
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                          decoration: BoxDecoration(
                            gradient: resolved.hasOutgoingGradient
                                ? LinearGradient(
                                    colors: resolved.outgoingBubbleColors,
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  )
                                : null,
                            color: resolved.hasOutgoingGradient
                                ? null
                                : resolved.outgoingBubbleColors.first,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(4),
                            ),
                            border: Border.all(
                              color: resolved.outgoingBorderColor,
                              width: 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.25 : 0.06,
                                ),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Reply Quote Banner
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: resolved.outgoingReplyColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border(
                                    right: BorderSide(
                                      color: resolved.accent,
                                      width: 3.5,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'فريق الدعم الفني',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: resolved.accent,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'مرحباً بك! جرب اختيار أي خلفية...',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: resolved.outgoingTextColor
                                            .withValues(alpha: 0.75),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'خلفيات واتساب وزخارف الدودلز المتكررة تعطي مظهراً رائعاً ومريحاً للغاية للعين! 🚀✨',
                                style: TextStyle(
                                  color: resolved.outgoingTextColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    '10:32 ص',
                                    style: TextStyle(
                                      color: resolved.outgoingTextColor
                                          .withValues(alpha: 0.65),
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.done_all_rounded,
                                    size: 15,
                                    color: Color(0xFF34B7F1), // WhatsApp Blue Read Ticks
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // 3. Audio Voice Note Bubble
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 290),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: resolved.hasOutgoingGradient
                                ? resolved.outgoingBubbleColors.first
                                : resolved.outgoingBubbleColors.first,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: resolved.outgoingBorderColor,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: resolved.accent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Audio waveform visualizer bars
                                    Row(
                                      children: List.generate(
                                        22,
                                        (i) => Expanded(
                                          child: Container(
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 1.2,
                                            ),
                                            height: 4.0 + (i * 7 % 14),
                                            decoration: BoxDecoration(
                                              color: resolved.outgoingTextColor
                                                  .withValues(
                                                alpha: i < 10 ? 0.9 : 0.35,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '0:24',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: resolved.outgoingTextColor
                                                .withValues(alpha: 0.7),
                                          ),
                                        ),
                                        const Icon(
                                          Icons.done_all_rounded,
                                          size: 13,
                                          color: Color(0xFF34B7F1),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Mockup Chat Input Field Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: (isDark
                          ? const Color(0xFF1B222C)
                          : Colors.white)
                      .withValues(alpha: 0.92),
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.emoji_emotions_outlined,
                      size: 20,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.attach_file_rounded,
                      size: 20,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF131820)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'اكتب رسالة تجريبية...',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: resolved.accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: resolved.accent.withValues(alpha: 0.35),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 17,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
