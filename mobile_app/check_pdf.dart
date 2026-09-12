import 'dart:io';

void main() async {
  final bytes = await File('test_output.pdf').readAsBytes();
  final content = String.fromCharCodes(bytes);
  final pageMatches = RegExp(r'/Type\s*/Page\b').allMatches(content);
  print('Pages: ${pageMatches.length}');
}
