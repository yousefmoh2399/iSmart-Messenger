import 'dart:io';

void main() async {
  final result = await Process.run(
    'powershell',
    [
      '-NoProfile',
      '-Command',
      r'Get-WmiObject -Query "SELECT Name FROM Win32_Printer WHERE Default = $true" | Select-Object -ExpandProperty Name'
    ],
  );
  print('Default Printer on Windows: "${result.stdout.toString().trim()}"');
}
