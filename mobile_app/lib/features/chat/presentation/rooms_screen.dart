import 'package:flutter/material.dart';

import '../../../shared/models/app_user.dart';
import '../models/chat_models.dart';
import 'conversation_screen.dart';

class RoomsScreen extends StatelessWidget {
  const RoomsScreen({
    super.key,
    required this.currentUser,
    required this.conversations,
  });

  final AppUser? currentUser;
  final List<ChatConversation> conversations;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (conversations.isEmpty) {
      return _RoomsEmptyState(colorScheme: colorScheme);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      itemCount: conversations.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90E2).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.groups_outlined,
                  color: Color(0xFF4A90E2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المجموعات والإعلانات',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${conversations.length} مساحة نشطة بين المجموعات والغرف والقنوات الإعلانية.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final conversation = conversations[index - 1];
        final accent = conversation.type == 'broadcast'
            ? const Color(0xFFE67E22)
            : const Color(0xFF4A90E2);
        return InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ConversationScreen(conversation: conversation),
            ),
          ),
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.42),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: accent.withValues(alpha: 0.12),
                  child: Icon(
                    conversation.type == 'broadcast'
                        ? Icons.campaign_outlined
                        : Icons.groups_outlined,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.displayTitle(currentUser?.id ?? ''),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        conversation.type == 'broadcast'
                            ? 'إعلان عام'
                            : 'غرفة جماعية',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          conversation.type == 'broadcast'
                              ? 'قناة للإعلانات'
                              : '${conversation.members.length} عضو',
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (conversation.isPinned)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(end: 8),
                    child: Icon(Icons.push_pin_outlined, size: 18),
                  ),
                if (conversation.unreadCount > 0)
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: accent,
                    child: Text(
                      '${conversation.unreadCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RoomsEmptyState extends StatelessWidget {
  const _RoomsEmptyState({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 120),
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: const Color(
                  0xFF4A90E2,
                ).withValues(alpha: 0.12),
                child: const Icon(
                  Icons.forum_outlined,
                  size: 30,
                  color: Color(0xFF4A90E2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'لا توجد غرف أو إعلانات حتى الآن',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'بمجرد إنشاء غرفة جماعية أو قناة إعلانية ستظهر هنا لتصل إليها بسرعة.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
