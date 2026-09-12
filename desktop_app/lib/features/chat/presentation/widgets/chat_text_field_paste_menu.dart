import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChatTextFieldPasteMenu extends StatelessWidget {
  const ChatTextFieldPasteMenu({
    super.key,
    required this.controller,
    required this.enabled,
    required this.child,
  });

  final TextEditingController controller;
  final bool enabled;
  final Widget child;

  Future<void> _pasteAtSelection() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    final value = controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final nextText =
        selection.textBefore(value.text) +
        text +
        selection.textAfter(value.text);
    final nextOffset = selection.start + text.length;
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    if (!enabled) {
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<_TextFieldAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: _TextFieldAction.paste,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.content_paste_rounded),
            title: Text('لصق'),
          ),
        ),
      ],
    );
    if (action == _TextFieldAction.paste) {
      await _pasteAtSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == 2) {
          _showMenu(context, event.position);
        }
      },
      child: child,
    );
  }
}

enum _TextFieldAction { paste }
