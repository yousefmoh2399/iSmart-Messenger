import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';


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

/// Displays the WhatsApp-style attachment send flow on desktop.
Future<AttachmentSendDraft?> showAttachmentSendDialog(
  BuildContext context,
  String originalPath,
) async {
  if (_isImagePath(originalPath)) {
    return showDialog<AttachmentSendDraft>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.75),
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
// WHATSAPP-STYLE MEDIA EDITOR (DESKTOP)
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
  Color _activeColor = const Color(0xFF25D366);
  final double _activeWidth = 5.0;
  bool _saving = false;
  bool _restrictForwardAndDownload = false;
  Size _canvasSize = Size.zero;

  final TextEditingController _captionController = TextEditingController();

  final List<_MarkupStroke> _strokes = <_MarkupStroke>[];
  final List<_MarkupCircle> _circles = <_MarkupCircle>[];
  final List<_MarkupTool> _actionHistory = <_MarkupTool>[];

  List<Offset>? _activeStroke;
  Offset? _circleStart;
  Offset? _circleEnd;

  static const List<Color> _palette = <Color>[
    Color(0xFF25D366),
    Color(0xFF34B7F1),
    Color(0xFFFF3B30),
    Color(0xFFFFD200),
    Color(0xFFAF52DE),
    Color(0xFFFFFFFF),
    Color(0xFF111827),
  ];

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) return;
      setState(() {
        _image = frame.image;
      });
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  void _undo() {
    if (_actionHistory.isEmpty) return;
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

  void _quickSend() {
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
        _circles.isNotEmpty;

    if (image == null || !hasEdits) {
      return widget.imagePath;
    }

    final origW = image.width.toDouble();
    final origH = image.height.toDouble();
    final isRotatedQuarter = (_quarterTurns % 2) != 0;
    final targetW = isRotatedQuarter ? origH : origW;
    final targetH = isRotatedQuarter ? origW : origH;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, targetW, targetH),
    );

    canvas.save();
    switch (_quarterTurns % 4) {
      case 1:
        canvas.translate(origH, 0);
        canvas.rotate(math.pi / 2);
        break;
      case 2:
        canvas.translate(origW, origH);
        canvas.rotate(math.pi);
        break;
      case 3:
        canvas.translate(0, origW);
        canvas.rotate(3 * math.pi / 2);
        break;
      case 0:
      default:
        break;
    }
    canvas.drawImage(image, Offset.zero, Paint());
    canvas.restore();

    if (_strokes.isNotEmpty || _circles.isNotEmpty) {
      final scaleX = _canvasSize.width > 0 ? targetW / _canvasSize.width : 1.0;
      final scaleY = _canvasSize.height > 0 ? targetH / _canvasSize.height : 1.0;
      final avgScale = (scaleX + scaleY) / 2;

      for (final stroke in _strokes) {
        if (stroke.points.length < 2) continue;
        final path = Path()
          ..moveTo(stroke.points.first.dx * scaleX, stroke.points.first.dy * scaleY);
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

      for (final circle in _circles) {
        final paint = Paint()
          ..color = circle.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = circle.width * avgScale;
        canvas.drawOval(
          Rect.fromPoints(
            Offset(circle.start.dx * scaleX, circle.start.dy * scaleY),
            Offset(circle.end.dx * scaleX, circle.end.dy * scaleY),
          ),
          paint,
        );
      }
    }

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(targetW.toInt(), targetH.toInt());
    final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return widget.imagePath;
    }

    final outBytes = byteData.buffer.asUint8List();
    final tempDir = await getTemporaryDirectory();
    final outputPath = p.join(
      tempDir.path,
      'ismart_desktop_media_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await File(outputPath).writeAsBytes(outBytes, flush: true);
    return outputPath;
  }

  Offset _clampPoint(Offset local) {
    return Offset(
      local.dx.clamp(0, _canvasSize.width).toDouble(),
      local.dy.clamp(0, _canvasSize.height).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return Dialog(
        backgroundColor: const Color(0xFF0B141B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: const SizedBox(
          width: 320,
          height: 240,
          child: Center(
            child: CircularProgressIndicator(color: Color(0xFF25D366)),
          ),
        ),
      );
    }

    final isRotatedQuarter = (_quarterTurns % 2) != 0;
    final effectiveSourceSize = Size(
      isRotatedQuarter ? image.height.toDouble() : image.width.toDouble(),
      isRotatedQuarter ? image.width.toDouble() : image.height.toDouble(),
    );

    return Dialog(
      backgroundColor: const Color(0xFF0B141B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 740),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              // -------------------------------------------------------------
              // TOP BAR
              // -------------------------------------------------------------
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                color: const Color(0xFF111B21),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                      tooltip: 'إلغاء',
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'معاينة وتعديل الصورة',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    // Quick Send Button
                    InkWell(
                      onTap: _saving ? null : _quickSend,
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFFF59E0B).withOpacity(0.7),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 18),
                            SizedBox(width: 4),
                            Text(
                              'إرسال سريع',
                              style: TextStyle(
                                color: Color(0xFFFBBF24),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Rotate 90°
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () {
                              setState(() {
                                _quarterTurns = (_quarterTurns + 1) % 4;
                              });
                            },
                      icon: const Icon(
                        Icons.rotate_90_degrees_cw_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      tooltip: 'تدوير 90°',
                    ),
                    // Markup Tool Toggle
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () {
                              setState(() {
                                _isMarkupActive = !_isMarkupActive;
                              });
                            },
                      icon: Icon(
                        Icons.edit_rounded,
                        color: _isMarkupActive ? const Color(0xFF25D366) : Colors.white,
                        size: 22,
                      ),
                      tooltip: 'رسم وتوضيح',
                    ),
                    if (_isMarkupActive && _actionHistory.isNotEmpty) ...[
                      IconButton(
                        onPressed: _saving ? null : _undo,
                        icon: const Icon(Icons.undo_rounded, color: Colors.white, size: 22),
                        tooltip: 'تراجع',
                      ),
                      IconButton(
                        onPressed: _saving ? null : _clearAll,
                        icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 22),
                        tooltip: 'مسح الكل',
                      ),
                    ],
                  ],
                ),
              ),

              // -------------------------------------------------------------
              // MARKUP TOOLBAR
              // -------------------------------------------------------------
              if (_isMarkupActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: const Color(0xFF1F2C34),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('قلم', style: TextStyle(fontSize: 12)),
                        selected: _tool == _MarkupTool.pen,
                        selectedColor: const Color(0xFF25D366),
                        onSelected: (_) => setState(() => _tool = _MarkupTool.pen),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('دائرة', style: TextStyle(fontSize: 12)),
                        selected: _tool == _MarkupTool.circle,
                        selectedColor: const Color(0xFF25D366),
                        onSelected: (_) => setState(() => _tool = _MarkupTool.circle),
                      ),
                      const SizedBox(width: 16),
                      Row(
                        children: _palette.map((color) {
                          final isSelected = _activeColor == color;
                          return GestureDetector(
                            onTap: () => setState(() => _activeColor = color),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? Colors.white : Colors.transparent,
                                  width: 2.2,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),

              // -------------------------------------------------------------
              // MAIN VIEW
              // -------------------------------------------------------------
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final fitted = applyBoxFit(
                      BoxFit.contain,
                      effectiveSourceSize,
                      Size(constraints.maxWidth - 20, constraints.maxHeight - 20),
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
                          onPanStart: _isMarkupActive
                              ? (details) {
                                  final point = _clampPoint(details.localPosition);
                                  setState(() {
                                    if (_tool == _MarkupTool.pen) {
                                      _activeStroke = <Offset>[point];
                                    } else {
                                      _circleStart = point;
                                      _circleEnd = point;
                                    }
                                  });
                                }
                              : null,
                          onPanUpdate: _isMarkupActive
                              ? (details) {
                                  final point = _clampPoint(details.localPosition);
                                  setState(() {
                                    if (_tool == _MarkupTool.pen) {
                                      _activeStroke?.add(point);
                                    } else {
                                      _circleEnd = point;
                                    }
                                  });
                                }
                              : null,
                          onPanEnd: _isMarkupActive
                              ? (_) {
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
                                          (start - end).distance >= 10) {
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
                                }
                              : null,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Center(
                                child: RotatedBox(
                                quarterTurns: _quarterTurns,
                                child: Image.file(
                                  File(widget.imagePath),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            CustomPaint(
                              painter: _DesktopMarkupCanvasPainter(
                                strokes: _strokes,
                                circles: _circles,
                                activeStroke: _activeStroke,
                                activeCircleStart: _circleStart,
                                activeCircleEnd: _circleEnd,
                                activeColor: _activeColor,
                                activeWidth: _activeWidth,
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
            // BOTTOM BAR
            // -------------------------------------------------------------
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(
                color: const Color(0xFF111B21),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Per-Message Security Capsule
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _restrictForwardAndDownload = !_restrictForwardAndDownload;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _restrictForwardAndDownload
                            ? const Color(0xFF059669).withOpacity(0.25)
                            : Colors.white.withOpacity(0.08),
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
                                ? '🔒 محتوى محمي: منع إعادة التوجيه والتحميل (لهذه الرسالة فقط)'
                                : '🔓 مسموح بإعادة التوجيه · اضغط للقفل (لهذه الرسالة فقط)',
                            style: TextStyle(
                              color: _restrictForwardAndDownload
                                  ? const Color(0xFF34D399)
                                  : Colors.white70,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // WhatsApp Caption & Send Button
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
                            style: const TextStyle(color: Colors.white, fontSize: 14.5),
                            maxLines: 3,
                            minLines: 1,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _submitSend(),
                            decoration: const InputDecoration(
                              hintText: 'إضافة شرح... (أو اضغط إرسال)',
                              hintStyle: TextStyle(color: Colors.white54, fontSize: 13.5),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: _saving ? null : _submitSend,
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: const BoxDecoration(
                            color: Color(0xFF25D366),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.send_rounded,
                                    color: Colors.white,
                                    size: 20,
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
    ),
  );
}
}

// =============================================================================
// DOCUMENT & VIDEO ATTACHMENT DIALOG (DESKTOP)
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
    if (ext == '.zip' || ext == '.rar' || ext == '.7z') return Icons.folder_zip_rounded;
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

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: fileColor.withOpacity(0.12),
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
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                maxLines: 1,
                decoration: InputDecoration(
                  labelText: 'اسم الملف',
                  prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded, size: 20),
                  filled: true,
                  fillColor: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _captionController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'إضافة شرح أو ملاحظة (اختياري)',
                  prefixIcon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                  filled: true,
                  fillColor: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _restrictForwardAndDownload = !_restrictForwardAndDownload;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _restrictForwardAndDownload
                        ? const Color(0xFF059669).withOpacity(isDark ? 0.25 : 0.12)
                        : (isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _restrictForwardAndDownload
                          ? const Color(0xFF10B981)
                          : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
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
                                    : (isDark ? Colors.white : const Color(0xFF0F172A)),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _restrictForwardAndDownload
                                  ? 'منع التحميل وإعادة التوجيه لهذا الملف فقط'
                                  : 'اضغط للقفل ومنع التحميل أو إعادة التوجيه',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white54 : Colors.black45,
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
// DESKTOP MARKUP CANVAS PAINTER
// =============================================================================

class _DesktopMarkupCanvasPainter extends CustomPainter {
  const _DesktopMarkupCanvasPainter({
    required this.strokes,
    required this.circles,
    required this.activeStroke,
    required this.activeCircleStart,
    required this.activeCircleEnd,
    required this.activeColor,
    required this.activeWidth,
  });

  final List<_MarkupStroke> strokes;
  final List<_MarkupCircle> circles;
  final List<Offset>? activeStroke;
  final Offset? activeCircleStart;
  final Offset? activeCircleEnd;
  final Color activeColor;
  final double activeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintStroke(canvas, stroke.points, stroke.color, stroke.width);
    }
    for (final circle in circles) {
      _paintCircle(canvas, circle.start, circle.end, circle.color, circle.width);
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

  void _paintStroke(Canvas canvas, List<Offset> points, Color color, double width) {
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

  void _paintCircle(Canvas canvas, Offset start, Offset end, Color color, double width) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas.drawOval(Rect.fromPoints(start, end), paint);
  }

  @override
  bool shouldRepaint(covariant _DesktopMarkupCanvasPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.circles != circles ||
        oldDelegate.activeStroke != activeStroke ||
        oldDelegate.activeCircleStart != activeCircleStart ||
        oldDelegate.activeCircleEnd != activeCircleEnd ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeWidth != activeWidth;
  }
}
