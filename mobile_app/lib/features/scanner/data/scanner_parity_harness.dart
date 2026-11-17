import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'native_scanner_bridge.dart';

/// Debug-only parity harness (Step 5) that runs all 6 native filters on a directory
/// of sample images and writes `<basename>_<filter>.jpg` into `outputDir`.
class ScannerParityHarness {
  static const List<String> filters = <String>[
    'original',
    'lighten',
    'enhance',
    'gray',
    'eco',
    'no_handwriting',
  ];

  /// Runs all 6 filters on every `.jpg` / `.jpeg` / `.png` file in [sampleDirPath]
  /// and writes the outputs to [outputDirPath]. Only active in [kDebugMode].
  static Future<Map<String, Map<String, int>>> runBatchParity({
    required String sampleDirPath,
    required String outputDirPath,
    int maxSide = 0,
  }) async {
    if (!kDebugMode) {
      throw UnsupportedError('ScannerParityHarness is only available in kDebugMode');
    }

    final sampleDir = Directory(sampleDirPath);
    if (!sampleDir.existsSync()) {
      throw ArgumentError('Sample directory does not exist: $sampleDirPath');
    }

    final outDir = Directory(outputDirPath);
    await outDir.create(recursive: true);

    final files = sampleDir
        .listSync()
        .whereType<File>()
        .where((f) {
          final ext = p.extension(f.path).toLowerCase();
          return ext == '.jpg' || ext == '.jpeg' || ext == '.png';
        })
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final timings = <String, Map<String, int>>{};

    for (final file in files) {
      final baseName = p.basenameWithoutExtension(file.path);
      final fileTimings = <String, int>{};

      for (final filter in filters) {
        final outPath = p.join(outDir.path, '${baseName}_$filter.jpg');
        final sw = Stopwatch()..start();
        await NativeScannerBridge.applyFilter(
          path: file.path,
          filter: filter,
          outPath: outPath,
          maxSide: maxSide,
        );
        sw.stop();
        fileTimings[filter] = sw.elapsedMilliseconds;
        debugPrint(
          '[DocScan][Parity] $baseName [$filter] -> ${sw.elapsedMilliseconds}ms ($outPath)',
        );
      }

      timings[baseName] = fileTimings;
    }

    return timings;
  }
}
