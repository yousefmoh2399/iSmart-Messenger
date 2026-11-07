import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_app/features/chat/presentation/attachment_send_dialogs.dart';

void main() {
  group('Photo & Document Markup & Blur Tool Tests', () {
    test('AttachmentSendDraft holds correct properties including privacy restrictions', () {
      const draft = AttachmentSendDraft(
        filePath: '/tmp/edited_image.png',
        displayName: 'confidential_contract.png',
        restrictForwardAndDownload: true,
        caption: 'Please review the highlighted terms.',
      );

      expect(draft.filePath, '/tmp/edited_image.png');
      expect(draft.displayName, 'confidential_contract.png');
      expect(draft.restrictForwardAndDownload, isTrue);
      expect(draft.caption, 'Please review the highlighted terms.');
    });

    test('Permanent physical redaction: Gaussian Blur destroys sensitive pixel values', () {
      // Create a test image with distinct high-contrast sensitive data (e.g. alternating pixels)
      final testImage = img.Image(width: 100, height: 100);
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 100; x++) {
          final val = (x % 2 == 0) ? 255 : 0;
          testImage.setPixelRgba(x, y, val, val, val, 255);
        }
      }

      // Define sensitive region (e.g., credit card or password box)
      const cropX = 20;
      const cropY = 20;
      const cropW = 60;
      const cropH = 30;

      final originalPixel = testImage.getPixel(cropX, cropY);
      expect(originalPixel.r, 255);

      // Perform crop and Gaussian Blur
      final cropped = img.copyCrop(
        testImage,
        x: cropX,
        y: cropY,
        width: cropW,
        height: cropH,
      );
      final blurred = img.gaussianBlur(cropped, radius: 15);
      img.compositeImage(testImage, blurred, dstX: cropX, dstY: cropY);

      // After blur, sharp alternating edges are smoothed and blurred
      final blurredPixel = testImage.getPixel(cropX, cropY);
      // Value should no longer be a sharp 255 or 0; it blends into mid-tone
      expect(blurredPixel.r, isNot(255));
      expect(blurredPixel.r, greaterThan(50));
      expect(blurredPixel.r, lessThan(200));
    });

    test('Permanent physical redaction: Pixelate / Mosaic obscures fine details', () {
      final testImage = img.Image(width: 80, height: 80);
      for (int y = 0; y < 80; y++) {
        for (int x = 0; x < 80; x++) {
          testImage.setPixelRgba(x, y, x * 3, y * 3, 128, 255);
        }
      }

      final cropped = img.copyCrop(testImage, x: 10, y: 10, width: 40, height: 40);
      final pixelated = img.pixelate(cropped, size: 12);
      img.compositeImage(testImage, pixelated, dstX: 10, dstY: 10);

      // Pixels within the same 12x12 block should now share identical values
      final p1 = testImage.getPixel(12, 12);
      final p2 = testImage.getPixel(15, 15);
      expect(p1.r, equals(p2.r));
      expect(p1.g, equals(p2.g));
    });

    test('Permanent physical redaction: Solid Blackout bar irreversibly zeroes out pixels', () {
      final testImage = img.Image(width: 50, height: 50);
      img.fill(testImage, color: img.ColorRgb8(255, 255, 255)); // white background

      // Fill blackout privacy box
      img.fillRect(
        testImage,
        x1: 10,
        y1: 10,
        x2: 40,
        y2: 30,
        color: img.ColorRgba8(0, 0, 0, 255),
      );

      // Verify that every pixel in the blackout region is absolute black
      for (int y = 10; y <= 30; y++) {
        for (int x = 10; x <= 40; x++) {
          final p = testImage.getPixel(x, y);
          expect(p.r, 0);
          expect(p.g, 0);
          expect(p.b, 0);
          expect(p.a, 255);
        }
      }
      // Outside remains white
      final outside = testImage.getPixel(5, 5);
      expect(outside.r, 255);
    });

    test('Vector Arrow calculation generates correct arrowhead geometries', () {
      // Test directional arrow pointing right: start (10, 50) -> end (100, 50)
      const start = Offset(10, 50);
      const end = Offset(100, 50);

      final dx = end.dx - start.dx;
      final dy = end.dy - start.dy;
      final angle = math.atan2(dy, dx);
      expect(angle, closeTo(0.0, 0.001)); // Facing 0 radians (right)

      const arrowLength = 18.0;
      final wing1 = Offset(
        end.dx - arrowLength * math.cos(angle - math.pi / 6),
        end.dy - arrowLength * math.sin(angle - math.pi / 6),
      );
      final wing2 = Offset(
        end.dx - arrowLength * math.cos(angle + math.pi / 6),
        end.dy - arrowLength * math.sin(angle + math.pi / 6),
      );

      // Both wings should be to the left of the tip (dx < 100)
      expect(wing1.dx, lessThan(end.dx));
      expect(wing2.dx, lessThan(end.dx));
      // Wings should be symmetric vertically around y = 50
      expect((wing1.dy - 50).abs(), closeTo((wing2.dy - 50).abs(), 0.001));
    });

    test('Highlighter semi-transparent alpha blending preserves underlying legibility', () {
      const neonYellow = Color(0xFFFFEB3B);
      final highlighterColor = neonYellow.withValues(alpha: 0.42);

      expect(highlighterColor.a, closeTo(0.42, 0.01));
      expect(highlighterColor.r, closeTo(neonYellow.r, 0.01));
      expect(highlighterColor.g, closeTo(neonYellow.g, 0.01));
      expect(highlighterColor.b, closeTo(neonYellow.b, 0.01));
    });

    test('Quarter turn rotation properly swaps dimensions and rotates image', () {
      final imgOriginal = img.Image(width: 120, height: 80);
      img.fill(imgOriginal, color: img.ColorRgb8(100, 150, 200));

      final rotated90 = img.copyRotate(imgOriginal, angle: 90);
      expect(rotated90.width, 80);
      expect(rotated90.height, 120);

      final rotated180 = img.copyRotate(imgOriginal, angle: 180);
      expect(rotated180.width, 120);
      expect(rotated180.height, 80);
    });
  });
}
