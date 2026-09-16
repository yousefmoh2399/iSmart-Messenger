import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/signature_model.dart';
import '../data/signature_storage_service.dart';

/// Result returned when the user confirms a signature from the bottom sheet.
class SignatureResult {
  const SignatureResult({required this.pngBytes, required this.isSaved});

  /// Raw PNG bytes of the drawn/selected signature.
  final Uint8List pngBytes;

  /// Whether the user chose to save this signature for future use.
  final bool isSaved;
}

/// Shows a bottom sheet with:
/// 1. A horizontal list of previously saved signatures to pick from.
/// 2. A full drawing canvas to create a new signature.
///
/// Returns a [SignatureResult] or null if the user dismisses.
Future<SignatureResult?> showSignatureBottomSheet({
  required BuildContext context,
  required SignatureStorageService storageService,
}) {
  return showModalBottomSheet<SignatureResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SignatureBottomSheet(storageService: storageService),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal sheet widget
// ─────────────────────────────────────────────────────────────────────────────

class _SignatureBottomSheet extends StatefulWidget {
  const _SignatureBottomSheet({required this.storageService});
  final SignatureStorageService storageService;

  @override
  State<_SignatureBottomSheet> createState() => _SignatureBottomSheetState();
}

class _SignatureBottomSheetState extends State<_SignatureBottomSheet> {
  final List<List<Offset>> _strokes = [];
  List<Offset>? _currentStroke;
  List<SignatureModel> _savedSignatures = [];
  bool _loadingSignatures = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSignatures();
  }

  Future<void> _loadSignatures() async {
    final sigs = await widget.storageService.loadAllSignatures();
    if (mounted) {
      setState(() {
        _savedSignatures = sigs;
        _loadingSignatures = false;
      });
    }
  }

  bool get _hasDrawing =>
      _strokes.isNotEmpty ||
      (_currentStroke != null && _currentStroke!.isNotEmpty);

  void _clearCanvas() => setState(() {
        _strokes.clear();
        _currentStroke = null;
      });

  Future<Uint8List> _renderToPng({
    required Size canvasSize,
    double devicePixelRatio = 2.0,
  }) async {
    final pixelWidth = (canvasSize.width * devicePixelRatio).toInt();
    final pixelHeight = (canvasSize.height * devicePixelRatio).toInt();

    // Single recorder at 2× resolution for sharpness
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()),
    );
    canvas.scale(devicePixelRatio, devicePixelRatio);

    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in _strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 2.0, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final p = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        p.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(p, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelWidth, pixelHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _confirmNewSignature({required bool save}) async {
    if (!_hasDrawing) return;
    setState(() => _saving = true);

    try {
      // Get canvas size from context — the drawing area
      final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
      final size = box?.size ?? const Size(300, 200);

      final pngBytes = await _renderToPng(canvasSize: size);

      if (save) {
        await widget.storageService.saveSignature(pngBytes);
      }

      if (mounted) {
        Navigator.of(context).pop(
          SignatureResult(pngBytes: pngBytes, isSaved: save),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء معالجة التوقيع: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _selectSavedSignature(SignatureModel sig) async {
    try {
      final bytes = await File(sig.filePath).readAsBytes();
      if (mounted) {
        Navigator.of(context).pop(
          SignatureResult(pngBytes: bytes, isSaved: true),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحميل التوقيع المحفوظ.')),
        );
      }
    }
  }

  Future<void> _deleteSavedSignature(SignatureModel sig) async {
    await widget.storageService.deleteSignature(sig.id);
    await _loadSignatures();
  }

  final GlobalKey _canvasKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appThemePalette;
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // ── Handle ──
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.7,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'إضافة توقيع',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.only(bottom: mq.padding.bottom + 16),
                  children: [
                    // ── Saved signatures horizontal list ──
                    if (!_loadingSignatures && _savedSignatures.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: Text(
                          'توقيعاتك السابقة',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 100,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _savedSignatures.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final sig = _savedSignatures[index];
                            return GestureDetector(
                              onTap: () => _selectSavedSignature(sig),
                              onLongPress: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('حذف التوقيع'),
                                    content: const Text(
                                      'هل تريد حذف هذا التوقيع المحفوظ؟',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('إلغاء'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: palette.danger,
                                        ),
                                        child: const Text('حذف'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  await _deleteSavedSignature(sig);
                                }
                              },
                              child: Container(
                                width: 140,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF2C2C2E)
                                      : const Color(0xFFF2F2F7),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: palette.accent.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(13),
                                  child: Image.file(
                                    File(sig.filePath),
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(Icons.broken_image_outlined),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Divider(height: 24),
                      ),
                    ],

                    // ── Canvas instructions ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: Row(
                        children: [
                          Text(
                            'ارسم توقيعك الجديد',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          if (_hasDrawing)
                            TextButton.icon(
                              onPressed: _clearCanvas,
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('مسح'),
                              style: TextButton.styleFrom(
                                foregroundColor: palette.danger,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // ── Drawing canvas ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        key: _canvasKey,
                        height: 220,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: palette.accent.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: GestureDetector(
                            onPanStart: (d) {
                              setState(() {
                                _currentStroke = [d.localPosition];
                              });
                            },
                            onPanUpdate: (d) {
                              setState(() {
                                _currentStroke?.add(d.localPosition);
                              });
                            },
                            onPanEnd: (_) {
                              if (_currentStroke != null &&
                                  _currentStroke!.isNotEmpty) {
                                setState(() {
                                  _strokes.add(List.from(_currentStroke!));
                                  _currentStroke = null;
                                });
                              }
                            },
                            child: CustomPaint(
                              painter: _SignaturePainter(
                                strokes: _strokes,
                                currentStroke: _currentStroke,
                              ),
                              child: _hasDrawing
                                  ? null
                                  : Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.draw_rounded,
                                            size: 36,
                                            color: theme.colorScheme
                                                .onSurfaceVariant
                                                .withValues(alpha: 0.4),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'اسحب إصبعك هنا للتوقيع',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant
                                                      .withValues(alpha: 0.5),
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

                    const SizedBox(height: 20),

                    // ── Action buttons ──
                    if (_hasDrawing) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () =>
                                        _confirmNewSignature(save: true),
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.bookmark_add_rounded),
                              label: const Text('استخدام وحفظ للمرات القادمة'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () =>
                                        _confirmNewSignature(save: false),
                              icon: const Icon(Icons.check_circle_outline_rounded),
                              label: const Text('استخدام مرة واحدة فقط'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                foregroundColor: palette.accent,
                                side: BorderSide(
                                  color: palette.accent.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painter for the drawing canvas
// ─────────────────────────────────────────────────────────────────────────────

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({required this.strokes, required this.currentStroke});

  final List<List<Offset>> strokes;
  final List<Offset>? currentStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    void drawStroke(List<Offset> stroke) {
      if (stroke.isEmpty) return;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 2.0, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        return;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    for (final stroke in strokes) {
      drawStroke(stroke);
    }
    if (currentStroke != null) {
      drawStroke(currentStroke!);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) =>
      old.strokes != strokes || old.currentStroke != currentStroke;
}
