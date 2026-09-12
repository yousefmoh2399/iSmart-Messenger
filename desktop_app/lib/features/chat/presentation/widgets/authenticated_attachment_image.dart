import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/providers/providers.dart';
import '../../../../shared/widgets/app_loading_placeholders.dart';
import '../../models/chat_models.dart';

class AuthenticatedAttachmentImage extends ConsumerStatefulWidget {
  const AuthenticatedAttachmentImage({
    super.key,
    required this.message,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorFallback,
  });

  final ChatMessage message;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorFallback;

  @override
  ConsumerState<AuthenticatedAttachmentImage> createState() =>
      _AuthenticatedAttachmentImageState();
}

class _AuthenticatedAttachmentImageState
    extends ConsumerState<AuthenticatedAttachmentImage> {
  late Future<Uint8List> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytes();
  }

  @override
  void didUpdateWidget(covariant AuthenticatedAttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.updatedAt != widget.message.updatedAt) {
      _bytesFuture = _loadBytes();
    }
  }

  Future<Uint8List> _loadBytes() {
    return ref
        .read(chatRepositoryProvider)
        .fetchAttachmentPreviewBytes(widget.message);
  }

  @override
  Widget build(BuildContext context) {
    Widget loadingPlaceholder() =>
        widget.placeholder ??
        AppMediaLoadingPlaceholder(
          width: widget.width,
          height: widget.height,
          borderRadius: 12,
        );

    Widget errorPlaceholder() =>
        widget.errorFallback ??
        Container(
          color: const Color(0xFFF0F4F9),
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined),
        );

    return FutureBuilder<Uint8List>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: loadingPlaceholder(),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: errorPlaceholder(),
          );
        }
        if (_isSvgMessage(widget.message, bytes)) {
          return SvgPicture.memory(
            bytes,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            placeholderBuilder: (_) => SizedBox(
              width: widget.width,
              height: widget.height,
              child: loadingPlaceholder(),
            ),
          );
        }
        return Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (_, __, ___) => SizedBox(
            width: widget.width,
            height: widget.height,
            child: errorPlaceholder(),
          ),
        );
      },
    );
  }

  bool _isSvgMessage(ChatMessage message, Uint8List bytes) {
    final mime = message.mimeType?.toLowerCase().trim() ?? '';
    final name = message.fileName?.toLowerCase().trim() ?? '';
    if (mime == 'image/svg+xml' || name.endsWith('.svg')) {
      return true;
    }
    final sample = String.fromCharCodes(bytes.take(256)).toLowerCase();
    return sample.contains('<svg');
  }
}
