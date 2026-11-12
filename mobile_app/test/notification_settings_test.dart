import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/settings/user_preferences.dart';
import 'package:mobile_app/core/settings/user_preferences_store.dart';
import 'package:mobile_app/shared/services/local_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Notification Preferences & Grouping Settings Tests', () {
    test('UserPreferences defaults initialize all notification options correctly', () {
      final prefs = UserPreferences.defaults();

      expect(prefs.notificationsEnabled, isTrue);
      expect(prefs.messageNotificationsEnabled, isTrue);
      expect(prefs.messageToneId, equals('default'));
      expect(prefs.messageVibrate, isTrue);
      expect(prefs.messagePreview, isTrue);

      expect(prefs.groupNotificationsEnabled, isTrue);
      expect(prefs.groupToneId, equals('default'));
      expect(prefs.groupVibrate, isTrue);
      expect(prefs.groupPreview, isTrue);

      expect(prefs.groupNotificationsByChat, isTrue);
      expect(prefs.inAppBanners, isTrue);
      expect(prefs.reactionNotifications, isTrue);
      expect(prefs.autoClearOnOpen, isTrue);
    });

    test('UserPreferences copyWith updates individual notification options', () {
      final prefs = UserPreferences.defaults();

      final updated = prefs.copyWith(
        notificationsEnabled: false,
        messageNotificationsEnabled: false,
        groupToneId: 'chime',
        groupVibrate: false,
        groupNotificationsByChat: false,
        autoClearOnOpen: false,
      );

      expect(updated.notificationsEnabled, isFalse);
      expect(updated.messageNotificationsEnabled, isFalse);
      expect(updated.groupToneId, equals('chime'));
      expect(updated.groupTone.id, equals('chime'));
      expect(updated.groupVibrate, isFalse);
      expect(updated.groupNotificationsByChat, isFalse);
      expect(updated.autoClearOnOpen, isFalse);

      // Unchanged fields remain defaults
      expect(updated.messageVibrate, isTrue);
      expect(updated.groupPreview, isTrue);
      expect(updated.inAppBanners, isTrue);
    });

    test('UserPreferencesStore persists and reloads all notification options', () async {
      SharedPreferences.setMockInitialValues({});
      final store = UserPreferencesStore();

      var loaded = await store.load();
      expect(loaded.notificationsEnabled, isTrue);
      expect(loaded.groupNotificationsByChat, isTrue);

      await store.save(
        loaded.copyWith(
          notificationsEnabled: false,
          groupToneId: 'alert',
          groupNotificationsByChat: true,
          messagePreview: false,
          autoClearOnOpen: true,
        ),
      );

      loaded = await store.load();
      expect(loaded.notificationsEnabled, isFalse);
      expect(loaded.groupToneId, equals('alert'));
      expect(loaded.groupTone.id, equals('alert'));
      expect(loaded.messagePreview, isFalse);
      expect(loaded.groupNotificationsByChat, isTrue);
      expect(loaded.autoClearOnOpen, isTrue);
    });

    test('LocalNotificationService tone mapping matches NotificationTone', () {
      expect(
        LocalNotificationService.androidFcmChannelIdForToneId('chime'),
        equals('chat_messages_chime_v1'),
      );
      expect(
        LocalNotificationService.androidFcmChannelIdForToneId('alert'),
        equals('chat_messages_alert_v1'),
      );
      expect(
        LocalNotificationService.androidFcmChannelIdForToneId('silent'),
        equals('chat_messages_silent_v1'),
      );
      expect(
        LocalNotificationService.androidFcmChannelIdForToneId('default'),
        equals('chat_messages_default_v1'),
      );
    });
  });
}
