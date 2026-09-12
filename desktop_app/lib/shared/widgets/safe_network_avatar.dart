import 'package:flutter/material.dart';
import 'authenticated_network_image.dart';

class SafeNetworkAvatar extends StatelessWidget {
  const SafeNetworkAvatar({
    super.key,
    required this.radius,
    required this.backgroundColor,
    this.imageUrl,
    this.httpHeaders,
    this.fallbackText,
    this.fallbackTextStyle,
    this.fallbackIcon,
    this.fallbackIconColor,
    this.fallbackIconSize,
  });

  final double radius;
  final Color backgroundColor;
  final String? imageUrl;
  final Map<String, String>? httpHeaders;
  final String? fallbackText;
  final TextStyle? fallbackTextStyle;
  final IconData? fallbackIcon;
  final Color? fallbackIconColor;
  final double? fallbackIconSize;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = imageUrl?.trim() ?? '';

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: normalizedUrl.isEmpty
          ? _FallbackContent(
              text: fallbackText,
              textStyle: fallbackTextStyle,
              icon: fallbackIcon,
              iconColor: fallbackIconColor,
              iconSize: fallbackIconSize,
            )
          : ClipOval(
              child: AuthenticatedNetworkImage(
                imageUrl: normalizedUrl,
                httpHeaders: httpHeaders,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                placeholder: _FallbackContent(
                  text: fallbackText,
                  textStyle: fallbackTextStyle,
                  icon: fallbackIcon,
                  iconColor: fallbackIconColor,
                  iconSize: fallbackIconSize,
                ),
                errorWidget: _FallbackContent(
                  text: fallbackText,
                  textStyle: fallbackTextStyle,
                  icon: fallbackIcon,
                  iconColor: fallbackIconColor,
                  iconSize: fallbackIconSize,
                ),
              ),
            ),
    );
  }
}

class _FallbackContent extends StatelessWidget {
  const _FallbackContent({
    this.text,
    this.textStyle,
    this.icon,
    this.iconColor,
    this.iconSize,
  });

  final String? text;
  final TextStyle? textStyle;
  final IconData? icon;
  final Color? iconColor;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    if (text != null && text!.trim().isNotEmpty) {
      return Text(text!, style: textStyle, maxLines: 1);
    }
    return Icon(icon ?? Icons.person, color: iconColor, size: iconSize);
  }
}
