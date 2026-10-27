import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/core/settings/user_preferences.dart';
import 'package:desktop_app/core/settings/user_preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationDisplayMode Tests', () {
    test('defaultMode is all', () {
      expect(NotificationDisplayMode.defaultMode, NotificationDisplayMode.all);
    });

    test('fromId returns correct enum value', () {
      expect(NotificationDisplayMode.fromId('all'), NotificationDisplayMode.all);
      expect(NotificationDisplayMode.fromId('hide_details'), NotificationDisplayMode.hideDetails);
      expect(NotificationDisplayMode.fromId('sound_only'), NotificationDisplayMode.soundOnly);
      expect(NotificationDisplayMode.fromId('invalid'), NotificationDisplayMode.all);
      expect(NotificationDisplayMode.fromId(null), NotificationDisplayMode.all);
    });

    test('UserPreferences defaults to all display mode', () {
      final prefs = UserPreferences.defaults();
      expect(prefs.notificationDisplayModeId, 'all');
      expect(prefs.notificationDisplayMode, NotificationDisplayMode.all);
    });

    test('UserPreferences copyWith updates display mode correctly', () {
      final prefs = UserPreferences.defaults();
      final updated = prefs.copyWith(notificationDisplayModeId: 'sound_only');
      expect(updated.notificationDisplayModeId, 'sound_only');
      expect(updated.notificationDisplayMode, NotificationDisplayMode.soundOnly);
    });

    test('UserPreferencesStore loads and saves display mode', () async {
      SharedPreferences.setMockInitialValues({});
      final store = UserPreferencesStore();

      var loaded = await store.load();
      expect(loaded.notificationDisplayMode, NotificationDisplayMode.all);

      await store.save(loaded.copyWith(notificationDisplayModeId: 'sound_only'));
      loaded = await store.load();
      expect(loaded.notificationDisplayMode, NotificationDisplayMode.soundOnly);

      await store.save(loaded.copyWith(notificationDisplayModeId: 'hide_details'));
      loaded = await store.load();
      expect(loaded.notificationDisplayMode, NotificationDisplayMode.hideDetails);
    });
  });
}
