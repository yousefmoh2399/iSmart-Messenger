import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/image_filter_type.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../data/image_processing_service.dart';

enum _ScanQualityMode { auto, pro, fast }

class ScanReviewScreen extends ConsumerStatefulWidget {
  const ScanReviewScreen({
    super.key,
    required this.rawImagePath,
    required this.sessionId,
  });

  final String rawImagePath;
  final String sessionId;

  @override
  ConsumerState<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends ConsumerState<ScanReviewScreen>
    with SingleTickerProviderStateMixin {
  ImageFilterType _filter = ImageFilterType.document;
  int _quarterTurns = 0;
  _ScanQualityMode _qualityMode = _ScanQualityMode.fast;
  Uint8List? _previewBytes;
  Uint8List? _sourceBytes;
  bool _busy = false;
  String? _statusMessage;
  int _requestId = 0;
  late final AnimationController _scanLineController;
  final Map<String, Uint8List> _previewCache = {};

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _loadInitialPreview();
  }

  @override
  void dispose() {
    _previewCache.clear();
    _scanLineController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialPreview() async {
    final sourceBytes = await File(widget.rawImagePath).readAsBytes();
    if (!mounted) return;

    setState(() {
      _sourceBytes = sourceBytes;
      _previewBytes = sourceBytes;
      _statusMessage = null;
      _busy = false;
    });

    _rebuildPreview();
  }

  Future<void> _rebuildPreview() async {
    final requestId = ++_requestId;
    final cacheKey = '${_filter.index}-$_quarterTurns-${_qualityMode.name}';

    if (_previewCache.containsKey(cacheKey)) {
      setState(() {
        _previewBytes = _previewCache[cacheKey];
        _busy = false;
        _statusMessage = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _statusMessage = switch (_filter) {
        ImageFilterType.document =>
          'جار اكتشاف الحواف، تصحيح المنظور، وتنظيف الورقة...',
        ImageFilterType.color =>
          'جار تحسين الإضاءة والخلفية مع الحفاظ على الألوان...',
        ImageFilterType.grayscale =>
          'جار إبراز النص وتنظيف الصفحة في الوضع الرمادي...',
        ImageFilterType.blackWhite =>
          'جار تحويل الصفحة إلى أبيض وأسود واضح للطباعة...',
      };
    });

    try {
      final sourceBytes = _sourceBytes ??= await File(
        widget.rawImagePath,
      ).readAsBytes();

      final imageProcessingService = ref.read(imageProcessingServiceProvider);
      Uint8List bytes;
      final previewPreferredQuality = switch (_qualityMode) {
        _ScanQualityMode.auto => ScanProcessingQuality.balanced,
        _ScanQualityMode.pro => ScanProcessingQuality.enhanced,
        _ScanQualityMode.fast => ScanProcessingQuality.preview,
      };
      final previewTimeout = switch (_qualityMode) {
        _ScanQualityMode.auto => const Duration(seconds: 9),
        _ScanQualityMode.pro => const Duration(seconds: 18),
        _ScanQualityMode.fast => const Duration(seconds: 5),
      };
      try {
        bytes = await imageProcessingService
            .transformBytes(
              bytes: sourceBytes,
              filter: _filter,
              quarterTurns: _quarterTurns,
              quality: previewPreferredQuality,
            )
            .timeout(previewTimeout);
      } on TimeoutException {
        if (!mounted || requestId != _requestId) return;
        if (_qualityMode == _ScanQualityMode.pro) {
          rethrow;
        }
        setState(() {
          _statusMessage =
              'الجهاز احتاج وقتًا أطول؛ تم التحويل تلقائيًا إلى وضع سريع متوازن للحفاظ على جودة احترافية.';
        });
        bytes = await imageProcessingService
            .transformBytes(
              bytes: sourceBytes,
              filter: _filter,
              quarterTurns: _quarterTurns,
              quality: ScanProcessingQuality.preview,
            )
            .timeout(const Duration(seconds: 8));
      }
      if (!mounted || requestId != _requestId) return;
      setState(() {
        // Before adding to cache, limit to max 4 entries (one per filter type)
        if (_previewCache.length >= 4) {
          _previewCache.remove(_previewCache.keys.first);
        }
        _previewCache[cacheKey] = bytes;
        _previewBytes = bytes;
        _busy = false;
        _statusMessage = null;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _previewBytes = _sourceBytes;
        _busy = false;
        _statusMessage = error is TimeoutException
            ? 'المعالجة استغرقت وقتًا طويلًا على هذا الجهاز. تم عرض النسخة الأصلية مؤقتًا.'
            : 'تعذر تطبيق التحسين الآن على الهاتف. تم عرض النسخة الأصلية ويمكنك المحاولة مرة أخرى.';
      });
    }
  }

  Future<void> _confirm() async {
    final previewBytes = _previewBytes;
    if (previewBytes == null) return;
    if (mounted) {
      setState(() {
        _busy = true;
        _statusMessage = 'جار تجهيز النسخة النهائية بجودة سكانر احترافية...';
      });
    }

    try {
      final pageId = const Uuid().v4();
      final imagePath = await ref
          .read(localDocumentStoreProvider)
          .savePageBytes(
            sessionId: widget.sessionId,
            pageId: pageId,
            bytes: previewBytes,
          );

      if (!mounted) return;
      Navigator.pop(
        context,
        ScanPage(id: pageId, imagePath: imagePath, createdAt: DateTime.now()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusMessage = 'حدث خطأ أثناء الحفظ. حاول مرة أخرى.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('مراجعة الصفحة')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final previewHeight = (constraints.maxHeight * 0.48).clamp(
              280.0,
              520.0,
            );
            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: 16 + bottomInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        height: previewHeight,
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Center(
                                child: _previewBytes == null
                                    ? const Text('جار تحميل الصفحة...')
                                    : Image.memory(
                                        _previewBytes!,
                                        fit: BoxFit.contain,
                                        cacheWidth: 1400,
                                      ),
                              ),
                              if (_busy)
                                _ScannerLoadingOverlay(
                                  controller: _scanLineController,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_statusMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _statusMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF92400E)),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final filter in ImageFilterType.values)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: ChoiceChip(
                                  label: Text(filter.label),
                                  selected: filter == _filter,
                                  onSelected: _busy
                                      ? null
                                      : (_) {
                                          setState(() => _filter = filter);
                                          _rebuildPreview();
                                        },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: SegmentedButton<_ScanQualityMode>(
                        segments: const [
                          ButtonSegment<_ScanQualityMode>(
                            value: _ScanQualityMode.auto,
                            label: Text('تلقائي'),
                            icon: Icon(Icons.auto_awesome_rounded),
                          ),
                          ButtonSegment<_ScanQualityMode>(
                            value: _ScanQualityMode.pro,
                            label: Text('احترافي'),
                            icon: Icon(Icons.workspace_premium_rounded),
                          ),
                          ButtonSegment<_ScanQualityMode>(
                            value: _ScanQualityMode.fast,
                            label: Text('سريع'),
                            icon: Icon(Icons.speed_rounded),
                          ),
                        ],
                        selected: {_qualityMode},
                        onSelectionChanged: _busy
                            ? null
                            : (selection) {
                                if (selection.isEmpty) {
                                  return;
                                }
                                setState(() => _qualityMode = selection.first);
                                _rebuildPreview();
                              },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Text(
                        switch (_qualityMode) {
                          _ScanQualityMode.auto =>
                            'تلقائي: أعلى جودة ممكنة مع تحويل ذكي لو الجهاز بطيء.',
                          _ScanQualityMode.pro =>
                            'احترافي: أقصى تحسين للنص والورق، وقد يأخذ وقتًا أطول.',
                          _ScanQualityMode.fast =>
                            'سريع: أسرع معاينة وحفظ مع جودة ممتازة للأجهزة المتوسطة.',
                        },
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'وضع "مسح ذكي" أصبح يكتشف حدود الورقة، يصحح الميل والمنظور، يخفف الظلال والتجاعيد، وينظف الخلفية ليجعل الصفحة أقرب لنتيجة سكانر حقيقي.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      setState(
                                        () => _quarterTurns =
                                            (_quarterTurns + 3) % 4,
                                      );
                                      _rebuildPreview();
                                    },
                              icon: const Icon(Icons.rotate_left),
                              label: const Text('تدوير'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _confirm,
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('اعتماد الصفحة'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ScannerLoadingOverlay extends StatelessWidget {
  const _ScannerLoadingOverlay({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.white.withValues(alpha: 0.28),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final travelHeight = (constraints.maxHeight - 120).clamp(
              40.0,
              400.0,
            );

            return Stack(
              children: [
                const Positioned(
                  top: 24,
                  left: 24,
                  right: 24,
                  child: Column(
                    children: [
                      Text(
                        'جار تجهيز المستند',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'يتم تحسين الورقة وتنظيف الخلفية وإبراز النص.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, child) {
                    final top = 90 + (travelHeight * controller.value);
                    return Positioned(
                      top: top,
                      left: 28,
                      right: 28,
                      child: child!,
                    );
                  },
                  child: Column(
                    children: [
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Colors.transparent,
                              Color(0xFF0F766E),
                              Colors.transparent,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(99),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x660F766E),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
