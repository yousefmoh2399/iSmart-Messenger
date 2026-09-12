import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/shared/models/document_paper_size.dart';

void main() {
  test('provides a label for every paper size', () {
    expect(DocumentPaperSize.a4.label, 'ورقة عادية (A4)');
    expect(DocumentPaperSize.idCard.label, 'بطاقة هوية');
    expect(DocumentPaperSize.receipt.label, 'إيصال');
    expect(DocumentPaperSize.auto.label, 'تلقائي (بدون هوامش)');
  });

  test('parses known names and defaults unknown values to auto', () {
    expect(
      DocumentPaperSizeLabels.fromName('idCard'),
      DocumentPaperSize.idCard,
    );
    expect(DocumentPaperSizeLabels.fromName(null), DocumentPaperSize.auto);
    expect(DocumentPaperSizeLabels.fromName('unknown'), DocumentPaperSize.auto);
  });
}
