import 'package:flutter/material.dart';

import 'chat_text_field_paste_menu.dart';
import 'emoji_picker_panel.dart';

class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSend,
    required this.onSendOptions,
    required this.onAttachFile,
    required this.onPickImage,
    required this.onSendScreenshot,
    required this.onOpenReactionPicker,
    this.onSendPoll,
    this.onSendChecklist,
    this.onSendGif,
    this.isEditing = false,
    this.isUploading = false,
    this.uploadProgress = 0,
    this.uploadLabel,
    this.enabled = true,
    this.enterSendsMessage = true,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onSendOptions;
  final VoidCallback onAttachFile;
  final VoidCallback onPickImage;
  final VoidCallback onSendScreenshot;
  final VoidCallback onOpenReactionPicker;
  final VoidCallback? onSendPoll;
  final VoidCallback? onSendChecklist;
  final VoidCallback? onSendGif;
  final bool isEditing;
  final bool isUploading;
  final double uploadProgress;
  final String? uploadLabel;
  final bool enabled;
  final bool enterSendsMessage;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  bool _actionsExpanded = false;

  void _toggleActions() {
    if (!widget.enabled) {
      return;
    }
    setState(() {
      _actionsExpanded = !_actionsExpanded;
    });
  }

  void _runAction(VoidCallback callback) {
    callback();
    if (_actionsExpanded) {
      setState(() {
        _actionsExpanded = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.38),
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isUploading)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              strokeWidth: 2.8,
                              value: widget.uploadProgress <= 0
                                  ? null
                                  : widget.uploadProgress,
                              color: const Color(0xFF3390EC),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                            ),
                          ),
                          Icon(
                            Icons.upload_rounded,
                            size: 18,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.uploadLabel ?? 'مرفق',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              minHeight: 3,
                              value: widget.uploadProgress <= 0
                                  ? null
                                  : widget.uploadProgress,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              color: const Color(0xFF3390EC),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(widget.uploadProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              ),
            Row(
              children: [
                PopupMenuButton<VoidCallback>(
                  tooltip: 'إجراءات الشات',
                  enabled: widget.enabled && !widget.isUploading,
                  onSelected: (action) => action(),
                  icon: const Icon(Icons.attach_file_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                  offset: const Offset(0, -250),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: widget.onPickImage,
                      child: const Row(
                        children: [Icon(Icons.image_rounded), SizedBox(width: 12), Text('صور')],
                      ),
                    ),
                    PopupMenuItem(
                      value: widget.onAttachFile,
                      child: const Row(
                        children: [Icon(Icons.insert_drive_file_rounded), SizedBox(width: 12), Text('ملفات')],
                      ),
                    ),
                    PopupMenuItem(
                      value: widget.onSendScreenshot,
                      child: const Row(
                        children: [Icon(Icons.screenshot_monitor_rounded), SizedBox(width: 12), Text('لقطة شاشة')],
                      ),
                    ),
                    PopupMenuItem(
                      value: widget.onOpenReactionPicker,
                      child: const Row(
                        children: [Icon(Icons.add_reaction_rounded), SizedBox(width: 12), Text('رياكت')],
                      ),
                    ),
                    if (widget.onSendPoll != null)
                      PopupMenuItem(
                        value: widget.onSendPoll,
                        child: const Row(
                          children: [Icon(Icons.poll_rounded), SizedBox(width: 12), Text('استطلاع رأي')],
                        ),
                      ),
                    if (widget.onSendChecklist != null)
                      PopupMenuItem(
                        value: widget.onSendChecklist,
                        child: const Row(
                          children: [Icon(Icons.checklist_rounded), SizedBox(width: 12), Text('قائمة مهام')],
                        ),
                      ),
                    if (widget.onSendGif != null)
                      PopupMenuItem(
                        value: widget.onSendGif,
                        child: const Row(
                          children: [Icon(Icons.gif_box_rounded), SizedBox(width: 12), Text('GIF')],
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 2),
                IconButton.filledTonal(
                  tooltip: 'إيموجي',
                  onPressed: widget.enabled && !widget.isUploading
                      ? () {
                          // Note: implement opening the emoji picker overlay/dialog here
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              contentPadding: EdgeInsets.zero,
                              content: SizedBox(
                                width: 350,
                                height: 400,
                                child: EmojiPickerPanel(
                                  onEmojiSelected: (emoji) {
                                    final text = widget.controller.text;
                                    final selection = widget.controller.selection;
                                    final newText = text.replaceRange(
                                      selection.start > -1 ? selection.start : text.length,
                                      selection.end > -1 ? selection.end : text.length,
                                      emoji.emoji,
                                    );
                                    widget.controller.value = TextEditingValue(
                                      text: newText,
                                      selection: TextSelection.collapsed(
                                        offset: (selection.start > -1 ? selection.start : text.length) + emoji.emoji.length,
                                      ),
                                    );
                                    Navigator.pop(context);
                                  },
                                ),
                              ),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.emoji_emotions_rounded),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: ChatTextFieldPasteMenu(
                      controller: widget.controller,
                      enabled: widget.enabled,
                      child: TextField(
                        controller: widget.controller,
                        enabled: widget.enabled,
                        onChanged: widget.onChanged,
                        keyboardType: TextInputType.multiline,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.center,
                        textInputAction: widget.enterSendsMessage
                            ? TextInputAction.send
                            : TextInputAction.newline,
                        onSubmitted: widget.enterSendsMessage && widget.enabled
                            ? (_) => widget.onSend()
                            : null,
                        decoration: InputDecoration(
                          hintText: widget.enabled
                              ? (widget.isEditing
                                    ? 'عدّل الرسالة...'
                                    : 'اكتب رسالة...')
                              : 'هذه المحادثة للقراءة فقط',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder: (context, value, _) {
                      final canSend =
                          widget.enabled &&
                          !widget.isUploading &&
                          value.text.trim().isNotEmpty;
                      return GestureDetector(
                        onSecondaryTap: canSend && !widget.isEditing
                            ? widget.onSendOptions
                            : null,
                        child: FilledButton(
                          onPressed: canSend ? widget.onSend : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                          ),
                          child: Icon(
                            widget.isEditing
                                ? Icons.check_rounded
                                : Icons.send_rounded,
                            size: 18,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  const _ActionChipButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: Theme.of(
          context,
        ).colorScheme.surface.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}
