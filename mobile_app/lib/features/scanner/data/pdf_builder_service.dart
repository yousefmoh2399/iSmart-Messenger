import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/models/document_paper_size.dart';
import 'image_processing_service.dart';

export '../../../shared/models/document_paper_size.dart';

class PdfBuilderService {
  Future<Uint8List> buildPdf({
    required List<String> imagePaths,
    required List<DocumentPaperSize> paperSizes,
    bool applyEnhancement = false,
  }) async {
    final normalizedPaths = List<String>.from(imagePaths);
    return Isolate.run(
      () => _buildPdfBytes(normalizedPaths, paperSizes, applyEnhancement),
    );
  }
}

Future<Uint8List> _buildPdfBytes(
  List<String> imagePaths,
  List<DocumentPaperSize> paperSizes,
  bool applyEnhancement,
) async {
  debugPrint(
    'PdfBuilderService: Starting PDF build. Total pages: ${imagePaths.length}',
  );
  final sw = Stopwatch()..start();
  final document = pw.Document();

  for (var index = 0; index < imagePaths.length; index++) {
    final imagePath = imagePaths[index];
    final paperSize = index < paperSizes.length
        ? paperSizes[index]
        : DocumentPaperSize.auto;
    final pageStopwatch = Stopwatch()..start();

    debugPrint(
      '[PdfBuilder] Page ${index + 1}/${imagePaths.length} - path: $imagePath, paperSize: ${paperSize.name}',
    );

    final prepared = await _safePrepareImage(imagePath, applyEnhancement);
    final image = pw.MemoryImage(prepared.bytes);

    final width = prepared.width.toDouble();
    final height = prepared.height.toDouble();

    final isLandscape = width > height;
    final format = isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

    pw.Widget imageWidget;
    switch (paperSize) {
      case DocumentPaperSize.idCard:
        final cardWidthMm = isLandscape ? 85.6 : 53.98;
        final cardWidth = cardWidthMm * PdfPageFormat.mm;
        final cardHeight = cardWidth * (height / width);
        imageWidget = pw.SizedBox(
          width: cardWidth,
          height: cardHeight,
          child: pw.Image(image, fit: pw.BoxFit.contain),
        );
        break;
      case DocumentPaperSize.receipt:
        final receiptWidth = 80.0 * PdfPageFormat.mm;
        final receiptHeight = receiptWidth * (height / width);
        imageWidget = pw.SizedBox(
          width: receiptWidth,
          height: receiptHeight,
          child: pw.Image(image, fit: pw.BoxFit.contain),
        );
        break;
      case DocumentPaperSize.a4:
      case DocumentPaperSize.auto:
        imageWidget = pw.FittedBox(
          fit: pw.BoxFit.contain,
          child: pw.Image(image, fit: pw.BoxFit.contain),
        );
        break;
    }

    document.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(8 * PdfPageFormat.mm),
        ),
        build: (_) => pw.Center(child: imageWidget),
      ),
    );

    debugPrint(
      '[PdfBuilder] Page ${index + 1} ready in ${pageStopwatch.elapsedMilliseconds}ms (read+prepare+layout)',
    );
  }

  final saveStopwatch = Stopwatch()..start();
  final pdfBytes = await document.save();
  debugPrint(
    '[PdfBuilder] PDF encode/save took ${saveStopwatch.elapsedMilliseconds}ms',
  );
  debugPrint(
    '[PdfBuilder] DONE in ${sw.elapsedMilliseconds}ms - output ${pdfBytes.length} bytes',
  );

  return pdfBytes;
}

Future<_PreparedPdfImage> _safePrepareImage(
  String imagePath,
  bool applyEnhancement,
) async {
  final prepareStopwatch = Stopwatch()..start();
  debugPrint('[PdfBuilder] _safePrepareImage START for $imagePath');

  final readStopwatch = Stopwatch()..start();
  final originalBytes = await File(imagePath).readAsBytes();
  debugPrint(
    '[PdfBuilder] File read took ${readStopwatch.elapsedMilliseconds}ms (${originalBytes.length} bytes)',
  );

  img.Image? decoded;
  try {
    decoded = img.decodeImage(originalBytes);
  } catch (e) {
    debugPrint('[PdfBuilder] Failed to decode image $imagePath: $e');
    throw Exception('فشل قراءة الصورة، قد تكون تالفة.');
  }

  if (decoded == null) {
    debugPrint('[PdfBuilder] Decoded image is null for $imagePath');
    throw Exception('الصورة فارغة أو غير مدعومة.');
  }

  final orientation = decoded.exif.imageIfd.orientation ?? 1;
  if (orientation != 1) {
    debugPrint('[PdfBuilder] Baking EXIF orientation ($orientation)...');
    decoded = img.bakeOrientation(decoded);
  }

  if (decoded.numChannels == 4) {
    debugPrint('[PdfBuilder] Removing alpha channel...');
    final whiteBg = img.Image(
      width: decoded.width,
      height: decoded.height,
      numChannels: 3,
    );
    img.fill(whiteBg, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(whiteBg, decoded);
    decoded = whiteBg;
  } else if (decoded.numChannels != 3) {
    final rgb = img.Image(
      width: decoded.width,
      height: decoded.height,
      numChannels: 3,
    );
    img.fill(rgb, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(rgb, decoded);
    decoded = rgb;
  }

  const int maxDimension = 2048;
  if (decoded.width > maxDimension || decoded.height > maxDimension) {
    debugPrint(
      '[PdfBuilder] Resizing ${decoded.width}x${decoded.height} to max $maxDimension...',
    );
    decoded = img.copyResize(
      decoded,
      width: decoded.width > decoded.height ? maxDimension : null,
      height: decoded.height > decoded.width ? maxDimension : null,
      interpolation: img.Interpolation.linear,
    );
  }

  var finalBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 85));

  if (applyEnhancement) {
    try {
      debugPrint('[PdfBuilder] Applying enhancement pipeline...');
      final enhancedBytes = processEnhancementOnly(finalBytes);
      final enhancedDecoded = img.decodeImage(enhancedBytes);
      if (enhancedDecoded != null) {
        finalBytes = enhancedBytes;
        decoded = enhancedDecoded;
      }
    } catch (e) {
      debugPrint('[PdfBuilder] Enhancement failed: $e');
    }
  }

  debugPrint(
    '[PdfBuilder] _safePrepareImage DONE in ${prepareStopwatch.elapsedMilliseconds}ms',
  );

  return _PreparedPdfImage(
    bytes: finalBytes,
    width: decoded!.width,
    height: decoded.height,
  );
}

class _PreparedPdfImage {
  final Uint8List bytes;
  final int width;
  final int height;

  const _PreparedPdfImage({
    required this.bytes,
    required this.width,
    required this.height,
  });
}
