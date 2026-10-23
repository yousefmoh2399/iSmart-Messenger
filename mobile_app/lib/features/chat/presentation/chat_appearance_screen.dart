import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import 'chat_appearance.dart';

class ChatAppearanceScreen extends ConsumerStatefulWidget {
  const ChatAppearanceScreen({super.key});

  @override
  ConsumerState<ChatAppearanceScreen> createState() =>
      _ChatAppearanceScreenState();
}

class _ChatAppearanceScreenState extends ConsumerState<ChatAppearanceScreen> {
  int _selectedTabIndex = 0; // 0: الخلفيات, 1: الثيمات, 2: تخصيص يدوي
  bool? _previewIsDark;

  Future<void> _save(ChatPreferences next) async {
    HapticFeedback.lightImpact();
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
          'هل تريد إعادة ضبط المظهر والخلفية إلى المظهر الافتراضي القياسي؟',
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
                  content: Text('تم استعادة المظهر الافتراضي بنجاح'),
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
    final theme = Theme.of(context);
    final appIsDark = theme.brightness == Brightness.dark;
    final previewDark = _previewIsDark ?? appIsDark;

    final scaffoldBg = appIsDark
        ? const Color(0xFF0F141A)
        : const Color(0xFFF6F8FA);
    final cardBg = appIsDark ? const Color(0xFF1B222C) : Colors.white;
    final borderColor = appIsDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text(
          'مظهر المحادثات',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: 'استعادة الافتراضي',
            onPressed: _resetToDefaults,
          ),
        ],
        backgroundColor: scaffoldBg,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // 1. Live Interactive Chat Preview Card
          _LiveChatPreview(
            preferences: prefs,
            isDark: previewDark,
            onTogglePreviewDark: () => setState(
              () => _previewIsDark = !previewDark,
            ),
          ),

          const SizedBox(height: 16),

          // 2. Modern Segmented Tab Switcher (الخلفيات / الثيمات / تخصيص يدوي)
          _SegmentedSwitcher(
            selectedIndex: _selectedTabIndex,
            onChanged: (index) {
              HapticFeedback.selectionClick();
              setState(() => _selectedTabIndex = index);
            },
          ),

          const SizedBox(height: 18),

          // 3. Tab Contents
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: switch (_selectedTabIndex) {
              0 => _WallpapersView(
                  key: const ValueKey('wallpapers_view'),
                  preferences: prefs,
                  isDark: previewDark,
                  cardBg: cardBg,
                  borderColor: borderColor,
                  onSave: _save,
                ),
              1 => _ThemesView(
                  key: const ValueKey('themes_view'),
                  preferences: prefs,
                  isDark: previewDark,
                  cardBg: cardBg,
                  borderColor: borderColor,
                  onSave: _save,
                ),
              _ => _CustomizerView(
                  key: const ValueKey('customizer_view'),
                  preferences: prefs,
                  isDark: previewDark,
                  cardBg: cardBg,
                  onSaveCustom: (custom, {wallpaperId}) => _saveCustomTheme(
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Interactive Chat Preview
// ─────────────────────────────────────────────────────────────────────────────
class _LiveChatPreview extends StatelessWidget {
  const _LiveChatPreview({
    required this.preferences,
    required this.isDark,
    this.onTogglePreviewDark,
  });

  final ChatPreferences preferences;
  final bool isDark;
  final VoidCallback? onTogglePreviewDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = ChatAppearanceCatalog.resolveAppearance(
      preferences: preferences,
      isDark: isDark,
      colorScheme: theme.colorScheme,
    );

    return Container(
      height: 235,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background Backdrop with live wallpaper & doodles
          Positioned.fill(
            child: ChatBackdrop(
              preferences: preferences,
              isDark: isDark,
            ),
          ),

          // Chat Foreground Content
          Column(
            children: [
              // Mock App Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1B222C).withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.88),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.06),
                      width: 0.8,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Mock Avatar
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            resolved.accent,
                            resolved.accent.withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          'أ',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Peer Name & Status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'أحمد محمود (المدير الإداري)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF22C55E),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'متصل الآن',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.7)
                                      : Colors.black.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Translucent action icons
                    if (onTogglePreviewDark != null)
                      IconButton(
                        icon: Icon(
                          isDark
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_rounded,
                          size: 19,
                          color: isDark ? Colors.amber : const Color(0xFF64748B),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: isDark ? 'معاينة النهاري' : 'معاينة الليلي',
                        onPressed: onTogglePreviewDark,
                      ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.videocam_outlined,
                      size: 20,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.call_outlined,
                      size: 18,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                  ],
                ),
              ),

              // Mock Chat Bubbles
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Incoming Message Bubble (Left in LTR / Right in RTL)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 260),
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                          decoration: BoxDecoration(
                            color: resolved.incomingBubbleColor,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(4),
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
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'السلام عليكم، هل اطلعت على تقرير المشروع؟ 📊',
                                style: TextStyle(
                                  color: resolved.incomingTextColor,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Align(
                                alignment: AlignmentDirectional.bottomEnd,
                                child: Text(
                                  '10:30 ص',
                                  style: TextStyle(
                                    color: resolved.incomingTextColor
                                        .withValues(alpha: 0.55),
                                    fontSize: 9.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Spacer(),

                      // 2. Outgoing Message Bubble (Right in LTR / Left in RTL)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 270),
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                          decoration: BoxDecoration(
                            color: resolved.outgoingBubbleColors.length == 1
                                ? resolved.outgoingBubbleColors.first
                                : null,
                            gradient: resolved.outgoingBubbleColors.length > 1
                                ? LinearGradient(
                                    colors: resolved.outgoingBubbleColors,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                              bottomLeft: Radius.circular(4),
                              bottomRight: Radius.circular(16),
                            ),
                            border: Border.all(
                              color: resolved.outgoingBorderColor,
                              width: 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: resolved.accent.withValues(
                                  alpha: isDark ? 0.30 : 0.15,
                                ),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'وعليكم السلام، نعم واعتمدته بالكامل! رائع جداً 👍',
                                style: TextStyle(
                                  color: resolved.outgoingTextColor,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    '10:31 ص',
                                    style: TextStyle(
                                      color: resolved.outgoingTextColor
                                          .withValues(alpha: 0.65),
                                      fontSize: 9.5,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.done_all_rounded,
                                    size: 15,
                                    color: isDark
                                        ? const Color(0xFF53BDEB)
                                        : const Color(0xFF34B7F1),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Segmented Tab Switcher (Apple Pill Style)
// ─────────────────────────────────────────────────────────────────────────────
class _SegmentedSwitcher extends StatelessWidget {
  const _SegmentedSwitcher({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E2632) : const Color(0xFFE5E9EF);
    final activeBg = isDark ? const Color(0xFF2C3646) : Colors.white;

    final tabs = [
      (icon: Icons.wallpaper_rounded, label: 'الخلفيات'),
      (icon: Icons.palette_outlined, label: 'الثيمات'),
      (icon: Icons.tune_rounded, label: 'تخصيص يدوي'),
    ];

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          final isSelected = selectedIndex == idx;

          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(idx),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: isSelected ? activeBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.3 : 0.08,
                            ),
                            blurRadius: 4,
                            offset: const Offset(0, 1.5),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        size: 16,
                        color: isSelected
                            ? (isDark ? Colors.white : Colors.black87)
                            : (isDark ? Colors.white54 : Colors.black54),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? (isDark ? Colors.white : Colors.black87)
                              : (isDark ? Colors.white54 : Colors.black54),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1: Wallpapers View
// ─────────────────────────────────────────────────────────────────────────────
class _WallpapersView extends StatelessWidget {
  const _WallpapersView({
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
  final Future<void> Function(ChatPreferences) onSave;

  @override
  Widget build(BuildContext context) {
    final waWallpapers = ChatAppearanceCatalog.wallpapers
        .where((w) => w.category == 'whatsapp')
        .toList();
    final gradWallpapers = ChatAppearanceCatalog.wallpapers
        .where((w) => w.category == 'gradient')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // WhatsApp Doodles Toggle Tile
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF00A884).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.draw_rounded,
                  color: Color(0xFF00A884),
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'رسومات وزخارف واتساب (Doodles)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'إظهار الرموز والزخارف الكلاسيكية الشفافة فوق الخلفية',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: preferences.doodles,
                activeColor: const Color(0xFF00A884),
                onChanged: (val) => onSave(preferences.copyWith(doodles: val)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        // Section 1: WhatsApp Classics
        _SectionHeader(
          title: 'خلفيات واتساب الكلاسيكية',
          subtitle: 'الألوان الرسمية المعتمدة في واتساب آيفون مع الزخارف الهادئة',
          icon: Icons.check_circle_outline_rounded,
        ),
        const SizedBox(height: 10),

        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: waWallpapers.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
          ),
          itemBuilder: (context, index) {
            final wallpaper = waWallpapers[index];
            final selected = preferences.wallpaperId == wallpaper.id ||
                (preferences.wallpaperId == 'default' &&
                    wallpaper.id == 'wa_classic');

            return _WallpaperCard(
              wallpaper: wallpaper,
              selected: selected,
              isDark: isDark,
              showDoodles: preferences.doodles && wallpaper.hasDoodles,
              onTap: () => onSave(preferences.copyWith(wallpaperId: wallpaper.id)),
            );
          },
        ),

        const SizedBox(height: 24),

        // Section 2: Modern Gradients
        _SectionHeader(
          title: 'تدرجات لونية عصرية',
          subtitle: 'تدرجات أنيقة وعميقة تضيف لمسة حيوية ومميزة للمحادثة',
          icon: Icons.auto_awesome_rounded,
        ),
        const SizedBox(height: 10),

        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: gradWallpapers.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
          ),
          itemBuilder: (context, index) {
            final wallpaper = gradWallpapers[index];
            final selected = preferences.wallpaperId == wallpaper.id;

            return _WallpaperCard(
              wallpaper: wallpaper,
              selected: selected,
              isDark: isDark,
              showDoodles: false,
              onTap: () => onSave(preferences.copyWith(wallpaperId: wallpaper.id)),
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wallpaper Card
// ─────────────────────────────────────────────────────────────────────────────
class _WallpaperCard extends StatelessWidget {
  const _WallpaperCard({
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

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? const Color(0xFF00A884)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.08)),
            width: selected ? 2.5 : 1.0,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: const Color(0xFF00A884).withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              // Background gradient or solid
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),

              // Subtle Doodle Watermark overlay
              if (showDoodles)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.85,
                    child: CustomPaint(
                      painter: WhatsAppDoodlePainter(
                        doodleColor: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : const Color(0xFF334155).withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                ),

              // Selected checkmark in top-start corner
              if (selected)
                PositionedDirectional(
                  top: 8,
                  start: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF00A884),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),

              // Title Pill at Bottom
              Positioned(
                bottom: 6,
                left: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    wallpaper.title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5,
                    ),
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
// Tab 2: Themes View
// ─────────────────────────────────────────────────────────────────────────────
class _ThemesView extends StatelessWidget {
  const _ThemesView({
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
  final Future<void> Function(ChatPreferences) onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'ثيمات المحادثة الجاهزة',
          subtitle:
              'تنسيقات احترافية متكاملة لفقاعات الرسائل ونصوصها بألوان دقيقة',
          icon: Icons.color_lens_rounded,
        ),
        const SizedBox(height: 12),

        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ChatAppearanceCatalog.themes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final theme = ChatAppearanceCatalog.themes[index];
            final isSelected = preferences.themeId == theme.id;

            return _ThemeCard(
              theme: theme,
              isSelected: isSelected,
              isDark: isDark,
              cardBg: cardBg,
              borderColor: borderColor,
              onTap: () {
                // When selecting whatsapp theme, automatically select whatsapp classic wallpaper if on default
                final wallpaperId = theme.id == 'whatsapp'
                    ? 'wa_classic'
                    : (theme.id == 'ios' ? 'wa_slate' : preferences.wallpaperId);

                onSave(
                  preferences.copyWith(
                    themeId: theme.id,
                    wallpaperId: wallpaperId,
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme Card with Mini Bubble Preview Strip
// ─────────────────────────────────────────────────────────────────────────────
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.isSelected,
    required this.isDark,
    required this.cardBg,
    required this.borderColor,
    required this.onTap,
  });

  final ChatThemeOption theme;
  final bool isSelected;
  final bool isDark;
  final Color cardBg;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outgoingColor =
        isDark ? theme.outgoingDarkColor : theme.outgoingLightColor;
    final incomingColor =
        isDark ? theme.incomingDarkColor : theme.incomingLightColor;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00A884)
                : borderColor,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: const Color(0xFF00A884).withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Dot, Title, Badge, and Radio Indicator
            Row(
              children: [
                // Theme Color Circle
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: theme.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: theme.color.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  theme.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                if (theme.badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: theme.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      theme.badge!,
                      style: TextStyle(
                        color: theme.color,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF00A884),
                    size: 22,
                  )
                else
                  Icon(
                    Icons.radio_button_unchecked_rounded,
                    color: isDark ? Colors.white30 : Colors.black26,
                    size: 22,
                  ),
              ],
            ),

            const SizedBox(height: 6),

            // Description
            Text(
              theme.description,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 12),

            // Mini Chat Bubble Demonstration Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF13181F)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  // Mini Incoming Bubble
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: incomingColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black12,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      'رسالة واردة',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Mini Outgoing Bubble
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: outgoingColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: outgoingColor.withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      'رسالة مرسلة',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: theme.id == 'ios'
                            ? Colors.white
                            : (isDark ? Colors.white : Colors.black87),
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
// Tab 3: Customizer View
// ─────────────────────────────────────────────────────────────────────────────
class _CustomizerView extends StatelessWidget {
  const _CustomizerView({
    super.key,
    required this.preferences,
    required this.isDark,
    required this.cardBg,
    required this.onSaveCustom,
    required this.onSavePrefs,
  });

  final ChatPreferences preferences;
  final bool isDark;
  final Color cardBg;
  final Future<void> Function(ChatCustomTheme, {String? wallpaperId})
      onSaveCustom;
  final Future<void> Function(ChatPreferences) onSavePrefs;

  @override
  Widget build(BuildContext context) {
    final custom = preferences.customTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'تخصيص يدوي حر',
          subtitle: 'حدد درجات الألوان للفقاعات ولون التمييز وخلفية المحادثة',
          icon: Icons.tune_rounded,
        ),
        const SizedBox(height: 12),

        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ColorPickerRow(
                title: 'لون التمييز (Accent)',
                selectedColor: ChatAppearanceCatalog.colorFromHex(
                  custom.accentColorHex,
                ),
                colors: ChatAppearanceCatalog.customAccentSwatches,
                onSelected: (color) => onSaveCustom(
                  custom.copyWith(
                    accentColorHex: ChatAppearanceCatalog.colorToHex(color),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 0.5, thickness: 0.5, indent: 16),
              ),
              _ColorPickerRow(
                title: 'بداية فقاعة الإرسال',
                selectedColor: ChatAppearanceCatalog.colorFromHex(
                  custom.outgoingBubbleColorHexes.first,
                ),
                colors: ChatAppearanceCatalog.customBubbleSwatches,
                onSelected: (color) {
                  final colors = [...custom.outgoingBubbleColorHexes];
                  if (colors.isEmpty) {
                    colors.add(ChatAppearanceCatalog.colorToHex(color));
                  } else {
                    colors[0] = ChatAppearanceCatalog.colorToHex(color);
                  }
                  if (colors.length == 1) {
                    colors.add(colors.first);
                  }
                  return onSaveCustom(
                    custom.copyWith(outgoingBubbleColorHexes: colors),
                  );
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 0.5, thickness: 0.5, indent: 16),
              ),
              _ColorPickerRow(
                title: 'نهاية فقاعة الإرسال',
                selectedColor: ChatAppearanceCatalog.colorFromHex(
                  custom.outgoingBubbleColorHexes.length > 1
                      ? custom.outgoingBubbleColorHexes[1]
                      : custom.outgoingBubbleColorHexes.first,
                ),
                colors: ChatAppearanceCatalog.customBubbleSwatches,
                onSelected: (color) {
                  final colors = [...custom.outgoingBubbleColorHexes];
                  if (colors.isEmpty) {
                    colors.add(ChatAppearanceCatalog.colorToHex(color));
                  }
                  if (colors.length == 1) {
                    colors.add(ChatAppearanceCatalog.colorToHex(color));
                  } else {
                    colors[1] = ChatAppearanceCatalog.colorToHex(color);
                  }
                  return onSaveCustom(
                    custom.copyWith(outgoingBubbleColorHexes: colors),
                  );
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 0.5, thickness: 0.5, indent: 16),
              ),
              _ColorPickerRow(
                title: 'لون فقاعة الاستقبال',
                selectedColor: ChatAppearanceCatalog.colorFromHex(
                  custom.incomingBubbleColorHex,
                ),
                colors: ChatAppearanceCatalog.customBubbleSwatches,
                onSelected: (color) => onSaveCustom(
                  custom.copyWith(
                    incomingBubbleColorHex:
                        ChatAppearanceCatalog.colorToHex(color),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 0.5, thickness: 0.5, indent: 16),
              ),
              _WallpaperPaletteRow(
                title: 'لوحة ألوان الخلفية المخصصة',
                selectedColors: custom.wallpaperColorHexes
                    .map(ChatAppearanceCatalog.colorFromHex)
                    .toList(),
                palettes: ChatAppearanceCatalog.customWallpaperPalettes,
                onSelected: (palette) => onSaveCustom(
                  custom.copyWith(
                    wallpaperColorHexes: palette
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
              child: FilledButton.icon(
                onPressed: () => onSavePrefs(
                  preferences.copyWith(
                    themeId: 'custom',
                    wallpaperId: 'custom',
                  ),
                ),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('تطبيق التخصيص الآن'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00A884),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onSaveCustom(
                  ChatCustomTheme.defaults,
                  wallpaperId: 'custom',
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('إعادة ضبط الألوان'),
                style: OutlinedButton.styleFrom(
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Color Picker Row
// ─────────────────────────────────────────────────────────────────────────────
class _ColorPickerRow extends StatelessWidget {
  const _ColorPickerRow({
    required this.title,
    required this.selectedColor,
    required this.colors,
    required this.onSelected,
  });

  final String title;
  final Color selectedColor;
  final List<Color> colors;
  final Future<void> Function(Color) onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
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
                padding: const EdgeInsets.only(left: 10),
                child: GestureDetector(
                  onTap: () => onSelected(color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF00A884)
                            : Colors.black.withValues(alpha: 0.15),
                        width: selected ? 2.5 : 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: selected ? 0.35 : 0.15),
                          blurRadius: selected ? 8 : 3,
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

// ─────────────────────────────────────────────────────────────────────────────
// Wallpaper Palette Row
// ─────────────────────────────────────────────────────────────────────────────
class _WallpaperPaletteRow extends StatelessWidget {
  const _WallpaperPaletteRow({
    required this.title,
    required this.selectedColors,
    required this.palettes,
    required this.onSelected,
  });

  final String title;
  final List<Color> selectedColors;
  final List<List<Color>> palettes;
  final Future<void> Function(List<Color>) onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: palettes.map((palette) {
              final isSelected = palette.length == selectedColors.length &&
                  List.generate(
                    palette.length,
                    (index) =>
                        ChatAppearanceCatalog.colorToHex(palette[index]) ==
                        ChatAppearanceCatalog.colorToHex(selectedColors[index]),
                  ).every((e) => e);

              return Padding(
                padding: const EdgeInsets.only(left: 10),
                child: GestureDetector(
                  onTap: () => onSelected(palette),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 74,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF00A884)
                            : Colors.black.withValues(alpha: 0.15),
                        width: isSelected ? 2.5 : 1.0,
                      ),
                      gradient: LinearGradient(
                        colors: palette,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        if (isSelected)
                          BoxShadow(
                            color: const Color(0xFF00A884).withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                      ],
                    ),
                    child: isSelected
                        ? const Center(
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                              size: 20,
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

// ─────────────────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: const Color(0xFF00A884),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
