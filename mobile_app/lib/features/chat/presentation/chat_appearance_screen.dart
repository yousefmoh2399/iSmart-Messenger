import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import 'chat_appearance.dart';

class ChatAppearanceScreen extends ConsumerWidget {
  const ChatAppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final prefs = user?.chatPreferences ?? ChatPreferences.defaults;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

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
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('مظهر المحادثات'),
        backgroundColor: scaffoldBg,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _SectionTitle(
            title: 'الثيم',
            subtitle:
                'تلجرام يربط كل ثيم بنسخة فاتحة وداكنة. هنا نفس الفكرة داخل الشات.',
          ),
          const SizedBox(height: 8),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: ChatAppearanceCatalog.themes.asMap().entries.map((
                entry,
              ) {
                final index = entry.key;
                final theme = entry.value;
                final isLast = index == ChatAppearanceCatalog.themes.length - 1;
                final selected = prefs.themeId == theme.id;

                return Column(
                  children: [
                    ListTile(
                      onTap: () => save(
                        prefs.copyWith(
                          themeId: theme.id,
                          wallpaperId: theme.id == 'system'
                              ? prefs.wallpaperId
                              : prefs.wallpaperId,
                        ),
                      ),
                      leading: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: theme.color,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: theme.color.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      title: Text(
                        theme.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        theme.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: selected
                          ? const Icon(Icons.check, color: Colors.blue)
                          : null,
                    ),
                    if (!isLast)
                      const Divider(height: 0.5, thickness: 0.5, indent: 56),
                  ],
                );
              }).toList(),
            ),
          ),
          if (prefs.themeId != 'system' || prefs.wallpaperId != 'default') ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => save(
                prefs.copyWith(themeId: 'system', wallpaperId: 'default'),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                alignment: Alignment.centerRight,
              ),
              child: const Text('إرجاع الشكل الافتراضي'),
            ),
          ],
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'الخلفية',
            subtitle:
                'الخلفية الآن تتبدل مع الثيم المختار، ويمكنك أيضًا تخصيصها يدويًا.',
          ),
          const SizedBox(height: 8),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(16),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.85,
              children: ChatAppearanceCatalog.wallpapers.map((wallpaper) {
                final selected = prefs.wallpaperId == wallpaper.id;
                return _WallpaperCard(
                  title: wallpaper.title,
                  colors: wallpaper.previewColors,
                  selected: selected,
                  onTap: () => save(prefs.copyWith(wallpaperId: wallpaper.id)),
                );
              }).toList(),
            ),
          ),
          if (prefs.wallpaperId == 'custom') ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => save(prefs.copyWith(wallpaperId: 'default')),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                alignment: Alignment.centerRight,
              ),
              child: const Text('إلغاء الخلفية المخصصة'),
            ),
          ],
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'الثيم المخصص',
            subtitle: 'اختر لون التمييز، ولون الرسائل، وخلفية مخصصة.',
          ),
          const SizedBox(height: 8),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 0.5, thickness: 0.5, indent: 16),
                ),
                _ColorPickerCard(
                  title: 'بداية الرسالة الصادرة',
                  selectedColor: ChatAppearanceCatalog.colorFromHex(
                    prefs.customTheme.outgoingBubbleColorHexes.first,
                  ),
                  colors: ChatAppearanceCatalog.customBubbleSwatches,
                  onSelected: (color) {
                    final colors = [
                      ...prefs.customTheme.outgoingBubbleColorHexes,
                    ];
                    if (colors.isEmpty) {
                      colors.add(ChatAppearanceCatalog.colorToHex(color));
                    } else {
                      colors[0] = ChatAppearanceCatalog.colorToHex(color);
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
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 0.5, thickness: 0.5, indent: 16),
                ),
                _ColorPickerCard(
                  title: 'نهاية الرسالة الصادرة',
                  selectedColor: ChatAppearanceCatalog.colorFromHex(
                    prefs.customTheme.outgoingBubbleColorHexes.length > 1
                        ? prefs.customTheme.outgoingBubbleColorHexes[1]
                        : prefs.customTheme.outgoingBubbleColorHexes.first,
                  ),
                  colors: ChatAppearanceCatalog.customBubbleSwatches,
                  onSelected: (color) {
                    final colors = [
                      ...prefs.customTheme.outgoingBubbleColorHexes,
                    ];
                    if (colors.isEmpty) {
                      colors.add(ChatAppearanceCatalog.colorToHex(color));
                    }
                    if (colors.length == 1) {
                      colors.add(ChatAppearanceCatalog.colorToHex(color));
                    } else {
                      colors[1] = ChatAppearanceCatalog.colorToHex(color);
                    }
                    return saveCustomTheme(
                      prefs.customTheme.copyWith(
                        outgoingBubbleColorHexes: colors,
                      ),
                    );
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 0.5, thickness: 0.5, indent: 16),
                ),
                _ColorPickerCard(
                  title: 'لون الرسالة الواردة',
                  selectedColor: ChatAppearanceCatalog.colorFromHex(
                    prefs.customTheme.incomingBubbleColorHex,
                  ),
                  colors: ChatAppearanceCatalog.customBubbleSwatches,
                  onSelected: (color) => saveCustomTheme(
                    prefs.customTheme.copyWith(
                      incomingBubbleColorHex: ChatAppearanceCatalog.colorToHex(
                        color,
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 0.5, thickness: 0.5, indent: 16),
                ),
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
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => save(
                    prefs.copyWith(themeId: 'custom', wallpaperId: 'custom'),
                  ),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('تطبيق المخصص'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => saveCustomTheme(
                    ChatCustomTheme.defaults,
                    wallpaperId: 'custom',
                  ),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('إرجاع الألوان'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'الإعدادات تحفظ على حسابك وتظهر على أي جهاز، مع نسختي نهار/ليل.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? Colors.blue.withValues(alpha: 0.8)
              : Colors.transparent,
          width: selected ? 2 : 0,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
              if (selected)
                const Positioned(
                  bottom: 8,
                  left: 8,
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
            ],
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: colors.map((color) {
              final selected =
                  ChatAppearanceCatalog.colorToHex(color) ==
                  ChatAppearanceCatalog.colorToHex(selectedColor);
              return Padding(
                padding: const EdgeInsets.only(left: 12),
                child: InkWell(
                  onTap: () => onSelected(color),
                  borderRadius: BorderRadius.circular(999),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.blue : Colors.transparent,
                        width: selected ? 2 : 0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.28),
                          blurRadius: selected ? 8 : 4,
                          offset: const Offset(0, 2),
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
                ),
              );
            }).toList(),
          ),
        ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: palettes.map((palette) {
              final selected =
                  palette.length == selectedColors.length &&
                  List.generate(
                    palette.length,
                    (index) =>
                        ChatAppearanceCatalog.colorToHex(palette[index]) ==
                        ChatAppearanceCatalog.colorToHex(selectedColors[index]),
                  ).every((entry) => entry);
              return Padding(
                padding: const EdgeInsets.only(left: 12),
                child: InkWell(
                  onTap: () => onSelected(palette),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 80,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? Colors.blue : Colors.transparent,
                        width: selected ? 2 : 0,
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: palette,
                      ),
                    ),
                    child: selected
                        ? const Align(
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
