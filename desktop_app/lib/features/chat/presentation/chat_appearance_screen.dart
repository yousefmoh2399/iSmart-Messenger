import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/desktop_workspace_sidebar.dart';
import '../../files/presentation/files_dashboard_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../servers/presentation/servers_screen.dart';
import '../../updates/presentation/update_center_screen.dart';
import 'chat_appearance.dart';
import 'chat_dashboard_screen.dart';

class ChatAppearanceScreen extends ConsumerWidget {
  const ChatAppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final prefs = user?.chatPreferences ?? ChatPreferences.defaults;
    final themeMode =
        ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.light;
    final canOpenAdmin = user?.canManageChat == true;

    Future<void> save(ChatPreferences next) async {
      await ref
          .read(authControllerProvider.notifier)
          .updateChatPreferences(next);
    }

    Future<void> saveCustomTheme(ChatCustomTheme next, {String? wallpaperId}) {
      return save(
        prefs.copyWith(
          themeId: 'custom',
          wallpaperId: wallpaperId ?? prefs.wallpaperId,
          customTheme: next,
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: Icon(Icons.arrow_back),
                    ),
                  ),
                  _SectionTitle(
                    title: 'الثيم',
                    subtitle:
                        'كل ثيم له نسخته النهارية والليلية مع الرسالة وخلفية متناسقة.',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: ChatAppearanceCatalog.themes.map((theme) {
                      final selected = prefs.themeId == theme.id;
                      return _ChoiceChipCard(
                        title: theme.title,
                        subtitle: theme.description,
                        selected: selected,
                        swatch: theme.color,
                        onTap: () => save(prefs.copyWith(themeId: theme.id)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed:
                          prefs.themeId == 'system' &&
                              prefs.wallpaperId == 'default'
                          ? null
                          : () => save(
                              prefs.copyWith(
                                themeId: 'system',
                                wallpaperId: 'default',
                              ),
                            ),
                      icon: const Icon(Icons.format_paint_outlined),
                      label: const Text('إرجاع الشكل الافتراضي'),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(
                    title: 'الخلفية',
                    subtitle:
                        'يمكنك ترك الخلفية للثيم نفسه أو اختيار خلفية مستقلة،   .',
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.75,
                    children: ChatAppearanceCatalog.wallpapers.map((wallpaper) {
                      final selected = prefs.wallpaperId == wallpaper.id;
                      return _WallpaperCard(
                        title: wallpaper.title,
                        colors: wallpaper.previewColors,
                        selected: selected,
                        onTap: () =>
                            save(prefs.copyWith(wallpaperId: wallpaper.id)),
                      );
                    }).toList(),
                  ),
                  if (prefs.wallpaperId == 'custom') ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            save(prefs.copyWith(wallpaperId: 'default')),
                        icon: const Icon(Icons.wallpaper_outlined),
                        label: const Text('إلغاء الخلفية المخصصة'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _SectionTitle(
                    title: 'الثيم المخصص',
                    subtitle:
                        'اضبط ألوان الرسالة والخلفية لتعمل كـ chat-specific theme متزامن بين الأجهزة.',
                  ),
                  const SizedBox(height: 10),
                  _ColorPickerCard(
                    title: 'لون التمييز',
                    selectedColor: ChatAppearanceCatalog.colorFromHex(
                      prefs.customTheme.accentColorHex,
                    ),
                    colors: ChatAppearanceCatalog.customAccentSwatches,
                    onSelected: (color) => saveCustomTheme(
                      prefs.customTheme.copyWith(
                        accentColorHex: ChatAppearanceCatalog.colorToHex(color),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _ColorPickerCard(
                          title: 'بداية الرسالة',
                          selectedColor: ChatAppearanceCatalog.colorFromHex(
                            prefs.customTheme.outgoingBubbleColorHexes.first,
                          ),
                          colors: ChatAppearanceCatalog.customBubbleSwatches,
                          onSelected: (color) {
                            final colors = [
                              ...prefs.customTheme.outgoingBubbleColorHexes,
                            ];
                            if (colors.isEmpty) {
                              colors.add(
                                ChatAppearanceCatalog.colorToHex(color),
                              );
                            } else {
                              colors[0] = ChatAppearanceCatalog.colorToHex(
                                color,
                              );
                            }
                            if (colors.length == 1) {
                              colors.add(colors.first);
                            }
                            return saveCustomTheme(
                              prefs.customTheme.copyWith(
                                outgoingBubbleColorHexes: colors,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ColorPickerCard(
                          title: 'نهاية الرسالة',
                          selectedColor: ChatAppearanceCatalog.colorFromHex(
                            prefs.customTheme.outgoingBubbleColorHexes.length >
                                    1
                                ? prefs.customTheme.outgoingBubbleColorHexes[1]
                                : prefs
                                      .customTheme
                                      .outgoingBubbleColorHexes
                                      .first,
                          ),
                          colors: ChatAppearanceCatalog.customBubbleSwatches,
                          onSelected: (color) {
                            final colors = [
                              ...prefs.customTheme.outgoingBubbleColorHexes,
                            ];
                            if (colors.isEmpty) {
                              colors.add(
                                ChatAppearanceCatalog.colorToHex(color),
                              );
                            }
                            if (colors.length == 1) {
                              colors.add(
                                ChatAppearanceCatalog.colorToHex(color),
                              );
                            } else {
                              colors[1] = ChatAppearanceCatalog.colorToHex(
                                color,
                              );
                            }
                            return saveCustomTheme(
                              prefs.customTheme.copyWith(
                                outgoingBubbleColorHexes: colors,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _ColorPickerCard(
                    title: 'لون الرسالة الواردة',
                    selectedColor: ChatAppearanceCatalog.colorFromHex(
                      prefs.customTheme.incomingBubbleColorHex,
                    ),
                    colors: ChatAppearanceCatalog.customBubbleSwatches,
                    onSelected: (color) => saveCustomTheme(
                      prefs.customTheme.copyWith(
                        incomingBubbleColorHex:
                            ChatAppearanceCatalog.colorToHex(color),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _WallpaperPaletteCard(
                    title: 'خلفية الثيم المخصص',
                    selectedColors: prefs.customTheme.wallpaperColorHexes
                        .map(ChatAppearanceCatalog.colorFromHex)
                        .toList(),
                    palettes: ChatAppearanceCatalog.customWallpaperPalettes,
                    onSelected: (colors) => saveCustomTheme(
                      prefs.customTheme.copyWith(
                        wallpaperColorHexes: colors
                            .map(ChatAppearanceCatalog.colorToHex)
                            .toList(),
                      ),
                      wallpaperId: 'custom',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => save(
                            prefs.copyWith(
                              themeId: 'custom',
                              wallpaperId: 'custom',
                            ),
                          ),
                          icon: const Icon(Icons.auto_awesome_outlined),
                          label: const Text('تطبيق الثيم المخصص'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => saveCustomTheme(
                            ChatCustomTheme.defaults,
                            wallpaperId: 'custom',
                          ),
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('إرجاع ألوان الثيم المخصص'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'الإعدادات تحفظ على حسابك وتظهر على أي جهاز مع نسختي نهار/ليل داخل الشات.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            DesktopWorkspaceSidebar(
              user: user,
              activeSection: DesktopWorkspaceSection.chat,
              currentThemeMode: themeMode,
              isDark: themeMode == ThemeMode.dark,
              accentColor: Theme.of(context).colorScheme.primary,
              onOpenChat: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const ChatDashboardScreen()),
              ),
              onRefresh: () => ref.invalidate(authControllerProvider),
              onOpenFiles: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const FilesDashboardScreen()),
              ),
              onOpenServers: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const ServersScreen()),
              ),
              onOpenProfile: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
              onOpenUpdates: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UpdateCenterScreen()),
              ),
              onToggleTheme: () => ref
                  .read(themeModeControllerProvider.notifier)
                  .cycleThemeMode(),
              onOpenTickets: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) =>
                      const ChatDashboardScreen(openTicketsOnStart: true),
                ),
              ),
              onLogout: () =>
                  ref.read(authControllerProvider.notifier).logout(),
              onCreateConversation: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const ChatDashboardScreen()),
              ),
              onOpenAdmin: canOpenAdmin
                  ? () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) =>
                            const ChatDashboardScreen(openAdminOnStart: true),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _ChoiceChipCard extends StatelessWidget {
  const _ChoiceChipCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.swatch,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final Color swatch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? swatch.withValues(alpha: 0.14) : cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? swatch.withValues(alpha: 0.55)
                : cs.outlineVariant,
          ),
        ),
        child: SizedBox(
          width: 192,
          height: MediaQuery.sizeOf(context).height * .09,
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: swatch.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WallpaperCard extends StatelessWidget {
  const _WallpaperCard({
    required this.title,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: 0.7)
                : cs.outlineVariant,
            width: selected ? 1.4 : 1,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -12,
              right: -8,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (selected)
              const Positioned(
                top: 8,
                left: 8,
                child: Icon(Icons.check_circle_rounded, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

class _ColorPickerCard extends StatelessWidget {
  const _ColorPickerCard({
    required this.title,
    required this.selectedColor,
    required this.colors,
    required this.onSelected,
  });

  final String title;
  final Color selectedColor;
  final List<Color> colors;
  final Future<void> Function(Color color) onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: colors.map((color) {
              final selected =
                  ChatAppearanceCatalog.colorToHex(color) ==
                  ChatAppearanceCatalog.colorToHex(selectedColor);
              return InkWell(
                onTap: () => onSelected(color),
                borderRadius: BorderRadius.circular(999),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.28),
                        blurRadius: selected ? 12 : 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
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

class _WallpaperPaletteCard extends StatelessWidget {
  const _WallpaperPaletteCard({
    required this.title,
    required this.selectedColors,
    required this.palettes,
    required this.onSelected,
  });

  final String title;
  final List<Color> selectedColors;
  final List<List<Color>> palettes;
  final Future<void> Function(List<Color> colors) onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: palettes.map((palette) {
              final selected =
                  palette.length == selectedColors.length &&
                  List.generate(
                    palette.length,
                    (index) =>
                        ChatAppearanceCatalog.colorToHex(palette[index]) ==
                        ChatAppearanceCatalog.colorToHex(selectedColors[index]),
                  ).every((entry) => entry);
              return InkWell(
                onTap: () => onSelected(palette),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 124,
                  height: 62,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? cs.primary.withValues(alpha: 0.72)
                          : cs.outlineVariant,
                      width: selected ? 1.5 : 1,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: palette,
                    ),
                  ),
                  child: selected
                      ? const Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                            ),
                          ),
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
