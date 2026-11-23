import 'package:flutter/widgets.dart';

/// Computes a non-zero [Rect] anchor for iPad `UIActivityViewController` popovers.
///
/// iOS throws an `NSInvalidArgumentException` on iPad when `sharePositionOrigin`
/// is null or zero-sized; this falls back to a 1x1 center rect when the caller's
/// render object has no valid layout box.
Rect resolveSharePositionOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is RenderBox &&
      renderObject.hasSize &&
      renderObject.size.width > 0 &&
      renderObject.size.height > 0) {
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }
  final screenSize = MediaQuery.sizeOf(context);
  return Rect.fromCenter(
    center: screenSize.center(Offset.zero),
    width: 1,
    height: 1,
  );
}
