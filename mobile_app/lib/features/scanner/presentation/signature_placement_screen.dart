import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/signature_composer_service.dart';

/// Allows the user to position and resize a signature on top of a scanned page.
///
/// The user can:
/// - Drag the signature to any position (pan gesture)
/// - Pinch to resize it (scale gesture)
/// - Tap "تطبيق وحفظ" to composite the signature into the image
///
/// Returns the composited JPEG [Uint8List] or null if the user cancels.
class SignaturePlacementScreen extends StatefulWidget {
  const SignaturePlacementScreen({
    super.key,
    required this.pageImagePath,
    required this.signatureBytes,
  });

  /// Path to the scanned page JPEG on disk.
  final String pageImagePath;

  /// PNG bytes of the signature (may have transparent background).
  final Uint8List signatureBytes;

  @override
  State<SignaturePlacementScreen> createState() =>
      _SignaturePlacementScreenState();
}

class _SignaturePlacementScreenState extends State<SignaturePlacementScreen> {
  // Relative position of the signature centre (0.0–1.0 of page size)
  double _relX = 0.1;
  double _relY = 0.7;

  // Signature width as a fraction of the page width (0.0–1.0)
  double _relW = 0.35;

  // Track scale gesture starting state
  double _baseRelW = 0.35;

  bool _applying = false;

  // We need the displayed image size to convert pointer offsets to relative coords
  final GlobalKey _imageKey = GlobalKey();

  Size get _imageRenderSize {
    final box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size ?? const Size(300, 400);
  }

  Future<void> _apply() async {
    if (_applying) return;
    setState(() => _applying = true);

    try {
      final pageBytes = await File(widget.pageImagePath).readAsBytes();
      final composer = SignatureComposerService();
      final result = await composer.compositeSignatureOnImage(
        pageImageBytes: pageBytes,
        signatureBytes: widget.signatureBytes,
        relativeX: _relX,
        relativeY: _relY,
        relativeWidth: _relW,
      );

      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تطبيق التوقيع: $e')),
        );
        setState(() => _applying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'ضع التوقيع على الصفحة',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton.icon(
              onPressed: _applying ? null : _apply,
              icon: _applying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('تطبيق'),
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Instruction banner ──
            Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'اسحب التوقيع لتحديد مكانه • استخدم إصبعين لتكبيره أو تصغيره',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ),

            // ── Page + draggable signature ──
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    // Pan: move signature
                    onPanUpdate: (details) {
                      final size = _imageRenderSize;
                      setState(() {
                        _relX =
                            (_relX + details.delta.dx / size.width).clamp(
                              0.0,
                              1.0 - _relW,
                            );
                        _relY = (_relY + details.delta.dy / size.height).clamp(
                          0.0,
                          0.95,
                        );
                      });
                    },
                    // Scale: resize signature
                    onScaleStart: (_) {
                      _baseRelW = _relW;
                    },
                    onScaleUpdate: (details) {
                      setState(() {
                        _relW = (_baseRelW * details.scale).clamp(0.1, 0.9);
                      });
                    },
                    child: Stack(
                      children: [
                        // Page image
                        Positioned.fill(
                          child: Image.file(
                            File(widget.pageImagePath),
                            key: _imageKey,
                            fit: BoxFit.contain,
                          ),
                        ),

                        // Signature overlay
                        LayoutBuilder(
                          builder: (ctx, inner) {
                            final size = _imageRenderSize;
                            final sigLeft = _relX * size.width;
                            final sigTop = _relY * size.height;
                            final sigWidth = _relW * size.width;

                            // Centre the displayed stack inside the constraints
                            final offsetX =
                                (constraints.maxWidth - size.width) / 2;
                            final offsetY =
                                (constraints.maxHeight - size.height) / 2;

                            return Positioned(
                              left: offsetX + sigLeft,
                              top: offsetY + sigTop,
                              child: IgnorePointer(
                                child: Container(
                                  width: sigWidth,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: palette.accent.withOpacity(0.7),
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Image.memory(
                                    widget.signatureBytes,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // ── Bottom hint + cancel ──
            Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _applying ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white30),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _applying ? null : _apply,
                      icon: _applying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.done_all_rounded),
                      label: const Text('تطبيق وحفظ'),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
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
