import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/chat/models/chat_models.dart';
import 'package:mobile_app/features/chat/presentation/widgets/chat_audio_attachment_player.dart';
import 'package:mobile_app/features/chat/presentation/widgets/chat_mute_duration_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Smart Mute Duration Tests', () {
    final baseConv = ChatConversation(
      id: 'conv_123',
      type: 'direct',
      name: 'Test Conversation',
      description: '',
      departmentId: null,
      createdBy: 'user1',
      members: const [],
      admins: const [],
      broadcastPublisherIds: const [],
      blockedMemberIds: const [],
      pinnedMessage: null,
      lastMessage: null,
      unreadCount: 0,
      isArchived: false,
      isMuted: false,
      mutedUntil: null,
      isPinned: false,
      isFavorite: false,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('isEffectivelyMuted returns false when unmuted', () {
      expect(baseConv.isEffectivelyMuted, isFalse);
    });

    test('isEffectivelyMuted returns true when muted indefinitely (mutedUntil = null)', () {
      final conv = baseConv.copyWith(isMuted: true, clearMutedUntil: true);
      expect(conv.isEffectivelyMuted, isTrue);
    });

    test('isEffectivelyMuted returns true when muted with future expiration', () {
      final conv = baseConv.copyWith(
        isMuted: true,
        mutedUntil: DateTime.now().add(const Duration(hours: 8)),
      );
      expect(conv.isEffectivelyMuted, isTrue);
    });

    test('isEffectivelyMuted returns false when muted with expired expiration', () {
      final conv = baseConv.copyWith(
        isMuted: true,
        mutedUntil: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(conv.isEffectivelyMuted, isFalse);
    });

    test('SmartMuteResult converts duration to future mutedUntil date', () {
      const result = SmartMuteResult.temporary(Duration(hours: 8));
      expect(result.isAlways, isFalse);
      expect(result.duration, equals(const Duration(hours: 8)));
      final mutedUntil = result.toMutedUntil();
      expect(mutedUntil, isNotNull);
      expect(mutedUntil!.isAfter(DateTime.now()), isTrue);

      const alwaysResult = SmartMuteResult.always();
      expect(alwaysResult.isAlways, isTrue);
      expect(alwaysResult.duration, isNull);
      expect(alwaysResult.toMutedUntil(), isNull);
    });

    test('ChatConversation fromJson and toJson round-trip preserves mutedUntil', () {
      final futureDate = DateTime.now().add(const Duration(days: 7));
      final json = baseConv
          .copyWith(isMuted: true, mutedUntil: futureDate)
          .toJson();
      expect(json['isMuted'], isTrue);
      expect(json['mutedUntil'], isNotNull);

      final restored = ChatConversation.fromJson(json);
      expect(restored.isMuted, isTrue);
      expect(restored.mutedUntil, isNotNull);
      expect(restored.isEffectivelyMuted, isTrue);
    });
  });

  group('Persistent Voice Speed Tests', () {
    test('ChatAudioPlaybackCoordinator sets and broadcasts speed updates', () async {
      SharedPreferences.setMockInitialValues({'preferred_voice_speed': 1.5});

      await ChatAudioPlaybackCoordinator.ensureSpeedInitialized();
      expect(ChatAudioPlaybackCoordinator.playbackSpeedNotifier.value, equals(1.5));

      await ChatAudioPlaybackCoordinator.setPlaybackSpeed(2.0);
      expect(ChatAudioPlaybackCoordinator.playbackSpeedNotifier.value, equals(2.0));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('preferred_voice_speed'), equals(2.0));

      // Reset
      await ChatAudioPlaybackCoordinator.setPlaybackSpeed(1.0);
      expect(ChatAudioPlaybackCoordinator.playbackSpeedNotifier.value, equals(1.0));
    });
  });
}
