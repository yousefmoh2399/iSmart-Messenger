import 'dart:io';
import 'dart:convert';

void main() async {
  final file = File(Platform.environment['TEMP']! + '\\cs_print_log.txt');
  final log = await file.readAsString();
  final match = RegExp(r'inlineFileBase64: ([A-Za-z0-9+/=]+)').firstMatch(log);
  if (match != null) {
    final bytes = base64Decode(match.group(1)!);
    await File('extracted.pdf').writeAsBytes(bytes);
    print('Extracted to extracted.pdf, size: ${bytes.length}');
  } else {
    print('Not found');
  }
}
