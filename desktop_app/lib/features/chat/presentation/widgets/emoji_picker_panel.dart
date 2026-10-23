import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

class EmojiPickerPanel extends StatelessWidget {
  const EmojiPickerPanel({super.key, required this.onEmojiSelected});

  final void Function(Emoji emoji) onEmojiSelected;

  @override
  Widget build(BuildContext context) {
    final emojiStyle = TextStyle(
      fontSize: 26,
      color: Theme.of(context).colorScheme.onSurface,
      fontFamily: 'Segoe UI Emoji',
      fontFamilyFallback: const [
        'Segoe UI Emoji',
        'Apple Color Emoji',
        'Noto Color Emoji',
        'Segoe UI Symbol',
      ],
    );

    return EmojiPicker(
      onEmojiSelected: (category, emoji) => onEmojiSelected(emoji),
      config: Config(
        checkPlatformCompatibility: false,
        emojiTextStyle: emojiStyle,
        emojiViewConfig: EmojiViewConfig(
          emojiSizeMax: 28,
          backgroundColor: Theme.of(context).colorScheme.surface,
          buttonMode: ButtonMode.MATERIAL,
        ),
        bottomActionBarConfig: const BottomActionBarConfig(
          showBackspaceButton: false,
          showSearchViewButton: false,
        ),
        searchViewConfig: SearchViewConfig(
          backgroundColor: Theme.of(context).colorScheme.surface,
        ),
        categoryViewConfig: CategoryViewConfig(
          backgroundColor: Theme.of(context).colorScheme.surface,
        ),
      ),
    );
  }
}
