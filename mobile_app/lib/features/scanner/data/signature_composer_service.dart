import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Composites a signature PNG on top of a scanned page image.
/// Runs entirely in an [Isolate] to avoid UI jank.
class SignatureComposerService {
  /// Merges [signatureBytes] (PNG with transparency) onto [pageImageBytes]
  /// at [relativeX], [relativeY] (0.0–1.0 relative to page dimensions)
  /// with [relativeWidth] (0.0–1.0 relative to page width).
  ///
  /// Returns the final composited JPEG bytes.
  Future<Uint8List> compositeSignatureOnImage({
    required Uint8List pageImageBytes,
    required Uint8List signatureBytes,
    required double relativeX,
    required double relativeY,
    required double relativeWidth,
  }) async {
    return Isolate.run(() {
      return _composite(
        pageImageBytes,
        signatureBytes,
        relativeX,
        relativeY,
        relativeWidth,
      );
    });
  }
}

Uint8List _composite(
  Uint8List pageBytes,
  Uint8List sigBytes,
  double relX,
  double relY,
  double relW,
) {
  // Decode page
  final page = img.decodeImage(pageBytes);
  if (page == null) throw Exception('تعذر فك ضغط صورة الصفحة.');

  // Bake EXIF orientation if needed
  final bakedPage = page.exif.imageIfd.orientation != null &&
          page.exif.imageIfd.orientation != 1
      ? img.bakeOrientation(page)
      : page;

  // Decode signature (PNG with alpha)
  final sig = img.decodeImage(sigBytes);
  if (sig == null) throw Exception('تعذر فك ضغط صورة التوقيع.');

  // Compute target dimensions for the signature
  final targetWidth = (bakedPage.width * relW).round().clamp(10, bakedPage.width);
  final aspectRatio = sig.height / sig.width;
  final targetHeight = (targetWidth * aspectRatio).round().clamp(1, bakedPage.height);

  // Resize signature
  final resizedSig = img.copyResize(
    sig,
    width: targetWidth,
    height: targetHeight,
    interpolation: img.Interpolation.linear,
  );

  // Compute pixel offsets (clamp so signature stays inside the page)
  final offsetX = (bakedPage.width * relX).round().clamp(0, bakedPage.width - targetWidth);
  final offsetY = (bakedPage.height * relY).round().clamp(0, bakedPage.height - targetHeight);

  // Composite — blends the transparent PNG on top of the page
  img.compositeImage(
    bakedPage,
    resizedSig,
    dstX: offsetX,
    dstY: offsetY,
  );

  debugPrint(
    '[SignatureComposer] Composited ${targetWidth}x${targetHeight}px sig at ($offsetX,$offsetY) on ${bakedPage.width}x${bakedPage.height}px page.',
  );

  return Uint8List.fromList(img.encodeJpg(bakedPage, quality: 92));
}
