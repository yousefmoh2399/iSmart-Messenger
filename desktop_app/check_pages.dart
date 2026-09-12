import 'dart:io';

void main() async {
  final file = File('1784547106238_Yousef_Mohamed-HQ_2026_07_20_13_17_19.pdf');
  final bytes = await file.readAsBytes();
  final content = String.fromCharCodes(bytes);
  final count = RegExp(r'/Type\s*/Page\b').allMatches(content).length;
  print('Pages: $count');
}
