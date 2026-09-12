import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/formatters.dart';
import '../../models/chat_models.dart';

enum ChatSidebarFilter {
  all,
  direct,
  departments,
  branches,
  rooms,
  favorites,
  archived,
}

DateTime conversationActivityAt(ChatConversation conversation) {
  return conversation.lastMessage?.createdAt ?? conversation.updatedAt;
}

List<ChatConversation> sortConversationsForSidebar(
  List<ChatConversation> source,
) {
  final active = source
      .where((conversation) => !conversation.isArchived)
      .toList();
  final archived = source
      .where((conversation) => conversation.isArchived)
      .toList();

  int sortFn(ChatConversation a, ChatConversation b) {
    if (a.isPinned != b.isPinned) {
      return a.isPinned ? -1 : 1;
    }
    if (a.isFavorite != b.isFavorite) {
      return a.isFavorite ? -1 : 1;
    }
    return conversationActivityAt(b).compareTo(conversationActivityAt(a));
  }

  active.sort(sortFn);
  archived.sort(sortFn);
  return [...active, ...archived];
}

String formatConversationTime(ChatConversation conversation) {
  final stamp = conversation.lastMessage?.createdAt ?? conversation.updatedAt;
  final now = DateTime.now();
  if (stamp.year == now.year &&
      stamp.month == now.month &&
      stamp.day == now.day) {
    return formatEgyptTime(stamp);
  }
  return DateFormat('dd/MM').format(stamp.toLocal());
}

String formatPresenceLabel(ChatDirectoryUser user) {
  if (user.presenceStatus == 'online') {
    return 'متصل الآن';
  }
  if (user.presenceStatus == 'meeting') {
    return 'في اجتماع';
  }
  if (user.presenceStatus == 'lunch') {
    return 'استراحة';
  }
  if (user.presenceStatus == 'idle') {
    final at = user.lastActiveAt ?? user.lastSeen;
    if (at == null) {
      return 'خامل';
    }
    return 'خامل منذ ${formatEgyptTime(at)}';
  }
  final lastSeen = user.lastSeen ?? user.lastActiveAt;
  if (lastSeen == null) {
    return 'غير متصل';
  }
  return 'آخر ظهور ${formatEgyptDateTime(lastSeen, datePattern: 'dd/MM', separator: ' ')}';
}

Color presenceColor(String status) => switch (status) {
  'online' => const Color(0xFF27AE60),
  'meeting' => const Color(0xFFE67E22),
  'lunch' => const Color(0xFFF59E0B),
  'idle' => const Color(0xFFF39C12),
  _ => const Color(0xFF9AA7B4),
};

Color conversationTypeAccent(String type) => switch (type) {
  'department' => const Color(0xFF19A974),
  'broadcast' => const Color(0xFFE67E22),
  'group' => const Color(0xFF4A90E2),
  _ => const Color(0xFF3390EC),
};

IconData conversationTypeIcon(String type) => switch (type) {
  'department' => Icons.apartment_rounded,
  'broadcast' => Icons.campaign_rounded,
  'group' => Icons.groups_rounded,
  _ => Icons.person_rounded,
};
