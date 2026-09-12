import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/services/web_platform_bridge.dart' as web_bridge;

final RegExp _linkPattern = RegExp(
  r'((?:https?:\/\/|www\.)[^\s<>()]+|(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}(?:\/[^\s<>()]*)?)',
  caseSensitive: false,
);

class ChatLinkText extends StatefulWidget {
  const ChatLinkText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  State<ChatLinkText> createState() => _ChatLinkTextState();
}

class _ChatLinkTextState extends State<ChatLinkText> {
  final List<GestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _open(String label) async {
    final uri = _linkUri(label);
    if (uri == null) return;

    if (web_bridge.isElectron()) {
      await web_bridge.openUrlInNewTab(uri.toString());
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copy(String label) async {
    await Clipboard.setData(ClipboardData(text: label));
  }

  Future<void> _showMenu(
    BuildContext context,
    Offset position,
    String label,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<_LinkAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: _LinkAction.open,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.open_in_browser_rounded),
            title: Text('فتح الرابط'),
          ),
        ),
        PopupMenuItem(
          value: _LinkAction.copy,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.content_copy_rounded),
            title: Text('نسخ الرابط'),
          ),
        ),
      ],
    );
    if (action == _LinkAction.open) {
      await _open(label);
    } else if (action == _LinkAction.copy) {
      await _copy(label);
    }
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final matches = _linkPattern.allMatches(widget.text).toList();
    if (matches.isEmpty) {
      return Text(
        widget.text,
        style: widget.style,
        textAlign: widget.textAlign,
      );
    }

    final linkStyle = widget.style.copyWith(
      color: const Color(0xFF2A8CFF),
      decoration: TextDecoration.underline,
      decorationColor: const Color(0xFF2A8CFF),
      fontWeight: FontWeight.w700,
    );

    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      final rawLink = _trimTrailingPunctuation(match.group(0)!);
      final trailing = widget.text.substring(
        match.start + rawLink.length,
        match.end,
      );

      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          _open(rawLink);
        }
        ..onSecondaryTapDown = (details) {
          _showMenu(context, details.globalPosition, rawLink);
        };

      _recognizers.add(recognizer);

      spans.add(
        TextSpan(
          text: rawLink,
          style: linkStyle,
          recognizer: recognizer,
          mouseCursor: SystemMouseCursors.click,
        ),
      );
      if (trailing.isNotEmpty) {
        spans.add(TextSpan(text: trailing));
      }
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      textAlign: widget.textAlign,
    );
  }
}

enum _LinkAction { open, copy }

Uri? _linkUri(String value) {
  final raw = value.trim();
  if (raw.isEmpty) {
    return null;
  }
  return Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
}

String _trimTrailingPunctuation(String value) {
  return value.replaceFirst(RegExp(r'[.,;:!?،؛؟\]\)}]+$'), '');
}
