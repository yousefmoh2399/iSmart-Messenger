import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
  final _signatureController = _SignatureController();

  /// Key attached to the RepaintBoundary inside _SignaturePadWidget
  final GlobalKey _repaintKey = GlobalKey();

  List<SignatureModel> _savedSignatures = [];
  bool _loadingSignatures = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _signatureController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadSignatures();
  }

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
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

  bool get _hasDrawing => _signatureController.hasDrawing;

  void _clearCanvas() {
    _signatureController.clear();
  }

  Future<void> _confirmNewSignature({required bool save}) async {
    if (!_hasDrawing) return;
    setState(() => _saving = true);

    try {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final pngBytes = await _signatureController.captureFromRepaintBoundary(
        _repaintKey,
        dpr,
      );
      if (pngBytes == null) throw Exception('توقيع فارغ');

      if (save) {
        await widget.storageService.saveSignature(pngBytes);
      }

      if (mounted) {
        Navigator.of(
          context,
        ).pop(SignatureResult(pngBytes: pngBytes, isSaved: save));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ أثناء معالجة التوقيع: $e')));
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _selectSavedSignature(SignatureModel sig) async {
    try {
      final bytes = await File(sig.filePath).readAsBytes();
      if (mounted) {
        Navigator.of(
          context,
        ).pop(SignatureResult(pngBytes: bytes, isSaved: true));
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
                                    color: palette.accent.withValues(
                                      alpha: 0.3,
                                    ),
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
                          child: _SignaturePadWidget(
                            controller: _signatureController,
                            showHint: !_hasDrawing,
                            theme: theme,
                            repaintKey: _repaintKey,
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
                                  : () => _confirmNewSignature(save: true),
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
                                  : () => _confirmNewSignature(save: false),
                              icon: const Icon(
                                Icons.check_circle_outline_rounded,
                              ),
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
// Signature Controller
// ─────────────────────────────────────────────────────────────────────────────

class _SignatureController extends ChangeNotifier {
  final List<List<Offset>> strokes = [];
  List<Offset>? currentStroke;

  bool get hasDrawing =>
      strokes.isNotEmpty ||
      (currentStroke != null && currentStroke!.isNotEmpty);

  void clear() {
    strokes.clear();
    currentStroke = null;
    notifyListeners();
  }

  void startStroke(Offset point) {
    currentStroke = [point];
    notifyListeners();
  }

  void updateStroke(Offset point) {
    currentStroke?.add(point);
    notifyListeners();
  }

  void endStroke() {
    if (currentStroke != null && currentStroke!.isNotEmpty) {
      strokes.add(List.from(currentStroke!));
    }
    currentStroke = null;
    notifyListeners();
  }

  /// Captures the drawn signature directly from the rendered widget on screen.
  /// This is the most reliable approach — it captures exactly what the user
  /// sees, at the device's native pixel density.
  Future<Uint8List?> captureFromRepaintBoundary(
    GlobalKey repaintKey,
    double devicePixelRatio,
  ) async {
    if (!hasDrawing) return null;

    // Commit any in-progress stroke
    if (currentStroke != null && currentStroke!.isNotEmpty) {
      strokes.add(List.from(currentStroke!));
      currentStroke = null;
      notifyListeners();
    }

    // Wait one frame for the painter to finish rendering the last stroke
    await Future<void>.delayed(Duration.zero);

    try {
      final renderObject = repaintKey.currentContext?.findRenderObject();
      if (renderObject == null) return null;
      final boundary = renderObject as RenderRepaintBoundary;

      // Capture at native resolution for crisp output
      final image = await boundary.toImage(pixelRatio: devicePixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      return byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
    } catch (e) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signature Pad Widget
// ─────────────────────────────────────────────────────────────────────────────

class _SignaturePadWidget extends StatelessWidget {
  const _SignaturePadWidget({
    required this.controller,
    required this.showHint,
    required this.theme,
    required this.repaintKey,
  });

  final _SignatureController controller;
  final bool showHint;
  final ThemeData theme;
  final GlobalKey repaintKey;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => controller.startStroke(d.localPosition),
      onPanUpdate: (d) => controller.updateStroke(d.localPosition),
      onPanEnd: (_) => controller.endStroke(),
      onPanCancel: () => controller.endStroke(),
      child: RepaintBoundary(
        key: repaintKey,
        child: CustomPaint(
          painter: _SignaturePainter(controller),
          child: showHint
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.draw_rounded,
                        size: 36,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'اسحب إصبعك هنا للتوقيع',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signature Painter
// ─────────────────────────────────────────────────────────────────────────────

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.controller) : super(repaint: controller);
  final _SignatureController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    void drawStroke(List<Offset> stroke) {
      if (stroke.isEmpty) return;
      if (stroke.length == 1) {
        canvas.drawCircle(
          stroke.first,
          2.0,
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.fill,
        );
        return;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    for (final stroke in controller.strokes) {
      drawStroke(stroke);
    }

    final current = controller.currentStroke;
    if (current != null && current.isNotEmpty) {
      drawStroke(current);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => false;
}
