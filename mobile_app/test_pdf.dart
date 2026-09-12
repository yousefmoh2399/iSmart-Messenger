import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() async {
  final document = pw.Document();
  final format = PdfPageFormat.a4;
  
  document.addPage(
    pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(8 * PdfPageFormat.mm),
      ),
      build: (_) => pw.Container(
        color: PdfColors.white,
        child: pw.Center(
          child: pw.SizedBox(width: 100, height: 100),
        ),
      ),
    ),
  );
  
  final bytes = await document.save();
  print('Document generated. Bytes: ${bytes.length}');
  final file = File('test_output.pdf');
  await file.writeAsBytes(bytes);
}
