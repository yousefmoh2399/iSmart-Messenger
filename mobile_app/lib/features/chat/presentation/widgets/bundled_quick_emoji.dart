import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// ويدجت لعرض الإيموجيات المدمجة محلياً مع التطبيق لضمان ظهور التفاعلات السريعة
/// بنسبة 100% حتى في حال انقطاع الإنترنت أو العمل عبر شبكة داخلية (Intranet)
/// بدون الحاجة لتحميل خطوط النظام أو خطوط الويب.
class BundledQuickEmoji extends StatelessWidget {
  const BundledQuickEmoji({
    super.key,
    required this.emoji,
    this.size = 24.0,
    this.animate = true,
    this.repeat = false,
    this.textFallbackStyle,
  });

  final String emoji;
  final double size;
  final bool animate;
  final bool repeat;
  final TextStyle? textFallbackStyle;

  /// خريطة الإيموجيات المدمجة في حزمة التطبيق (assets/emojis)
  static const Map<String, String> _bundledEmojiAssetMap = {
    '👍': 'assets/emojis/thumbsUp.json',
    '❤️': 'assets/emojis/redHeart.json',
    '👏': 'assets/emojis/clap.json',
    '✅': 'assets/emojis/checkMark.json',
    '🔥': 'assets/emojis/fire.json',
    '⚠️': 'assets/emojis/warning.json',
    '🙏': 'assets/emojis/foldedHands.json',
    '😂': 'assets/emojis/joy.json',
    '🎉': 'assets/emojis/partyPopper.json',
    '💯': 'assets/emojis/oneHundred.json',
    '👌': 'assets/emojis/ok.json',
    '😍': 'assets/emojis/heartEyes.json',
    '🤔': 'assets/emojis/thinkingFace.json',
    '😎': 'assets/emojis/sunglassesFace.json',
    '👀': 'assets/emojis/eyes.json',
    '✨': 'assets/emojis/sparkles.json',
    '🚀': 'assets/emojis/rocket.json',
    '😡': 'assets/emojis/angry.json',
    '😢': 'assets/emojis/sad.json',
    '🤝': 'assets/emojis/handshake.json',
  };

  /// التحقق مما إذا كان الإيموجي مدمجاً مع التطبيق محلياً
  static bool isBundled(String emoji) => getAssetForEmoji(emoji) != null;

  /// جلب مسار ملف Lottie المحلي للإيموجي مع التعامل مع variation selectors
  static String? getAssetForEmoji(String emoji) {
    if (_bundledEmojiAssetMap.containsKey(emoji)) {
      return _bundledEmojiAssetMap[emoji];
    }
    final stripped = emoji.replaceAll('\uFE0F', '');
    if (_bundledEmojiAssetMap.containsKey(stripped)) {
      return _bundledEmojiAssetMap[stripped];
    }
    for (final entry in _bundledEmojiAssetMap.entries) {
      if (entry.key.replaceAll('\uFE0F', '') == stripped) {
        return entry.value;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final assetPath = getAssetForEmoji(emoji);

    if (assetPath != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Lottie.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          animate: animate,
          repeat: repeat,
          errorBuilder: (context, error, stackTrace) => _buildFallback(context),
        ),
      );
    }

    return _buildFallback(context);
  }

  Widget _buildFallback(BuildContext context) {
    final fallbackStyle = textFallbackStyle ??
        TextStyle(
          fontSize: size * 0.78,
          height: 1.1,
          fontFamily: 'Segoe UI Emoji',
          fontFamilyFallback: const [
            'Segoe UI Emoji',
            'Apple Color Emoji',
            'Noto Color Emoji',
            'Segoe UI Symbol',
          ],
        );

    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          emoji,
          textAlign: TextAlign.center,
          style: fallbackStyle,
        ),
      ),
    );
  }
}
