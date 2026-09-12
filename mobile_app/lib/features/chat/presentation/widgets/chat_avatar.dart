import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/network/media_url_resolver.dart';

class ChatAvatar extends StatelessWidget {
  final double radius;
  final Color backgroundColor;
  final String? avatarUrl;
  final Widget fallback;

  const ChatAvatar({
    super.key,
    required this.radius,
    required this.backgroundColor,
    required this.avatarUrl,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = resolveMediaUrl(avatarUrl);
    if (resolvedUrl == null || resolvedUrl.trim().isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: fallback,
      );
    }

    return CachedNetworkImage(
      imageUrl: resolvedUrl,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        backgroundImage: imageProvider,
      ),
      placeholder: (context, url) => CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: fallback,
      ),
      errorWidget: (context, url, error) => CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: fallback,
      ),
    );
  }
}
