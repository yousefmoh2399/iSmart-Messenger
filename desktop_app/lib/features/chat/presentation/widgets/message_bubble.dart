import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/safe_network_avatar.dart';
import '../../models/chat_models.dart';
import '../chat_appearance.dart';
import 'authenticated_attachment_image.dart';
import 'chat_animated_reaction_picker.dart';
import 'chat_audio_attachment_player.dart';
import 'chat_poll_bubble.dart';
import 'chat_text_parser.dart';
import '../../../../shared/models/app_user.dart';

const List<String> _kReactionEmojiFontFallbacks = <String>[
  'Apple Color Emoji',
  'Segoe UI Emoji',
];

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.showAvatar,
    required this.showSenderName,
    required this.senderName,
    required this.currentUserId,
    required this.onReply,
    required this.onCopy,
    required this.onOpenAttachment,
    required this.onToggleFavorite,
    this.onSaveAttachment,
    this.onPrintAttachment,
    required this.onReact,
    this.onTap,
    this.onLongPress,
    this.onVotePoll,
    this.onExportPoll,
    this.avatarUrl,
    this.replyPreview,
    this.replyPreviewSender,
    this.forwardedFrom,
    this.onEdit,
    this.onDelete,
    this.token,
    this.highlightQuery,
    this.selected = false,
    this.selectionMode = false,
    this.isActiveSearchMatch = false,
    this.chatPreferences = ChatPreferences.defaults,
  });

  final ChatMessage message;
  final bool isMine;
  final bool showAvatar;
  final bool showSenderName;
  final String senderName;
  final String currentUserId;
  final String? avatarUrl;
  final String? replyPreview;
  final String? replyPreviewSender;
  final String? forwardedFrom;
  final VoidCallback onReply;
  final VoidCallback onCopy;
  final VoidCallback onOpenAttachment;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onSaveAttachment;
  final VoidCallback? onPrintAttachment;
  final Future<void> Function(String emoji) onReact;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<List<String>>? onVotePoll;
  final VoidCallback? onExportPoll;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final String? token;
  final String? highlightQuery;
  final bool selected;
  final bool selectionMode;
  final bool isActiveSearchMatch;
  final ChatPreferences chatPreferences;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _hovered = false;

  Future<void> _openReactionPicker() async {
    await showChatReactionPickerDialog(
      context: context,
      onReact: widget.onReact,
    );
  }

  Future<void> _handleMenuAction(_BubbleMenuAction action) async {
    switch (action) {
      case _BubbleMenuAction.react:
        await _openReactionPicker();
        break;
      case _BubbleMenuAction.reply:
        widget.onReply();
        break;
      case _BubbleMenuAction.copy:
        await Clipboard.setData(ClipboardData(text: widget.message.content));
        widget.onCopy();
        break;
      case _BubbleMenuAction.favorite:
        widget.onToggleFavorite();
        break;
      case _BubbleMenuAction.saveAttachment:
        widget.onSaveAttachment?.call();
        break;
      case _BubbleMenuAction.edit:
        widget.onEdit?.call();
        break;
      case _BubbleMenuAction.delete:
        widget.onDelete?.call();
        break;
    }
  }

  Future<void> _showContextMenuAt(Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<_BubbleMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: _BubbleMenuAction.react,
          child: _PopupActionRow(
            icon: Icons.add_reaction_outlined,
            label: 'إضافة تفاعل',
            color: Color(0xFF3390EC),
          ),
        ),
        const PopupMenuItem(
          value: _BubbleMenuAction.reply,
          child: _PopupActionRow(
            icon: Icons.reply_rounded,
            label: 'رد',
            color: Color(0xFF3390EC),
          ),
        ),
        const PopupMenuItem(
          value: _BubbleMenuAction.favorite,
          child: _PopupActionRow(
            icon: Icons.star_outline_rounded,
            label: 'تبديل المفضلة',
            color: Color(0xFFF59E0B),
          ),
        ),
        const PopupMenuItem(
          value: _BubbleMenuAction.copy,
          child: _PopupActionRow(
            icon: Icons.content_copy_rounded,
            label: 'نسخ',
            color: Color(0xFF708499),
          ),
        ),
        if (widget.message.hasAttachment && widget.onSaveAttachment != null)
          const PopupMenuItem(
            value: _BubbleMenuAction.saveAttachment,
            child: _PopupActionRow(
              icon: Icons.save_alt_rounded,
              label: 'حفظ الملف',
              color: Color(0xFF2E7D32),
            ),
          ),
        if (widget.onEdit != null)
          const PopupMenuItem(
            value: _BubbleMenuAction.edit,
            child: _PopupActionRow(
              icon: Icons.edit_outlined,
              label: 'تعديل',
              color: Color(0xFFF59E0B),
            ),
          ),
        if (widget.onDelete != null)
          const PopupMenuItem(
            value: _BubbleMenuAction.delete,
            child: _PopupActionRow(
              icon: Icons.delete_outline_rounded,
              label: 'حذف',
              color: Color(0xFFE53935),
            ),
          ),
      ],
    );
    if (selected != null) {
      await _handleMenuAction(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final resolved = ChatAppearanceCatalog.resolveAppearance(
      preferences: widget.chatPreferences,
      isDark: isDark,
      colorScheme: theme.colorScheme,
    );
    final bubbleUsesDarkTone = resolved.isDarkVariant;

    final textColor = widget.isMine
        ? resolved.outgoingTextColor
        : resolved.incomingTextColor;

    final bubbleColor = widget.isMine
        ? resolved.outgoingBubbleColors.first
        : resolved.incomingBubbleColor;

    final borderColor = widget.isMine
        ? resolved.outgoingBorderColor
        : resolved.incomingBorderColor;

    final subColor = widget.isMine
        ? (bubbleUsesDarkTone
              ? const Color(0xFFC9DDF2)
              : const Color(0xFF5C748B))
        : (bubbleUsesDarkTone
              ? const Color(0xFF9BB0C3)
              : const Color(0xFF7A8A99));

    final selectedFill = const Color(0xFF3390EC).withValues(alpha: 0.14);
    final searchMatchFill = isDark
        ? const Color(0xFF5E4A17)
        : const Color(0xFFFDF3C7);

    final searchMatchBorder = isDark
        ? const Color(0xFFD6A62C)
        : const Color(0xFFF59E0B);

    final status = _messageStatus(widget.message, widget.currentUserId);
    final headers = widget.token == null || widget.token!.isEmpty
        ? null
        : {'Authorization': 'Bearer ${widget.token}'};

    final screenW = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = math.min(
      480.0,
      screenW * (widget.message.hasAttachment ? 0.55 : 0.42),
    );

    final topMargin = widget.showAvatar ? 10.0 : 3.0;

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: EdgeInsets.only(top: topMargin),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
              decoration: BoxDecoration(
                color: widget.selected
                    ? selectedFill
                    : (widget.isActiveSearchMatch
                          ? searchMatchFill
                          : bubbleColor),
                gradient:
                    !widget.selected &&
                        !widget.isActiveSearchMatch &&
                        widget.isMine &&
                        resolved.hasOutgoingGradient
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: resolved.outgoingBubbleColors,
                      )
                    : null,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(widget.isMine ? 18 : 6),
                  bottomRight: Radius.circular(widget.isMine ? 6 : 18),
                ),
                border: Border.all(
                  color: widget.selected
                      ? const Color(0xFF3390EC)
                      : (widget.isActiveSearchMatch
                            ? searchMatchBorder
                            : borderColor),
                  width: widget.selected || widget.isActiveSearchMatch
                      ? 1.2
                      : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.05),
                    blurRadius: isDark ? 10 : 8,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.showSenderName)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        widget.senderName,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: resolved.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (widget.forwardedFrom != null &&
                      widget.forwardedFrom!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.forward_rounded,
                            size: 15,
                            color: Color(0xFF3390EC),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'معاد توجيهها من ${widget.forwardedFrom!}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: resolved.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.message.sentToAllDepartments ||
                      widget.message.broadcastTargetDepartmentNames.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE67E22).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        widget.message.sentToAllDepartments
                            ? 'إرسال إلى كل الأقسام'
                            : 'إرسال إلى: ${widget.message.broadcastTargetDepartmentNames.join('، ')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB85714),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (widget.replyPreview != null &&
                      widget.replyPreview!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: widget.isMine
                            ? resolved.outgoingReplyColor
                            : resolved.incomingReplyColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border(
                          left: BorderSide(
                            color: widget.isMine
                                ? resolved.accent.withValues(alpha: 0.92)
                                : resolved.accent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.replyPreviewSender != null &&
                              widget.replyPreviewSender!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                widget.replyPreviewSender!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: resolved.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          Text(
                            widget.replyPreview!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: subColor,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                        sizeFactor: animation,
                        child: child,
                      ),
                    ),
                    child: widget.message.isDeleted
                        ? Text(
                            'تم حذف هذه الرسالة',
                            key: ValueKey('deleted_${widget.message.id}'),
                            style: TextStyle(
                              color: subColor,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        : Column(
                            key: ValueKey('message_${widget.message.id}'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.message.content.isNotEmpty)
                                () {
                                  final text = widget.message.content.trim();
                                  final emojiRegex = RegExp(r'^(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])$');
                                  final isSingle = text.runes.length == 1 && emojiRegex.hasMatch(text);
                                  
                                  return ChatRichText(
                                    text: widget.message.content,
                                    style: TextStyle(
                                      color: textColor,
                                      height: 1.4,
                                      fontSize: isSingle ? 48.0 : 14.2,
                                    ),
                                  );
                                }(),
                              if (widget.message.isPollMessage)
                                Padding(
                                  padding: EdgeInsets.only(top: widget.message.content.isEmpty ? 0 : 8.0),
                                  child: ChatPollBubble(
                                    message: widget.message,
                                    isMine: widget.isMine,
                                    onVote: widget.onVotePoll ?? (_) {},
                                    onExport: widget.onExportPoll ?? () {},
                                  ),
                                ),
                              if (widget.message.isGifMessage && widget.message.fileUrl != null)
                                Padding(
                                  padding: EdgeInsets.only(top: widget.message.content.isEmpty ? 0 : 8.0),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      widget.message.fileUrl!,
                                      fit: BoxFit.cover,
                                      width: 260,
                                      height: 190,
                                    ),
                                  ),
                                ),
                              if (widget.message.hasAttachment && !widget.message.isGifMessage)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: _AttachmentPreview(
                                    message: widget.message,
                                    textColor: textColor,
                                    onOpen: widget.onOpenAttachment,
                                    onPrint: widget.onPrintAttachment,
                                    token: widget.token,
                                    isMine: widget.isMine,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatEgyptTime(widget.message.createdAt),
                        style: TextStyle(
                          color: subColor,
                          fontSize: 11,
                          height: 1,
                        ),
                      ),
                      if (widget.message.isEdited) ...[
                        const SizedBox(width: 6),
                        Text(
                          'معدلة',
                          style: TextStyle(
                            color: subColor,
                            fontSize: 11,
                            height: 1,
                          ),
                        ),
                      ],
                      if (status != null) ...[
                        const SizedBox(width: 6),
                        Icon(status.icon, size: 15, color: status.color),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (_sortedReactionEntries(widget.message).isNotEmpty)
              Transform.translate(
                offset: const Offset(0, -10),
                child: Align(
                  alignment: widget.isMine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: _ReactionBar(
                    message: widget.message,
                    onReact: widget.onReact,
                    isMine: widget.isMine,
                    currentUserId: widget.currentUserId,
                    isDark: isDark,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onSecondaryTapDown: (details) =>
          _showContextMenuAt(details.globalPosition),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: widget.isMine
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: widget.isMine
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(child: bubble),
                  if (!widget.isMine && widget.showAvatar)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 2),
                      child: SafeNetworkAvatar(
                        radius: 14,
                        backgroundColor: isDark
                            ? const Color(0xFF223446)
                            : const Color(0xFFDCE6F2),
                        imageUrl: widget.avatarUrl,
                        httpHeaders: headers,
                        fallbackText: widget.senderName.isEmpty
                            ? '?'
                            : widget.senderName[0].toUpperCase(),
                        fallbackTextStyle: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? const Color(0xFFE7EEF6)
                              : const Color(0xFF24415C),
                        ),
                      ),
                    )
                  else if (!widget.isMine && !widget.showAvatar)
                    const SizedBox(width: 36),
                ],
              ),
            ),
            if (widget.selectionMode)
              Positioned(
                top: 2,
                left: widget.isMine ? 0 : null,
                right: widget.isMine ? null : 0,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 140),
                  scale: widget.selected ? 1 : 0.9,
                  child: Icon(
                    widget.selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: widget.selected
                        ? const Color(0xFF3390EC)
                        : const Color(0xFF9AA7B4),
                    size: 20,
                  ),
                ),
              ),
            if (!widget.selectionMode)
              Positioned(
                top: -2,
                right: widget.isMine ? null : 44,
                left: widget.isMine ? 44 : null,
                child: AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: const Duration(milliseconds: 140),
                  child: IgnorePointer(
                    ignoring: !_hovered,
                    child: _ActionStrip(
                      onOpenReactionPicker: _openReactionPicker,
                      onOpenMenu: () async {
                        final box = context.findRenderObject() as RenderBox?;
                        if (box == null) {
                          return;
                        }
                        final topRight = box.localToGlobal(
                          Offset(box.size.width, 0),
                        );
                        await _showContextMenuAt(topRight);
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionStrip extends StatelessWidget {
  const _ActionStrip({
    required this.onOpenReactionPicker,
    required this.onOpenMenu,
  });

  final Future<void> Function() onOpenReactionPicker;
  final Future<void> Function() onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF223446) : Colors.white,
      elevation: isDark ? 1 : 3,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0xFF2B4155) : const Color(0xFFE1EAF3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'إضافة تفاعل',
                onPressed: onOpenReactionPicker,
                icon: Icon(
                  Icons.add_reaction_outlined,
                  size: 17,
                  color: isDark
                      ? const Color(0xFFE7EEF6)
                      : const Color(0xFF506579),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'المزيد',
                onPressed: onOpenMenu,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 18,
                  color: isDark
                      ? const Color(0xFFE7EEF6)
                      : const Color(0xFF506579),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.message,
    required this.textColor,
    required this.onOpen,
    required this.token,
    required this.isMine,
    this.onPrint,
  });

  final ChatMessage message;
  final Color textColor;
  final VoidCallback onOpen;
  final String? token;
  final bool isMine;
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (message.fileUrl == null || message.fileUrl!.isEmpty) {
      return const SizedBox.shrink();
    }

    if (message.isImageMessage) {
      return InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Hero(
            tag: 'image_${message.id}',
            child: AuthenticatedAttachmentImage(
              message: message,
              fit: BoxFit.cover,
              height: 190,
              width: 260,
              errorFallback: Container(
                height: 120,
                alignment: Alignment.center,
                color: const Color(0xFFF0F4F9),
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      );
    }

    if (message.isAudioMessage) {
      return ChatAudioAttachmentPlayer(message: message, token: token);
    }

    final isPdf = message.isPdfMessage;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMine
              ? (isDark ? const Color(0xFF244668) : const Color(0xFFE5F0FA))
              : (isDark ? const Color(0xFF223446) : const Color(0xFFF7FAFD)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF30485C) : const Color(0xFFDCE6F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPdf ? Icons.picture_as_pdf_outlined : Icons.attach_file_rounded,
              color: textColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message.fileName ?? (isPdf ? 'مرفق PDF' : 'مرفق'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textColor),
              ),
            ),
            if (message.isPrintableAttachment && onPrint != null)
              IconButton(
                tooltip: 'طباعة',
                onPressed: onPrint,
                icon: const Icon(Icons.print_rounded),
              ),
            TextButton(
              onPressed: message.attachmentDownloadAllowed ? onOpen : null,
              child: Text(
                message.attachmentDownloadAllowed ? 'تحميل' : 'عرض فقط',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.message,
    required this.onReact,
    required this.currentUserId,
    required this.isMine,
    required this.isDark,
  });

  final ChatMessage message;
  final Future<void> Function(String emoji) onReact;
  final String currentUserId;
  final bool isMine;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final reactions = _sortedReactionEntries(message);
    if (reactions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Wrap(
        spacing: 3,
        runSpacing: 4,
        alignment: isMine ? WrapAlignment.end : WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < reactions.length; i++)
            _AnimatedReactionChip(
              emoji: reactions[i].key,
              count: reactions[i].value.length,
              selected: reactions[i].value.contains(currentUserId),
              isMine: isMine,
              isDark: isDark,
              staggerIndex: i,
              onTap: () => onReact(reactions[i].key),
            ),
        ],
      ),
    );
  }
}

enum _BubbleMenuAction {
  react,
  reply,
  favorite,
  copy,
  saveAttachment,
  edit,
  delete,
}

class _PopupActionRow extends StatelessWidget {
  const _PopupActionRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}


class _AnimatedReactionChip extends StatefulWidget {
  const _AnimatedReactionChip({
    required this.emoji,
    required this.count,
    required this.selected,
    required this.isMine,
    required this.isDark,
    required this.staggerIndex,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool selected;
  final bool isMine;
  final bool isDark;
  final int staggerIndex;
  final VoidCallback onTap;

  @override
  State<_AnimatedReactionChip> createState() => _AnimatedReactionChipState();
}

class _AnimatedReactionChipState extends State<_AnimatedReactionChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tapController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 120),
  );
  late final Animation<double> _tapScale = Tween<double>(
    begin: 1.0,
    end: 0.94,
  ).animate(CurvedAnimation(parent: _tapController, curve: Curves.easeOut));

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  void _handleTap() {
    unawaited(
      _tapController.forward(from: 0).then((_) => _tapController.reverse()),
    );
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.selected
        ? (widget.isDark
              ? const Color(0xFF2B5278).withValues(alpha: 0.88)
              : const Color(0xFFD8EAFD))
        : (widget.isDark
              ? const Color(0xFF2A3441).withValues(alpha: 0.92)
              : const Color(0xFFF8FAFC));
    final borderColor = widget.selected
        ? const Color(0xFF3390EC)
        : (widget.isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0));

    final emojiStyle = TextStyle(
      fontSize: 17,
      height: 1.05,
      fontFamilyFallback: _kReactionEmojiFontFallbacks,
    );

    return ScaleTransition(
      scale: _tapScale,
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: borderColor,
              width: widget.selected ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: widget.isDark ? 0.22 : 0.05,
                ),
                blurRadius: widget.selected ? 8 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.emoji, style: emojiStyle),
              const SizedBox(width: 3),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Text(
                  '${widget.count}',
                  key: ValueKey(widget.count),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: widget.selected
                        ? const Color(0xFF3390EC)
                        : (widget.isDark
                              ? const Color(0xFFB8C7D6)
                              : const Color(0xFF64748B)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageStatus {
  const _MessageStatus(this.icon, this.color);
  final IconData icon;
  final Color color;
}

_MessageStatus? _messageStatus(ChatMessage message, String currentUserId) {
  if (message.sender?.id != currentUserId) {
    return null;
  }
  if (message.seenBy.any((entry) => entry.userId != currentUserId)) {
    return const _MessageStatus(Icons.done_all_rounded, Color(0xFF4FC3F7));
  }
  if (message.deliveredTo.any((entry) => entry.userId != currentUserId)) {
    return const _MessageStatus(Icons.done_all_rounded, Color(0xFF94A3B8));
  }
  return const _MessageStatus(Icons.done_rounded, Color(0xFF94A3B8));
}

List<MapEntry<String, List<String>>> _reactionEntries(ChatMessage message) {
  final metadata = message.metadata;
  if (metadata == null) {
    return const [];
  }
  final rawReactions = metadata['reactions'];
  if (rawReactions is! Map) {
    return const [];
  }
  return rawReactions.entries
      .where((entry) => entry.key != null && entry.value is List)
      .map(
        (entry) => MapEntry(
          entry.key.toString(),
          (entry.value as List<dynamic>)
              .map((userId) => userId.toString())
              .toList(),
        ),
      )
      .where((entry) => entry.value.isNotEmpty)
      .toList();
}

List<MapEntry<String, List<String>>> _sortedReactionEntries(
  ChatMessage message,
) {
  final entries = List<MapEntry<String, List<String>>>.from(
    _reactionEntries(message),
  );
  entries.sort((a, b) {
    final byCount = b.value.length.compareTo(a.value.length);
    if (byCount != 0) {
      return byCount;
    }
    return a.key.compareTo(b.key);
  });
  return entries;
}
