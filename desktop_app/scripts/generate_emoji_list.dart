import 'dart:io';

void main() {
  final pngDir = Directory('assets/noto_emojis_png');
  final lottieDir = Directory('assets/animated_emoji_lottie');

  final pngFiles = pngDir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList();
  final lottieFiles = lottieDir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList();

  final pngCodes = pngFiles.map((name) => name.replaceAll('emoji_u', '').replaceAll('.png', '')).toList();
  final lottieCodes = lottieFiles.map((name) => name.replaceAll('emoji_u', '').replaceAll('.json', '')).toList();

  final dartContent = '''
// GENERATED FILE. DO NOT EDIT.

const Set<String> availablePngEmojis = {
  ${pngCodes.map((c) => "'$c'").join(',\n  ')}
};

const Set<String> availableLottieEmojis = {
  ${lottieCodes.map((c) => "'$c'").join(',\n  ')}
};
''';

  File('lib/core/constants/available_emojis.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(dartContent);

  print('Generated available_emojis.dart');
}
