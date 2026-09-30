import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_app/features/scanner/data/native_scanner_bridge.dart';
import 'package:mobile_app/features/scanner/data/pdf_builder_service.dart';
import 'package:mobile_app/shared/models/document_paper_size.dart';
import 'package:mobile_app/shared/models/scan_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ismart/doc_scanner');
  final methodCalls = <MethodCall>[];
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('native_bridge_test_');
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      methodCalls.add(call);
      switch (call.method) {
        case 'warp':
          return call.arguments['outPath'] as String;
        case 'applyFilter':
          return call.arguments['outPath'] as String;
        case 'rotateLeft':
          return call.arguments['outPath'] as String;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('NativeScannerBridge.warp passes quarterTurns to native method channel', () async {
    final corners = [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9];
    const outPath = '/tmp/warped.jpg';

    // Call warp with quarterTurns = 1
    final result = await NativeScannerBridge.warp(
      path: '/tmp/raw.jpg',
      corners: corners,
      outPath: outPath,
      maxSide: 1600,
      quarterTurns: 1,
    );

    expect(result, equals(outPath));
    expect(methodCalls.length, equals(1));
    expect(methodCalls.first.method, equals('warp'));

    final args = methodCalls.first.arguments as Map;
    expect(args['path'], equals('/tmp/raw.jpg'));
    expect(args['outPath'], equals(outPath));
    expect(args['corners'], equals(corners));
    expect(args['maxSide'], equals(1600));
    expect(args['quarterTurns'], equals(1));
  });

  test('NativeScannerBridge.warp omits quarterTurns when 0', () async {
    final corners = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];
    const outPath = '/tmp/warped_default.jpg';

    final result = await NativeScannerBridge.warp(
      path: '/tmp/raw.jpg',
      corners: corners,
      outPath: outPath,
    );

    expect(result, equals(outPath));
    expect(methodCalls.length, equals(1));
    final args = methodCalls.first.arguments as Map;
    expect(args.containsKey('quarterTurns'), isFalse);
    expect(args.containsKey('maxSide'), isFalse);
  });

  test('PdfBuilderService receives upright JPEGs (EXIF orientation 1) and builds valid PDF', () async {
    // Generate a synthetic upright portrait JPEG
    final image = img.Image(width: 300, height: 400);
    img.fill(image, color: img.ColorRgb8(240, 240, 240));
    final jpegBytes = img.encodeJpg(image);

    final pageFile = File('${tempDir.path}/upright_page.jpg');
    await pageFile.writeAsBytes(jpegBytes);

    final page = ScanPage(
      id: 'test-page-1',
      imagePath: pageFile.path,
      createdAt: DateTime.now(),
      paperSize: DocumentPaperSize.a4,
      quarterTurns: 0,
    );

    final pdfBuilder = PdfBuilderService();
    final pdfBytes = await pdfBuilder.buildPdf(
      imagePaths: [pageFile.path],
      paperSizes: [DocumentPaperSize.a4],
    );

    expect(pdfBytes, isNotNull);
    expect(pdfBytes.length, greaterThan(100));
    // Valid PDF starts with %PDF-
    final header = String.fromCharCodes(pdfBytes.take(5));
    expect(header, equals('%PDF-'));
  });
}
