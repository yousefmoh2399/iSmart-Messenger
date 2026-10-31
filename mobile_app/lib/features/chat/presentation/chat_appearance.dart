import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/models/app_user.dart';

class ChatThemeOption {
  const ChatThemeOption({
    required this.id,
    required this.title,
    required this.description,
    required this.color,
    required this.outgoingLightColor,
    required this.incomingLightColor,
    required this.outgoingDarkColor,
    required this.incomingDarkColor,
    this.badge,
  });

  final String id;
  final String title;
  final String description;
  final Color color;
  final Color outgoingLightColor;
  final Color incomingLightColor;
  final Color outgoingDarkColor;
  final Color incomingDarkColor;
  final String? badge;
}

class ChatWallpaperOption {
  const ChatWallpaperOption({
    required this.id,
    required this.title,
    required this.category,
    required this.previewColors,
    required this.lightColors,
    required this.darkColors,
    this.hasDoodles = true,
  });

  final String id;
  final String title;
  final String category; // 'whatsapp', 'gradient'
  final List<Color> previewColors;
  final List<Color> lightColors;
  final List<Color> darkColors;
  final bool hasDoodles;
}

class ChatResolvedAppearance {
  const ChatResolvedAppearance({
    required this.accent,
    required this.outgoingBubbleColors,
    required this.incomingBubbleColor,
    required this.outgoingTextColor,
    required this.incomingTextColor,
    required this.outgoingBorderColor,
    required this.incomingBorderColor,
    required this.outgoingReplyColor,
    required this.incomingReplyColor,
    required this.wallpaperColors,
    required this.patternColor,
    required this.sparkleColor,
    required this.isDarkVariant,
    this.showDoodles = true,
  });

  final Color accent;
  final List<Color> outgoingBubbleColors;
  final Color incomingBubbleColor;
  final Color outgoingTextColor;
  final Color incomingTextColor;
  final Color outgoingBorderColor;
  final Color incomingBorderColor;
  final Color outgoingReplyColor;
  final Color incomingReplyColor;
  final List<Color> wallpaperColors;
  final Color patternColor;
  final Color sparkleColor;
  final bool isDarkVariant;
  final bool showDoodles;

  bool get hasOutgoingGradient =>
      outgoingBubbleColors.length > 1 &&
      outgoingBubbleColors.any((entry) => entry != outgoingBubbleColors.first);
}

class ChatAppearanceCatalog {
  static const themes = <ChatThemeOption>[
    ChatThemeOption(
      id: 'whatsapp',
      title: 'واتساب الرسمي',
      description: 'فقاعات خضراء كلاسيكية مع خلفية البيج ورسومات واتساب',
      color: Color(0xFF00A884),
      outgoingLightColor: Color(0xFFD9FDD3),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF005C4B),
      incomingDarkColor: Color(0xFF202C33),
      badge: 'الأكثر طلباً',
    ),
    ChatThemeOption(
      id: 'ios',
      title: 'رسائل آبل',
      description: 'مظهر iMessage الأنيق بفقاعة زرقاء ناصعة ورمادي هادئ',
      color: Color(0xFF007AFF),
      outgoingLightColor: Color(0xFF007AFF),
      incomingLightColor: Color(0xFFE9E9EB),
      outgoingDarkColor: Color(0xFF0B84FE),
      incomingDarkColor: Color(0xFF26252A),
      badge: 'Apple iOS',
    ),
    ChatThemeOption(
      id: 'classic',
      title: 'تلجرام كلاسيك',
      description: 'مظهر تلجرام الشهير بفقاعة خضراء هادئة وأزرق ناصع',
      color: Color(0xFF3390EC),
      outgoingLightColor: Color(0xFFEFFDDE),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF2B5278),
      incomingDarkColor: Color(0xFF182533),
    ),
    ChatThemeOption(
      id: 'mint',
      title: 'زمرد فاخر',
      description: 'درجات خضراء زمردية ملكية مريحة للعين',
      color: Color(0xFF10B981),
      outgoingLightColor: Color(0xFFD1FAE5),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF064E3B),
      incomingDarkColor: Color(0xFF14241F),
    ),
    ChatThemeOption(
      id: 'sunset',
      title: 'غروب دافئ',
      description: 'ألوان كهرمانية وذهبية دافئة مريحة للمساء',
      color: Color(0xFFF59E0B),
      outgoingLightColor: Color(0xFFFEF3C7),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF78350F),
      incomingDarkColor: Color(0xFF271F1B),
    ),
    ChatThemeOption(
      id: 'mono',
      title: 'جرافيت داكن',
      description: 'مظهر احترافي محايد لشاشات OLED وراحة العين',
      color: Color(0xFF64748B),
      outgoingLightColor: Color(0xFFE2E8F0),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF27272A),
      incomingDarkColor: Color(0xFF18181B),
    ),
    ChatThemeOption(
      id: 'system',
      title: 'افتراضي التطبيق',
      description: 'يتكيف تلقائياً مع السمة العامة للتطبيق',
      color: Color(0xFF0284C7),
      outgoingLightColor: Color(0xFFDDF4FF),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF1E3A5F),
      incomingDarkColor: Color(0xFF182533),
    ),
    ChatThemeOption(
      id: 'custom',
      title: 'تخصيص يدوي',
      description: 'اختر بحرية ألوان الرسائل والخلفية بالكامل',
      color: Color(0xFF8B5CF6),
      outgoingLightColor: Color(0xFF5BA9FF),
      incomingLightColor: Color(0xFFF1F5F9),
      outgoingDarkColor: Color(0xFF2F8CFF),
      incomingDarkColor: Color(0xFF1E293B),
    ),
  ];

  static const wallpapers = <ChatWallpaperOption>[
    // 1. WhatsApp Classics
    ChatWallpaperOption(
      id: 'wa_classic',
      title: 'البيج الكلاسيكي',
      category: 'whatsapp',
      previewColors: [Color(0xFFEFEAE2), Color(0xFFE6DFD5)],
      lightColors: [Color(0xFFEFEAE2), Color(0xFFEFEAE2)],
      darkColors: [Color(0xFF0B141A), Color(0xFF0B141A)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_emerald',
      title: 'زمرد واتساب',
      category: 'whatsapp',
      previewColors: [Color(0xFF00A884), Color(0xFF054640)],
      lightColors: [Color(0xFFD5F3E4), Color(0xFFE2F8EE)],
      darkColors: [Color(0xFF053E31), Color(0xFF084D3E)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_midnight',
      title: 'أزرق ليلي',
      category: 'whatsapp',
      previewColors: [Color(0xFF1F2C40), Color(0xFF0C131F)],
      lightColors: [Color(0xFFDCEAF7), Color(0xFFEDF4FA)],
      darkColors: [Color(0xFF0C131F), Color(0xFF141F30)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_sand',
      title: 'رمال دافئة',
      category: 'whatsapp',
      previewColors: [Color(0xFFF7F3EB), Color(0xFFEDE5D8)],
      lightColors: [Color(0xFFF7F3EB), Color(0xFFF2ECE1)],
      darkColors: [Color(0xFF1E1B18), Color(0xFF282420)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_slate',
      title: 'رمادي أنيق',
      category: 'whatsapp',
      previewColors: [Color(0xFFECEFF1), Color(0xFFCFD8DC)],
      lightColors: [Color(0xFFECEFF1), Color(0xFFE4E8EB)],
      darkColors: [Color(0xFF141C22), Color(0xFF1B242B)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_mint',
      title: 'نسيم النعناع',
      category: 'whatsapp',
      previewColors: [Color(0xFFDFF7EF), Color(0xFFC7F0E1)],
      lightColors: [Color(0xFFDFF7EF), Color(0xFFEEFAF4)],
      darkColors: [Color(0xFF10261F), Color(0xFF16332A)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_sky',
      title: 'سماء هادئة',
      category: 'whatsapp',
      previewColors: [Color(0xFFBAE6FD), Color(0xFF7DD3FC)],
      lightColors: [Color(0xFFE0F2FE), Color(0xFFEFF8FF)],
      darkColors: [Color(0xFF0C2233), Color(0xFF102D42)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_lilac',
      title: 'لافندر ناعم',
      category: 'whatsapp',
      previewColors: [Color(0xFFEDE9FE), Color(0xFFDDD6FE)],
      lightColors: [Color(0xFFEDE9FE), Color(0xFFF5F2FE)],
      darkColors: [Color(0xFF1C162E), Color(0xFF251E3C)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_rose',
      title: 'وردي هادئ',
      category: 'whatsapp',
      previewColors: [Color(0xFFFBCFE8), Color(0xFFF472B6)],
      lightColors: [Color(0xFFFCE7F3), Color(0xFFFFF1F7)],
      darkColors: [Color(0xFF2B1420), Color(0xFF381B2B)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_peach',
      title: 'شروق خوخي',
      category: 'whatsapp',
      previewColors: [Color(0xFFFFEDD5), Color(0xFFFED7AA)],
      lightColors: [Color(0xFFFFEDD5), Color(0xFFFFF6EB)],
      darkColors: [Color(0xFF2A1B10), Color(0xFF382516)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_forest',
      title: 'غابة خضراء',
      category: 'whatsapp',
      previewColors: [Color(0xFF064E3B), Color(0xFF022C22)],
      lightColors: [Color(0xFFE3F7E9), Color(0xFFF0FDF4)],
      darkColors: [Color(0xFF0A2218), Color(0xFF0F2E21)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_coffee',
      title: 'موكا دافئة',
      category: 'whatsapp',
      previewColors: [Color(0xFF78350F), Color(0xFF451A03)],
      lightColors: [Color(0xFFF5EBE1), Color(0xFFFAF3EC)],
      darkColors: [Color(0xFF231812), Color(0xFF2E2018)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_dark_oled',
      title: 'واتساب OLED',
      category: 'whatsapp',
      previewColors: [Color(0xFF0B141A), Color(0xFF000000)],
      lightColors: [Color(0xFFE5DDD5), Color(0xFFECE5DD)],
      darkColors: [Color(0xFF0B141A), Color(0xFF070B0E)],
      hasDoodles: true,
    ),

    // 2. Modern Gradients
    ChatWallpaperOption(
      id: 'grad_aurora',
      title: 'شفق قطبي',
      category: 'gradient',
      previewColors: [Color(0xFF11998E), Color(0xFF38EF7D)],
      lightColors: [Color(0xFFD4FC79), Color(0xFF96E6A1)],
      darkColors: [Color(0xFF09203F), Color(0xFF1B4965)],
      hasDoodles: false,
    ),
    ChatWallpaperOption(
      id: 'grad_ocean',
      title: 'أعماق المحيط',
      category: 'gradient',
      previewColors: [Color(0xFF2193B0), Color(0xFF6DD5ED)],
      lightColors: [Color(0xFFC6E7FF), Color(0xFF99D3FF)],
      darkColors: [Color(0xFF0F2027), Color(0xFF203A43)],
      hasDoodles: false,
    ),
    ChatWallpaperOption(
      id: 'grad_sunset',
      title: 'تدرج الغروب',
      category: 'gradient',
      previewColors: [Color(0xFFFF512F), Color(0xFFDD2476)],
      lightColors: [Color(0xFFFFE2D2), Color(0xFFFFD1DC)],
      darkColors: [Color(0xFF3D1635), Color(0xFF5A1E38)],
      hasDoodles: false,
    ),
    ChatWallpaperOption(
      id: 'grad_purple',
      title: 'أرجواني ملكي',
      category: 'gradient',
      previewColors: [Color(0xFF8A2387), Color(0xFFE94057)],
      lightColors: [Color(0xFFF3E5F5), Color(0xFFEDE7F6)],
      darkColors: [Color(0xFF1F1135), Color(0xFF2F174A)],
      hasDoodles: false,
    ),
    ChatWallpaperOption(
      id: 'grad_nordic',
      title: 'سحر الشمال',
      category: 'gradient',
      previewColors: [Color(0xFF3A6073), Color(0xFF3A7BD5)],
      lightColors: [Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
      darkColors: [Color(0xFF1E293B), Color(0xFF0F172A)],
      hasDoodles: false,
    ),
    ChatWallpaperOption(
      id: 'grad_oled',
      title: 'أسود فاحم OLED',
      category: 'gradient',
      previewColors: [Color(0xFF1E2124), Color(0xFF000000)],
      lightColors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
      darkColors: [Color(0xFF000000), Color(0xFF080808)],
      hasDoodles: false,
    ),
  ];

  static const customAccentSwatches = <Color>[
    Color(0xFF00A884), // WhatsApp Green
    Color(0xFF007AFF), // Apple Blue
    Color(0xFF3390EC), // Telegram Blue
    Color(0xFF10B981), // Emerald
    Color(0xFF0EA5E9), // Sky Blue
    Color(0xFF8B5CF6), // Violet
    Color(0xFFF59E0B), // Amber
    Color(0xFFEF4444), // Coral Red
    Color(0xFFEC4899), // Pink
    Color(0xFF64748B), // Slate
  ];

  static const customBubbleSwatches = <Color>[
    Color(0xFFD9FDD3), // WhatsApp light outgoing
    Color(0xFF005C4B), // WhatsApp dark outgoing
    Color(0xFF007AFF), // Apple Blue
    Color(0xFFE9E9EB), // Apple Light Gray
    Color(0xFF5BA9FF),
    Color(0xFF2F8CFF),
    Color(0xFF18BFA0),
    Color(0xFF10B981),
    Color(0xFF7C3AED),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF17212B),
    Color(0xFF202C33),
    Color(0xFFFFFFFF),
  ];

  static const customWallpaperPalettes = <List<Color>>[
    [Color(0xFFEFEAE2), Color(0xFFEFEAE2)],
    [Color(0xFF0B141A), Color(0xFF0B141A)],
    [Color(0xFFD5F3E4), Color(0xFFE2F8EE)],
    [Color(0xFF053E31), Color(0xFF084D3E)],
    [Color(0xFFDCEAF7), Color(0xFFEDF4FA)],
    [Color(0xFF0C131F), Color(0xFF141F30)],
    [Color(0xFFF7F3EB), Color(0xFFF2ECE1)],
    [Color(0xFF1E1B18), Color(0xFF282420)],
    [Color(0xFFEDE9FE), Color(0xFFF5F2FE)],
    [Color(0xFF1C162E), Color(0xFF251E3C)],
  ];

  static bool usesSystemMode(String themeId) => themeId == 'system';

  static bool usesCustomTheme(String themeId) => themeId == 'custom';

  static ChatThemeOption themeById(String themeId) {
    for (final entry in themes) {
      if (entry.id == themeId) {
        return entry;
      }
    }
    // Handle backwards compatibility for legacy theme ids
    if (themeId == 'violet') {
      return themeById('mint');
    }
    return themes.first; // Defaults to WhatsApp
  }

  static ChatWallpaperOption wallpaperById(String wallpaperId) {
    for (final entry in wallpapers) {
      if (entry.id == wallpaperId) {
        return entry;
      }
    }
    // Handle backwards compatibility for legacy wallpaper ids
    return switch (wallpaperId) {
      'default' => wallpapers.first, // wa_classic
      'night' => wallpaperById('wa_midnight'),
      'sky' => wallpaperById('wa_sky'),
      'mint' => wallpaperById('wa_mint'),
      'violet' => wallpaperById('wa_lilac'),
      'sunset' => wallpaperById('wa_peach'),
      _ => wallpapers.first,
    };
  }

  static Color colorFromHex(
    String hex, {
    Color fallback = const Color(0xFF00A884),
  }) {
    final normalized = hex.trim();
    final raw = normalized.startsWith('#')
        ? normalized.substring(1)
        : normalized;
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(raw)) {
      return fallback;
    }
    return Color(int.parse('FF$raw', radix: 16));
  }

  static String colorToHex(Color color) {
    final value = color.toARGB32() & 0x00FFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static ChatResolvedAppearance resolveAppearance({
    required ChatPreferences preferences,
    required bool isDark,
    required ColorScheme colorScheme,
  }) {
    if (preferences.themeId == 'system') {
      return _resolveSystemAppearance(
        preferences: preferences,
        isDark: isDark,
        colorScheme: colorScheme,
      );
    }
    if (preferences.themeId == 'custom') {
      return _resolveCustomAppearance(preferences: preferences, isDark: isDark);
    }
    return _resolvePresetAppearance(preferences: preferences, isDark: isDark);
  }

  static ChatResolvedAppearance _resolveSystemAppearance({
    required ChatPreferences preferences,
    required bool isDark,
    required ColorScheme colorScheme,
  }) {
    final wallpaperColors = _wallpaperColorsFor(
      wallpaperId: preferences.wallpaperId,
      isDark: isDark,
      fallback: isDark
          ? const [Color(0xFF0B141A), Color(0xFF0B141A)]
          : const [Color(0xFFEFEAE2), Color(0xFFEFEAE2)],
      customTheme: preferences.customTheme,
    );
    final patternColor = _doodleColorFor(
      wallpaperColors: wallpaperColors,
      isDark: isDark,
    );
    return ChatResolvedAppearance(
      accent: colorScheme.primary,
      outgoingBubbleColors: isDark
          ? const [Color(0xFF1E3A5F), Color(0xFF274B7A)]
          : const [Color(0xFFDDF4FF), Color(0xFFF0FAFF)],
      incomingBubbleColor: isDark
          ? const Color(0xFF182533)
          : colorScheme.surfaceContainerLowest,
      outgoingTextColor: isDark
          ? const Color(0xFFF4FBFF)
          : const Color(0xFF102331),
      incomingTextColor: isDark
          ? const Color(0xFFF2F5F7)
          : const Color(0xFF182533),
      outgoingBorderColor: colorScheme.primary.withValues(
        alpha: isDark ? 0.40 : 0.18,
      ),
      incomingBorderColor: isDark
          ? const Color(0xFF243140)
          : colorScheme.outlineVariant.withValues(alpha: 0.3),
      outgoingReplyColor: isDark
          ? const Color(0xFF1E3A5F)
          : const Color(0xFFECF7FF),
      incomingReplyColor: isDark
          ? const Color(0xFF223446)
          : const Color(0xFFF8FBFE),
      wallpaperColors: wallpaperColors,
      patternColor: patternColor,
      sparkleColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : colorScheme.primary.withValues(alpha: 0.03),
      isDarkVariant: isDark,
      showDoodles: preferences.doodles,
    );
  }

  static ChatResolvedAppearance _resolvePresetAppearance({
    required ChatPreferences preferences,
    required bool isDark,
  }) {
    final wallpaperColors = _wallpaperColorsFor(
      wallpaperId: preferences.wallpaperId,
      isDark: isDark,
      fallback: _defaultWallpaperForTheme(preferences.themeId, isDark),
      customTheme: preferences.customTheme,
    );

    final patternColor = _doodleColorFor(
      wallpaperColors: wallpaperColors,
      isDark: isDark,
    );

    // 1. WhatsApp Official Theme
    if (preferences.themeId == 'whatsapp') {
      return ChatResolvedAppearance(
        accent: const Color(0xFF00A884),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF005C4B)]
            : const [Color(0xFFD9FDD3)],
        incomingBubbleColor: isDark
            ? const Color(0xFF202C33)
            : const Color(0xFFFFFFFF),
        outgoingTextColor: isDark
            ? const Color(0xFFE9EDEF)
            : const Color(0xFF111B21),
        incomingTextColor: isDark
            ? const Color(0xFFE9EDEF)
            : const Color(0xFF111B21),
        outgoingBorderColor: isDark
            ? const Color(0xFF02735E).withValues(alpha: 0.4)
            : const Color(0xFFC6EDB8),
        incomingBorderColor: isDark
            ? const Color(0xFF2A3942).withValues(alpha: 0.4)
            : const Color(0xFFE2E8F0),
        outgoingReplyColor: isDark
            ? const Color(0xFF025142)
            : const Color(0xFFC7EBC1),
        incomingReplyColor: isDark
            ? const Color(0xFF1B242A)
            : const Color(0xFFF1F5F9),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.04 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 2. Apple iOS Theme
    if (preferences.themeId == 'ios') {
      return ChatResolvedAppearance(
        accent: const Color(0xFF007AFF),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF0B84FE)]
            : const [Color(0xFF007AFF)],
        incomingBubbleColor: isDark
            ? const Color(0xFF26252A)
            : const Color(0xFFE9E9EB),
        outgoingTextColor: Colors.white,
        incomingTextColor: isDark ? Colors.white : Colors.black,
        outgoingBorderColor: Colors.transparent,
        incomingBorderColor: isDark
            ? const Color(0xFF333338)
            : const Color(0xFFD8D8DC),
        outgoingReplyColor: isDark
            ? const Color(0xFF0868C7)
            : const Color(0xFF1A87FF),
        incomingReplyColor: isDark
            ? const Color(0xFF1F1E22)
            : const Color(0xFFDCDCE0),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.04 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 3. Telegram Classic Theme
    if (preferences.themeId == 'classic') {
      return ChatResolvedAppearance(
        accent: const Color(0xFF3390EC),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF2B5278), Color(0xFF33628F)]
            : const [Color(0xFFEFFDDE)],
        incomingBubbleColor: isDark
            ? const Color(0xFF182533)
            : const Color(0xFFFFFFFF),
        outgoingTextColor: isDark
            ? const Color(0xFFF4FBFF)
            : const Color(0xFF111B21),
        incomingTextColor: isDark
            ? const Color(0xFFF2F5F7)
            : const Color(0xFF182533),
        outgoingBorderColor: isDark
            ? const Color(0xFF3D6B9C)
            : const Color(0xFFDBF2C6),
        incomingBorderColor: isDark
            ? const Color(0xFF243140)
            : const Color(0xFFE2E8F0),
        outgoingReplyColor: isDark
            ? const Color(0xFF244668)
            : const Color(0xFFDFECC9),
        incomingReplyColor: isDark
            ? const Color(0xFF223446)
            : const Color(0xFFF8FBFE),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 4. Emerald Luxury Theme
    if (preferences.themeId == 'mint') {
      return ChatResolvedAppearance(
        accent: const Color(0xFF10B981),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF064E3B), Color(0xFF047857)]
            : const [Color(0xFFD1FAE5)],
        incomingBubbleColor: isDark
            ? const Color(0xFF132B25)
            : const Color(0xFFFFFFFF),
        outgoingTextColor: isDark
            ? const Color(0xFFECFDF5)
            : const Color(0xFF064E3B),
        incomingTextColor: isDark
            ? const Color(0xFFECFDF5)
            : const Color(0xFF111827),
        outgoingBorderColor: isDark
            ? const Color(0xFF059669).withValues(alpha: 0.5)
            : const Color(0xFFA7F3D0),
        incomingBorderColor: isDark
            ? const Color(0xFF1F4439)
            : const Color(0xFFE5E7EB),
        outgoingReplyColor: isDark
            ? const Color(0xFF054534)
            : const Color(0xFFA7F3D0),
        incomingReplyColor: isDark
            ? const Color(0xFF17362E)
            : const Color(0xFFF3F4F6),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 5. Warm Sunset Theme
    if (preferences.themeId == 'sunset') {
      return ChatResolvedAppearance(
        accent: const Color(0xFFF59E0B),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF78350F), Color(0xFF92400E)]
            : const [Color(0xFFFEF3C7)],
        incomingBubbleColor: isDark
            ? const Color(0xFF271F1B)
            : const Color(0xFFFFFFFF),
        outgoingTextColor: isDark
            ? const Color(0xFFFFFBEB)
            : const Color(0xFF78350F),
        incomingTextColor: isDark
            ? const Color(0xFFFFFBEB)
            : const Color(0xFF1C1917),
        outgoingBorderColor: isDark
            ? const Color(0xFFB45309).withValues(alpha: 0.5)
            : const Color(0xFFFDE68A),
        incomingBorderColor: isDark
            ? const Color(0xFF382A24)
            : const Color(0xFFE5E7EB),
        outgoingReplyColor: isDark
            ? const Color(0xFF6B2F0D)
            : const Color(0xFFFDE68A),
        incomingReplyColor: isDark
            ? const Color(0xFF2F241F)
            : const Color(0xFFF3F4F6),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 6. Graphite Dark Theme (mono)
    return ChatResolvedAppearance(
      accent: const Color(0xFF94A3B8),
      outgoingBubbleColors: isDark
          ? const [Color(0xFF27272A)]
          : const [Color(0xFFE2E8F0)],
      incomingBubbleColor: isDark
          ? const Color(0xFF18181B)
          : const Color(0xFFFFFFFF),
      outgoingTextColor: isDark
          ? const Color(0xFFFAFAFA)
          : const Color(0xFF0F172A),
      incomingTextColor: isDark
          ? const Color(0xFFF4F4F5)
          : const Color(0xFF18181B),
      outgoingBorderColor: isDark
          ? const Color(0xFF3F3F46)
          : const Color(0xFFCBD5E1),
      incomingBorderColor: isDark
          ? const Color(0xFF27272A)
          : const Color(0xFFE2E8F0),
      outgoingReplyColor: isDark
          ? const Color(0xFF3F3F46)
          : const Color(0xFFCBD5E1),
      incomingReplyColor: isDark
          ? const Color(0xFF27272A)
          : const Color(0xFFF1F5F9),
      wallpaperColors: wallpaperColors,
      patternColor: patternColor,
      sparkleColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.02),
      isDarkVariant: isDark,
      showDoodles: preferences.doodles,
    );
  }

  static ChatResolvedAppearance _resolveCustomAppearance({
    required ChatPreferences preferences,
    required bool isDark,
  }) {
    final custom = preferences.customTheme;
    final accent = _adaptCustomColor(
      colorFromHex(custom.accentColorHex),
      isDark: isDark,
    );
    final outgoingBubbleColors = custom.outgoingBubbleColorHexes
        .map(colorFromHex)
        .map((color) => _adaptCustomColor(color, isDark: isDark))
        .toList();
    final incomingBubbleColor = _adaptCustomIncomingColor(
      colorFromHex(custom.incomingBubbleColorHex),
      isDark: isDark,
    );
    final wallpaperColors = _wallpaperColorsFor(
      wallpaperId: preferences.wallpaperId,
      isDark: isDark,
      fallback: custom.wallpaperColorHexes
          .map(colorFromHex)
          .map((color) => _adaptCustomWallpaperColor(color, isDark: isDark))
          .toList(),
      customTheme: custom,
    );
    final patternColor = _doodleColorFor(
      wallpaperColors: wallpaperColors,
      isDark: isDark,
    );

    return ChatResolvedAppearance(
      accent: accent,
      outgoingBubbleColors: outgoingBubbleColors,
      incomingBubbleColor: incomingBubbleColor,
      outgoingTextColor: isDark
          ? const Color(0xFFF7FBFF)
          : const Color(0xFF102331),
      incomingTextColor: isDark
          ? const Color(0xFFF1F5F8)
          : const Color(0xFF182533),
      outgoingBorderColor: accent.withValues(alpha: isDark ? 0.40 : 0.22),
      incomingBorderColor: accent.withValues(alpha: isDark ? 0.25 : 0.16),
      outgoingReplyColor: _blend(outgoingBubbleColors.first, accent, 0.20),
      incomingReplyColor: _blend(
        incomingBubbleColor,
        accent,
        isDark ? 0.18 : 0.08,
      ),
      wallpaperColors: wallpaperColors,
      patternColor: patternColor,
      sparkleColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : accent.withValues(alpha: 0.03),
      isDarkVariant: isDark,
      showDoodles: preferences.doodles,
    );
  }

  static Color _doodleColorFor({
    required List<Color> wallpaperColors,
    required bool isDark,
  }) {
    if (isDark) {
      return Colors.white.withValues(alpha: 0.055);
    }
    final avgLuminance = wallpaperColors.isEmpty
        ? 0.9
        : wallpaperColors
                .map((c) => c.computeLuminance())
                .reduce((a, b) => a + b) /
            wallpaperColors.length;

    if (avgLuminance > 0.6) {
      // Light background (such as Classic Beige #EFEAE2)
      return const Color(0xFF334155).withValues(alpha: 0.075);
    } else {
      return Colors.white.withValues(alpha: 0.08);
    }
  }

  static List<Color> _wallpaperColorsFor({
    required String wallpaperId,
    required bool isDark,
    required List<Color> fallback,
    required ChatCustomTheme customTheme,
  }) {
    if (wallpaperId == 'custom') {
      return customTheme.wallpaperColorHexes
          .map(colorFromHex)
          .map((color) => _adaptCustomWallpaperColor(color, isDark: isDark))
          .toList();
    }
    if (wallpaperId == 'default') {
      return fallback;
    }
    final wallpaper = wallpaperById(wallpaperId);
    return isDark ? wallpaper.darkColors : wallpaper.lightColors;
  }

  static List<Color> _defaultWallpaperForTheme(String themeId, bool isDark) {
    return switch (themeId) {
      'whatsapp' =>
        isDark
            ? const [Color(0xFF0B141A), Color(0xFF0B141A)]
            : const [Color(0xFFEFEAE2), Color(0xFFEFEAE2)],
      'ios' =>
        isDark
            ? const [Color(0xFF141C22), Color(0xFF1B242B)]
            : const [Color(0xFFECEFF1), Color(0xFFE4E8EB)],
      'mint' =>
        isDark
            ? const [Color(0xFF053E31), Color(0xFF084D3E)]
            : const [Color(0xFFD5F3E4), Color(0xFFE2F8EE)],
      'sunset' =>
        isDark
            ? const [Color(0xFF2A1B10), Color(0xFF382516)]
            : const [Color(0xFFFFEDD5), Color(0xFFFFF6EB)],
      'mono' =>
        isDark
            ? const [Color(0xFF000000), Color(0xFF080808)]
            : const [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
      _ =>
        isDark
            ? const [Color(0xFF0B141A), Color(0xFF0B141A)]
            : const [Color(0xFFEFEAE2), Color(0xFFEFEAE2)],
    };
  }

  static Color _adaptCustomColor(Color color, {required bool isDark}) {
    final luminance = color.computeLuminance();
    if (isDark) {
      final amount = luminance > 0.46 ? 0.48 : 0.28;
      return _blend(color, Colors.black, amount);
    }
    final amount = luminance < 0.18 ? 0.22 : 0.10;
    return _blend(color, Colors.white, amount);
  }

  static Color _adaptCustomIncomingColor(Color color, {required bool isDark}) {
    if (isDark) {
      return _blend(const Color(0xFF17212B), color, 0.26);
    }
    return _blend(Colors.white, color, 0.12);
  }

  static Color _adaptCustomWallpaperColor(Color color, {required bool isDark}) {
    final luminance = color.computeLuminance();
    if (isDark) {
      final amount = luminance > 0.42 ? 0.58 : 0.26;
      return _blend(color, Colors.black, amount);
    }
    final amount = luminance < 0.22 ? 0.32 : 0.08;
    return _blend(color, Colors.white, amount);
  }

  static Color _blend(Color base, Color overlay, double amount) {
    return Color.lerp(base, overlay, amount.clamp(0, 1))!;
  }
}

class ChatBackdrop extends StatelessWidget {
  const ChatBackdrop({
    super.key,
    required this.preferences,
    required this.isDark,
  });

  final ChatPreferences preferences;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final resolved = ChatAppearanceCatalog.resolveAppearance(
      preferences: preferences,
      isDark: isDark,
      colorScheme: Theme.of(context).colorScheme,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: resolved.wallpaperColors,
          stops: _buildGradientStops(resolved.wallpaperColors.length),
        ),
      ),
      child: Stack(
        children: [
          if (preferences.doodles && resolved.showDoodles)
            Positioned.fill(
              child: CustomPaint(
                painter: WhatsAppDoodlePainter(
                  doodleColor: resolved.patternColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<double> _buildGradientStops(int length) {
    if (length <= 1) {
      return const [0];
    }
    return List<double>.generate(
      length,
      (index) => index / math.max(1, length - 1),
    );
  }
}

class WhatsAppDoodlePainter extends CustomPainter {
  const WhatsAppDoodlePainter({
    required this.doodleColor,
  });

  final Color doodleColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (doodleColor.a <= 0.005) return;

    final strokePaint = Paint()
      ..color = doodleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = doodleColor
      ..style = PaintingStyle.fill;

    const cellW = 82.0;
    const cellH = 82.0;

    final cols = (size.width / cellW).ceil() + 1;
    final rows = (size.height / cellH).ceil() + 1;

    for (int r = 0; r < rows; r++) {
      final y = r * cellH + 24;
      final xOffset = (r % 2 == 1) ? (cellW / 2) : 0.0;

      for (int c = -1; c < cols; c++) {
        final x = c * cellW + xOffset + 24;
        final iconType = ((r * 7) + c + 100) % 12;

        canvas.save();
        canvas.translate(x, y);

        switch (iconType) {
          case 0:
            _drawChatBubble(canvas, strokePaint);
            break;
          case 1:
            _drawHeart(canvas, strokePaint);
            break;
          case 2:
            _drawCoffee(canvas, strokePaint);
            break;
          case 3:
            _drawCamera(canvas, strokePaint);
            break;
          case 4:
            _drawPaperPlane(canvas, strokePaint);
            break;
          case 5:
            _drawClock(canvas, strokePaint);
            break;
          case 6:
            _drawStar(canvas, strokePaint);
            break;
          case 7:
            _drawLightbulb(canvas, strokePaint);
            break;
          case 8:
            _drawMusicNote(canvas, strokePaint, fillPaint);
            break;
          case 9:
            _drawSmiley(canvas, strokePaint, fillPaint);
            break;
          case 10:
            _drawCloud(canvas, strokePaint);
            break;
          case 11:
            _drawHeadphones(canvas, strokePaint);
            break;
        }

        canvas.restore();
      }
    }
  }

  void _drawChatBubble(Canvas canvas, Paint paint) {
    final rrect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-8, -7, 16, 12),
      const Radius.circular(3.5),
    );
    canvas.drawRRect(rrect, paint);
    final tail = Path()
      ..moveTo(-1, 5)
      ..lineTo(-4, 9)
      ..lineTo(-4, 5);
    canvas.drawPath(tail, paint);
  }

  void _drawHeart(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(0, 5)
      ..cubicTo(-6.5, 0.5, -7.5, -5.5, 0, -5.5)
      ..cubicTo(7.5, -5.5, 6.5, 0.5, 0, 5);
    canvas.drawPath(path, paint);
  }

  void _drawCoffee(Canvas canvas, Paint paint) {
    final cup = RRect.fromRectAndCorners(
      const Rect.fromLTWH(-6, -4, 11, 10),
      bottomLeft: const Radius.circular(3.5),
      bottomRight: const Radius.circular(3.5),
    );
    canvas.drawRRect(cup, paint);
    final handle = Path()
      ..moveTo(5, -2)
      ..cubicTo(8.5, -2, 8.5, 3, 5, 3);
    canvas.drawPath(handle, paint);
    final steam = Path()
      ..moveTo(-2, -6)
      ..quadraticBezierTo(-4, -8, -1, -10);
    canvas.drawPath(steam, paint);
  }

  void _drawCamera(Canvas canvas, Paint paint) {
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-8, -4, 16, 11),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(body, paint);
    canvas.drawCircle(const Offset(0, 1.5), 3, paint);
    canvas.drawLine(const Offset(-3, -4), const Offset(-3, -6), paint);
    canvas.drawLine(const Offset(0, -4), const Offset(0, -6), paint);
  }

  void _drawPaperPlane(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(-7, 6)
      ..lineTo(0, -8)
      ..lineTo(7, 6)
      ..lineTo(0, 2)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(const Offset(0, -8), const Offset(0, 2), paint);
  }

  void _drawClock(Canvas canvas, Paint paint) {
    canvas.drawCircle(Offset.zero, 6.5, paint);
    canvas.drawLine(Offset.zero, const Offset(0, -3.8), paint);
    canvas.drawLine(Offset.zero, const Offset(2.8, 0), paint);
  }

  void _drawStar(Canvas canvas, Paint paint) {
    final path = Path();
    const double outerR = 6.5;
    const double innerR = 3.0;
    for (int i = 0; i < 10; i++) {
      final r = (i % 2 == 0) ? outerR : innerR;
      final angle = (i * math.pi / 5) - (math.pi / 2);
      final x = r * math.cos(angle);
      final y = r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawLightbulb(Canvas canvas, Paint paint) {
    canvas.drawCircle(const Offset(0, -2.5), 4.8, paint);
    canvas.drawLine(const Offset(-2, 2.5), const Offset(2, 2.5), paint);
    canvas.drawLine(const Offset(-1.2, 4.5), const Offset(1.2, 4.5), paint);
  }

  void _drawMusicNote(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(-2.5, 3.5), width: 5.5, height: 4),
      fill,
    );
    canvas.drawLine(const Offset(0, 3.5), const Offset(0, -6), stroke);
    final flag = Path()
      ..moveTo(0, -6)
      ..quadraticBezierTo(4, -5, 4, -1);
    canvas.drawPath(flag, stroke);
  }

  void _drawSmiley(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawCircle(Offset.zero, 6.5, stroke);
    canvas.drawCircle(const Offset(-2.2, -1.8), 0.8, fill);
    canvas.drawCircle(const Offset(2.2, -1.8), 0.8, fill);
    final smile = Path()
      ..moveTo(-3, 1.5)
      ..quadraticBezierTo(0, 4.5, 3, 1.5);
    canvas.drawPath(smile, stroke);
  }

  void _drawCloud(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(-6, 3)
      ..lineTo(6, 3)
      ..quadraticBezierTo(8, 0, 5, -1)
      ..quadraticBezierTo(4, -5, 0, -4)
      ..quadraticBezierTo(-4, -5, -4, -1)
      ..quadraticBezierTo(-8, 0, -6, 3);
    canvas.drawPath(path, paint);
  }

  void _drawHeadphones(Canvas canvas, Paint paint) {
    final band = Path()
      ..arcTo(
        const Rect.fromLTWH(-6, -6, 12, 12),
        math.pi,
        math.pi,
        false,
      );
    canvas.drawPath(band, paint);
    final cup1 = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-7.5, 0, 3, 5),
      const Radius.circular(1.5),
    );
    final cup2 = RRect.fromRectAndRadius(
      const Rect.fromLTWH(4.5, 0, 3, 5),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(cup1, paint);
    canvas.drawRRect(cup2, paint);
  }

  @override
  bool shouldRepaint(covariant WhatsAppDoodlePainter oldDelegate) {
    return oldDelegate.doodleColor != doodleColor;
  }
}
