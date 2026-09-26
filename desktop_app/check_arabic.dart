import 'dart:io';
void main() {
  var file = File('lib/features/chat/models/chat_models.dart');
  var content = file.readAsStringSync();
  var arabicPattern = RegExp(r'[\u0600-\u06FF]');
  var lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (arabicPattern.hasMatch(lines[i])) {
      print('Line \: \');
    }
  }
}
