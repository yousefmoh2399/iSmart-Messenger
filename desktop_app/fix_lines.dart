import 'dart:io';
import 'dart:convert';
void main() {
  String b(String s) => utf8.decode(base64.decode(s));

  var file1 = File('lib/features/chat/models/chat_models.dart');
  var lines1 = file1.readAsLinesSync();
  for (var i = 0; i < lines1.length; i++) {
    if (lines1[i].contains("return") && lines1[i].contains("??????")) {
      lines1[i] = "    return '\';";
    }
  }
  file1.writeAsStringSync(lines1.join('\n'));

  var file2 = File('lib/features/chat/presentation/chat_realtime_controller.dart');
  var lines2 = file2.readAsLinesSync();
  for (var i = 0; i < lines2.length; i++) {
    if (lines2[i].contains("message:") && lines2[i].contains("lastChangedAt")) continue;
    if (lines2[i].contains("message: '") && lines2[i].contains("+")) {
      lines2[i] = "            message: '\',";
    }
    if (lines2[i].contains("message: '") && lines2[i].contains("...")) {
      lines2[i] = "            message: '\',";
    }
    if (lines2[i].contains("event.payload['message']")) {
      lines2[i] = "                event.payload['message']?.toString() ?? '\',";
    }
    if (lines2[i].contains("message: socketService.isConnected")) {
      lines2[i] = "      message: socketService.isConnected ? '\' : '\',";
    }
  }
  file2.writeAsStringSync(lines2.join('\n'));

  var file3 = File('lib/shared/widgets/desktop_workspace_sidebar.dart');
  var lines3 = file3.readAsLinesSync();
  for (var i = 0; i < lines3.length; i++) {
    if (lines3[i].contains("? '") && lines3[i].contains("?'")) {
      lines3[i] = "          ? '\'";
    }
    if (lines3[i].contains("? '") && lines3[i].contains("...'")) {
      lines3[i] = "              ? '\'";
    }
    if (lines3[i].contains(": '") && lines3[i].contains("U,'")) {
      lines3[i] = "              : '\';";
    }
  }
  file3.writeAsStringSync(lines3.join('\n'));
}
