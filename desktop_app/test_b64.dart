import 'dart:io';
import 'dart:convert';

void main() {
  String b(String s) => utf8.decode(base64.decode(s));
  
  var file = File('lib/features/chat/models/chat_models.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll(RegExp(r'return \x27.*?\x27;'), "return '\';"); // '?????? ???? ???'
  file.writeAsStringSync(content);
}
