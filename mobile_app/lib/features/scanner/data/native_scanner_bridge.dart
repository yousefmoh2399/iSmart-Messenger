import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeScannerResult {
  const NativeScannerResult({
    required this.path,
    required this.corners,
    required this.width,
    required this.height,
  });

  final String path;
  final List<double> corners; // 8 normalized doubles [tl.x, tl.y, tr.x, tr.y, br.x, br.y, bl.x, bl.y]
  final int width;
  final int height;

  factory NativeScannerResult.fromMap(Map<dynamic, dynamic> map) {
    final rawCorners = (map['corners'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const <double>[];
    return NativeScannerResult(
      path: map['path'] as String? ?? '',
      corners: rawCorners,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
    );
  }
}

class NativeScannerBridge {
  static const MethodChannel _channel = MethodChannel('ismart/doc_scanner');

  /// Starts the embedded high-performance native ScannerActivity.
  /// Returns [NativeScannerResult] on successful capture, or null if cancelled.
  static Future<NativeScannerResult?> startScan({String? destDir}) async {
    final sw = Stopwatch()..start();
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'startScan',
        {'destDir': destDir},
      );
      debugPrint('[NativeScannerBridge] startScan completed in ${sw.elapsedMilliseconds}ms');
      if (result == null) return null;
      return NativeScannerResult.fromMap(result);
    } catch (e) {
      debugPrint('[NativeScannerBridge] startScan failed: $e');
      rethrow;
    }
  }

  /// Warps a document region defined by 8 normalized corners [tl.x, tl.y, tr.x, tr.y, br.x, br.y, bl.x, bl.y]
  /// and writes the perspective-rectified image to [outPath].
  static Future<String> warp({
    required String path,
    required List<double> corners,
    required String outPath,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await _channel.invokeMethod<String>('warp', {
        'path': path,
        'corners': corners,
        'outPath': outPath,
      });
      debugPrint('[NativeScannerBridge] warp completed in ${sw.elapsedMilliseconds}ms -> $outPath');
      return result ?? outPath;
    } catch (e) {
      debugPrint('[NativeScannerBridge] warp failed: $e');
      rethrow;
    }
  }

  /// Applies one of the OpenCV native document filters:
  /// 'enhance', 'lighten', 'gray', 'eco', 'no_handwriting', 'original'.
  /// Optional [maxSide] resizes the image before filtering (e.g. 200 for thumbnails, 1600 for preview).
  static Future<String> applyFilter({
    required String path,
    required String filter,
    required String outPath,
    int maxSide = 0,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await _channel.invokeMethod<String>('applyFilter', {
        'path': path,
        'filter': filter,
        'maxSide': maxSide,
        'outPath': outPath,
      });
      debugPrint('[NativeScannerBridge] applyFilter ($filter, maxSide=$maxSide) completed in ${sw.elapsedMilliseconds}ms -> $outPath');
      return result ?? outPath;
    } catch (e) {
      debugPrint('[NativeScannerBridge] applyFilter failed: $e');
      rethrow;
    }
  }

  /// Rotates an image 90 degrees counter-clockwise natively.
  static Future<String> rotateLeft({
    required String path,
    required String outPath,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await _channel.invokeMethod<String>('rotateLeft', {
        'path': path,
        'outPath': outPath,
      });
      debugPrint('[NativeScannerBridge] rotateLeft completed in ${sw.elapsedMilliseconds}ms -> $outPath');
      return result ?? outPath;
    } catch (e) {
      debugPrint('[NativeScannerBridge] rotateLeft failed: $e');
      rethrow;
    }
  }
}
