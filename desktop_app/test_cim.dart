import 'dart:io';
import 'dart:convert';

void main() async {
  final result = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    r'Get-CimInstance Win32_Printer | Where-Object {$_.Default -eq $true} | Select-Object -First 1 Name | ConvertTo-Json -Compress',
  ]);
  
  print('Exit code: ${result.exitCode}');
  print('STDOUT: ${result.stdout}');
  print('STDERR: ${result.stderr}');
  
  final raw = result.stdout.toString().trim();
  if (raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        print('Parsed Name: ${decoded['Name']?.toString().trim()}');
      }
    } catch (e) {
      print('JSON decode error: $e');
    }
  }
}
