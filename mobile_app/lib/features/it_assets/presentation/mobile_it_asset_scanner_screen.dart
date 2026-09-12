import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/services/permission_request_coordinator.dart';
import '../models/mobile_it_asset_models.dart';

enum ItAssetScanMode { lookup, sparePart, inventory }

class MobileItAssetScannerScreen extends ConsumerStatefulWidget {
  const MobileItAssetScannerScreen({
    super.key,
    this.initialMode = ItAssetScanMode.lookup,
  });

  final ItAssetScanMode initialMode;

  @override
  ConsumerState<MobileItAssetScannerScreen> createState() =>
      _MobileItAssetScannerScreenState();
}

class _MobileItAssetScannerScreenState
    extends ConsumerState<MobileItAssetScannerScreen>
    with WidgetsBindingObserver {
  late ItAssetScanMode _mode;
  final MobileScannerController _scannerController = MobileScannerController(
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _manualCodeController = TextEditingController();
  final _locationController = TextEditingController();
  final _employeeController = TextEditingController();
  bool _permissionGranted = false;
  bool _checkingPermission = true;
  bool _processing = false;
  bool _pausedAfterResult = false;
  List<MobileInventorySession> _sessions = const [];
  String? _selectedSessionId;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mode = widget.initialMode;
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_scannerController.dispose());
    _manualCodeController.dispose();
    _locationController.dispose();
    _employeeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_permissionGranted) return;
    if (state == AppLifecycleState.resumed && !_pausedAfterResult) {
      unawaited(_scannerController.start());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_scannerController.stop());
    }
  }

  Future<void> _initialize() async {
    final user = ref.read(authControllerProvider).valueOrNull;
    if (_mode == ItAssetScanMode.lookup && user?.canScanItAssets != true) {
      _mode = user?.canScanItSpareParts == true
          ? ItAssetScanMode.sparePart
          : ItAssetScanMode.inventory;
    }
    final status = await PermissionRequestCoordinator.run(
      Permission.camera.request,
    );
    if (!mounted) return;
    setState(() {
      _permissionGranted = status.isGranted;
      _checkingPermission = false;
    });
    if (status.isGranted) await _loadSessions();
  }

  Future<void> _loadSessions() async {
    final user = ref.read(authControllerProvider).valueOrNull;
    if (user?.canScanItInventory != true) return;
    try {
      final sessions = await ref
          .read(mobileItAssetsRepositoryProvider)
          .fetchActiveInventorySessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        if (_selectedSessionId == null && sessions.isNotEmpty) {
          _selectedSessionId = sessions.first.id;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.toString();
        _messageIsError = true;
      });
    }
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_processing || _pausedAfterResult) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim() ?? '')
        .firstWhere((entry) => entry.isNotEmpty, orElse: () => '');
    if (value.isNotEmpty) await _processCode(value);
  }

  Future<void> _processCode(String code) async {
    if (_processing || code.trim().isEmpty) return;
    setState(() {
      _processing = true;
      _message = null;
    });
    try {
      if (_mode == ItAssetScanMode.inventory) {
        if (_selectedSessionId == null) {
          throw Exception('اختر جلسة جرد نشطة أولًا.');
        }
        final duplicate = await ref
            .read(mobileItAssetsRepositoryProvider)
            .scanInventory(
              sessionId: _selectedSessionId!,
              code: code,
              foundLocation: _locationController.text.trim().isEmpty
                  ? null
                  : _locationController.text.trim(),
              foundEmployee: _employeeController.text.trim().isEmpty
                  ? null
                  : _employeeController.text.trim(),
            );
        if (!mounted) return;
        setState(() {
          _message = duplicate
              ? 'تم تسجيل الكود، لكنه كان ممسوحًا من قبل.'
              : 'تم تسجيل الجهاز في جلسة الجرد بنجاح.';
          _messageIsError = duplicate;
          _manualCodeController.clear();
        });
        await _loadSessions();
      } else if (_mode == ItAssetScanMode.sparePart) {
        final part = await ref
            .read(mobileItAssetsRepositoryProvider)
            .lookupSparePart(code);
        if (!mounted) return;
        _pausedAfterResult = true;
        await _scannerController.stop();
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobileSparePartDetailsScreen(part: part),
          ),
        );
        if (!mounted) return;
        _pausedAfterResult = false;
        await _scannerController.start();
      } else {
        final asset = await ref
            .read(mobileItAssetsRepositoryProvider)
            .lookupAsset(code);
        if (!mounted) return;
        _pausedAfterResult = true;
        await _scannerController.stop();
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobileItAssetDetailsScreen(asset: asset),
          ),
        );
        if (!mounted) return;
        _pausedAfterResult = false;
        await _scannerController.start();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.toString();
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    if (user == null || !user.canViewItAssets) {
      return const Scaffold(
        body: Center(child: Text('ليس لديك صلاحية لاستخدام ماسح أصول IT.')),
      );
    }
    final segments = <ButtonSegment<ItAssetScanMode>>[
      if (user.canScanItAssets)
        const ButtonSegment(
          value: ItAssetScanMode.lookup,
          icon: Icon(Icons.computer_outlined),
          label: Text('عرض جهاز'),
        ),
      if (user.canScanItSpareParts)
        const ButtonSegment(
          value: ItAssetScanMode.sparePart,
          icon: Icon(Icons.memory_outlined),
          label: Text('قطعة غيار'),
        ),
      if (user.canScanItInventory)
        const ButtonSegment(
          value: ItAssetScanMode.inventory,
          icon: Icon(Icons.inventory_rounded),
          label: Text('مسح جرد'),
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('ماسح أصول IT'),
        actions: [
          IconButton(
            tooltip: 'تبديل الكاميرا',
            onPressed: _permissionGranted
                ? _scannerController.switchCamera
                : null,
            icon: const Icon(Icons.cameraswitch_rounded),
          ),
          IconButton(
            tooltip: 'الفلاش',
            onPressed: _permissionGranted
                ? _scannerController.toggleTorch
                : null,
            icon: const Icon(Icons.flash_on_rounded),
          ),
        ],
      ),
      body: _checkingPermission
          ? const Center(child: CircularProgressIndicator())
          : !_permissionGranted
          ? _PermissionDenied(onOpenSettings: openAppSettings)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: SegmentedButton<ItAssetScanMode>(
                    segments: segments,
                    selected: {_mode},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _mode = selection.first;
                        _message = null;
                      });
                    },
                  ),
                ),
                if (_mode == ItAssetScanMode.inventory) _inventoryControls(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(
                            controller: _scannerController,
                            onDetect: _handleDetection,
                          ),
                          const _ScannerOverlay(),
                          if (_processing)
                            Container(
                              color: Colors.black45,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (_messageIsError ? Colors.red : Colors.green)
                            .withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _messageIsError
                              ? Colors.red.shade700
                              : Colors.green.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manualCodeController,
                          onSubmitted: _processCode,
                          decoration: const InputDecoration(
                            labelText: 'إدخال الكود يدويًا',
                            prefixIcon: Icon(Icons.keyboard_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _processing
                            ? null
                            : () => _processCode(
                                _manualCodeController.text.trim(),
                              ),
                        child: const Text('تنفيذ'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _inventoryControls() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _sessions.any((entry) => entry.id == _selectedSessionId)
              ? _selectedSessionId
              : null,
          decoration: const InputDecoration(labelText: 'جلسة الجرد'),
          items: _sessions
              .map(
                (session) => DropdownMenuItem(
                  value: session.id,
                  child: Text(
                    '${session.recordNumber} (${session.scannedCount}/${session.expectedCount})',
                  ),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _selectedSessionId = value),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'المكان الفعلي - اختياري',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _employeeController,
                decoration: const InputDecoration(
                  labelText: 'الموظف الفعلي - اختياري',
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class MobileItAssetDetailsScreen extends StatelessWidget {
  const MobileItAssetDetailsScreen({super.key, required this.asset});

  final MobileItAsset asset;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(asset.assetCode)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _detail('نوع الجهاز', asset.assetType),
                _detail('الماركة والموديل', '${asset.brand} ${asset.model}'),
                _detail('Serial Number', asset.serialNumber ?? '-'),
                _detail('الحالة', asset.status),
                _detail('حالة الجهاز', asset.condition),
                _detail('الفرع', asset.branchName),
                _detail('المكان الحالي', asset.location),
                _detail('الموظف المستلم', asset.assignedTo),
                _detail('ملاحظات', asset.notes),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'سجل الجهاز',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (asset.timeline.isEmpty)
          const Text('لا توجد حركات مسجلة.')
        else
          ...asset.timeline.reversed.map(
            (entry) => ListTile(
              leading: const Icon(Icons.timeline_rounded),
              title: Text(entry.details),
              subtitle: Text(
                '${entry.performedByName}'
                '${entry.documentNumber == null ? '' : ' • ${entry.documentNumber}'}',
              ),
            ),
          ),
      ],
    ),
  );

  static Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 125,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: Text(value.isEmpty ? '-' : value)),
      ],
    ),
  );
}

class MobileSparePartDetailsScreen extends StatelessWidget {
  const MobileSparePartDetailsScreen({super.key, required this.part});

  final MobileSparePart part;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(part.partCode)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  part.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                MobileItAssetDetailsScreen._detail('التصنيف', part.category),
                MobileItAssetDetailsScreen._detail(
                  'المتاح للاستخدام',
                  '${part.usableQuantity}',
                ),
                MobileItAssetDetailsScreen._detail(
                  'إجمالي المخزون',
                  '${part.quantityAvailable}',
                ),
                MobileItAssetDetailsScreen._detail(
                  'المحجوز',
                  '${part.quantityReserved}',
                ),
                MobileItAssetDetailsScreen._detail(
                  'التالف',
                  '${part.damagedQuantity}',
                ),
                MobileItAssetDetailsScreen._detail(
                  'حد إعادة الطلب',
                  '${part.minimumQuantity}',
                ),
                MobileItAssetDetailsScreen._detail('المكان', part.location),
                if (part.isLowStock)
                  const Card(
                    color: Color(0xFFFFE0B2),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'تنبيه: الرصيد المتاح وصل إلى حد إعادة الطلب أو أقل.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _PermissionDenied extends StatelessWidget {
  const _PermissionDenied({required this.onOpenSettings});
  final Future<bool> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, size: 56),
          const SizedBox(height: 16),
          const Text(
            'يجب السماح باستخدام الكاميرا لمسح QR وBarcode.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onOpenSettings,
            child: const Text('فتح إعدادات التطبيق'),
          ),
        ],
      ),
    ),
  );
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        width: 250,
        height: 250,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white, width: 3),
        ),
      ),
    ),
  );
}
