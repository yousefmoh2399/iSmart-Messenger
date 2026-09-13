import 'package:flutter/material.dart';
import 'emoji_picker_panel.dart';


/// نافذة اختيار التفاعلات (ديسكتوب / شريط الملحق) — محليّة + مرتبة بالاستخدام.
Future<void> showChatReactionPickerDialog({
  required BuildContext context,
  required Future<void> Function(String unicodeEmoji) onReact,
}) async {
  final theme = Theme.of(context);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 380,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'اختر تفاعلًا',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: EmojiPickerPanel(
                onEmojiSelected: (emoji) async {
                  Navigator.of(dialogContext).pop();
                  await onReact(emoji.emoji);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
