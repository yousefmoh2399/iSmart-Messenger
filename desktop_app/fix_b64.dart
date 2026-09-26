import 'dart:io';
import 'dart:convert';

void main() {
  String b(String s) => utf8.decode(base64.decode(s));
  
  var file1 = File('lib/features/chat/models/chat_models.dart');
  var content1 = file1.readAsStringSync();
  content1 = content1.replaceAll(RegExp(r"return '\?+ \?+ \?+';"), "return '\';");
  file1.writeAsStringSync(content1);

  var file2 = File('lib/features/chat/presentation/chat_realtime_controller.dart');
  var content2 = file2.readAsStringSync();
  content2 = content2.replaceAll(RegExp(r"message: 'U\.O.*?O\+?'"), "message: '\'");
  content2 = content2.replaceAll(RegExp(r"message: 'OO.*?U,\.\.\.'"), "message: '\'");
  content2 = content2.replaceAll(RegExp(r"\?\? 'U\?O.*?O\xef\xbf\xbd'"), "?? '\'");
  content2 = content2.replaceAll(RegExp(r"message: socketService\.isConnected \? 'U\.O.*?O\+' : 'OO.*?U,\.\.\.'"), "message: socketService.isConnected ? '\' : '\'");
  file2.writeAsStringSync(content2);

  var file3 = File('lib/shared/widgets/desktop_workspace_sidebar.dart');
  var content3 = file3.readAsStringSync();
  content3 = content3.replaceAll(RegExp(r"\? 'U\.O.*?U\?O\xef\xbf\xbd'"), "? '\'");
  content3 = content3.replaceAll(RegExp(r"\? 'OO.*?U,\.\.\.'"), "? '\'");
  content3 = content3.replaceAll(RegExp(r": 'OUSO.*?U,'"), ": '\'");
  file3.writeAsStringSync(content3);
}
