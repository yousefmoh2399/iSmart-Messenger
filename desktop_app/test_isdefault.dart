import 'dart:io';

void main() async {
  final printerName = "HP-IT (HP LaserJet Pro M404-M405)";
  
  final result = await Process.run(
    'powershell',
    [
      '-NoProfile',
      '-Command',
      r'Get-WmiObject -Query "SELECT Name FROM Win32_Printer WHERE Default = $true" | Select-Object -ExpandProperty Name'
    ],
  );
  
  final defaultPrinter = result.stdout.toString().trim();
  
  final isDefault = (printerName == null) ||
      (printerName.isEmpty) ||
      (printerName.trim().toLowerCase() == defaultPrinter.trim().toLowerCase());

  print('printerName: "$printerName"');
  print('defaultPrinter: "$defaultPrinter"');
  print('isDefault: $isDefault');
}
