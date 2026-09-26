import 'dart:io';

void main() {
  var file = File('lib/features/chat/presentation/chat_realtime_controller.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll(RegExp(r"'[?]+ [?]+'"), "'متصل الآن'");
  content = content.replaceAll(RegExp(r"'[?]+ [?]+ [?]+\.\.\.'"), "'جاري إعادة الاتصال...'");
  content = content.replaceAll(RegExp(r"'[?]+ [?]+\.\.\.'"), "'جاري الاتصال بالسيرفر...'");
  file.writeAsStringSync(content);

  var file2 = File('lib/shared/widgets/desktop_workspace_sidebar.dart');
  var content2 = file2.readAsStringSync();
  content2 = content2.replaceAll(RegExp(r"U\.OOU, O\x22O U,O3USOU\?O"), "متصل بالسيرفر");
  content2 = content2.replaceAll(RegExp(r"OO OUS O U,O OOO U,\.\.\."), "جاري الاتصال بالسيرفر...");
  content2 = content2.replaceAll(RegExp(r"OUSO U\.OOU,"), "غير متصل");
  file2.writeAsStringSync(content2);

  var file3 = File('lib/features/chat/models/chat_models.dart');
  var content3 = file3.readAsStringSync();
  content3 = content3.replaceAll(RegExp(r"'\?+ \?+ \?+'"), "'محادثة بدون اسم'");
  file3.writeAsStringSync(content3);
}
