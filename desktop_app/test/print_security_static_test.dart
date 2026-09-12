import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Print security static checks', () {
    test('Desktop print service does not log sensitive payload content', () {
      final source = File(
        'lib/shared/services/desktop_print_service.dart',
      ).readAsStringSync();

      expect(source, isNot(contains(r'payload: $payload')));
      expect(source, isNot(contains(r'Error response text: $text')));
      expect(source, isNot(contains(r'Unexpected JSON response: $text')));
      expect(source, isNot(contains(r'inlineFileBase64=$')));
      expect(source, isNot(contains(r'requestAuthToken=$')));
    });

    test('Desktop print service does not download SumatraPDF automatically', () {
      final source = File(
        'lib/shared/services/desktop_print_service.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('sumatrapdfreader.org')));
      expect(source, isNot(contains('_downloadPortableSumatraExe')));
      expect(source, isNot(contains('_resolvePortableSumatraDownloadUrl')));
      expect(source, isNot(contains('SumatraPDF-[^"]*.zip')));
    });

    test('Electron PDF handlers route PDFs to native service, not webContents.print', () {
      final ipcHandlers = File(
        'electron/printing/register_print_ipc_handlers.js',
      ).readAsStringSync();
      final pdfService = File(
        'electron/printing/pdf_print_service.js',
      ).readAsStringSync();

      expect(ipcHandlers, isNot(contains('webContents.print')));
      expect(pdfService, isNot(contains('webContents.print')));
    });
  });
}
