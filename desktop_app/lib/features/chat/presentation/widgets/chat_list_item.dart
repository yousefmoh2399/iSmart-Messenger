import 'package:flutter/material.dart';

import '../../../../shared/widgets/safe_network_avatar.dart';
import '../../models/chat_models.dart';
import 'chat_ui_helpers.dart';

class ChatListItem extends StatefulWidget {
  const ChatListItem({
    super.key,
    required this.conversation,
    required this.currentUserId,
    this.typingPreviewText,
    required this.selected,
    required this.onTap,
    required this.onTogglePin,
    required this.onToggleMute,
    required this.onToggleArchive,
    required this.onToggleFavorite,
    required this.onDeleteConversation,
  });

  final ChatConversation conversation;
  final String currentUserId;
  final String? typingPreviewText;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleArchive;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDeleteConversation;

  @override
  State<ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends State<ChatListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final peer = widget.conversation.type == 'direct'
        ? widget.conversation.members
              .where((entry) => entry.id != widget.currentUserId)
              .cast<ChatDirectoryUser?>()
              .firstWhere((_) => true, orElse: () => null)
        : null;
    final accent = conversationTypeAccent(widget.conversation.type);
    final title = widget.conversation.displayTitle(widget.currentUserId);
    final preview = widget.typingPreviewText ?? _previewText(widget.conversation);
    final avatarLabel = (peer?.displayName ?? title).trim();
    final onSurfaceVariant = colorScheme.onSurfaceVariant;
    final selectionColor = colorScheme.primary.withValues(alpha: 0.14);
    final hoverColor = colorScheme.onSurface.withValues(alpha: 0.04);
    final inactiveColor = colorScheme.surfaceContainerHighest;
    final isTypingPreview = widget.typingPreviewText != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 320;
        final avatarRadius = isNarrow ? 20.0 : 24.0;
        final horizontalPadding = isNarrow ? 8.0 : 12.0;
        final gap = isNarrow ? 8.0 : 12.0;

        return Material(
          color: Colors.transparent,
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: widget.selected ? selectionColor : (_isHovered ? hoverColor : Colors.transparent),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                  Stack(
                    children: [
                      SafeNetworkAvatar(
                        radius: avatarRadius,
                        backgroundColor: accent.withValues(alpha: 0.16),
                        imageUrl: peer?.avatarUrl,
                        fallbackText: avatarLabel.isEmpty
                            ? '?'
                            : avatarLabel.substring(0, 1).toUpperCase(),
                        fallbackTextStyle: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (peer != null)
                        Positioned(
                          bottom: 2,
                          left: 2,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: presenceColor(peer.presenceStatus),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: colorScheme.surface,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      // color: selected
                                      //     ? const Colors.black
                                      //     : const Colors.white,
                                    ),
                              ),
                            ),
                            if (widget.conversation.isPinned)
                              Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.push_pin_rounded,
                                  size: 14,
                                  color: colorScheme.primary,
                                ),
                              ),
                            if (widget.conversation.isFavorite)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: Color(0xFFFFC107),
                                ),
                              ),
                            if (widget.conversation.isMuted)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.volume_off_rounded,
                                  size: 14,
                                  color: Color(0xFF748494),
                                ),
                              ),
                            if (!widget.conversation.isActive)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: inactiveColor,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'معطلة',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            if (!isNarrow) ...[
                              const SizedBox(width: 6),
                              Text(
                                formatConversationTime(widget.conversation),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: isTypingPreview
                                          ? colorScheme.primary
                                          : widget.conversation.isActive
                                          ? onSurfaceVariant
                                          : onSurfaceVariant.withValues(
                                              alpha: 0.68,
                                            ),
                                      fontWeight: isTypingPreview
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                              ),
                            ),
                            if (widget.conversation.unreadCount > 0)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${widget.conversation.unreadCount}',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                          ],
                        ),
                        if (peer != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            formatPresenceLabel(peer),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: presenceColor(peer.presenceStatus),
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: isNarrow ? 2 : 4),
                  PopupMenuButton<String>(
                    tooltip: 'خيارات المحادثة',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'pin':
                          widget.onTogglePin();
                          break;
                        case 'mute':
                          widget.onToggleMute();
                          break;
                        case 'archive':
                          widget.onToggleArchive();
                          break;
                        case 'favorite':
                          widget.onToggleFavorite();
                          break;
                        case 'delete':
                          widget.onDeleteConversation();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'pin',
                        child: Text(
                          widget.conversation.isPinned
                              ? 'إزالة التثبيت'
                              : 'تثبيت المحادثة',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'mute',
                        child: Text(
                          widget.conversation.isMuted ? 'إلغاء الكتم' : 'كتم المحادثة',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(
                          widget.conversation.isArchived
                              ? 'إلغاء الأرشفة'
                              : 'أرشفة المحادثة',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'favorite',
                        child: Text(
                          widget.conversation.isFavorite
                              ? 'إزالة من المفضلة'
                              : 'إضافة إلى المفضلة',
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('مسح/مغادرة/حذف'),
                      ),
                    ],
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      size: isNarrow ? 16 : 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        );
      },
    );
  }
}

String _previewText(ChatConversation conversation) {
  final lastMessage = conversation.lastMessage;
  if (lastMessage == null) {
    return 'ابدأ المحادثة الآن';
  }

  final body = lastMessage.content.isNotEmpty
      ? lastMessage.content
      : switch (lastMessage.messageType) {
          'image' => 'صورة',
          'pdf' => 'ملف PDF',
          'audio' => 'ملاحظة صوتية',
          'file' => 'ملف مرفق',
          _ => 'رسالة',
        };

  if (conversation.type == 'direct' || lastMessage.senderName.trim().isEmpty) {
    return body;
  }

  return '${lastMessage.senderName}: $body';
}
