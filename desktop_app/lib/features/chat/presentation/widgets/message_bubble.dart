import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/safe_network_avatar.dart';
import '../../models/chat_models.dart';
import '../chat_appearance.dart';
import 'authenticated_attachment_image.dart';
import 'bundled_quick_emoji.dart';
import 'chat_animated_reaction_picker.dart';
import 'chat_audio_attachment_player.dart';
import 'chat_poll_bubble.dart';
import 'chat_text_parser.dart';

const List<String> _kReactionEmojiFontFallbacks = <String>[
  'Segoe UI Emoji',
  'Apple Color Emoji',
  'Noto Color Emoji',
  'Segoe UI Symbol',
];

final RegExp _singleEmojiRegex = RegExp(
  r'^(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])$',
);

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
    this.onSaveSticker,
    this.onPrintAttachment,
    required this.onReact,
    this.onShowDetails,
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
    this.onPin,
    this.token,
    this.highlightQuery,
    this.selected = false,
    this.selectionMode = false,
    this.isActiveSearchMatch = false,
    this.chatPreferences = ChatPreferences.defaults,
    this.albumMessages = const [],
    this.onOpenAlbum,
    this.onRetry,
    this.onForward,
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
  final VoidCallback? onSaveSticker;
  final VoidCallback? onPrintAttachment;
  final Future<void> Function(String emoji) onReact;
  final VoidCallback? onShowDetails;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Future<void> Function(List<String>)? onVotePoll;
  final VoidCallback? onExportPoll;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onPin;
  final String? token;
  final String? highlightQuery;
  final bool selected;
  final bool selectionMode;
  final bool isActiveSearchMatch;
  final ChatPreferences chatPreferences;
  final List<ChatMessage> albumMessages;
  final ValueChanged<ChatMessage>? onOpenAlbum;
  final VoidCallback? onRetry;
  final VoidCallback? onForward;

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
      case _BubbleMenuAction.forward:
        widget.onForward?.call();
        break;
      case _BubbleMenuAction.copy:
        await Clipboard.setData(ClipboardData(text: widget.message.content));
        widget.onCopy();
        break;
      case _BubbleMenuAction.favorite:
        widget.onToggleFavorite();
        break;
      case _BubbleMenuAction.openAttachment:
        widget.onOpenAttachment();
        break;
      case _BubbleMenuAction.saveAttachment:
        widget.onSaveAttachment?.call();
        break;
      case _BubbleMenuAction.saveSticker:
        widget.onSaveSticker?.call();
        break;
      case _BubbleMenuAction.edit:
        widget.onEdit?.call();
        break;
      case _BubbleMenuAction.delete:
        widget.onDelete?.call();
        break;
      case _BubbleMenuAction.pin:
        widget.onPin?.call();
        break;
      case _BubbleMenuAction.retry:
        widget.onRetry?.call();
        break;
      case _BubbleMenuAction.details:
        widget.onShowDetails?.call();
        break;
    }
  }

  Future<void> _showContextMenuAt(Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final isFailed = widget.message.metadata?['status'] == 'failed';
    final selected = await showMenu<_BubbleMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: isFailed
          ? [
              if (widget.onRetry != null)
                const PopupMenuItem(
                  value: _BubbleMenuAction.retry,
                  child: _PopupActionRow(
                    icon: Icons.refresh_rounded,
                    label: 'إعادة المحاولة',
                    color: Color(0xFFE53935),
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
            ]
          : [
              if (widget.onRetry != null)
                const PopupMenuItem(
                  value: _BubbleMenuAction.retry,
                  child: _PopupActionRow(
                    icon: Icons.refresh_rounded,
                    label: 'إعادة المحاولة',
                    color: Color(0xFFE53935),
                  ),
                ),
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
              if (widget.onForward != null)
                const PopupMenuItem(
                  value: _BubbleMenuAction.forward,
                  child: _PopupActionRow(
                    icon: Icons.shortcut_rounded,
                    label: 'إعادة توجيه',
                    color: Color(0xFF007AFF),
                  ),
                ),
              if (widget.onShowDetails != null)
                const PopupMenuItem(
                  value: _BubbleMenuAction.details,
                  child: _PopupActionRow(
                    icon: Icons.info_outline_rounded,
                    label: 'معلومات الرسالة',
                    color: Color(0xFF007AFF),
                  ),
                ),
              PopupMenuItem(
                value: _BubbleMenuAction.favorite,
                child: _PopupActionRow(
                  icon: widget.message.isFavoritedBy(widget.currentUserId)
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  label: widget.message.isFavoritedBy(widget.currentUserId)
                      ? 'إزالة من المفضلة'
                      : 'إضافة إلى المفضلة',
                  color: const Color(0xFFF59E0B),
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
              if (widget.message.hasAttachment && widget.message.attachmentDownloadAllowed)
                const PopupMenuItem(
                  value: _BubbleMenuAction.openAttachment,
                  child: _PopupActionRow(
                    icon: Icons.open_in_new_rounded,
                    label: 'فتح الملف',
                    color: Color(0xFF007AFF),
                  ),
                ),
              if (widget.message.hasAttachment && widget.onSaveAttachment != null)
                const PopupMenuItem(
                  value: _BubbleMenuAction.saveAttachment,
                  child: _PopupActionRow(
                    icon: Icons.drive_file_move_outlined,
                    label: 'نقل / حفظ الملف في مجلد...',
                    color: Color(0xFF2E7D32),
                  ),
                ),
              if (widget.onSaveSticker != null)
                const PopupMenuItem(
                  value: _BubbleMenuAction.saveSticker,
                  child: _PopupActionRow(
                    icon: Icons.auto_awesome_motion_rounded,
                    label: 'حفظ ضمن الملصقات',
                    color: Color(0xFF007AFF),
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
              if (widget.onPin != null)
                const PopupMenuItem(
                  value: _BubbleMenuAction.pin,
                  child: _PopupActionRow(
                    icon: Icons.push_pin_outlined,
                    label: 'تثبيت',
                    color: Color(0xFF9A6400),
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

    final forwardColor = widget.isMine
        ? (bubbleUsesDarkTone
            ? const Color(0xFFE0F2FE)
            : const Color(0xFF0369A1))
        : (isDark
            ? const Color(0xFF38BDF8)
            : const Color(0xFF0284C7));

    final replyBgColor = widget.isMine
        ? (bubbleUsesDarkTone
            ? Colors.black.withValues(alpha: 0.20)
            : Colors.black.withValues(alpha: 0.08))
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFF1F5F9));

    final replyBorderColor = widget.isMine
        ? (bubbleUsesDarkTone
            ? const Color(0xFF38BDF8)
            : const Color(0xFF0284C7))
        : resolved.accent;

    final replySenderColor = widget.isMine
        ? (bubbleUsesDarkTone
            ? Colors.white
            : const Color(0xFF0F172A))
        : resolved.accent;

    final replyTextColor = widget.isMine
        ? (bubbleUsesDarkTone
            ? const Color(0xFFE2E8F0)
            : const Color(0xFF334155))
        : (isDark
            ? const Color(0xFFCBD5E1)
            : const Color(0xFF475569));

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
                          Icon(
                            Icons.forward_rounded,
                            size: 15,
                            color: forwardColor,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'معاد توجيهها من ${widget.forwardedFrom!}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: forwardColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.message.sentToAllDepartments ||
                      widget.message.broadcastTargetDepartmentNames.isNotEmpty ||
                      widget.message.broadcastTargetUserNames.isNotEmpty)
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
                            ? 'إرسال إلى: كل الأقسام والموظفين'
                            : (widget.message.broadcastTargetDepartmentNames.isNotEmpty &&
                                    widget.message.broadcastTargetUserNames.isNotEmpty)
                                ? 'إرسال إلى أقسام: ${widget.message.broadcastTargetDepartmentNames.join('، ')} • وموظفون: ${widget.message.broadcastTargetUserNames.join('، ')}'
                                : widget.message.broadcastTargetDepartmentNames.isNotEmpty
                                    ? 'إرسال إلى: ${widget.message.broadcastTargetDepartmentNames.join('، ')}'
                                    : 'إرسال إلى: ${widget.message.broadcastTargetUserNames.join('، ')}',
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
                        color: replyBgColor,
                        borderRadius: BorderRadius.circular(10),
                        border: BorderDirectional(
                          start: BorderSide(
                            color: replyBorderColor,
                            width: 3.5,
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
                                  color: replySenderColor,
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
                              color: replyTextColor,
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
                            key: ValueKey(
                              'deleted_${widget.message.metadata?['clientMessageId']?.toString() ?? widget.message.id}',
                            ),
                            style: TextStyle(
                              color: subColor,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        : Column(
                            key: ValueKey(
                              'message_${widget.message.metadata?['clientMessageId']?.toString() ?? widget.message.id}',
                            ),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.message.content.isNotEmpty)
                                () {
                                  final text = widget.message.content.trim();
                                  final isSingle =
                                      text.runes.length == 1 &&
                                      _singleEmojiRegex.hasMatch(text);

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
                                  padding: EdgeInsets.only(
                                    top: widget.message.content.isEmpty
                                        ? 0
                                        : 8.0,
                                  ),
                                  child: ChatPollBubble(
                                    poll:
                                        widget.message.metadata?['poll']
                                            is Map<String, dynamic>
                                        ? widget.message.metadata!['poll']
                                              as Map<String, dynamic>
                                        : widget.message.metadata ?? {},
                                    currentUserId: widget.currentUserId,
                                    isMine: widget.isMine,
                                    onVote: widget.onVotePoll ?? (_) async {},
                                    onExport: widget.onExportPoll ?? () {},
                                  ),
                                ),
                              if (widget.message.isGifMessage &&
                                  widget.message.fileUrl != null)
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: widget.message.content.isEmpty
                                        ? 0
                                        : 8.0,
                                  ),
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
                              if (widget.albumMessages.length > 1)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: _DesktopMediaAlbum(
                                    messages: widget.albumMessages,
                                    onOpen: widget.onOpenAlbum ?? (_) {},
                                  ),
                                )
                              else if (widget.message.hasAttachment &&
                                  !widget.message.isGifMessage)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: _AttachmentPreview(
                                    message: widget.message,
                                    textColor: textColor,
                                    onOpen: widget.onOpenAttachment,
                                    onSaveAttachment: widget.onSaveAttachment,
                                    onPrint: widget.onPrintAttachment,
                                    onSaveSticker: widget.onSaveSticker,
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
                      if (widget.message.isAttachmentViewOnly ||
                          !widget.message.attachmentForwardAllowed ||
                          widget.message.metadata?['allowForward'] == false) ...[
                        const Tooltip(
                          message: 'محتوى محمي: غير مسموح بإعادة التوجيه',
                          child: Icon(
                            Icons.lock_rounded,
                            size: 11.5,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
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
                      if (widget.message.isFavoritedBy(widget.currentUserId)) ...[
                        const SizedBox(width: 4),
                        const Tooltip(
                          message: 'رسالة مفضلة',
                          child: Icon(
                            Icons.star_rounded,
                            size: 13.5,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                      if (status != null) ...[
                        const SizedBox(width: 6),
                        if (widget.message.metadata?['status'] == 'failed')
                          Tooltip(
                            message: 'خيارات الرسالة (إعادة المحاولة / حذف)',
                            child: InkWell(
                              onTapDown: (details) =>
                                  _showContextMenuAt(details.globalPosition),
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  status.icon,
                                  size: 15,
                                  color: status.color,
                                ),
                              ),
                            ),
                          )
                        else
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
    this.onSaveAttachment,
    this.onPrint,
    this.onSaveSticker,
  });

  final ChatMessage message;
  final Color textColor;
  final VoidCallback onOpen;
  final String? token;
  final bool isMine;
  final VoidCallback? onSaveAttachment;
  final VoidCallback? onPrint;
  final VoidCallback? onSaveSticker;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (message.fileUrl == null || message.fileUrl!.isEmpty) {
      return const SizedBox.shrink();
    }

    if (message.isStickerMessage) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: onSaveSticker ?? onOpen,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                maxWidth: 180,
                maxHeight: 180,
              ),
              child: Hero(
                tag: 'image_${message.id}',
                child: AuthenticatedAttachmentImage(
                  message: message,
                  fit: BoxFit.contain,
                  errorFallback: Container(
                    height: 120,
                    width: 120,
                    alignment: Alignment.center,
                    color: Colors.transparent,
                    child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
          if (onSaveSticker != null)
            Positioned(
              bottom: 2,
              left: 2,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onSaveSticker,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: (isDark ? const Color(0xFF1C1C1E) : Colors.white).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? const Color(0xFF38383E) : const Color(0xFFE2E8F0),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_awesome_motion_rounded,
                          size: 12,
                          color: Color(0xFF007AFF),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'حفظ كملصق',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
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
    final fileName = message.fileName ?? (isPdf ? 'مستند PDF' : 'ملف مرفق');
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    final fileStyle = _resolveFileStyle(ext, message.mimeType, isPdf);

    final cardBgColor = isMine
        ? (isDark ? const Color(0xFF1E354D) : const Color(0xFFF0F7FF))
        : (isDark ? const Color(0xFF1F2937) : const Color(0xFFF8FAFC));
    final borderColor = isMine
        ? (isDark ? const Color(0xFF2C4A6B) : const Color(0xFFD0E3F7))
        : (isDark ? const Color(0xFF374151) : const Color(0xFFE2E8F0));

    return Container(
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 330),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // File Info (tap anywhere to open)
          InkWell(
            onTap: message.attachmentDownloadAllowed ? onOpen : null,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                children: [
                  // File Icon Badge
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDark ? fileStyle.darkBg : fileStyle.lightBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: fileStyle.primaryColor.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      fileStyle.icon,
                      color: fileStyle.primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: fileStyle.primaryColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                fileStyle.typeLabel,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: fileStyle.primaryColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            if (message.fileSize != null && message.fileSize! > 0) ...[
                              const SizedBox(width: 6),
                              Text(
                                formatFileSize(message.fileSize!),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: textColor.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (message.isPrintableAttachment && onPrint != null) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'طباعة المرفق',
                      child: IconButton(
                        iconSize: 18,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        style: IconButton.styleFrom(
                          backgroundColor: isDark
                              ? const Color(0xFF2A3644)
                              : const Color(0xFFE8EEF5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: onPrint,
                        icon: Icon(Icons.print_rounded, color: textColor),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.8,
            color: borderColor.withValues(alpha: 0.7),
          ),
          if (!message.attachmentDownloadAllowed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'محتوى محمي: العرض فقط داخل التطبيق',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  // Button 1: Open
                  Expanded(
                    child: _AttachmentActionButton(
                      icon: Icons.open_in_new_rounded,
                      label: 'فتح',
                      tooltip: 'فتح الملف مباشرة في التطبيق الخاص به (مثل Excel)',
                      isPrimary: true,
                      primaryColor: fileStyle.primaryColor,
                      isDark: isDark,
                      textColor: textColor,
                      onTap: onOpen,
                    ),
                  ),
                  if (onSaveAttachment != null) ...[
                    const SizedBox(width: 8),
                    // Button 2: Move / Save to
                    Expanded(
                      child: _AttachmentActionButton(
                        icon: Icons.drive_file_move_outlined,
                        label: 'نقل',
                        tooltip: 'تحديد مجلد على جهازك لنقل أو حفظ الملف فيه',
                        isPrimary: false,
                        primaryColor: fileStyle.primaryColor,
                        isDark: isDark,
                        textColor: textColor,
                        onTap: onSaveAttachment,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AttachmentActionButton extends StatelessWidget {
  const _AttachmentActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.isPrimary,
    required this.primaryColor,
    required this.isDark,
    required this.textColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool isPrimary;
  final Color primaryColor;
  final bool isDark;
  final Color textColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isPrimary
        ? primaryColor.withValues(alpha: isDark ? 0.22 : 0.12)
        : (isDark ? const Color(0xFF263342) : const Color(0xFFEFF3F8));
    final fg = isPrimary ? primaryColor : textColor;
    final border = isPrimary
        ? primaryColor.withValues(alpha: 0.35)
        : (isDark ? const Color(0xFF384758) : const Color(0xFFD6E0EC));

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border, width: 0.8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14.5, color: fg),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileAttachmentStyle {
  final IconData icon;
  final Color primaryColor;
  final Color lightBg;
  final Color darkBg;
  final String typeLabel;

  const _FileAttachmentStyle({
    required this.icon,
    required this.primaryColor,
    required this.lightBg,
    required this.darkBg,
    required this.typeLabel,
  });
}

_FileAttachmentStyle _resolveFileStyle(String ext, String? mimeType, bool isPdf) {
  final normalizedExt = ext.toLowerCase();
  final normalizedMime = (mimeType ?? '').toLowerCase();

  // Excel / Spreadsheet
  if (normalizedExt == 'xlsx' ||
      normalizedExt == 'xls' ||
      normalizedExt == 'csv' ||
      normalizedExt == 'xlsm' ||
      normalizedExt == 'xlsb' ||
      normalizedMime.contains('spreadsheet') ||
      normalizedMime.contains('excel') ||
      normalizedMime.contains('csv')) {
    return const _FileAttachmentStyle(
      icon: Icons.table_chart_rounded,
      primaryColor: Color(0xFF107C41),
      lightBg: Color(0xFFE8F5E9),
      darkBg: Color(0xFF1B382B),
      typeLabel: 'EXCEL',
    );
  }

  // Word / Document
  if (normalizedExt == 'docx' ||
      normalizedExt == 'doc' ||
      normalizedExt == 'dotx' ||
      normalizedExt == 'rtf' ||
      normalizedMime.contains('word') ||
      normalizedMime.contains('wordprocessingml')) {
    return const _FileAttachmentStyle(
      icon: Icons.article_rounded,
      primaryColor: Color(0xFF185ABD),
      lightBg: Color(0xFFE8F0FE),
      darkBg: Color(0xFF192F4A),
      typeLabel: 'WORD',
    );
  }

  // PowerPoint / Presentation
  if (normalizedExt == 'pptx' ||
      normalizedExt == 'ppt' ||
      normalizedExt == 'ppsx' ||
      normalizedExt == 'potx' ||
      normalizedMime.contains('presentation') ||
      normalizedMime.contains('powerpoint')) {
    return const _FileAttachmentStyle(
      icon: Icons.co_present_rounded,
      primaryColor: Color(0xFFC43E1C),
      lightBg: Color(0xFFFCEEE9),
      darkBg: Color(0xFF3B1E17),
      typeLabel: 'PPT',
    );
  }

  // PDF Document
  if (isPdf ||
      normalizedExt == 'pdf' ||
      normalizedMime == 'application/pdf') {
    return const _FileAttachmentStyle(
      icon: Icons.picture_as_pdf_rounded,
      primaryColor: Color(0xFFDC2626),
      lightBg: Color(0xFFFEE2E2),
      darkBg: Color(0xFF381A1A),
      typeLabel: 'PDF',
    );
  }

  // Archives / Compressed
  if (normalizedExt == 'zip' ||
      normalizedExt == 'rar' ||
      normalizedExt == '7z' ||
      normalizedExt == 'tar' ||
      normalizedExt == 'gz' ||
      normalizedExt == 'bz2' ||
      normalizedExt == 'iso' ||
      normalizedMime.contains('zip') ||
      normalizedMime.contains('compressed') ||
      normalizedMime.contains('archive')) {
    return const _FileAttachmentStyle(
      icon: Icons.folder_zip_rounded,
      primaryColor: Color(0xFFD97706),
      lightBg: Color(0xFFFEF3C7),
      darkBg: Color(0xFF36270E),
      typeLabel: 'ZIP',
    );
  }

  // Audio files
  if (normalizedExt == 'mp3' ||
      normalizedExt == 'wav' ||
      normalizedExt == 'm4a' ||
      normalizedExt == 'aac' ||
      normalizedExt == 'ogg' ||
      normalizedExt == 'flac' ||
      normalizedMime.startsWith('audio/')) {
    return const _FileAttachmentStyle(
      icon: Icons.audio_file_rounded,
      primaryColor: Color(0xFF7C3AED),
      lightBg: Color(0xFFEDE9FE),
      darkBg: Color(0xFF2A1B3D),
      typeLabel: 'AUDIO',
    );
  }

  // Video files
  if (normalizedExt == 'mp4' ||
      normalizedExt == 'mov' ||
      normalizedExt == 'avi' ||
      normalizedExt == 'mkv' ||
      normalizedExt == 'webm' ||
      normalizedMime.startsWith('video/')) {
    return const _FileAttachmentStyle(
      icon: Icons.video_file_rounded,
      primaryColor: Color(0xFF0284C7),
      lightBg: Color(0xFFE0F2FE),
      darkBg: Color(0xFF122E40),
      typeLabel: 'VIDEO',
    );
  }

  // Code / Text files
  if (normalizedExt == 'txt' ||
      normalizedExt == 'json' ||
      normalizedExt == 'xml' ||
      normalizedExt == 'html' ||
      normalizedExt == 'css' ||
      normalizedExt == 'js' ||
      normalizedExt == 'dart' ||
      normalizedExt == 'py' ||
      normalizedExt == 'sql' ||
      normalizedExt == 'md' ||
      normalizedExt == 'log') {
    return _FileAttachmentStyle(
      icon: Icons.description_rounded,
      primaryColor: const Color(0xFF475569),
      lightBg: const Color(0xFFF1F5F9),
      darkBg: const Color(0xFF1E293B),
      typeLabel: normalizedExt.toUpperCase(),
    );
  }

  // Default fallback
  return _FileAttachmentStyle(
    icon: Icons.insert_drive_file_rounded,
    primaryColor: const Color(0xFF007AFF),
    lightBg: const Color(0xFFEBF5FF),
    darkBg: const Color(0xFF1A2A3D),
    typeLabel: normalizedExt.isNotEmpty ? normalizedExt.toUpperCase() : 'FILE',
  );
}

class _DesktopMediaAlbum extends StatelessWidget {
  const _DesktopMediaAlbum({required this.messages, required this.onOpen});
  final List<ChatMessage> messages;
  final ValueChanged<ChatMessage> onOpen;

  Widget _buildImage(ChatMessage message, [int? overflowCount]) {
    return InkWell(
      onTap: () => onOpen(message),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AuthenticatedAttachmentImage(
            message: message,
            fit: BoxFit.cover,
          ),
          if (overflowCount != null)
            ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Text(
                  '+$overflowCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = messages.length;
    if (count == 0) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 300,
        height: 240,
        child: _buildLayout(),
      ),
    );
  }

  Widget _buildLayout() {
    final count = messages.length;
    
    if (count == 1) {
      return _buildImage(messages[0]);
    }
    
    if (count == 2) {
      return Row(
        children: [
          Expanded(child: _buildImage(messages[0])),
          const SizedBox(width: 2),
          Expanded(child: _buildImage(messages[1])),
        ],
      );
    } 
    
    if (count == 3) {
      return Column(
        children: [
          Expanded(
            flex: 2,
            child: _buildImage(messages[0]),
          ),
          const SizedBox(height: 2),
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Expanded(child: _buildImage(messages[1])),
                const SizedBox(width: 2),
                Expanded(child: _buildImage(messages[2])),
              ],
            ),
          ),
        ],
      );
    }
    
    final overflow = count > 4 ? count - 4 : null;
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildImage(messages[0])),
              const SizedBox(width: 2),
              Expanded(child: _buildImage(messages[1])),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildImage(messages[2])),
              const SizedBox(width: 2),
              Expanded(child: _buildImage(messages[3], overflow)),
            ],
          ),
        ),
      ],
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
  forward,
  favorite,
  copy,
  openAttachment,
  saveAttachment,
  saveSticker,
  edit,
  delete,
  pin,
  retry,
  details,
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
      fontFamily: 'Segoe UI Emoji',
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
              BundledQuickEmoji(
                emoji: widget.emoji,
                size: 18,
                animate: false,
                textFallbackStyle: emojiStyle,
              ),
              const SizedBox(width: 4),
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
  final senderId = (message.sender?.id ?? message.senderId).trim();
  final myId = currentUserId.trim();
  if (senderId.isEmpty || (myId.isNotEmpty && senderId != myId)) {
    return null;
  }
  final msgStatus = message.metadata?['status']?.toString();
  if (msgStatus == 'failed') {
    return const _MessageStatus(Icons.error_outline_rounded, Color(0xFFEF4444));
  }
  if (msgStatus == 'pending' || message.id.startsWith('temp_')) {
    return const _MessageStatus(Icons.access_time_rounded, Color(0xFF8696A0));
  }
  if (message.seenBy.any((entry) => entry.userId.trim().isNotEmpty && entry.userId.trim() != myId)) {
    return const _MessageStatus(Icons.done_all_rounded, Color(0xFF53BDEB));
  }
  if (message.deliveredTo.any((entry) => entry.userId.trim().isNotEmpty && entry.userId.trim() != myId)) {
    return const _MessageStatus(Icons.done_all_rounded, Color(0xFF8696A0));
  }
  return const _MessageStatus(Icons.done_rounded, Color(0xFF8696A0));
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
