import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';

enum ChatConnectionStatus { connecting, connected, reconnecting, disconnected }

class ChatRealtimeState {
  const ChatRealtimeState({
    required this.status,
    required this.message,
    required this.lastChangedAt,
  });

  final ChatConnectionStatus status;
  final String? message;
  final DateTime lastChangedAt;

  bool get isConnected => status == ChatConnectionStatus.connected;
}

class ChatRealtimeController extends Notifier<ChatRealtimeState> {
  StreamSubscription<ChatSocketEvent>? _subscription;

  Future<void> _refreshDirectoryAndSession() async {
    try {
      await ref.read(chatOverviewControllerProvider.notifier).refresh();
    } catch (_) {}
    final authUser = ref.read(authControllerProvider).valueOrNull;
    if (authUser?.role == 'admin') {
      try {
        await ref.read(usersControllerProvider.notifier).refresh();
      } catch (_) {}
    }
  }

  @override
  ChatRealtimeState build() {
    ref.onDispose(() => _subscription?.cancel());
    _subscription?.cancel();

    final socketService = ref.read(chatSocketServiceProvider);
    final notifications = ref.read(localNotificationServiceProvider);
    _subscription = socketService.events.listen((event) async {
      switch (event.type) {
        case 'socket_connected':
          state = ChatRealtimeState(
            status: ChatConnectionStatus.connected,
            message: 'متصل الآن',
            lastChangedAt: DateTime.now(),
          );
          break;
        case 'socket_reconnecting':
          state = ChatRealtimeState(
            status: ChatConnectionStatus.reconnecting,
            message: 'جاري إعادة الاتصال...',
            lastChangedAt: DateTime.now(),
          );
          break;
        case 'socket_disconnected':
          state = ChatRealtimeState(
            status: ChatConnectionStatus.disconnected,
            message:
                event.payload['message']?.toString() ?? 'فشل الاتصال بالشات',
            lastChangedAt: DateTime.now(),
          );
          break;
        case 'socket_error':
          state = ChatRealtimeState(
            status: ChatConnectionStatus.disconnected,
            message:
                event.payload['message']?.toString() ?? 'فشل الاتصال بالشات',
            lastChangedAt: DateTime.now(),
          );
          break;
        case 'announcements_updated':
          try {
            await ref.read(announcementsControllerProvider.notifier).refresh();
            final authUser = ref.read(authControllerProvider).valueOrNull;
            if (authUser?.role == 'admin') {
              await ref
                  .read(adminAnnouncementsControllerProvider.notifier)
                  .refresh();
            }
          } catch (_) {}
          break;
        case 'receive_message':
          final authUser = ref.read(authControllerProvider).valueOrNull;
          if (authUser == null) {
            break;
          }
          final message = ChatMessage.fromJson(event.payload);
          final activeConversationId = ref.read(activeConversationIdProvider);
          final isChatVisible = ref.read(chatSectionVisibleProvider);
          final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
          ChatConversation? targetConversation;
          if (overview != null) {
            for (final entry in overview.conversations) {
              if (entry.id == message.conversationId) {
                targetConversation = entry;
                break;
              }
            }
          }

          final isMentioned =
              message.metadata?['mentions'] is List &&
              (message.metadata!['mentions'] as List).contains(authUser.id);

          if (message.sender?.id == authUser.id) {
            break;
          }

          if (targetConversation?.isMuted == true && !isMentioned) {
            break;
          }

          if (message.conversationId == activeConversationId && isChatVisible) {
            final shouldSuppress = await notifications
                .shouldSuppressActiveConversationNotification();
            if (shouldSuppress) {
              break;
            }
          }

          final title = message.sender?.displayName ?? 'رسالة جديدة';
          final body = message.content.isNotEmpty
              ? message.content
              : (message.fileName ?? 'تم إرسال مرفق');
          await notifications.showIncomingMessage(title: title, body: body);
          break;
        case 'message_reaction_added':
          final authUser = ref.read(authControllerProvider).valueOrNull;
          if (authUser == null) {
            break;
          }
          final conversationId =
              event.payload['conversationId']?.toString() ?? '';
          final reactorName =
              event.payload['reactorName']?.toString() ?? 'تفاعل جديد';
          final emoji = event.payload['emoji']?.toString() ?? '❤️';
          final activeConversationId = ref.read(activeConversationIdProvider);
          final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
          ChatConversation? targetConversation;
          if (overview != null) {
            for (final entry in overview.conversations) {
              if (entry.id == conversationId) {
                targetConversation = entry;
                break;
              }
            }
          }
          if (targetConversation?.isMuted == true) {
            break;
          }
          final isChatVisible = ref.read(chatSectionVisibleProvider);
          if (conversationId.isNotEmpty &&
              conversationId == activeConversationId &&
              isChatVisible) {
            final shouldSuppress = await notifications
                .shouldSuppressActiveConversationNotification();
            if (shouldSuppress) {
              break;
            }
          }
          await notifications.showIncomingMessage(
            title: reactorName,
            body: 'تفاعل على رسالتك: $emoji',
          );
          break;
        case 'ticket_updated':
          final notification = event.payload['notification'];
          final title = notification is Map
              ? notification['title']?.toString() ?? ''
              : '';
          final body = notification is Map
              ? notification['body']?.toString() ?? ''
              : '';
          final ticket = event.payload['ticket'];
          final fallbackTitle = _ticketNotificationFallbackTitle(
            event.payload['action']?.toString(),
            ticket,
          );
          final fallbackBody = _ticketNotificationFallbackBody(ticket);
          await notifications.showIncomingMessage(
            title: title.trim().isEmpty ? fallbackTitle : title,
            body: body.trim().isEmpty ? fallbackBody : body,
          );
          break;
        case 'departments_updated':
          await _refreshDirectoryAndSession();
          break;
        case 'branches_updated':
          await _refreshDirectoryAndSession();
          break;
        case 'users_updated':
          final authUser = ref.read(authControllerProvider).valueOrNull;
          if (authUser?.role == 'admin') {
            try {
              await ref.read(usersControllerProvider.notifier).refresh();
            } catch (_) {}
          }
          break;
        case 'user_profile_updated':
          final rawUser = event.payload['user'];
          final updatedUserId = rawUser is Map
              ? rawUser['id']?.toString()
              : null;
          final currentUserId = ref
              .read(authControllerProvider)
              .valueOrNull
              ?.id;
          if (updatedUserId != null && updatedUserId == currentUserId) {
            try {
              await ref
                  .read(authControllerProvider.notifier)
                  .refreshCurrentUser();
            } catch (_) {}
          }
          break;
        case 'session_expired':
          try {
            await ref.read(authRepositoryProvider).refreshToken();
            ref.invalidate(authTokenProvider);
            ref.invalidate(chatSocketConnectionProvider);
          } catch (_) {
            try {
              await ref.read(authControllerProvider.notifier).logout();
            } catch (_) {}
          }
          break;
        case 'force_logout':
          try {
            await ref.read(authControllerProvider.notifier).logout();
          } catch (_) {}
          break;
      }
    });

    return ChatRealtimeState(
      status: socketService.isConnected
          ? ChatConnectionStatus.connected
          : ChatConnectionStatus.connecting,
      message: socketService.isConnected ? 'متصل الآن' : 'جاري الاتصال...',
      lastChangedAt: DateTime.now(),
    );
  }
}

String _ticketNotificationFallbackTitle(String? action, Object? ticket) {
  final type = ticket is Map ? ticket['ticketType']?.toString() : null;
  final label = switch (type) {
    'complaint' => 'شكوى',
    'suggestion' => 'مقترح',
    _ => 'تذكرة',
  };

  return switch (action) {
    'created' => '$label جديدة',
    'comment_added' => 'رد جديد على $label',
    'status_updated' => 'تغيير حالة $label',
    'assignee_updated' => 'تحديث إسناد $label',
    _ => 'تحديث $label',
  };
}

String _ticketNotificationFallbackBody(Object? ticket) {
  if (ticket is! Map) {
    return 'يوجد تحديث على التذاكر';
  }

  final number = ticket['ticketNumber']?.toString() ?? '';
  final title = ticket['title']?.toString() ?? '';
  final prefix = number.trim().isEmpty ? 'Ticket' : number;

  return title.trim().isEmpty ? '$prefix: يوجد تحديث جديد' : '$prefix: $title';
}
