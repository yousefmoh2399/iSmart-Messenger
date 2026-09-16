import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/signature_composer_service.dart';

/// Allows the user to position and resize a signature on top of a scanned page.
///
/// Returns the composited JPEG [Uint8List] or null if the user cancels.
class SignaturePlacementScreen extends StatefulWidget {
  const SignaturePlacementScreen({
    super.key,
    required this.pageImagePath,
    required this.signatureBytes,
  });

  final String pageImagePath;
  final Uint8List signatureBytes;

  @override
  State<SignaturePlacementScreen> createState() =>
      _SignaturePlacementScreenState();
}

class _SignaturePlacementScreenState extends State<SignaturePlacementScreen> {
  // Relative position of the signature top-left corner (0.0–1.0 of IMAGE bounds)
  double _relX = 0.05;
  double _relY = 0.70;

  // Signature width as a fraction of the page width (0.0–1.0)
  double _relW = 0.40;
  double _baseRelW = 0.40;

  bool _applying = false;

  // Natural image dimensions (loaded once in initState)
  Size _imageNaturalSize = Size.zero;

  final GlobalKey _stackKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    final bytes = await File(widget.pageImagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    if (mounted) {
      setState(() {
        _imageNaturalSize = Size(
          image.width.toDouble(),
          image.height.toDouble(),
        );
      });
    }
  }

  /// The area (in stack-local coordinates) that the image actually occupies
  /// after BoxFit.contain letterboxing.
  Rect _imageFitRect(Size stackSize) {
    if (_imageNaturalSize == Size.zero || stackSize == Size.zero) {
      return Rect.fromLTWH(0, 0, stackSize.width, stackSize.height);
    }

    final scaleX = stackSize.width / _imageNaturalSize.width;
    final scaleY = stackSize.height / _imageNaturalSize.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final renderedW = _imageNaturalSize.width * scale;
    final renderedH = _imageNaturalSize.height * scale;
    final offsetX = (stackSize.width - renderedW) / 2;
    final offsetY = (stackSize.height - renderedH) / 2;

    return Rect.fromLTWH(offsetX, offsetY, renderedW, renderedH);
  }

  Size get _stackSize {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size ?? Size.zero;
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
                  final stackSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final fitRect = _imageFitRect(stackSize);

                  // Convert relative-to-image coords → screen coords for display
                  final screenLeft = fitRect.left + _relX * fitRect.width;
                  final screenTop = fitRect.top + _relY * fitRect.height;
                  final screenWidth = _relW * fitRect.width;

                  return GestureDetector(
                    // Single gesture handler for both drag and pinch
                    onScaleStart: (_) {
                      _baseRelW = _relW;
                    },
                    onScaleUpdate: (details) {
                      if (fitRect.width == 0 || fitRect.height == 0) return;
                      setState(() {
                        // Move (single finger = focalPointDelta)
                        final dxRel =
                            details.focalPointDelta.dx / fitRect.width;
                        final dyRel =
                            details.focalPointDelta.dy / fitRect.height;
                        _relX = (_relX + dxRel).clamp(0.0, 1.0 - _relW);
                        _relY = (_relY + dyRel).clamp(0.0, 0.95);

                        // Resize (two fingers = scale != 1)
                        if (details.pointerCount >= 2) {
                          _relW =
                              (_baseRelW * details.scale).clamp(0.05, 0.95);
                        }
                      });
                    },
                    child: Stack(
                      key: _stackKey,
                      fit: StackFit.expand,
                      children: [
                        // Page image
                        Image.file(
                          File(widget.pageImagePath),
                          fit: BoxFit.contain,
                        ),

                        // Signature overlay — positioned in screen coords
                        if (fitRect.width > 0)
                          Positioned(
                            left: screenLeft,
                            top: screenTop,
                            child: IgnorePointer(
                              child: Container(
                                width: screenWidth,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: palette.accent.withOpacity(0.8),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Image.memory(
                                  widget.signatureBytes,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                ),
                              ),
                            ),
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
