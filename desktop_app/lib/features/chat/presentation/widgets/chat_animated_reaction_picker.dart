import 'dart:async';

import 'package:flutter/material.dart';
import 'emoji_picker_panel.dart';

/// شريط التفاعل السريع واختيار الإيموجي للرسائل (Quick Reactions Bar).
/// يعرض شريطاً عائماً مدمجاً بالإيموجيات الأكثر استخداماً للرد بنقرة واحدة،
/// مع زر (+) لفتح مكتبة الإيموجي الكاملة عند الحاجة.
Future<void> showChatReactionPickerDialog({
  required BuildContext context,
  required Future<void> Function(String unicodeEmoji) onReact,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _ChatReactionDialog(onReact: onReact),
  );
}

class _ChatReactionDialog extends StatefulWidget {
  const _ChatReactionDialog({required this.onReact});

  final Future<void> Function(String unicodeEmoji) onReact;

  @override
  State<_ChatReactionDialog> createState() => _ChatReactionDialogState();
}

class _ChatReactionDialogState extends State<_ChatReactionDialog> {
  bool _showFullPicker = false;

  /// أشهر إيموجيات العمل والتفاعل السريع لتأكيد الاستلام أو الموافقة
  static const List<String> _quickEmojis = [
    '👍',
    '❤️',
    '👏',
    '✅',
    '🔥',
    '⚠️',
    '🙏',
    '😂',
    '🎉',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _showFullPicker
              ? _buildFullPicker(theme, isDark)
              : _buildQuickBar(theme, isDark),
        ),
      ),
    );
  }

  Widget _buildQuickBar(ThemeData theme, bool isDark) {
    return Container(
      key: const ValueKey('quick_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2128) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.14),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final emoji in _quickEmojis)
              _QuickEmojiButton(
                emoji: emoji,
                onSelected: () async {
                  Navigator.of(context).pop();
                  await widget.onReact(emoji);
                },
              ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              width: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.08),
            ),
            Tooltip(
              message: 'المزيد من الإيموجي',
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() => _showFullPicker = true),
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: 22,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullPicker(ThemeData theme, bool isDark) {
    return Container(
      key: const ValueKey('full_picker'),
      width: 380,
      height: 460,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2128) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.14),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'رجوع للتفاعلات السريعة',
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  onPressed: () => setState(() => _showFullPicker = false),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'اختر تفاعلًا',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'إغلاق',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
          Expanded(
            child: EmojiPickerPanel(
              onEmojiSelected: (emoji) async {
                Navigator.of(context).pop();
                await widget.onReact(emoji.emoji);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickEmojiButton extends StatefulWidget {
  const _QuickEmojiButton({
    required this.emoji,
    required this.onSelected,
  });

  final String emoji;
  final VoidCallback onSelected;

  @override
  State<_QuickEmojiButton> createState() => _QuickEmojiButtonState();
}

class _QuickEmojiButtonState extends State<_QuickEmojiButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovered
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          alignment: Alignment.center,
          child: AnimatedScale(
            scale: _hovered ? 1.25 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutBack,
            child: Text(
              widget.emoji,
              style: const TextStyle(
                fontSize: 22,
                fontFamilyFallback: [
                  'Segoe UI Emoji',
                  'Apple Color Emoji',
                  'Noto Color Emoji',
                  'Segoe UI Symbol',
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
