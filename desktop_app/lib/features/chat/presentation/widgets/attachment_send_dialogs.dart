import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../shared/widgets/button_loading_indicator.dart';
import '../../../../shared/widgets/loading_indicator.dart';

class AttachmentSendDraft {
  const AttachmentSendDraft({
    required this.filePath,
    required this.displayName,
    required this.restrictForwardAndDownload,
  });

  final String filePath;
  final String displayName;
  final bool restrictForwardAndDownload;
}

enum _MarkupTool { pen, circle }

class _MarkupStroke {
  const _MarkupStroke({
    required this.points,
    required this.color,
    required this.width,
  });

  final List<Offset> points;
  final Color color;
  final double width;
}

class _MarkupCircle {
  const _MarkupCircle({
    required this.start,
    required this.end,
    required this.color,
    required this.width,
  });

  final Offset start;
  final Offset end;
  final Color color;
  final double width;
}

const Set<String> _imageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.webp',
  '.gif',
  '.bmp',
};

bool _isImagePath(String path) {
  final ext = p.extension(path).toLowerCase();
  return _imageExtensions.contains(ext);
}

Future<AttachmentSendDraft?> showAttachmentSendDialog(
  BuildContext context,
  String originalPath,
) async {
  var effectivePath = originalPath;
  if (_isImagePath(originalPath)) {
    final editedPath = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImageMarkupEditorDialog(imagePath: originalPath),
    );
    if (editedPath == null) {
      return null;
    }
    effectivePath = editedPath;
  }
  if (!context.mounted) {
    return null;
  }

  return showDialog<AttachmentSendDraft>(
    context: context,
    builder: (_) => _AttachmentSendOptionsDialog(filePath: effectivePath),
  );
}

class _AttachmentSendOptionsDialog extends StatefulWidget {
  const _AttachmentSendOptionsDialog({required this.filePath});

  final String filePath;

  @override
  State<_AttachmentSendOptionsDialog> createState() =>
      _AttachmentSendOptionsDialogState();
}

class _AttachmentSendOptionsDialogState
    extends State<_AttachmentSendOptionsDialog> {
  late String _displayName;
  bool _restrictForwardAndDownload = false;

  @override
  void initState() {
    super.initState();
    _displayName = p.basename(widget.filePath);
  }

  void _submit() {
    final displayName = _displayName.trim();
    final fallbackName = p.basename(widget.filePath);
    Navigator.of(context).pop(
      AttachmentSendDraft(
        filePath: widget.filePath,
        displayName: displayName.isEmpty ? fallbackName : displayName,
        restrictForwardAndDownload: _restrictForwardAndDownload,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('خيارات إرسال المرفق'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              initialValue: _displayName,
              maxLines: 1,
              onChanged: (value) {
                _displayName = value;
              },
              decoration: const InputDecoration(
                labelText: 'اسم الملف قبل الإرسال',
                prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _restrictForwardAndDownload,
              onChanged: (value) {
                setState(() {
                  _restrictForwardAndDownload = value;
                });
              },
              title: const Text('عرض فقط داخل الشات'),
              subtitle: const Text('منع التحميل وإعادة التوجيه لهذا المرفق'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send_rounded),
          label: const Text('إرسال'),
        ),
      ],
    );
  }
}

class _ImageMarkupEditorDialog extends StatefulWidget {
  const _ImageMarkupEditorDialog({required this.imagePath});

  final String imagePath;

  @override
  State<_ImageMarkupEditorDialog> createState() =>
      _ImageMarkupEditorDialogState();
}

class _ImageMarkupEditorDialogState extends State<_ImageMarkupEditorDialog> {
  ui.Image? _image;
  _MarkupTool _tool = _MarkupTool.pen;
  Color _activeColor = const Color(0xFFE53935);
  double _activeWidth = 5;
  bool _saving = false;
  Size _canvasSize = Size.zero;

  final List<_MarkupStroke> _strokes = <_MarkupStroke>[];
  final List<_MarkupCircle> _circles = <_MarkupCircle>[];
  final List<_MarkupTool> _actionHistory = <_MarkupTool>[];

  List<Offset>? _activeStroke;
  Offset? _circleStart;
  Offset? _circleEnd;

  static const List<Color> _palette = <Color>[
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFFFB300),
    Color(0xFF8E24AA),
    Color(0xFF111827),
  ];

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      return;
    }
    setState(() {
      _image = frame.image;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _undo() {
    if (_actionHistory.isEmpty) {
      return;
    }
    final lastAction = _actionHistory.removeLast();
    setState(() {
      if (lastAction == _MarkupTool.pen && _strokes.isNotEmpty) {
        _strokes.removeLast();
      } else if (lastAction == _MarkupTool.circle && _circles.isNotEmpty) {
        _circles.removeLast();
      }
    });
  }

  void _clearAll() {
    setState(() {
      _strokes.clear();
      _circles.clear();
      _actionHistory.clear();
      _activeStroke = null;
      _circleStart = null;
      _circleEnd = null;
    });
  }

  Offset _clampPoint(Offset local) {
    return Offset(
      local.dx.clamp(0, _canvasSize.width).toDouble(),
      local.dy.clamp(0, _canvasSize.height).toDouble(),
    );
  }

  Future<String> _saveEditedImage() async {
    if (_image == null || (_strokes.isEmpty && _circles.isEmpty)) {
      return widget.imagePath;
    }
    final image = _image!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    );
    canvas.drawImage(image, Offset.zero, Paint());

    final scaleX = image.width / _canvasSize.width;
    final scaleY = image.height / _canvasSize.height;
    final averageScale = (scaleX + scaleY) / 2;

    for (final stroke in _strokes) {
      if (stroke.points.length < 2) {
        continue;
      }
      final path = Path()
        ..moveTo(
          stroke.points.first.dx * scaleX,
          stroke.points.first.dy * scaleY,
        );
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx * scaleX, point.dy * scaleY);
      }
      final paint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.width * averageScale;
      canvas.drawPath(path, paint);
    }

    for (final circle in _circles) {
      final paint = Paint()
        ..color = circle.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = circle.width * averageScale;
      canvas.drawOval(
        Rect.fromPoints(
          Offset(circle.start.dx * scaleX, circle.start.dy * scaleY),
          Offset(circle.end.dx * scaleX, circle.end.dy * scaleY),
        ),
        paint,
      );
    }

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(image.width, image.height);
    final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return widget.imagePath;
    }
    final outBytes = byteData.buffer.asUint8List();
    final tempDir = await getTemporaryDirectory();
    final outputPath = p.join(
      tempDir.path,
      'chat_markup_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await File(outputPath).writeAsBytes(outBytes, flush: true);
    return outputPath;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return const Dialog.fullscreen(
        child: Center(child: AppLoadingIndicator(size: 30)),
      );
    }

    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'إلغاء',
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'تعديل الصورة قبل الإرسال',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving || _actionHistory.isEmpty ? null : _undo,
                    icon: const Icon(Icons.undo_rounded),
                    tooltip: 'تراجع',
                  ),
                  IconButton(
                    onPressed: _saving || _actionHistory.isEmpty
                        ? null
                        : _clearAll,
                    icon: const Icon(Icons.layers_clear_rounded),
                    tooltip: 'مسح الكل',
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() {
                              _saving = true;
                            });
                            final editedPath = await _saveEditedImage();
                            if (!mounted) {
                              return;
                            }
                            Navigator.of(this.context).pop(editedPath);
                          },
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: ButtonLoadingIndicator(),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('التالي'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final sourceSize = Size(
                    image.width.toDouble(),
                    image.height.toDouble(),
                  );
                  final fitted = applyBoxFit(
                    BoxFit.contain,
                    sourceSize,
                    Size(constraints.maxWidth, constraints.maxHeight),
                  );
                  final renderSize = fitted.destination;
                  _canvasSize = renderSize;

                  return Center(
                    child: SizedBox(
                      width: renderSize.width,
                      height: renderSize.height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) {
                          final point = _clampPoint(details.localPosition);
                          setState(() {
                            if (_tool == _MarkupTool.pen) {
                              _activeStroke = <Offset>[point];
                            } else {
                              _circleStart = point;
                              _circleEnd = point;
                            }
                          });
                        },
                        onPanUpdate: (details) {
                          final point = _clampPoint(details.localPosition);
                          setState(() {
                            if (_tool == _MarkupTool.pen) {
                              _activeStroke?.add(point);
                            } else {
                              _circleEnd = point;
                            }
                          });
                        },
                        onPanEnd: (_) {
                          setState(() {
                            if (_tool == _MarkupTool.pen) {
                              final points = _activeStroke;
                              if (points != null && points.length > 1) {
                                _strokes.add(
                                  _MarkupStroke(
                                    points: List<Offset>.from(points),
                                    color: _activeColor,
                                    width: _activeWidth,
                                  ),
                                );
                                _actionHistory.add(_MarkupTool.pen);
                              }
                              _activeStroke = null;
                            } else {
                              final start = _circleStart;
                              final end = _circleEnd;
                              if (start != null &&
                                  end != null &&
                                  (start - end).distance >= 12) {
                                _circles.add(
                                  _MarkupCircle(
                                    start: start,
                                    end: end,
                                    color: _activeColor,
                                    width: _activeWidth,
                                  ),
                                );
                                _actionHistory.add(_MarkupTool.circle);
                              }
                              _circleStart = null;
                              _circleEnd = null;
                            }
                          });
                        },
                        child: CustomPaint(
                          painter: _ImageMarkupPainter(
                            image: image,
                            strokes: _strokes,
                            circles: _circles,
                            activeStroke: _activeStroke,
                            activeCircleStart: _circleStart,
                            activeCircleEnd: _circleEnd,
                            activeColor: _activeColor,
                            activeWidth: _activeWidth,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('قلم'),
                        selected: _tool == _MarkupTool.pen,
                        onSelected: (_) =>
                            setState(() => _tool = _MarkupTool.pen),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('دائرة'),
                        selected: _tool == _MarkupTool.circle,
                        onSelected: (_) =>
                            setState(() => _tool = _MarkupTool.circle),
                      ),
                      const SizedBox(width: 16),
                      const Text('السُمك'),
                      Expanded(
                        child: Slider(
                          value: _activeWidth,
                          min: 2,
                          max: 14,
                          onChanged: (value) {
                            setState(() {
                              _activeWidth = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: _palette
                        .map(
                          (color) => GestureDetector(
                            onTap: () => setState(() => _activeColor = color),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _activeColor == color
                                      ? Theme.of(context).colorScheme.onSurface
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageMarkupPainter extends CustomPainter {
  const _ImageMarkupPainter({
    required this.image,
    required this.strokes,
    required this.circles,
    required this.activeStroke,
    required this.activeCircleStart,
    required this.activeCircleEnd,
    required this.activeColor,
    required this.activeWidth,
  });

  final ui.Image image;
  final List<_MarkupStroke> strokes;
  final List<_MarkupCircle> circles;
  final List<Offset>? activeStroke;
  final Offset? activeCircleStart;
  final Offset? activeCircleEnd;
  final Color activeColor;
  final double activeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint(),
    );

    for (final stroke in strokes) {
      _paintStroke(canvas, stroke.points, stroke.color, stroke.width);
    }
    for (final circle in circles) {
      _paintCircle(
        canvas,
        circle.start,
        circle.end,
        circle.color,
        circle.width,
      );
    }

    final liveStroke = activeStroke;
    if (liveStroke != null && liveStroke.length > 1) {
      _paintStroke(canvas, liveStroke, activeColor, activeWidth);
    }
    if (activeCircleStart != null && activeCircleEnd != null) {
      _paintCircle(
        canvas,
        activeCircleStart!,
        activeCircleEnd!,
        activeColor,
        activeWidth,
      );
    }
  }

  void _paintStroke(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
  ) {
    if (points.length < 2) {
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width;
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

  @override
  bool shouldRepaint(covariant _ImageMarkupPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.strokes != strokes ||
        oldDelegate.circles != circles ||
        oldDelegate.activeStroke != activeStroke ||
        oldDelegate.activeCircleStart != activeCircleStart ||
        oldDelegate.activeCircleEnd != activeCircleEnd ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeWidth != activeWidth;
  }
}
