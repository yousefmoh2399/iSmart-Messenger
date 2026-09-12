import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

class EmojiPickerPanel extends StatelessWidget {
  const EmojiPickerPanel({super.key, required this.onEmojiSelected});

  final void Function(Emoji emoji) onEmojiSelected;

  @override
  Widget build(BuildContext context) {
    return EmojiPicker(
      onEmojiSelected: (category, emoji) => onEmojiSelected(emoji),
      config: Config(
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
