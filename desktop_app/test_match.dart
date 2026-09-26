import 'dart:io';
void main() {
  var file = File('lib/features/chat/models/chat_models.dart');
  var code = file.readAsStringSync();
  print(code.contains('factory ChatDirectoryUser.fromJson'));
}
