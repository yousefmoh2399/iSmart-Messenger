import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeStore {
  static const _key = 'theme_mode';

  Future<ThemeMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return switch (raw) {
      'dark' => ThemeMode.dark,
      _ => ThemeMode.light,
    };
  }

  Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'light',
    };
    await prefs.setString(_key, raw);
  }
}
