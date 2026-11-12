import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/features/chat/presentation/chat_appearance.dart';
import 'package:desktop_app/shared/models/app_user.dart';

void main() {
  group('Chat Appearance Catalog & Festive Theme Tests', () {
    test('festive_winter is present as the first theme with snow caps enabled', () {
      final winter = ChatAppearanceCatalog.themes.first;
      expect(winter.id, equals('festive_winter'));
      expect(winter.title, contains('رأس السنة والجليد'));
      expect(winter.hasSnowCaps, isTrue);
      expect(winter.badge, contains('رأس السنة'));
    });

    test('festive_halloween is present in themes catalog', () {
      final halloween = ChatAppearanceCatalog.themes.firstWhere((t) => t.id == 'festive_halloween');
      expect(halloween.title, contains('هالوين'));
      expect(halloween.hasSnowCaps, isFalse);
    });

    test('festive wallpapers wp_winter_snow and wp_halloween are in wallpapers list', () {
      final snowWp = ChatAppearanceCatalog.wallpaperById('wp_winter_snow');
      expect(snowWp.id, equals('wp_winter_snow'));
      expect(snowWp.category, equals('festive'));
      expect(snowWp.title, contains('رأس السنة'));

      final halloweenWp = ChatAppearanceCatalog.wallpaperById('wp_halloween');
      expect(halloweenWp.id, equals('wp_halloween'));
      expect(halloweenWp.category, equals('festive'));
    });

    test('resolveAppearance enables snow caps and correct festive colors for festive_winter', () {
      final prefs = ChatPreferences.defaults.copyWith(themeId: 'festive_winter');
      final resolved = ChatAppearanceCatalog.resolveAppearance(
        preferences: prefs,
        isDark: false,
        colorScheme: const ColorScheme.light(),
      );

      expect(resolved.hasSnowCaps, isTrue);
      expect(resolved.accent.value, equals(0xFF0284C7));
    });

    test('resolveAppearance disables snow caps for other themes like whatsapp', () {
      final prefs = ChatPreferences.defaults.copyWith(themeId: 'whatsapp');
      final resolved = ChatAppearanceCatalog.resolveAppearance(
        preferences: prefs,
        isDark: false,
        colorScheme: const ColorScheme.light(),
      );

      expect(resolved.hasSnowCaps, isFalse);
    });
  });
}
