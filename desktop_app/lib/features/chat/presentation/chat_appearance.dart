import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/models/app_user.dart';

class ChatThemeOption {
  const ChatThemeOption({
    required this.id,
    required this.title,
    required this.description,
    required this.color,
  });

  final String id;
  final String title;
  final String description;
  final Color color;
}

class ChatWallpaperOption {
  const ChatWallpaperOption({
    required this.id,
    required this.title,
    required this.previewColors,
    required this.lightColors,
    required this.darkColors,
  });

  final String id;
  final String title;
  final List<Color> previewColors;
  final List<Color> lightColors;
  final List<Color> darkColors;
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

  bool get hasOutgoingGradient =>
      outgoingBubbleColors.length > 1 &&
      outgoingBubbleColors.any((entry) => entry != outgoingBubbleColors.first);
}

class ChatAppearanceCatalog {
  static const themes = <ChatThemeOption>[
    ChatThemeOption(
      id: 'system',
      title: 'بدون ثيم',
      description: 'اتبع مظهر التطبيق العام فقط',
      color: Color(0xFF64748B),
    ),
    ChatThemeOption(
      id: 'classic',
      title: 'تلجرام',
      description: 'مظهر تلجرام بخلفية ورسالة متناسقة',
      color: Color(0xFF3390EC),
    ),
    ChatThemeOption(
      id: 'mint',
      title: 'زمرد',
      description: 'ألوان هادئة مع ورسالة متدرجة',
      color: Color(0xFF10B981),
    ),
    ChatThemeOption(
      id: 'violet',
      title: 'لافندر',
      description: 'بنفسجي مريح مع تباين أفضل',
      color: Color(0xFF7C3AED),
    ),
    ChatThemeOption(
      id: 'sunset',
      title: 'غروب',
      description: 'ألوان دافئة مناسبة للشات الطويل',
      color: Color(0xFFF59E0B),
    ),
    ChatThemeOption(
      id: 'mono',
      title: 'جرافيت',
      description: 'ستايل عملي قريب من Telegram Business',
      color: Color(0xFF64748B),
    ),
    ChatThemeOption(
      id: 'custom',
      title: 'ثيم مخصص',
      description: 'لون الرسالة والخلفية على ذوقك',
      color: Color(0xFF0EA5E9),
    ),
  ];

  static const wallpapers = <ChatWallpaperOption>[
    ChatWallpaperOption(
      id: 'default',
      title: 'افتراضي',
      previewColors: [Color(0xFFDCEEFF), Color(0xFFF6FBFF)],
      lightColors: [Color(0xFFDCEEFF), Color(0xFFF6FBFF), Color(0xFFEAF5FF)],
      darkColors: [Color(0xFF0E1621), Color(0xFF111B26), Color(0xFF17212B)],
    ),
    ChatWallpaperOption(
      id: 'night',
      title: 'ليلي',
      previewColors: [Color(0xFF0E1621), Color(0xFF17212B)],
      lightColors: [Color(0xFFCFD8E3), Color(0xFFEEF4F9), Color(0xFFDDE8F2)],
      darkColors: [Color(0xFF0E1621), Color(0xFF111B26), Color(0xFF17212B)],
    ),
    ChatWallpaperOption(
      id: 'sky',
      title: 'سماء',
      previewColors: [Color(0xFFDCEBFF), Color(0xFFF8FAFF)],
      lightColors: [Color(0xFFDCEBFF), Color(0xFFF8FAFF), Color(0xFFE8F3FF)],
      darkColors: [Color(0xFF111D2E), Color(0xFF15263A), Color(0xFF1A3047)],
    ),
    ChatWallpaperOption(
      id: 'mint',
      title: 'نسيم',
      previewColors: [Color(0xFFDFF7EF), Color(0xFFF8FFFB)],
      lightColors: [Color(0xFFDFF7EF), Color(0xFFF8FFFB), Color(0xFFEAFBF3)],
      darkColors: [Color(0xFF11261F), Color(0xFF153128), Color(0xFF183A30)],
    ),
    ChatWallpaperOption(
      id: 'violet',
      title: 'لافندر',
      previewColors: [Color(0xFFEDE9FE), Color(0xFFFFFFFF)],
      lightColors: [Color(0xFFEDE9FE), Color(0xFFFFFFFF), Color(0xFFF5F1FF)],
      darkColors: [Color(0xFF1D1730), Color(0xFF241C3B), Color(0xFF2B2148)],
    ),
    ChatWallpaperOption(
      id: 'sunset',
      title: 'غروب',
      previewColors: [Color(0xFFFFEDD5), Color(0xFFFFFFFF)],
      lightColors: [Color(0xFFFFEDD5), Color(0xFFFFFFFF), Color(0xFFFFF4E7)],
      darkColors: [Color(0xFF2A1B10), Color(0xFF352215), Color(0xFF402A17)],
    ),
    ChatWallpaperOption(
      id: 'custom',
      title: 'خلفية مخصصة',
      previewColors: [Color(0xFF0E1621), Color(0xFF17212B)],
      lightColors: [Color(0xFFDCEEFF), Color(0xFFF6FBFF), Color(0xFFEAF5FF)],
      darkColors: [Color(0xFF0E1621), Color(0xFF111B26), Color(0xFF17212B)],
    ),
  ];

  static const customAccentSwatches = <Color>[
    Color(0xFF3390EC),
    Color(0xFF0EA5E9),
    Color(0xFF22C55E),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF7C3AED),
    Color(0xFF8B5CF6),
    Color(0xFF64748B),
  ];

  static const customBubbleSwatches = <Color>[
    Color(0xFF2F8CFF),
    Color(0xFF5BA9FF),
    Color(0xFF18BFA0),
    Color(0xFF10B981),
    Color(0xFF7C3AED),
    Color(0xFF6366F1),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF17212B),
    Color(0xFF243B53),
    Color(0xFFF8FBFF),
    Color(0xFFFFFFFF),
  ];

  static const customWallpaperPalettes = <List<Color>>[
    [Color(0xFF0E1621), Color(0xFF111B26), Color(0xFF17212B)],
    [Color(0xFF111D2E), Color(0xFF15263A), Color(0xFF1A3047)],
    [Color(0xFF11261F), Color(0xFF153128), Color(0xFF183A30)],
    [Color(0xFF1D1730), Color(0xFF241C3B), Color(0xFF2B2148)],
    [Color(0xFF2A1B10), Color(0xFF352215), Color(0xFF402A17)],
    [Color(0xFFDCEEFF), Color(0xFFF6FBFF), Color(0xFFEAF5FF)],
    [Color(0xFFDFF7EF), Color(0xFFF8FFFB), Color(0xFFEAFBF3)],
    [Color(0xFFEDE9FE), Color(0xFFFFFFFF), Color(0xFFF5F1FF)],
  ];

  static bool usesSystemMode(String themeId) => themeId == 'system';

  static bool usesCustomTheme(String themeId) => themeId == 'custom';

  static ChatThemeOption themeById(String themeId) {
    for (final entry in themes) {
      if (entry.id == themeId) {
        return entry;
      }
    }
    return themes.first;
  }

  static ChatWallpaperOption wallpaperById(String wallpaperId) {
    for (final entry in wallpapers) {
      if (entry.id == wallpaperId) {
        return entry;
      }
    }
    return wallpapers.first;
  }

  static Color colorFromHex(
    String hex, {
    Color fallback = const Color(0xFF3390EC),
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
          ? const [Color(0xFF0E1621), Color(0xFF111B26), Color(0xFF17212B)]
          : const [Color(0xFFF5F9FD), Color(0xFFFCFEFF), Color(0xFFF7FBFF)],
      customTheme: preferences.customTheme,
    );
    return ChatResolvedAppearance(
      accent: colorScheme.primary,
      outgoingBubbleColors: isDark
          ? const [Color(0xFF2B5278), Color(0xFF33628F)]
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
        alpha: isDark ? 0.48 : 0.20,
      ),
      incomingBorderColor: isDark
          ? const Color(0xFF243140)
          : colorScheme.outlineVariant,
      outgoingReplyColor: isDark
          ? const Color(0xFF244668)
          : const Color(0xFFECF7FF),
      incomingReplyColor: isDark
          ? const Color(0xFF223446)
          : const Color(0xFFF8FBFE),
      wallpaperColors: wallpaperColors,
      patternColor: colorScheme.primary.withValues(alpha: isDark ? 0.10 : 0.08),
      sparkleColor: isDark
          ? Colors.white.withValues(alpha: 0.055)
          : colorScheme.primary.withValues(alpha: 0.035),
      isDarkVariant: isDark,
    );
  }

  static ChatResolvedAppearance _resolvePresetAppearance({
    required ChatPreferences preferences,
    required bool isDark,
  }) {
    final accent = switch (preferences.themeId) {
      'mint' => const Color(0xFF10B981),
      'violet' => const Color(0xFF7C3AED),
      'sunset' => const Color(0xFFF59E0B),
      'mono' => const Color(0xFF64748B),
      _ => const Color(0xFF3390EC),
    };

    final outgoingBubbleColors = isDark
        ? [
            _toneColor(accent, isDark: true, amount: 0.46),
            _toneColor(accent, isDark: true, amount: 0.30),
          ]
        : [
            _toneColor(accent, isDark: false, amount: 0.22),
            _toneColor(accent, isDark: false, amount: 0.04),
          ];

    final incomingBubbleColor = preferences.themeId == 'classic'
        ? (isDark ? const Color(0xFF182533) : const Color(0xFFF8FBFF))
        : _blendSurface(accent, isDark: isDark, strength: isDark ? 0.18 : 0.10);
    final wallpaperColors = _wallpaperColorsFor(
      wallpaperId: preferences.wallpaperId,
      isDark: isDark,
      fallback: _defaultWallpaperForTheme(preferences.themeId, isDark),
      customTheme: preferences.customTheme,
    );

    return ChatResolvedAppearance(
      accent: accent,
      outgoingBubbleColors: outgoingBubbleColors,
      incomingBubbleColor: incomingBubbleColor,
      outgoingTextColor: isDark
          ? const Color(0xFFF4FBFF)
          : const Color(0xFF102331),
      incomingTextColor: isDark
          ? const Color(0xFFF2F5F7)
          : const Color(0xFF182533),
      outgoingBorderColor: accent.withValues(alpha: isDark ? 0.50 : 0.28),
      incomingBorderColor: accent.withValues(alpha: isDark ? 0.32 : 0.20),
      outgoingReplyColor: _blend(outgoingBubbleColors.first, accent, 0.20),
      incomingReplyColor: _blend(
        incomingBubbleColor,
        accent,
        isDark ? 0.22 : 0.10,
      ),
      wallpaperColors: wallpaperColors,
      patternColor: accent.withValues(alpha: isDark ? 0.11 : 0.08),
      sparkleColor: isDark
          ? Colors.white.withValues(alpha: 0.055)
          : accent.withValues(alpha: 0.040),
      isDarkVariant: isDark,
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
      outgoingBorderColor: accent.withValues(alpha: isDark ? 0.52 : 0.28),
      incomingBorderColor: accent.withValues(alpha: isDark ? 0.34 : 0.22),
      outgoingReplyColor: _blend(outgoingBubbleColors.first, accent, 0.22),
      incomingReplyColor: _blend(
        incomingBubbleColor,
        accent,
        isDark ? 0.20 : 0.08,
      ),
      wallpaperColors: wallpaperColors,
      patternColor: accent.withValues(alpha: isDark ? 0.11 : 0.08),
      sparkleColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : accent.withValues(alpha: 0.04),
      isDarkVariant: isDark,
    );
  }

  static List<Color> _wallpaperColorsFor({
    required String wallpaperId,
    required bool isDark,
    required List<Color> fallback,
    required ChatCustomTheme customTheme,
  }) {
    if (!isDark) {
      return const [Color(0xFFF8FAFC), Color(0xFFF8FAFC), Color(0xFFF8FAFC)];
    }

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
    return wallpaper.darkColors;
  }

  static List<Color> _defaultWallpaperForTheme(String themeId, bool isDark) {
    return switch (themeId) {
      'mint' =>
        isDark
            ? const [Color(0xFF11261F), Color(0xFF153128), Color(0xFF183A30)]
            : const [Color(0xFFDFF7EF), Color(0xFFF8FFFB), Color(0xFFEAFBF3)],
      'violet' =>
        isDark
            ? const [Color(0xFF1D1730), Color(0xFF241C3B), Color(0xFF2B2148)]
            : const [Color(0xFFEDE9FE), Color(0xFFFFFFFF), Color(0xFFF5F1FF)],
      'sunset' =>
        isDark
            ? const [Color(0xFF2A1B10), Color(0xFF352215), Color(0xFF402A17)]
            : const [Color(0xFFFFEDD5), Color(0xFFFFFFFF), Color(0xFFFFF4E7)],
      'mono' =>
        isDark
            ? const [Color(0xFF131922), Color(0xFF1A2430), Color(0xFF202D3B)]
            : const [Color(0xFFF1F5F9), Color(0xFFFFFFFF), Color(0xFFF7FAFC)],
      _ =>
        isDark
            ? const [Color(0xFF0E1621), Color(0xFF111B26), Color(0xFF17212B)]
            : const [Color(0xFFDCEEFF), Color(0xFFF6FBFF), Color(0xFFEAF5FF)],
    };
  }

  static Color _toneColor(
    Color color, {
    required bool isDark,
    required double amount,
  }) {
    return isDark
        ? _blend(color, Colors.black, amount)
        : _blend(color, Colors.white, amount);
  }

  static Color _blendSurface(
    Color accent, {
    required bool isDark,
    required double strength,
  }) {
    return _blend(
      isDark ? const Color(0xFF17212B) : Colors.white,
      accent,
      strength,
    );
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
          Positioned.fill(
            child: CustomPaint(
              painter: _ChatPatternPainter(
                accentColor: resolved.patternColor,
                sparkleColor: resolved.sparkleColor,
                isDark: resolved.isDarkVariant,
              ),
            ),
          ),
          Positioned(
            top: -30,
            left: -20,
            child: _BackdropOrb(size: 210, color: resolved.patternColor),
          ),
          Positioned(
            top: 160,
            right: -18,
            child: _BackdropOrb(
              size: 170,
              color: resolved.patternColor.withValues(
                alpha: resolved.isDarkVariant ? 0.06 : 0.05,
              ),
            ),
          ),
          Positioned(
            bottom: -40,
            left: 90,
            child: _BackdropOrb(
              size: 240,
              color: resolved.patternColor.withValues(
                alpha: resolved.isDarkVariant ? 0.045 : 0.04,
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

class _ChatPatternPainter extends CustomPainter {
  const _ChatPatternPainter({
    required this.accentColor,
    required this.sparkleColor,
    required this.isDark,
  });

  final Color accentColor;
  final Color sparkleColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final outlinePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05;

    final linePaint = Paint()
      ..color = sparkleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isDark ? 1.0 : 0.95;

    canvas.drawCircle(
      Offset(size.width * 0.84, size.height * 0.68),
      22,
      outlinePaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.16, size.height * 0.76),
      14,
      outlinePaint,
    );

    final roundedRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * 0.50, size.height * 0.58),
        width: 24,
        height: 24,
      ),
      const Radius.circular(7),
    );
    canvas.drawRRect(roundedRect, outlinePaint);

    final path1 = Path()
      ..moveTo(size.width * 0.12, size.height * 0.18)
      ..quadraticBezierTo(
        size.width * 0.22,
        size.height * 0.08,
        size.width * 0.34,
        size.height * 0.19,
      );
    canvas.drawPath(path1, linePaint);

    final path2 = Path()
      ..moveTo(size.width * 0.63, size.height * 0.14)
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.04,
        size.width * 0.90,
        size.height * 0.18,
      );
    canvas.drawPath(path2, linePaint);
  }

  @override
  bool shouldRepaint(covariant _ChatPatternPainter oldDelegate) {
    return oldDelegate.accentColor != accentColor ||
        oldDelegate.sparkleColor != sparkleColor ||
        oldDelegate.isDark != isDark;
  }
}

class _BackdropOrb extends StatelessWidget {
  const _BackdropOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: color.a * 0.45),
            color.withValues(alpha: 0),
          ],
        ),
      ),
      child: SizedBox(width: size, height: size),
    );
  }
}
