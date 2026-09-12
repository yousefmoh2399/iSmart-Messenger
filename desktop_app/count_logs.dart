import 'dart:io';

void main() async {
  final file = File(Platform.environment['TEMP']! + '\\cs_print_log.txt');
  if (!await file.exists()) {
    print('No log file');
    return;
  }
  final lines = await file.readAsLines();
  int count = 0;
  for (var line in lines) {
    if (line.contains('executePrintJob called with payload')) {
      count++;
    }
  }
  print('executePrintJob called $count times.');
}
