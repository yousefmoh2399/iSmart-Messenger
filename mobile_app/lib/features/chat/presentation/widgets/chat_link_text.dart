import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _linkPattern = RegExp(
  r'((?:https?:\/\/|www\.)[^\s<>()]+|(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}(?:\/[^\s<>()]*)?)',
  caseSensitive: false,
);

class ChatLinkText extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.75;
    final matches = _linkPattern.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: style, textAlign: textAlign);
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final rawLink = _trimTrailingPunctuation(match.group(0)!);
      final trailing = text.substring(match.start + rawLink.length, match.end);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _InlineLink(label: rawLink, style: style, maxWidth: maxWidth),
        ),
      );
      if (trailing.isNotEmpty) {
        spans.add(TextSpan(text: trailing));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return Text.rich(TextSpan(children: spans), textAlign: textAlign);
  }
}

class _InlineLink extends StatelessWidget {
  const _InlineLink({
    required this.label,
    required this.style,
    required this.maxWidth,
  });

  final String label;
  final TextStyle style;
  final double maxWidth;

  Future<void> _open() async {
    final uri = _linkUri(label);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: label));
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
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
      await _open();
    } else if (action == _LinkAction.copy) {
      await _copy();
    }
  }

  @override
  Widget build(BuildContext context) {
    final linkStyle = style.copyWith(
      color: const Color(0xFF2A8CFF),
      decoration: TextDecoration.underline,
      decorationColor: const Color(0xFF2A8CFF),
      fontWeight: FontWeight.w700,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _open,
      onLongPressStart: (details) => _showMenu(context, details.globalPosition),
      onSecondaryTapDown: (details) =>
          _showMenu(context, details.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Text(label, style: linkStyle, softWrap: true),
        ),
      ),
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
