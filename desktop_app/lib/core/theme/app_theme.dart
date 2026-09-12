// import 'package:flutter/material.dart';

// class AppTheme {
//   // Don't specify a primary font - let system choose default
//   // Fallbacks will be used for missing glyphs (Arabic support)
//   static const String _fontFamily = 'NotoSansArabic';
//   static const List<String> _fontFallbacks = [
//     'Segoe UI',
//     'Tahoma',
//     'Arial',
//     'Helvetica',
//     'sans-serif',
//   ];

//   static const Color _telegramBlue = Color(0xFF3390EC);
//   static const Color _telegramBlueSoft = Color(0xFF64B5F6);
//   static const Color _lightBg = Color(0xFFEFF3F6);
//   static const Color _lightSurface = Color(0xFFF8FAFC);
//   static const Color _lightSurfaceAlt = Color(0xFFFFFFFF);
//   static const Color _darkBg = Color(0xFF18222D);
//   static const Color _darkSurface = Color(0xFF1F2C38);
//   static const Color _darkSurfaceAlt = Color(0xFF233240);

//   static ThemeData get lightTheme => _buildTheme(Brightness.light);
//   static ThemeData get darkTheme => _buildTheme(Brightness.dark);

//   static ThemeData _buildTheme(Brightness brightness) {
//     final isDark = brightness == Brightness.dark;
//     final scheme = ColorScheme.fromSeed(
//       seedColor: _telegramBlue,
//       brightness: brightness,
//       primary: isDark ? const Color(0xFF6FB3F2) : _telegramBlue,
//       secondary: _telegramBlueSoft,
//       surface: isDark ? _darkSurface : _lightSurfaceAlt,
//       surfaceContainer: isDark ? _darkSurfaceAlt : _lightSurface,
//       onPrimary: Colors.white,
//       onSurface: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF182533),
//       onSurfaceVariant: isDark
//           ? const Color(0xFF9FB0BE)
//           : const Color(0xFF6B7C8C),
//     );

//     final baseText = Typography.material2021(platform: TargetPlatform.windows)
//         .black
//         .apply(
//           bodyColor: scheme.onSurface,
//           displayColor: scheme.onSurface,
//           fontFamily: _fontFamily ?? 'NotoSansArabic',
//           fontFamilyFallback: _fontFallbacks,
//         );

//     return ThemeData(
//       useMaterial3: true,
//       brightness: brightness,
//       colorScheme: scheme,
//       textTheme: baseText.copyWith(
//         headlineSmall: baseText.headlineSmall?.copyWith(
//           fontWeight: FontWeight.w800,
//           height: 1.2,
//           fontFamily: _fontFamily,
//           fontFamilyFallback: _fontFallbacks,
//         ),
//         titleLarge: baseText.titleLarge?.copyWith(
//           fontWeight: FontWeight.w800,
//           fontFamily: _fontFamily,
//           fontFamilyFallback: _fontFallbacks,
//         ),
//         titleMedium: baseText.titleMedium?.copyWith(
//           fontWeight: FontWeight.w700,
//           fontFamily: _fontFamily,
//           fontFamilyFallback: _fontFallbacks,
//         ),
//         bodyMedium: baseText.bodyMedium?.copyWith(
//           height: 1.45,
//           fontFamily: _fontFamily,
//           fontFamilyFallback: _fontFallbacks,
//         ),
//       ),
//       scaffoldBackgroundColor: isDark ? _darkBg : _lightBg,
//       appBarTheme: AppBarTheme(
//         backgroundColor: Colors.transparent,
//         foregroundColor: scheme.onSurface,
//         elevation: 0,
//         scrolledUnderElevation: 0,
//         centerTitle: false,
//         surfaceTintColor: Colors.transparent,
//         titleTextStyle: baseText.titleLarge?.copyWith(
//           fontWeight: FontWeight.w800,
//           color: scheme.onSurface,
//           fontFamily: _fontFamily,
//           fontFamilyFallback: _fontFallbacks,
//         ),
//       ),
//       cardTheme: CardThemeData(
//         color: isDark ? _darkSurface : _lightSurfaceAlt,
//         elevation: 0,
//         margin: EdgeInsets.zero,
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(22),
//           side: BorderSide(
//             color: isDark ? const Color(0xFF314555) : const Color(0xFFD8E1E8),
//           ),
//         ),
//       ),
//       iconTheme: IconThemeData(
//         color: isDark ? const Color(0xFFD8E4F8) : const Color(0xFF183153),
//       ),
//       dividerTheme: DividerThemeData(
//         color: isDark ? const Color(0xFF20385D) : const Color(0xFFE2EAF5),
//         thickness: 1,
//         space: 1,
//       ),
//       chipTheme: ChipThemeData(
//         backgroundColor: isDark
//             ? const Color(0xFF243544)
//             : const Color(0xFFEAF3FB),
//         selectedColor: scheme.primary.withValues(alpha: 0.18),
//         side: BorderSide.none,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
//         labelStyle: TextStyle(
//           color: scheme.onSurface,
//           fontWeight: FontWeight.w700,
//           fontFamily: _fontFamily,
//           fontFamilyFallback: _fontFallbacks,
//         ),
//       ),
//       snackBarTheme: SnackBarThemeData(
//         behavior: SnackBarBehavior.floating,
//         backgroundColor: isDark
//             ? const Color(0xFF243544)
//             : const Color(0xFF2C3E50),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
//         contentTextStyle: const TextStyle(
//           color: Colors.white,
//           fontFamily: _fontFamily,
//           fontFamilyFallback: _fontFallbacks,
//         ),
//       ),
//       inputDecorationTheme: InputDecorationTheme(
//         filled: true,
//         fillColor: isDark ? const Color(0xFF233240) : const Color(0xFFF4F7FA),
//         hintStyle: TextStyle(
//           color: scheme.onSurfaceVariant,
//           fontFamily: _fontFamily,
//           fontFamilyFallback: _fontFallbacks,
//         ),
//         contentPadding: const EdgeInsets.symmetric(
//           horizontal: 18,
//           vertical: 16,
//         ),
//         border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(20),
//           borderSide: BorderSide(
//             color: isDark ? const Color(0xFF314555) : const Color(0xFFD4DDE5),
//           ),
//         ),
//         enabledBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(20),
//           borderSide: BorderSide(
//             color: isDark ? const Color(0xFF314555) : const Color(0xFFD4DDE5),
//           ),
//         ),
//         focusedBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(20),
//           borderSide: const BorderSide(color: _telegramBlue, width: 1.4),
//         ),
//       ),
//       filledButtonTheme: FilledButtonThemeData(
//         style: FilledButton.styleFrom(
//           minimumSize: const Size(0, 50),
//           backgroundColor: _telegramBlue,
//           foregroundColor: Colors.white,
//           textStyle: const TextStyle(
//             fontWeight: FontWeight.w800,
//             fontFamily: _fontFamily,
//             fontFamilyFallback: _fontFallbacks,
//           ),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(18),
//           ),
//         ),
//       ),
//       outlinedButtonTheme: OutlinedButtonThemeData(
//         style: OutlinedButton.styleFrom(
//           minimumSize: const Size(0, 48),
//           foregroundColor: scheme.onSurface,
//           side: BorderSide(
//             color: isDark ? const Color(0xFF385064) : const Color(0xFFC8D5DF),
//           ),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(18),
//           ),
//         ),
//       ),
//       iconButtonTheme: IconButtonThemeData(
//         style: IconButton.styleFrom(
//           minimumSize: const Size(44, 44),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(16),
//           ),
//         ),
//       ),
//       popupMenuTheme: PopupMenuThemeData(
//         color: isDark ? const Color(0xFF233240) : Colors.white,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
//         textStyle: TextStyle(
//           color: scheme.onSurface,
//           fontFamily: _fontFamily,
//           fontFamilyFallback: _fontFallbacks,
//         ),
//       ),
//       dataTableTheme: DataTableThemeData(
//         headingRowColor: WidgetStatePropertyAll(
//           isDark ? const Color(0xFF243544) : const Color(0xFFEAF1F6),
//         ),
//         headingTextStyle: TextStyle(
//           color: scheme.onSurface,
//           fontWeight: FontWeight.w800,
//           fontFamily: _fontFamily,
//           fontFamilyFallback: _fontFallbacks,
//         ),
//         dataTextStyle: TextStyle(
//           color: scheme.onSurface,
//           fontFamily: _fontFamily,
//           fontFamilyFallback: _fontFallbacks,
//         ),
//         dividerThickness: 0.5,
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';

class AppTheme {
  static const String _fontFamily = 'NotoSans';
  static const List<String> _fontFallbacks = ['NotoSansArabic'];

  static const Color _telegramBlue = Color(0xFF3390EC);
  static const Color _telegramBlueSoft = Color(0xFF64B5F6);
  static const Color _lightBg = Color(0xFFF1F5F9); // slate-100 for comfort
  static const Color _lightSurface = Color(0xFFF8FAFC); // slate-50
  static const Color _lightSurfaceAlt = Color(0xFFFFFFFF);
  static const Color _darkBg = Color(0xFF0F172A); // slate-900 for dark mode
  static const Color _darkSurface = Color(0xFF1E293B); // slate-800
  static const Color _darkSurfaceAlt = Color(0xFF334155); // slate-700

  static ThemeData get lightTheme => _buildTheme(Brightness.light);
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: _telegramBlue,
      brightness: brightness,
      primary: isDark ? const Color(0xFF6FB3F2) : _telegramBlue,
      secondary: _telegramBlueSoft,
      surface: isDark ? _darkSurface : _lightSurfaceAlt,
      surfaceContainer: isDark ? _darkSurfaceAlt : _lightSurface,
      onPrimary: Colors.white,
      onSurface: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF182533),
      onSurfaceVariant: isDark
          ? const Color(0xFF9FB0BE)
          : const Color(0xFF6B7C8C),
    );

    final baseText = Typography.material2021(platform: TargetPlatform.windows)
        .black
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallbacks,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: baseText.copyWith(
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          height: 1.2,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallbacks,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallbacks,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallbacks,
        ),
        bodyMedium: baseText.bodyMedium?.copyWith(
          height: 1.45,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallbacks,
        ),
      ),
      scaffoldBackgroundColor: isDark ? _darkBg : _lightBg,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: baseText.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallbacks,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? _darkSurface : _lightSurfaceAlt,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      iconTheme: IconThemeData(
        color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? const Color(0xFF243544)
            : const Color(0xFFEAF3FB),
        selectedColor: scheme.primary.withValues(alpha: 0.18),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallbacks,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF243544)
            : const Color(0xFF2C3E50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentTextStyle: TextStyle(
          color: Colors.white,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallbacks,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallbacks,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: _telegramBlue, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          backgroundColor: _telegramBlue,
          foregroundColor: Colors.white,
          textStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontFamily: _fontFamily,
            fontFamilyFallback: _fontFallbacks,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          foregroundColor: scheme.onSurface,
          side: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: TextStyle(
          color: scheme.onSurface,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallbacks,
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(
          isDark ? const Color(0xFF243544) : const Color(0xFFEAF1F6),
        ),
        headingTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallbacks,
        ),
        dataTextStyle: TextStyle(
          color: scheme.onSurface,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallbacks,
        ),
        dividerThickness: 0.5,
      ),
    );
  }
}
