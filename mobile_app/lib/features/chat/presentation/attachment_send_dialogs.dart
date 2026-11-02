import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class _IsolateBlurJob {
  const _IsolateBlurJob({
    required this.fileBytes,
    required this.quarterTurns,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.regions,
  });

  final Uint8List fileBytes;
  final int quarterTurns;
  final double canvasWidth;
  final double canvasHeight;
  final List<_MarkupBlurRegion> regions;
}

Uint8List? _processRedactedImageInIsolate(_IsolateBlurJob job) {
  img.Image? decoded = img.decodeImage(job.fileBytes);
  if (decoded == null) return null;

  final turns = job.quarterTurns % 4;
  if (turns != 0) {
    decoded = img.copyRotate(decoded, angle: turns * 90);
  }

  const maxDimension = 2048;
  if (decoded.width > maxDimension || decoded.height > maxDimension) {
    if (decoded.width >= decoded.height) {
      decoded = img.copyResize(decoded, width: maxDimension);
    } else {
      decoded = img.copyResize(decoded, height: maxDimension);
    }
  }

  if (job.regions.isNotEmpty &&
      job.canvasWidth > 0 &&
      job.canvasHeight > 0) {
    final scaleX = decoded.width / job.canvasWidth;
    final scaleY = decoded.height / job.canvasHeight;

    for (final region in job.regions) {
      final rect = region.rect;
      final x1 = (rect.left * scaleX).round().clamp(0, decoded.width - 1);
      final y1 = (rect.top * scaleY).round().clamp(0, decoded.height - 1);
      final x2 = (rect.right * scaleX).round().clamp(0, decoded.width);
      final y2 = (rect.bottom * scaleY).round().clamp(0, decoded.height);

      final w = x2 - x1;
      final h = y2 - y1;
      if (w <= 0 || h <= 0) continue;

      if (region.style == _BlurStyle.blackout) {
        img.fillRect(
          decoded,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          color: img.ColorRgba8(0, 0, 0, 255),
        );
      } else if (region.style == _BlurStyle.mosaic) {
        final crop = img.copyCrop(decoded, x: x1, y: y1, width: w, height: h);
        final pixelSize = math.max(6, (math.min(w, h) / 7).round());
        final pixelated = img.pixelate(
          crop,
          size: pixelSize,
          mode: img.PixelateMode.average,
        );
        img.compositeImage(decoded, pixelated, dstX: x1, dstY: y1);
      } else {
        final crop = img.copyCrop(decoded, x: x1, y: y1, width: w, height: h);
        final blurRadius = math.max(8, (math.min(w, h) / 6).round());
        final blurred = img.gaussianBlur(crop, radius: blurRadius);
        img.compositeImage(decoded, blurred, dstX: x1, dstY: y1);
      }
    }
  }

  return img.encodePng(decoded);
}

class AttachmentSendDraft {
  const AttachmentSendDraft({
    required this.filePath,
    required this.displayName,
    required this.restrictForwardAndDownload,
    this.caption,
  });

  final String filePath;
  final String displayName;
  final bool restrictForwardAndDownload;
  final String? caption;
}

enum _MarkupTool {
  pen,
  highlighter,
  blur,
  arrow,
  circle,
  rectangle,
  text,
}

enum _BlurStyle {
  blur,
  mosaic,
  blackout,
}

class _MarkupStroke {
  const _MarkupStroke({
    required this.points,
    required this.color,
    required this.width,
    this.isHighlighter = false,
  });

  final List<Offset> points;
  final Color color;
  final double width;
  final bool isHighlighter;
}

class _MarkupShape {
  const _MarkupShape({
    required this.start,
    required this.end,
    required this.color,
    required this.width,
    required this.tool,
  });

  final Offset start;
  final Offset end;
  final Color color;
  final double width;
  final _MarkupTool tool;
}

class _MarkupBlurRegion {
  const _MarkupBlurRegion({
    required this.rect,
    required this.style,
  });

  final Rect rect;
  final _BlurStyle style;
}

class _MarkupTextAnnotation {
  _MarkupTextAnnotation({
    required this.id,
    required this.text,
    required this.position,
    required this.color,
    this.hasBackground = true,
  });

  final String id;
  String text;
  Offset position;
  Color color;
  bool hasBackground;
  double fontSize = 16.0;
}

class _MarkupTextAnnotationDialogResult {
  final String text;
  final Color color;
  final bool hasBackground;

  const _MarkupTextAnnotationDialogResult({
    required this.text,
    required this.color,
    required this.hasBackground,
  });
}

class _MarkupTextAnnotationDialog extends StatefulWidget {
  const _MarkupTextAnnotationDialog({
    required this.initialText,
    required this.initialColor,
    required this.initialHasBackground,
    required this.palette,
    required this.isEditing,
  });

  final String initialText;
  final Color initialColor;
  final bool initialHasBackground;
  final List<Color> palette;
  final bool isEditing;

  @override
  State<_MarkupTextAnnotationDialog> createState() =>
      _MarkupTextAnnotationDialogState();
}

class _MarkupTextAnnotationDialogState
    extends State<_MarkupTextAnnotationDialog> {
  late final TextEditingController _controller;
  late Color _textColor;
  late bool _hasBg;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _textColor = widget.initialColor;
    _hasBg = widget.initialHasBackground;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Row(
        children: [
          const Icon(
            Icons.text_fields_rounded,
            color: Color(0xFF007AFF),
            size: 24,
          ),
          const SizedBox(width: 8),
          Text(
            widget.isEditing ? 'تعديل النص' : 'إضافة نص توضيحي',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'اكتب ملاحظتك التوضيحية هنا...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'لون النص:',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: widget.palette.map((c) {
                  final isSel = _textColor == c;
                  return GestureDetector(
                    onTap: () => setState(() => _textColor = c),
                    child: Container(
                      margin: const EdgeInsets.only(left: 6),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSel
                              ? const Color(0xFF007AFF)
                              : Colors.black26,
                          width: isSel ? 3 : 1,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'خلفية داكنة لسهولة القراءة:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                CupertinoSwitch(
                  value: _hasBg,
                  onChanged: (val) => setState(() => _hasBg = val),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            final text = _controller.text.trim();
            if (text.isNotEmpty) {
              Navigator.pop(
                context,
                _MarkupTextAnnotationDialogResult(
                  text: text,
                  color: _textColor,
                  hasBackground: _hasBg,
                ),
              );
            }
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

enum _MarkupActionType {
  stroke,
  shape,
  blur,
  text,
}

class _MarkupAction {
  const _MarkupAction(this.type, this.data);
  final _MarkupActionType type;
  final dynamic data;
}

const Set<String> _imageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.webp',
  '.gif',
  '.bmp',
};

const Set<String> _videoExtensions = <String>{
  '.mp4',
  '.mov',
  '.avi',
  '.mkv',
  '.webm',
  '.3gp',
};

bool _isImagePath(String path) {
  final ext = p.extension(path).toLowerCase();
  return _imageExtensions.contains(ext);
}

bool _isVideoPath(String path) {
  final ext = p.extension(path).toLowerCase();
  return _videoExtensions.contains(ext);
}

String _formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Displays the WhatsApp/iOS-style attachment send flow with Quick Photo Markup & Blur Tool.
Future<AttachmentSendDraft?> showAttachmentSendDialog(
  BuildContext context,
  String originalPath,
) async {
  if (_isImagePath(originalPath)) {
    return showDialog<AttachmentSendDraft>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (_) => _WhatsAppMediaEditorDialog(imagePath: originalPath),
    );
  }

  return showDialog<AttachmentSendDraft>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _DocumentAttachmentSendDialog(filePath: originalPath),
  );
}

// =============================================================================
// WHATSAPP & APPLE STYLE PHOTO / DOCUMENT MARKUP & BLUR EDITOR
// =============================================================================

class _WhatsAppMediaEditorDialog extends StatefulWidget {
  const _WhatsAppMediaEditorDialog({required this.imagePath});

  final String imagePath;

  @override
  State<_WhatsAppMediaEditorDialog> createState() =>
      _WhatsAppMediaEditorDialogState();
}

class _WhatsAppMediaEditorDialogState
    extends State<_WhatsAppMediaEditorDialog> {
  ui.Image? _image;
  int _quarterTurns = 0;
  bool _isMarkupActive = false;
  _MarkupTool _tool = _MarkupTool.pen;
  _BlurStyle _activeBlurStyle = _BlurStyle.blur;

  Color _activeColor = const Color(0xFF25D366); // WhatsApp Green
  Color _activeHighlighterColor = const Color(0xFFFFEB3B); // Neon Yellow
  Color _activeTextColor = const Color(0xFFFFFFFF);
  bool _activeTextHasBackground = true;

  double _activeWidth = 5.0;
  double _activeHighlighterWidth = 24.0;
  bool _saving = false;
  bool _restrictForwardAndDownload = false;
  Size _canvasSize = Size.zero;

  final TextEditingController _captionController = TextEditingController();

  final List<_MarkupStroke> _strokes = <_MarkupStroke>[];
  final List<_MarkupShape> _shapes = <_MarkupShape>[];
  final List<_MarkupBlurRegion> _blurRegions = <_MarkupBlurRegion>[];
  final List<_MarkupTextAnnotation> _textAnnotations = <_MarkupTextAnnotation>[];
  final List<_MarkupAction> _actionHistory = <_MarkupAction>[];

  List<Offset>? _activeStroke;
  Offset? _shapeStart;
  Offset? _shapeEnd;
  Offset? _blurStart;
  Offset? _blurEnd;

  static const List<Color> _palette = <Color>[
    Color(0xFF25D366), // WhatsApp Emerald
    Color(0xFF34B7F1), // Sky Blue
    Color(0xFFFF3B30), // Red
    Color(0xFFFFD200), // Yellow
    Color(0xFFAF52DE), // Purple
    Color(0xFFFF9500), // Orange
    Color(0xFFFFFFFF), // White
    Color(0xFF1E293B), // Dark Slate
  ];

  static const List<Color> _highlighterPalette = <Color>[
    Color(0xFFFFEB3B), // Fluorescent Yellow
    Color(0xFF00E676), // Neon Green
    Color(0xFF00E5FF), // Sky Cyan
    Color(0xFFFF4081), // Hot Pink
    Color(0xFFFF9100), // Vivid Orange
  ];

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _image?.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image = frame.image;
      });
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  void _undo() {
    if (_actionHistory.isEmpty) return;
    HapticFeedback.selectionClick();
    final lastAction = _actionHistory.removeLast();
    setState(() {
      switch (lastAction.type) {
        case _MarkupActionType.stroke:
          if (_strokes.isNotEmpty) _strokes.removeLast();
          break;
        case _MarkupActionType.shape:
          if (_shapes.isNotEmpty) _shapes.removeLast();
          break;
        case _MarkupActionType.blur:
          if (_blurRegions.isNotEmpty) _blurRegions.removeLast();
          break;
        case _MarkupActionType.text:
          if (_textAnnotations.isNotEmpty) {
            final id = lastAction.data as String?;
            if (id != null) {
              _textAnnotations.removeWhere((t) => t.id == id);
            } else {
              _textAnnotations.removeLast();
            }
          }
          break;
      }
    });
  }

  void _clearAll() {
    HapticFeedback.mediumImpact();
    setState(() {
      _strokes.clear();
      _shapes.clear();
      _blurRegions.clear();
      _textAnnotations.clear();
      _actionHistory.clear();
      _activeStroke = null;
      _shapeStart = null;
      _shapeEnd = null;
      _blurStart = null;
      _blurEnd = null;
    });
  }

  void _quickSend() {
    HapticFeedback.lightImpact();
    final caption = _captionController.text.trim();
    Navigator.of(context).pop(
      AttachmentSendDraft(
        filePath: widget.imagePath,
        displayName: p.basename(widget.imagePath),
        restrictForwardAndDownload: _restrictForwardAndDownload,
        caption: caption.isNotEmpty ? caption : null,
      ),
    );
  }

  Future<void> _submitSend() async {
    if (_saving) return;
    HapticFeedback.mediumImpact();

    setState(() {
      _saving = true;
    });

    try {
      final finalPath = await _exportProcessedImage();
      if (!mounted) return;

      final caption = _captionController.text.trim();
      Navigator.of(context).pop(
        AttachmentSendDraft(
          filePath: finalPath,
          displayName: p.basename(finalPath),
          restrictForwardAndDownload: _restrictForwardAndDownload,
          caption: caption.isNotEmpty ? caption : null,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
      });
    }
  }

  Future<String> _exportProcessedImage() async {
    final image = _image;
    final hasEdits = _quarterTurns != 0 ||
        _strokes.isNotEmpty ||
        _shapes.isNotEmpty ||
        _blurRegions.isNotEmpty ||
        _textAnnotations.isNotEmpty;

    if (image == null || !hasEdits) {
      return widget.imagePath;
    }

    ui.Image? uiBaseImage;
    bool disposeBaseImage = false;
    try {
      double targetW;
      double targetH;
      final turns = _quarterTurns % 4;

      if (_blurRegions.isNotEmpty) {
        // Offload pixel redaction (Gaussian Blur / Pixelate / Blackout) to a background isolate
        // so the main UI thread stays 60fps responsive!
        final fileBytes = await File(widget.imagePath).readAsBytes();
        final processedBytes = await compute(
          _processRedactedImageInIsolate,
          _IsolateBlurJob(
            fileBytes: fileBytes,
            quarterTurns: turns,
            canvasWidth: _canvasSize.width,
            canvasHeight: _canvasSize.height,
            regions: List<_MarkupBlurRegion>.from(_blurRegions),
          ),
        );
        if (processedBytes == null) {
          return widget.imagePath;
        }
        final codec = await ui.instantiateImageCodec(processedBytes);
        final frame = await codec.getNextFrame();
        uiBaseImage = frame.image;
        disposeBaseImage = true;
        codec.dispose();
        targetW = uiBaseImage.width.toDouble();
        targetH = uiBaseImage.height.toDouble();
      } else {
        // Fast-path: No pixel redaction needed! Render directly from hardware-decoded _image on GPU Canvas!
        uiBaseImage = image;
        disposeBaseImage = false;
        final isRotatedQuarter = (turns % 2) != 0;
        final rawW = (isRotatedQuarter ? image.height : image.width).toDouble();
        final rawH = (isRotatedQuarter ? image.width : image.height).toDouble();
        const maxDimension = 2048.0;
        final longest = math.max(rawW, rawH);
        final exportScale =
            longest > maxDimension ? (maxDimension / longest) : 1.0;
        targetW = math.max(1.0, (rawW * exportScale).roundToDouble());
        targetH = math.max(1.0, (rawH * exportScale).roundToDouble());
      }

      // Draw base image + vector annotations (strokes, highlighters, shapes, arrows, texts) on GPU Canvas
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, targetW, targetH),
      );

      if (_blurRegions.isNotEmpty) {
        canvas.drawImage(uiBaseImage, Offset.zero, Paint());
      } else {
        canvas.save();
        final isRotatedQuarter = (turns % 2) != 0;
        final dstImageW = isRotatedQuarter ? targetH : targetW;
        final dstImageH = isRotatedQuarter ? targetW : targetH;
        if (turns == 1) {
          canvas.translate(targetW, 0);
          canvas.rotate(math.pi / 2);
        } else if (turns == 2) {
          canvas.translate(targetW, targetH);
          canvas.rotate(math.pi);
        } else if (turns == 3) {
          canvas.translate(0, targetH);
          canvas.rotate(3 * math.pi / 2);
        }
        canvas.drawImageRect(
          uiBaseImage,
          Rect.fromLTWH(
            0,
            0,
            uiBaseImage.width.toDouble(),
            uiBaseImage.height.toDouble(),
          ),
          Rect.fromLTWH(0, 0, dstImageW, dstImageH),
          Paint()..filterQuality = FilterQuality.medium,
        );
        canvas.restore();
      }

      final scaleX = _canvasSize.width > 0 ? targetW / _canvasSize.width : 1.0;
      final scaleY = _canvasSize.height > 0 ? targetH / _canvasSize.height : 1.0;
      final avgScale = (scaleX + scaleY) / 2;

      // Highlighters
      for (final stroke in _strokes.where((s) => s.isHighlighter)) {
        if (stroke.points.length < 2) continue;
        final path = Path()
          ..moveTo(
            stroke.points.first.dx * scaleX,
            stroke.points.first.dy * scaleY,
          );
        for (final pt in stroke.points.skip(1)) {
          path.lineTo(pt.dx * scaleX, pt.dy * scaleY);
        }
        final paint = Paint()
          ..color = stroke.color.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = stroke.width * avgScale * 3.4;
        canvas.drawPath(path, paint);
      }

      // Normal Pen Strokes
      for (final stroke in _strokes.where((s) => !s.isHighlighter)) {
        if (stroke.points.length < 2) continue;
        final path = Path()
          ..moveTo(
            stroke.points.first.dx * scaleX,
            stroke.points.first.dy * scaleY,
          );
        for (final pt in stroke.points.skip(1)) {
          path.lineTo(pt.dx * scaleX, pt.dy * scaleY);
        }
        final paint = Paint()
          ..color = stroke.color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = stroke.width * avgScale;
        canvas.drawPath(path, paint);
      }

      // Shapes (Circles, Rectangles, Arrows)
      for (final shape in _shapes) {
        final start = Offset(shape.start.dx * scaleX, shape.start.dy * scaleY);
        final end = Offset(shape.end.dx * scaleX, shape.end.dy * scaleY);
        final paint = Paint()
          ..color = shape.color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = shape.width * avgScale;

        if (shape.tool == _MarkupTool.circle) {
          canvas.drawOval(Rect.fromPoints(start, end), paint);
        } else if (shape.tool == _MarkupTool.rectangle) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromPoints(start, end),
              Radius.circular(8 * avgScale),
            ),
            paint,
          );
        } else if (shape.tool == _MarkupTool.arrow) {
          canvas.drawLine(start, end, paint);
          final dist = (end - start).distance;
          if (dist >= 10) {
            final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
            final arrowHeadSize = math.min(24.0 * avgScale, dist * 0.4);
            const arrowAngle = math.pi / 6;

            final p1 = Offset(
              end.dx - arrowHeadSize * math.cos(angle - arrowAngle),
              end.dy - arrowHeadSize * math.sin(angle - arrowAngle),
            );
            final p2 = Offset(
              end.dx - arrowHeadSize * math.cos(angle + arrowAngle),
              end.dy - arrowHeadSize * math.sin(angle + arrowAngle),
            );

            final headPath = Path()
              ..moveTo(p1.dx, p1.dy)
              ..lineTo(end.dx, end.dy)
              ..lineTo(p2.dx, p2.dy);
            canvas.drawPath(headPath, paint);
          }
        }
      }

      // Text Annotations
      for (final textAnn in _textAnnotations) {
        final scaledPos = Offset(
          textAnn.position.dx * scaleX,
          textAnn.position.dy * scaleY,
        );
        final fontSize = textAnn.fontSize * avgScale;

        final textSpan = TextSpan(
          text: textAnn.text,
          style: TextStyle(
            color: textAnn.color,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.rtl,
        )..layout();

        final paddingH = 10.0 * avgScale;
        final paddingV = 5.0 * avgScale;
        final badgeRect = Rect.fromLTWH(
          scaledPos.dx,
          scaledPos.dy,
          textPainter.width + paddingH * 2,
          textPainter.height + paddingV * 2,
        );

        if (textAnn.hasBackground) {
          final bgPaint = Paint()..color = const Color(0xCC000000);
          final borderPaint = Paint()
            ..color = const Color(0x40FFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0 * avgScale;
          final rrect = RRect.fromRectAndRadius(
            badgeRect,
            Radius.circular(8 * avgScale),
          );
          canvas.drawRRect(rrect, bgPaint);
          canvas.drawRRect(rrect, borderPaint);
        }

        textPainter.paint(
          canvas,
          Offset(scaledPos.dx + paddingH, scaledPos.dy + paddingV),
        );
      }

      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(
        targetW.toInt(),
        targetH.toInt(),
      );
      picture.dispose();
      final finalByteData =
          await finalImage.toByteData(format: ui.ImageByteFormat.png);
      finalImage.dispose();
      if (finalByteData == null) {
        return widget.imagePath;
      }

      final outBytes = finalByteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final outputPath = p.join(
        tempDir.path,
        'ismart_markup_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await File(outputPath).writeAsBytes(outBytes, flush: true);
      return outputPath;
    } catch (_) {
      return widget.imagePath;
    } finally {
      if (disposeBaseImage) {
        uiBaseImage?.dispose();
      }
    }
  }

  Offset _clampPoint(Offset local) {
    return Offset(
      local.dx.clamp(0, _canvasSize.width).toDouble(),
      local.dy.clamp(0, _canvasSize.height).toDouble(),
    );
  }

  Future<void> _showAddTextDialog({
    Offset? position,
    _MarkupTextAnnotation? existing,
  }) async {
    HapticFeedback.selectionClick();

    final result = await showDialog<_MarkupTextAnnotationDialogResult>(
      context: context,
      builder: (ctx) => _MarkupTextAnnotationDialog(
        initialText: existing?.text ?? '',
        initialColor: existing?.color ?? _activeTextColor,
        initialHasBackground:
            existing?.hasBackground ?? _activeTextHasBackground,
        palette: _palette,
        isEditing: existing != null,
      ),
    );

    if (result != null && result.text.isNotEmpty) {
      setState(() {
        _activeTextColor = result.color;
        _activeTextHasBackground = result.hasBackground;

        if (existing != null) {
          existing.text = result.text;
          existing.color = result.color;
          existing.hasBackground = result.hasBackground;
        } else {
          final newId = DateTime.now().microsecondsSinceEpoch.toString();
          final defaultPos = position ??
              Offset(
                math.max(16, (_canvasSize.width - 160) / 2),
                math.max(16, (_canvasSize.height - 40) / 2),
              );
          final ann = _MarkupTextAnnotation(
            id: newId,
            text: result.text,
            position: defaultPos,
            color: result.color,
            hasBackground: result.hasBackground,
          );
          _textAnnotations.add(ann);
          _actionHistory.add(_MarkupAction(_MarkupActionType.text, newId));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B141B),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF25D366)),
        ),
      );
    }

    final isRotatedQuarter = (_quarterTurns % 2) != 0;
    final effectiveSourceSize = Size(
      isRotatedQuarter ? image.height.toDouble() : image.width.toDouble(),
      isRotatedQuarter ? image.width.toDouble() : image.height.toDouble(),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0B141B),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // -------------------------------------------------------------
            // TOP BAR: Cancel, Quick Send, Rotate, Markup Toggle, Undo
            // -------------------------------------------------------------
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: const Color(0xFF0B141B).withValues(alpha: 0.9),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    tooltip: 'إلغاء',
                  ),
                  const Spacer(),
                  // Quick Send Button
                  InkWell(
                    onTap: _saving ? null : _quickSend,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.bolt_rounded,
                            color: Color(0xFFF59E0B),
                            size: 18,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'إرسال سريع',
                            style: TextStyle(
                              color: Color(0xFFFBBF24),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Rotate 90°
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _quarterTurns = (_quarterTurns + 1) % 4;
                            });
                          },
                    icon: const Icon(
                      Icons.rotate_90_degrees_cw_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    tooltip: 'تدوير 90°',
                  ),
                  // Markup Draw Tool Toggle
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _isMarkupActive = !_isMarkupActive;
                            });
                          },
                    icon: Icon(
                      Icons.edit_rounded,
                      color: _isMarkupActive
                          ? const Color(0xFF25D366)
                          : Colors.white,
                      size: 24,
                    ),
                    tooltip: 'رسم وتوضيح',
                  ),
                  if (_isMarkupActive && _actionHistory.isNotEmpty) ...[
                    IconButton(
                      onPressed: _saving ? null : _undo,
                      icon: const Icon(
                        Icons.undo_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      tooltip: 'تراجع',
                    ),
                    IconButton(
                      onPressed: _saving ? null : _clearAll,
                      icon: const Icon(
                        Icons.delete_sweep_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      tooltip: 'مسح الكل',
                    ),
                  ],
                ],
              ),
            ),

            // -------------------------------------------------------------
            // MARKUP TOOLBAR & SUB-BAR (WHEN ACTIVE)
            // -------------------------------------------------------------
            if (_isMarkupActive) ...[
              Container(
                color: const Color(0xFF1F2C34),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Row 1: Tool Selector
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          _buildToolChip(
                            tool: _MarkupTool.pen,
                            label: 'قلم',
                            icon: Icons.edit_outlined,
                          ),
                          _buildToolChip(
                            tool: _MarkupTool.highlighter,
                            label: 'تظليل نصوص',
                            icon: Icons.highlight_rounded,
                          ),
                          _buildToolChip(
                            tool: _MarkupTool.blur,
                            label: 'تمويه وحجب',
                            icon: Icons.blur_on_rounded,
                          ),
                          _buildToolChip(
                            tool: _MarkupTool.arrow,
                            label: 'سهم',
                            icon: Icons.arrow_right_alt_rounded,
                          ),
                          _buildToolChip(
                            tool: _MarkupTool.circle,
                            label: 'دائرة',
                            icon: Icons.circle_outlined,
                          ),
                          _buildToolChip(
                            tool: _MarkupTool.rectangle,
                            label: 'مستطيل',
                            icon: Icons.crop_square_rounded,
                          ),
                          _buildToolChip(
                            tool: _MarkupTool.text,
                            label: 'نص توضيحي',
                            icon: Icons.text_fields_rounded,
                          ),
                        ],
                      ),
                    ),
                    // Row 2: Sub-options
                    _buildSubToolBar(),
                  ],
                ),
              ),
            ],

            // -------------------------------------------------------------
            // MAIN VIEW: Image + Blurs + CustomPaint + Text Annotations
            // -------------------------------------------------------------
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fitted = applyBoxFit(
                    BoxFit.contain,
                    effectiveSourceSize,
                    Size(constraints.maxWidth, constraints.maxHeight),
                  );
                  final renderSize = fitted.destination;
                  _canvasSize = renderSize;

                  return Center(
                    child: SizedBox(
                      width: renderSize.width,
                      height: renderSize.height,
                      child: GestureDetector(
                        behavior: _isMarkupActive
                            ? HitTestBehavior.opaque
                            : HitTestBehavior.deferToChild,
                        onTapUp: _isMarkupActive && _tool == _MarkupTool.text
                            ? (details) => _showAddTextDialog(
                                  position: _clampPoint(details.localPosition),
                                )
                            : null,
                        onPanStart: _isMarkupActive
                            ? (details) {
                                final point = _clampPoint(details.localPosition);
                                setState(() {
                                  if (_tool == _MarkupTool.pen ||
                                      _tool == _MarkupTool.highlighter) {
                                    _activeStroke = <Offset>[point];
                                  } else if (_tool == _MarkupTool.blur) {
                                    _blurStart = point;
                                    _blurEnd = point;
                                  } else if (_tool == _MarkupTool.arrow ||
                                      _tool == _MarkupTool.circle ||
                                      _tool == _MarkupTool.rectangle) {
                                    _shapeStart = point;
                                    _shapeEnd = point;
                                  }
                                });
                              }
                            : null,
                        onPanUpdate: _isMarkupActive
                            ? (details) {
                                final point = _clampPoint(details.localPosition);
                                setState(() {
                                  if (_tool == _MarkupTool.pen ||
                                      _tool == _MarkupTool.highlighter) {
                                    _activeStroke?.add(point);
                                  } else if (_tool == _MarkupTool.blur) {
                                    _blurEnd = point;
                                  } else if (_tool == _MarkupTool.arrow ||
                                      _tool == _MarkupTool.circle ||
                                      _tool == _MarkupTool.rectangle) {
                                    _shapeEnd = point;
                                  }
                                });
                              }
                            : null,
                        onPanEnd: _isMarkupActive
                            ? (_) {
                                setState(() {
                                  if (_tool == _MarkupTool.pen ||
                                      _tool == _MarkupTool.highlighter) {
                                    final points = _activeStroke;
                                    if (points != null && points.length > 1) {
                                      final isHigh =
                                          _tool == _MarkupTool.highlighter;
                                      _strokes.add(
                                        _MarkupStroke(
                                          points: List<Offset>.from(points),
                                          color: isHigh
                                              ? _activeHighlighterColor
                                              : _activeColor,
                                          width: isHigh
                                              ? _activeHighlighterWidth
                                              : _activeWidth,
                                          isHighlighter: isHigh,
                                        ),
                                      );
                                      _actionHistory.add(
                                        const _MarkupAction(
                                          _MarkupActionType.stroke,
                                          null,
                                        ),
                                      );
                                    }
                                    _activeStroke = null;
                                  } else if (_tool == _MarkupTool.blur) {
                                    final start = _blurStart;
                                    final end = _blurEnd;
                                    if (start != null &&
                                        end != null &&
                                        (start - end).distance >= 8) {
                                      final rect = Rect.fromPoints(start, end);
                                      _blurRegions.add(
                                        _MarkupBlurRegion(
                                          rect: rect,
                                          style: _activeBlurStyle,
                                        ),
                                      );
                                      _actionHistory.add(
                                        const _MarkupAction(
                                          _MarkupActionType.blur,
                                          null,
                                        ),
                                      );
                                    }
                                    _blurStart = null;
                                    _blurEnd = null;
                                  } else if (_tool == _MarkupTool.arrow ||
                                      _tool == _MarkupTool.circle ||
                                      _tool == _MarkupTool.rectangle) {
                                    final start = _shapeStart;
                                    final end = _shapeEnd;
                                    if (start != null &&
                                        end != null &&
                                        (start - end).distance >= 8) {
                                      _shapes.add(
                                        _MarkupShape(
                                          start: start,
                                          end: end,
                                          color: _activeColor,
                                          width: _activeWidth,
                                          tool: _tool,
                                        ),
                                      );
                                      _actionHistory.add(
                                        const _MarkupAction(
                                          _MarkupActionType.shape,
                                          null,
                                        ),
                                      );
                                    }
                                    _shapeStart = null;
                                    _shapeEnd = null;
                                  }
                                });
                              }
                            : null,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 1. The rotated base image
                            Center(
                              child: RotatedBox(
                                quarterTurns: _quarterTurns,
                                child: Image.file(
                                  File(widget.imagePath),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),

                            // 2. Live Frosted Blurs overlay
                            for (final blur in _blurRegions)
                              Positioned.fromRect(
                                rect: blur.rect,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: blur.style == _BlurStyle.blackout
                                      ? Container(
                                          color: Colors.black,
                                          child: const Center(
                                            child: Icon(
                                              Icons.lock_rounded,
                                              color: Colors.white54,
                                              size: 14,
                                            ),
                                          ),
                                        )
                                      : BackdropFilter(
                                          filter: ui.ImageFilter.blur(
                                            sigmaX:
                                                blur.style == _BlurStyle.mosaic
                                                    ? 18
                                                    : 12,
                                            sigmaY:
                                                blur.style == _BlurStyle.mosaic
                                                    ? 18
                                                    : 12,
                                          ),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: blur.style ==
                                                      _BlurStyle.mosaic
                                                  ? Colors.black
                                                      .withValues(alpha: 0.35)
                                                  : Colors.white
                                                      .withValues(alpha: 0.12),
                                              border: Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.35),
                                                width: 1,
                                              ),
                                            ),
                                            child: Center(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 5,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.45),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      blur.style ==
                                                              _BlurStyle.mosaic
                                                          ? Icons
                                                              .grid_view_rounded
                                                          : Icons
                                                              .blur_on_rounded,
                                                      color: Colors.white,
                                                      size: 11,
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      blur.style ==
                                                              _BlurStyle.mosaic
                                                          ? 'بيكسل'
                                                          : 'تمويه',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 9.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                              ),

                            // 3. Custom Canvas for drawing & vectors
                            CustomPaint(
                              painter: _MarkupCanvasPainter(
                                strokes: _strokes,
                                shapes: _shapes,
                                activeStroke: _activeStroke,
                                activeShapeStart: _shapeStart,
                                activeShapeEnd: _shapeEnd,
                                activeShapeTool: _tool,
                                activeBlurStart: _blurStart,
                                activeBlurEnd: _blurEnd,
                                activeColor: _tool == _MarkupTool.highlighter
                                    ? _activeHighlighterColor
                                    : _activeColor,
                                activeWidth: _tool == _MarkupTool.highlighter
                                    ? _activeHighlighterWidth
                                    : _activeWidth,
                                isHighlighter:
                                    _tool == _MarkupTool.highlighter,
                              ),
                            ),

                            // 4. Interactive draggable Text Annotations
                            for (final ann in _textAnnotations)
                              Positioned(
                                left: ann.position.dx,
                                top: ann.position.dy,
                                child: GestureDetector(
                                  onPanUpdate: (details) {
                                    setState(() {
                                      ann.position = Offset(
                                        (ann.position.dx + details.delta.dx)
                                            .clamp(
                                          0,
                                          math.max(
                                            0,
                                            _canvasSize.width - 60,
                                          ),
                                        ),
                                        (ann.position.dy + details.delta.dy)
                                            .clamp(
                                          0,
                                          math.max(
                                            0,
                                            _canvasSize.height - 30,
                                          ),
                                        ),
                                      );
                                    });
                                  },
                                  onTap: () =>
                                      _showAddTextDialog(existing: ann),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ann.hasBackground
                                          ? Colors.black
                                              .withValues(alpha: 0.72)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: ann.hasBackground
                                            ? Colors.white
                                                .withValues(alpha: 0.25)
                                            : Colors.transparent,
                                        width: 0.8,
                                      ),
                                      boxShadow: ann.hasBackground
                                          ? [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.3),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          ann.text,
                                          style: TextStyle(
                                            color: ann.color,
                                            fontSize: ann.fontSize,
                                            fontWeight: FontWeight.w700,
                                            shadows: ann.hasBackground
                                                ? null
                                                : const [
                                                    Shadow(
                                                      color: Colors.black87,
                                                      blurRadius: 4,
                                                      offset: Offset(1, 1),
                                                    ),
                                                  ],
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            setState(() {
                                              _textAnnotations.removeWhere(
                                                (t) => t.id == ann.id,
                                              );
                                              _actionHistory.removeWhere(
                                                (a) => a.data == ann.id,
                                              );
                                            });
                                          },
                                          child: const Icon(
                                            Icons.cancel_rounded,
                                            color: Colors.white70,
                                            size: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // -------------------------------------------------------------
            // BOTTOM BAR: Per-Message Security Pill + Caption & Send
            // -------------------------------------------------------------
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0B141B).withValues(alpha: 0.95),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Forward Protection Capsule
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _restrictForwardAndDownload =
                            !_restrictForwardAndDownload;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _restrictForwardAndDownload
                            ? const Color(0xFF059669).withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _restrictForwardAndDownload
                              ? const Color(0xFF10B981)
                              : Colors.white24,
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _restrictForwardAndDownload
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            size: 15,
                            color: _restrictForwardAndDownload
                                ? const Color(0xFF34D399)
                                : Colors.white70,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _restrictForwardAndDownload
                                ? '🔒 محتوى محمي: منع إعادة التوجيه (لهذه الرسالة فقط)'
                                : '🔓 مسموح بإعادة التوجيه · اضغط للقفل (لهذه الرسالة فقط)',
                            style: TextStyle(
                              color: _restrictForwardAndDownload
                                  ? const Color(0xFF34D399)
                                  : Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 2. Caption Input & Circular Green Send Button
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F2C34),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _captionController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                            maxLines: 4,
                            minLines: 1,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _submitSend(),
                            decoration: const InputDecoration(
                              hintText: 'إضافة شرح... (أو اضغط إرسال)',
                              hintStyle: TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        onTap: _saving ? null : _submitSend,
                        borderRadius: BorderRadius.circular(25),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: Color(0xFF25D366),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: _saving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.send_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolChip({
    required _MarkupTool tool,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _tool == tool;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _tool = tool);
          if (tool == _MarkupTool.text && _textAnnotations.isEmpty) {
            _showAddTextDialog();
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF25D366)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubToolBar() {
    if (_tool == _MarkupTool.blur) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildBlurStyleChip(
                  style: _BlurStyle.blur,
                  label: '🌫️ تمويه بلوري',
                ),
                const SizedBox(width: 8),
                _buildBlurStyleChip(
                  style: _BlurStyle.mosaic,
                  label: '🔲 فسيفساء بيكسل',
                ),
                const SizedBox(width: 8),
                _buildBlurStyleChip(
                  style: _BlurStyle.blackout,
                  label: '⬛ حجب كامل',
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'اسحب إصبعك فوق الأرقام أو البيانات الحساسة لطمسها',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      );
    }

    if (_tool == _MarkupTool.highlighter) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: Row(
          children: [
            const Text(
              'تظليل:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _highlighterPalette.map((color) {
                    final isSel = _activeHighlighterColor == color;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _activeHighlighterColor = color);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSel ? Colors.white : Colors.transparent,
                            width: 2.2,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Width selector for highlighter
            GestureDetector(
              onTap: () {
                setState(() {
                  _activeHighlighterWidth =
                      _activeHighlighterWidth == 24.0 ? 34.0 : 24.0;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _activeHighlighterWidth == 24.0 ? 'عرض متوسط' : 'عرض عريض',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_tool == _MarkupTool.text) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: Row(
          children: [
            InkWell(
              onTap: () => _showAddTextDialog(),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'إضافة نص جديد',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'اضغط على أي نص لتحريكه أو تعديله',
                style: TextStyle(color: Colors.white54, fontSize: 11.5),
              ),
            ),
          ],
        ),
      );
    }

    // Default palette for Pen, Arrow, Shapes
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _palette.map((color) {
                  final isSelected = _activeColor == color;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _activeColor = color);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2.2,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.6),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Stroke width toggle
          GestureDetector(
            onTap: () {
              setState(() {
                if (_activeWidth == 3.0) {
                  _activeWidth = 5.0;
                } else if (_activeWidth == 5.0) {
                  _activeWidth = 8.0;
                } else {
                  _activeWidth = 3.0;
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _activeWidth == 3.0
                    ? 'خط رفيع'
                    : _activeWidth == 5.0
                        ? 'خط متوسط'
                        : 'خط عريض',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlurStyleChip({
    required _BlurStyle style,
    required String label,
  }) {
    final isSel = _activeBlurStyle == style;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _activeBlurStyle = style);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSel
              ? const Color(0xFF007AFF)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// DOCUMENT & VIDEO ATTACHMENT DIALOG
// =============================================================================

class _DocumentAttachmentSendDialog extends StatefulWidget {
  const _DocumentAttachmentSendDialog({required this.filePath});

  final String filePath;

  @override
  State<_DocumentAttachmentSendDialog> createState() =>
      _DocumentAttachmentSendDialogState();
}

class _DocumentAttachmentSendDialogState
    extends State<_DocumentAttachmentSendDialog> {
  late TextEditingController _nameController;
  final TextEditingController _captionController = TextEditingController();
  bool _restrictForwardAndDownload = false;
  int _fileBytes = 0;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: p.basename(widget.filePath));
    _readFileSize();
  }

  Future<void> _readFileSize() async {
    try {
      final size = await File(widget.filePath).length();
      if (!mounted) return;
      setState(() {
        _fileBytes = size;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  void _quickSend() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(
      AttachmentSendDraft(
        filePath: widget.filePath,
        displayName: p.basename(widget.filePath),
        restrictForwardAndDownload: _restrictForwardAndDownload,
        caption: _captionController.text.trim().isNotEmpty
            ? _captionController.text.trim()
            : null,
      ),
    );
  }

  void _submit() {
    final rawName = _nameController.text.trim();
    final fallbackName = p.basename(widget.filePath);
    final caption = _captionController.text.trim();

    Navigator.of(context).pop(
      AttachmentSendDraft(
        filePath: widget.filePath,
        displayName: rawName.isEmpty ? fallbackName : rawName,
        restrictForwardAndDownload: _restrictForwardAndDownload,
        caption: caption.isNotEmpty ? caption : null,
      ),
    );
  }

  IconData _getFileIcon() {
    final ext = p.extension(widget.filePath).toLowerCase();
    if (_isVideoPath(widget.filePath)) return Icons.video_file_rounded;
    if (ext == '.pdf') return Icons.picture_as_pdf_rounded;
    if (ext == '.doc' || ext == '.docx') return Icons.description_rounded;
    if (ext == '.xls' || ext == '.xlsx') return Icons.table_chart_rounded;
    if (ext == '.zip' || ext == '.rar' || ext == '.7z') {
      return Icons.folder_zip_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileColor() {
    final ext = p.extension(widget.filePath).toLowerCase();
    if (_isVideoPath(widget.filePath)) return const Color(0xFF8B5CF6);
    if (ext == '.pdf') return const Color(0xFFEF4444);
    if (ext == '.doc' || ext == '.docx') return const Color(0xFF3B82F6);
    if (ext == '.xls' || ext == '.xlsx') return const Color(0xFF10B981);
    if (ext == '.zip' || ext == '.rar') return const Color(0xFFF59E0B);
    return const Color(0xFF6B7280);
  }

  @override
  Widget build(BuildContext context) {
    final fileColor = _getFileColor();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isImageDoc = _isImagePath(widget.filePath);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: fileColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_getFileIcon(), color: fileColor, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إرسال مرفق',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
                if (_fileBytes > 0)
                  Text(
                    _formatFileSize(_fileBytes),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Markup & Blur option button if file is editable as image
              if (isImageDoc) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    final edited = await showDialog<AttachmentSendDraft>(
                      context: context,
                      barrierDismissible: false,
                      useSafeArea: false,
                      builder: (_) =>
                          _WhatsAppMediaEditorDialog(imagePath: widget.filePath),
                    );
                    if (edited != null && mounted) {
                      navigator.pop(edited);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF)
                          .withValues(alpha: isDark ? 0.2 : 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            const Color(0xFF007AFF).withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.edit_note_rounded,
                          color: Color(0xFF007AFF),
                          size: 22,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تعديل وتمويه المستند (تظليل، حجب، أسهم)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: Color(0xFF007AFF),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'فتح أداة التحرير السريعة للتظليل أو طمس الأرقام السرية',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_left_rounded,
                          color: Color(0xFF007AFF),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              // File name editor
              TextFormField(
                controller: _nameController,
                maxLines: 1,
                decoration: InputDecoration(
                  labelText: 'اسم الملف',
                  prefixIcon: const Icon(
                    Icons.drive_file_rename_outline_rounded,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Caption input
              TextFormField(
                controller: _captionController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'إضافة شرح أو ملاحظة (اختياري)',
                  prefixIcon: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Per-message forward protection pill
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _restrictForwardAndDownload =
                        !_restrictForwardAndDownload;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _restrictForwardAndDownload
                        ? const Color(0xFF059669)
                            .withValues(alpha: isDark ? 0.25 : 0.12)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _restrictForwardAndDownload
                          ? const Color(0xFF10B981)
                          : (isDark
                              ? Colors.white12
                              : const Color(0xFFE2E8F0)),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _restrictForwardAndDownload
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        size: 20,
                        color: _restrictForwardAndDownload
                            ? const Color(0xFF10B981)
                            : (isDark ? Colors.white60 : Colors.black54),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _restrictForwardAndDownload
                                  ? '🔒 محتوى محمي (لهذه الرسالة فقط)'
                                  : '🔓 مسموح بإعادة التوجيه (لهذه الرسالة فقط)',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: _restrictForwardAndDownload
                                    ? const Color(0xFF10B981)
                                    : (isDark
                                        ? Colors.white
                                        : const Color(0xFF0F172A)),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _restrictForwardAndDownload
                                  ? 'منع التحميل وإعادة التوجيه لهذا الملف فقط'
                                  : 'اضغط للقفل ومنع التحميل أو إعادة التوجيه',
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        OutlinedButton.icon(
          onPressed: _quickSend,
          icon: const Icon(Icons.bolt_rounded, size: 18),
          label: const Text('إرسال سريع'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('إرسال'),
        ),
      ],
    );
  }
}

// =============================================================================
// MARKUP CANVAS PAINTER
// =============================================================================

class _MarkupCanvasPainter extends CustomPainter {
  const _MarkupCanvasPainter({
    required this.strokes,
    required this.shapes,
    required this.activeStroke,
    required this.activeShapeStart,
    required this.activeShapeEnd,
    required this.activeShapeTool,
    required this.activeBlurStart,
    required this.activeBlurEnd,
    required this.activeColor,
    required this.activeWidth,
    required this.isHighlighter,
  });

  final List<_MarkupStroke> strokes;
  final List<_MarkupShape> shapes;
  final List<Offset>? activeStroke;
  final Offset? activeShapeStart;
  final Offset? activeShapeEnd;
  final _MarkupTool? activeShapeTool;
  final Offset? activeBlurStart;
  final Offset? activeBlurEnd;
  final Color activeColor;
  final double activeWidth;
  final bool isHighlighter;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Highlighters (bottom layer)
    for (final stroke in strokes.where((s) => s.isHighlighter)) {
      _paintHighlighter(
        canvas,
        stroke.points,
        stroke.color,
        stroke.width,
      );
    }

    // 2. Normal Pen Strokes
    for (final stroke in strokes.where((s) => !s.isHighlighter)) {
      _paintStroke(canvas, stroke.points, stroke.color, stroke.width);
    }

    // 3. Shapes
    for (final shape in shapes) {
      if (shape.tool == _MarkupTool.circle) {
        _paintCircle(
          canvas,
          shape.start,
          shape.end,
          shape.color,
          shape.width,
        );
      } else if (shape.tool == _MarkupTool.rectangle) {
        _paintRectangle(
          canvas,
          shape.start,
          shape.end,
          shape.color,
          shape.width,
        );
      } else if (shape.tool == _MarkupTool.arrow) {
        _paintArrow(
          canvas,
          shape.start,
          shape.end,
          shape.color,
          shape.width,
        );
      }
    }

    // 4. Live Active Stroke
    final liveStroke = activeStroke;
    if (liveStroke != null && liveStroke.length > 1) {
      if (isHighlighter) {
        _paintHighlighter(canvas, liveStroke, activeColor, activeWidth);
      } else {
        _paintStroke(canvas, liveStroke, activeColor, activeWidth);
      }
    }

    // 5. Live Active Shape
    if (activeShapeStart != null &&
        activeShapeEnd != null &&
        activeShapeTool != null) {
      if (activeShapeTool == _MarkupTool.circle) {
        _paintCircle(
          canvas,
          activeShapeStart!,
          activeShapeEnd!,
          activeColor,
          activeWidth,
        );
      } else if (activeShapeTool == _MarkupTool.rectangle) {
        _paintRectangle(
          canvas,
          activeShapeStart!,
          activeShapeEnd!,
          activeColor,
          activeWidth,
        );
      } else if (activeShapeTool == _MarkupTool.arrow) {
        _paintArrow(
          canvas,
          activeShapeStart!,
          activeShapeEnd!,
          activeColor,
          activeWidth,
        );
      }
    }

    // 6. Live Active Blur Drag Box
    if (activeBlurStart != null && activeBlurEnd != null) {
      final rect = Rect.fromPoints(activeBlurStart!, activeBlurEnd!);
      final previewPaint = Paint()
        ..color = const Color(0x66007AFF)
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = const Color(0xFF007AFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rrect, previewPaint);
      canvas.drawRRect(rrect, borderPaint);
    }
  }

  void _paintStroke(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
  ) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final pt in points.skip(1)) {
      path.lineTo(pt.dx, pt.dy);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width;
    canvas.drawPath(path, paint);
  }

  void _paintHighlighter(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
  ) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final pt in points.skip(1)) {
      path.lineTo(pt.dx, pt.dy);
    }
    final paint = Paint()
      ..color = color.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width * 1.35;
    canvas.drawPath(path, paint);
  }

  void _paintCircle(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    double width,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas.drawOval(Rect.fromPoints(start, end), paint);
  }

  void _paintRectangle(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    double width,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(start, end),
        const Radius.circular(8),
      ),
      paint,
    );
  }

  void _paintArrow(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    double width,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width;

    canvas.drawLine(start, end, paint);

    final distance = (end - start).distance;
    if (distance < 8) return;

    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final arrowHeadSize = math.min(20.0, distance * 0.4);
    const arrowAngle = math.pi / 6;

    final p1 = Offset(
      end.dx - arrowHeadSize * math.cos(angle - arrowAngle),
      end.dy - arrowHeadSize * math.sin(angle - arrowAngle),
    );
    final p2 = Offset(
      end.dx - arrowHeadSize * math.cos(angle + arrowAngle),
      end.dy - arrowHeadSize * math.sin(angle + arrowAngle),
    );

    final headPath = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(end.dx, end.dy)
      ..lineTo(p2.dx, p2.dy);
    canvas.drawPath(headPath, paint);
  }

  @override
  bool shouldRepaint(covariant _MarkupCanvasPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.shapes != shapes ||
        oldDelegate.activeStroke != activeStroke ||
        oldDelegate.activeShapeStart != activeShapeStart ||
        oldDelegate.activeShapeEnd != activeShapeEnd ||
        oldDelegate.activeShapeTool != activeShapeTool ||
        oldDelegate.activeBlurStart != activeBlurStart ||
        oldDelegate.activeBlurEnd != activeBlurEnd ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeWidth != activeWidth ||
        oldDelegate.isHighlighter != isHighlighter;
  }
}
