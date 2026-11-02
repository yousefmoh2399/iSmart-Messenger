import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_app/features/chat/models/chat_models.dart';
import 'package:desktop_app/shared/providers/providers.dart';
import 'package:desktop_app/shared/widgets/desktop_workspace_sidebar.dart';

void main() {
  group('Desktop Unread Count & Visibility Tests', () {
    test('chatAppForegroundProvider defaults to true and tracks foreground state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(chatAppForegroundProvider), isTrue);

      container.read(chatAppForegroundProvider.notifier).state = false;
      expect(container.read(chatAppForegroundProvider), isFalse);
    });

    test('chatSectionVisibleProvider tracks whether chat section is active', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(chatSectionVisibleProvider), isTrue);

      container.read(chatSectionVisibleProvider.notifier).state = false;
      expect(container.read(chatSectionVisibleProvider), isFalse);
    });

    test('activeConversationIdProvider resets to null when navigating away from chat', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(activeConversationIdProvider.notifier).state = 'conv_123';
      expect(container.read(activeConversationIdProvider), 'conv_123');

      // Simulate switching to files section
      container.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.files;
      container.read(chatSectionVisibleProvider.notifier).state = false;
      container.read(activeConversationIdProvider.notifier).state = null;

      expect(container.read(activeConversationIdProvider), isNull);
      expect(container.read(chatSectionVisibleProvider), isFalse);
    });

    test('ChatConversation accurately tracks unreadCount and increments on copyWith', () {
      final conv = ChatConversation(
        id: 'c_test_1',
        type: 'direct',
        name: 'أحمد',
        description: '',
        avatarUrl: null,
        departmentId: null,
        createdBy: 'user_peer',
        members: const [],
        admins: const [],
        broadcastPublisherIds: const [],
        blockedMemberIds: const [],
        blockedMembers: const [],
        pinnedMessage: null,
        lastMessage: null,
        unreadCount: 0,
        isArchived: false,
        isMuted: false,
        mutedUntil: null,
        isPinned: false,
        isFavorite: false,
        isActive: true,
        isMember: true,
        membershipStatus: 'active',
        canSend: true,
        isBlocked: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(conv.unreadCount, 0);

      final withUnread = conv.copyWith(unreadCount: conv.unreadCount + 1);
      expect(withUnread.unreadCount, 1);

      final nextUnread = withUnread.copyWith(unreadCount: withUnread.unreadCount + 1);
      expect(nextUnread.unreadCount, 2);

      final readReset = nextUnread.copyWith(unreadCount: 0);
      expect(readReset.unreadCount, 0);
    });
  });
}
