import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../../../../core/constants/available_emojis.dart';

final RegExp _linkPattern = RegExp(
  r'((?:https?:\/\/|www\.)[^\s<>()]+|(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}(?:\/[^\s<>()]*)?)',
  caseSensitive: false,
);

final RegExp _emojiRegex = RegExp(
  r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])',
);

class ChatRichText extends StatefulWidget {
  const ChatRichText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  State<ChatRichText> createState() => _ChatRichTextState();
}

class _ChatRichTextState extends State<ChatRichText> {
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

  String _getEmojiHex(String emojiStr) {
    return emojiStr.runes
        .map((r) => r.toRadixString(16).toLowerCase())
        .join('_');
  }

  List<InlineSpan> _parseEmojis(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    final matches = _emojiRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      spans.add(TextSpan(text: text));
      return spans;
    }

    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }

      final emojiStr = match.group(0)!;
      final hex = _getEmojiHex(emojiStr);

      if (availablePngEmojis.contains(hex)) {
        final fontSize = style.fontSize ?? 14.0;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Image.asset(
              'assets/noto_emojis_png/emoji_u$hex.png',
              width: fontSize * 1.3,
              height: fontSize * 1.3,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: emojiStr));
      }

      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final matches = _linkPattern.allMatches(widget.text).toList();
    if (matches.isEmpty) {
      return Text.rich(
        TextSpan(
          style: widget.style,
          children: _parseEmojis(widget.text, widget.style),
        ),
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
        spans.addAll(
          _parseEmojis(
            widget.text.substring(cursor, match.start),
            widget.style,
          ),
        );
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
        spans.addAll(_parseEmojis(trailing, widget.style));
      }
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      spans.addAll(_parseEmojis(widget.text.substring(cursor), widget.style));
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
