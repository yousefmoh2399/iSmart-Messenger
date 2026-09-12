import 'dart:io';

void main() async {
  final file = File(Platform.environment['TEMP']! + '\\cs_print_log.txt');
  if (!await file.exists()) {
    print('No log file');
    return;
  }
  final lines = await file.readAsLines();
  // Get last 20 lines
  final start = lines.length > 20 ? lines.length - 20 : 0;
  for (int i = start; i < lines.length; i++) {
    print(lines[i]);
  }
}
