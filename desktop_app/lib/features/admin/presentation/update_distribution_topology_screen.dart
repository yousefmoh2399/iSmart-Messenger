import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../chat/data/chat_socket_service.dart';
import '../../chat/models/chat_models.dart';
import '../models/update_management_models.dart';

/// Active device pulling an update on the live n8n canvas (100% real data).
/// Appears when an update command is dispatched or when real telemetry arrives,
/// turns green ONLY when the real update completes, and disappears 5 seconds after completion.
class _ActivePullingDevice {
  _ActivePullingDevice({
    required this.id,
    required this.deviceUid,
    required this.hostname,
    required this.cashierName,
    required this.username,
    required this.branchName,
    required this.branchCode,
    required this.ipAddress,
    required this.originalVersion,
    required this.targetVersion,
    required this.slotIndex,
    required this.position,
    this.phase = 'dispatching', // 'dispatching', 'awaiting_pull', 'pulling', 'completed', 'failed'
    this.progress = 0.05,
  });

  final String id;
  final String deviceUid;
  final String hostname;
  final String cashierName;
  final String username;
  final String branchName;
  final String branchCode;
  final String ipAddress;
  final String originalVersion;
  final String targetVersion;
  final int slotIndex;
  Offset position;

  String phase;
  double progress;
  double speedMbps = 0.0;
  int chunksPulled = 0;
  final int totalChunks = 10;
  bool isCompleted = false;
  bool hasError = false;
  String statusMessage = 'جاري إرسال أمر التحديث للجهاز...';
  int remainingSeconds = 5;
  int awaitingPullSeconds = 8;
}

/// Persistent device entry representing real registered fleet devices in the database.
class _FleetUpdateDevice {
  _FleetUpdateDevice({
    required this.id,
    required this.deviceUid,
    required this.hostname,
    required this.cashierName,
    required this.username,
    required this.branchName,
    required this.branchCode,
    required this.ipAddress,
    required this.currentVersion,
    required this.targetVersion,
    required this.isOnline,
    required this.os,
    required this.updateStatus,
    required this.updateProgress,
    this.updateError,
    this.isUpdated = false,
  });

  final String id;
  final String deviceUid;
  final String hostname;
  final String cashierName;
  final String username;
  final String branchName;
  final String branchCode;
  final String ipAddress;
  String currentVersion;
  final String targetVersion;
  final bool isOnline;
  final String os;
  String updateStatus;
  int updateProgress;
  String? updateError;
  bool isUpdated;
}

/// Authentic n8n-style Update Distribution Network Screen (100% Real Telemetry & Database State).
class UpdateDistributionTopologyScreen extends ConsumerStatefulWidget {
  const UpdateDistributionTopologyScreen({
    super.key,
    required this.releases,
    required this.devices,
    required this.branches,
    this.targetVersion,
    this.onReload,
    this.isEmbedded = false,
  });

  final List<ManagedUpdateRelease> releases;
  final List<ManagedUpdateDevice> devices;
  final List<BranchSummary> branches;
  final String? targetVersion;
  final Future<void> Function()? onReload;
  final bool isEmbedded;

  @override
  ConsumerState<UpdateDistributionTopologyScreen> createState() =>
      _UpdateDistributionTopologyScreenState();
}

class _UpdateDistributionTopologyScreenState
    extends ConsumerState<UpdateDistributionTopologyScreen>
    with SingleTickerProviderStateMixin {
  int _activeTab = 0; // 0 = n8n Map, 1 = Outdated, 2 = Updated, 3 = Logs

  late final AnimationController _pulseController;
  Timer? _countdownTicker;
  Timer? _backendSyncTicker;

  StreamSubscription<ChatSocketEvent>? _socketSub;
  bool _isSocketConnected = false;
  bool _isAutoRolloutActive = false;
  bool _isReloading = false;

  String _targetVersion = '1.1.22';
  ManagedUpdateRelease? _activeRelease;

  // Active pulling devices visible on the n8n canvas (unlimited non-overlapping slots)
  final List<_ActivePullingDevice> _canvasPullingDevices = [];

  // Complete directory of REAL physical devices from database
  final List<_FleetUpdateDevice> _allFleetDevices = [];
  final List<Map<String, dynamic>> _distributionLogs = [];

  // Search & filter state
  String _searchFilter = '';
  String _selectedBranch = 'all';

  // Canvas Dimensions & Geometry Constants (sized so text NEVER overflows outside cards)
  final TransformationController _interactiveController =
      TransformationController();
  static const Size _serverSize = Size(315, 132);
  static const Size _deviceCardSize = Size(285, 118);
  static const int _rowsPerColumn = 4;
  static const double _rowGap = 18.0;
  static const double _colGap = 36.0;
  static const double _wireCorridorGap = 105.0;

  Offset _serverPosition = const Offset(410, 260);
  double _lastCanvasWidth = 1180.0;
  double _lastCanvasHeight = 680.0;

  int _getSideColumnCount() {
    if (_canvasPullingDevices.isEmpty) return 1;
    int maxSlot = 0;
    for (final d in _canvasPullingDevices) {
      if (d.slotIndex > maxSlot) maxSlot = d.slotIndex;
    }
    // Each pair of columns (Left + Right) holds `_rowsPerColumn * 2` = 8 devices
    return (maxSlot ~/ (_rowsPerColumn * 2)) + 1;
  }

  Offset _computeSlotCoordinate(
      int slotIndex, double canvasWidth, double canvasHeight) {
    const slotsPerPair = _rowsPerColumn * 2; // 8 slots per (Left, Right) column pair
    final pairColIndex = slotIndex ~/ slotsPerPair; // 0 = inner columns, 1 = outer columns, etc.
    final rem = slotIndex % slotsPerPair;
    final isLeft = rem.isEven; // Alternate Left (0, 2, 4, 6) and Right (1, 3, 5, 7) symmetrically
    final row = rem ~/ 2; // 0..3

    final serverX = (canvasWidth - _serverSize.width) / 2.0;

    final leftX = serverX -
        _wireCorridorGap -
        _deviceCardSize.width -
        (pairColIndex * (_deviceCardSize.width + _colGap));
    final rightX = serverX +
        _serverSize.width +
        _wireCorridorGap +
        (pairColIndex * (_deviceCardSize.width + _colGap));
    final x = isLeft ? leftX : rightX;

    const totalColHeight =
        (_rowsPerColumn * 118.0) + ((_rowsPerColumn - 1) * _rowGap); // 526.0
    final startY = math.max(36.0, (canvasHeight - totalColHeight) / 2.0);
    final staggerY = pairColIndex.isOdd ? 16.0 : 0.0;
    final y = startY + staggerY + (row * (_deviceCardSize.height + _rowGap));
    return Offset(x, y);
  }

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _initTargetRelease();
    _buildFleetDevices();
    _buildInitialLogs();

    // 1-Second Ticker for countdowns
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _tickDeviceCountdowns();
    });

    // Periodic real backend sync while devices are actively pulling
    _backendSyncTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (_canvasPullingDevices.any((d) => !d.isCompleted && !d.hasError)) {
        unawaited(widget.onReload?.call());
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _listenToLiveSocket();
      }
    });
  }

  @override
  void didUpdateWidget(covariant UpdateDistributionTopologyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.releases != widget.releases ||
        oldWidget.devices != widget.devices ||
        oldWidget.targetVersion != widget.targetVersion) {
      _initTargetRelease();
      _buildFleetDevices();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _interactiveController.dispose();
    _countdownTicker?.cancel();
    _backendSyncTicker?.cancel();
    _socketSub?.cancel();
    super.dispose();
  }

  void _initTargetRelease() {
    if (widget.releases.isNotEmpty) {
      _activeRelease = widget.releases.firstWhere(
        (r) => widget.targetVersion != null && r.version == widget.targetVersion,
        orElse: () => widget.releases.first,
      );
      _targetVersion = widget.targetVersion ?? _activeRelease!.version;
    } else {
      _targetVersion = widget.targetVersion ?? '1.1.22';
    }
  }

  void _buildInitialLogs() {
    _distributionLogs.clear();
    final now = DateTime.now();
    _distributionLogs.add({
      'time': _formatTime(now),
      'level': 'SUCCESS',
      'source': 'ReleaseHub',
      'message':
          'خادم التحديثات المركزي جاهز بالنسخة المعتمدة v$_targetVersion (يعرض الأجهزة والبيانات الحقيقية فقط من السيرفر).',
    });
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  void _listenToLiveSocket() {
    _socketSub?.cancel();
    final socketService = ref.read(chatSocketServiceProvider);
    setState(() {
      _isSocketConnected = socketService.isConnected;
    });

    _socketSub = socketService.events.listen((event) {
      if (!mounted) return;
      if (event.type == 'socket_connected') {
        setState(() => _isSocketConnected = true);
        _logEvent('SUCCESS', 'WebSocket',
            '🟢 متصل بالسيرفر المركزي لحظياً - متابعة التحديثات الحقيقية نشطة');
      } else if (event.type == 'socket_disconnected' ||
          event.type == 'socket_reconnecting') {
        setState(() => _isSocketConnected = false);
      } else if (event.type == 'update_telemetry' ||
          event.type == 'updates_updated') {
        _handleLiveTelemetryEvent(event.payload);
      }
    });
  }

  void _handleLiveTelemetryEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    final action = (data['action'] ?? '').toString();
    if (action == 'release_created' ||
        action == 'release_updated' ||
        action == 'job_created') {
      unawaited(widget.onReload?.call());
      if (action == 'job_created') {
        return;
      }
    }

    final deviceUid = (data['deviceUid'] ?? '').toString();
    final deviceId = (data['deviceId'] ?? '').toString();
    final hostName =
        (data['hostName'] ?? data['deviceName'] ?? '').toString();
    final status = (data['status'] ?? '').toString().toLowerCase();
    final rawProgress = data['progress'];
    final progressPct =
        (rawProgress is num ? rawProgress.toDouble() : 0.0).clamp(0.0, 100.0);
    final progressVal = progressPct / 100.0;
    final message = (data['message'] ?? '').toString();
    final targetVer = (data['targetVersion'] ?? _targetVersion).toString();

    // Match real fleet device
    _FleetUpdateDevice? match;
    for (final dev in _allFleetDevices) {
      if ((deviceId.isNotEmpty && dev.id == deviceId) ||
          (deviceUid.isNotEmpty &&
              dev.deviceUid.isNotEmpty &&
              dev.deviceUid == deviceUid) ||
          (hostName.isNotEmpty &&
              dev.hostname.toLowerCase() == hostName.toLowerCase())) {
        match = dev;
        break;
      }
    }

    if (match == null) {
      final fallbackHost = hostName.isNotEmpty
          ? hostName
          : (deviceUid.isNotEmpty ? 'Device-$deviceUid' : 'POS-Terminal');
      match = _FleetUpdateDevice(
        id: deviceId.isNotEmpty
            ? deviceId
            : 'dev_${deviceUid.isNotEmpty ? deviceUid : DateTime.now().millisecondsSinceEpoch}',
        deviceUid: deviceUid,
        hostname: fallbackHost,
        cashierName: (data['deviceName'] ?? data['lastKnownFullName'] ?? 'جهاز نشط بالفرع').toString(),
        username: (data['username'] ?? '-').toString(),
        branchName: data['branchCode'] != null && data['branchCode'] != '00' && data['branchCode'] != 'MAIN'
            ? 'فرع ${data['branchCode']}'
            : 'الفرع',
        branchCode: (data['branchCode'] ?? '00').toString(),
        ipAddress: (data['clientIp'] ?? '-').toString(),
        currentVersion: (data['currentVersion'] ?? '1.1.20').toString(),
        targetVersion: targetVer,
        isOnline: true,
        os: (data['platform'] ?? '').toString().contains('mobile')
            ? 'Android'
            : 'Windows Desktop',
        updateStatus: status,
        updateProgress: progressPct.toInt(),
        isUpdated: status == 'completed',
      );
      _allFleetDevices.add(match);
      unawaited(widget.onReload?.call());
    }

    _ActivePullingDevice? onCanvas;
    for (final c in _canvasPullingDevices) {
      if (c.id == match.id ||
          (match.deviceUid.isNotEmpty && c.deviceUid == match.deviceUid) ||
          (match.hostname.isNotEmpty && c.hostname.toLowerCase() == match.hostname.toLowerCase())) {
        onCanvas = c;
        break;
      }
    }

    if (onCanvas == null &&
        (status == 'downloading' ||
            status == 'installing' ||
            status == 'acknowledged' ||
            status == 'completed' ||
            status == 'failed')) {
      onCanvas = _spawnDeviceOnCanvas(
        match,
        initialPhase: status == 'completed' ? 'completed' : 'pulling',
      );
    }

    if (onCanvas != null) {
      if (status == 'completed') {
        HapticFeedback.heavyImpact();
        setState(() {
          onCanvas!.phase = 'completed';
          onCanvas.progress = 1.0;
          onCanvas.chunksPulled = onCanvas.totalChunks;
          onCanvas.isCompleted = true;
          onCanvas.hasError = false;
          onCanvas.statusMessage = 'تم التثبيت والمطابقة بنجاح ✓';
          onCanvas.remainingSeconds = 25;
          match!.isUpdated = true;
          match.currentVersion = targetVer;
          match.updateStatus = 'completed';
          match.updateProgress = 100;
        });
        _logEvent('SUCCESS', match.hostname,
            '✅ [بيانات حقيقية] اكتمل سحب وتثبيت التحديث v$targetVer للجهاز ${match.hostname} بنجاح!');
        unawaited(widget.onReload?.call());
      } else if (status == 'failed' || status == 'cancelled') {
        setState(() {
          onCanvas!.phase = 'failed';
          onCanvas.hasError = true;
          onCanvas.statusMessage =
              message.isNotEmpty ? message : 'تعذر إكمال التحديث';
          onCanvas.remainingSeconds = 15;
          match!.updateStatus = status;
          match.updateError = onCanvas.statusMessage;
        });
        _logEvent('ERROR', match.hostname,
            '❌ [بيانات حقيقية] فشل تحديث الجهاز ${match.hostname}: ${onCanvas.statusMessage}');
        unawaited(widget.onReload?.call());
      } else {
        setState(() {
          onCanvas!.phase = 'pulling';
          onCanvas.hasError = false;
          onCanvas.progress = progressVal.clamp(0.08, 0.98);
          onCanvas.speedMbps = 14.2;
          onCanvas.chunksPulled = (onCanvas.progress * onCanvas.totalChunks)
              .round()
              .clamp(1, onCanvas.totalChunks);
          onCanvas.statusMessage = message.isNotEmpty
              ? message
              : (status == 'installing'
                  ? 'جاري تثبيت الحزمة على الجهاز...'
                  : 'جاري سحب حزمة التحديث من السيرفر...');
          match!.updateStatus = status;
          match.updateProgress = progressPct.round();
        });
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // 100% REAL FLEET DATA INITIALIZATION (ZERO FAKE DEMO PEOPLE)
  // ══════════════════════════════════════════════════════════════════════════════
  void _buildFleetDevices() {
    _allFleetDevices.clear();

    // Populate strictly from real `widget.devices` stored in database
    for (final d in widget.devices) {
      final host = (d.hostName != null && d.hostName!.trim().isNotEmpty)
          ? d.hostName!.trim()
          : ((d.deviceName != null && d.deviceName!.trim().isNotEmpty)
              ? d.deviceName!.trim()
              : (d.deviceUid.isNotEmpty
                  ? d.deviceUid
                  : 'POS-${d.branchCode}'));
      final cashier =
          (d.lastKnownFullName != null && d.lastKnownFullName!.trim().isNotEmpty)
              ? d.lastKnownFullName!.trim()
              : ((d.lastKnownUsername != null &&
                      d.lastKnownUsername!.trim().isNotEmpty)
                  ? d.lastKnownUsername!.trim()
                  : 'موظف الفرع');
      final bName = widget.branches
          .firstWhere(
            (b) => b.code == d.branchCode,
            orElse: () => BranchSummary(
              id: '',
              name: 'فرع ${d.branchCode}',
              code: d.branchCode,
              description: '',
              membersCount: 0,
            ),
          )
          .name;

      final currentVer =
          d.appVersion.trim().isNotEmpty ? d.appVersion.trim() : 'غير معروف';
      final isUp = currentVer == _targetVersion.trim() ||
          (d.updateStatus.toLowerCase() == 'completed' &&
              d.updateTargetVersion == _targetVersion.trim());

      final fleetDev = _FleetUpdateDevice(
        id: d.id,
        deviceUid: d.deviceUid,
        hostname: host,
        cashierName: cashier,
        username: d.lastKnownUsername ?? '-',
        branchName: bName,
        branchCode: d.branchCode,
        ipAddress: (d.localIp != null && d.localIp!.trim().isNotEmpty)
            ? d.localIp!.trim()
            : '-',
        currentVersion: isUp ? _targetVersion : currentVer,
        targetVersion: _targetVersion,
        isOnline: d.isOnline,
        os: d.platform == 'mobile_android' ? 'Android' : 'Windows Desktop',
        updateStatus: d.updateStatus,
        updateProgress: d.updateProgress,
        updateError: d.updateError,
        isUpdated: isUp,
      );

      _allFleetDevices.add(fleetDev);

      // Sync with any existing canvas card or spawn if currently downloading/installing in real life
      final st = d.updateStatus.toLowerCase();
      _ActivePullingDevice? existingCanvas;
      for (final c in _canvasPullingDevices) {
        if (c.id == fleetDev.id ||
            (fleetDev.deviceUid.isNotEmpty &&
                c.deviceUid == fleetDev.deviceUid)) {
          existingCanvas = c;
          break;
        }
      }

      if (existingCanvas != null) {
        if (isUp && !existingCanvas.isCompleted) {
          existingCanvas.phase = 'completed';
          existingCanvas.progress = 1.0;
          existingCanvas.chunksPulled = existingCanvas.totalChunks;
          existingCanvas.isCompleted = true;
          existingCanvas.statusMessage = 'محدث ومطابق بنجاح ✓';
          existingCanvas.remainingSeconds = 5;
        } else if (st == 'downloading' || st == 'installing') {
          existingCanvas.phase = 'pulling';
          existingCanvas.progress =
              (d.updateProgress / 100.0).clamp(0.1, 0.98);
          existingCanvas.chunksPulled =
              (existingCanvas.progress * existingCanvas.totalChunks)
                  .round()
                  .clamp(1, existingCanvas.totalChunks);
        }
      } else if (!isUp && (st == 'downloading' || st == 'installing')) {
        final spawned = _spawnDeviceOnCanvas(fleetDev, initialPhase: 'pulling');
        if (spawned != null) {
          spawned.progress = (d.updateProgress / 100.0).clamp(0.1, 0.95);
          spawned.chunksPulled =
              (spawned.progress * spawned.totalChunks).round().clamp(1, 10);
          spawned.statusMessage = st == 'installing'
              ? 'جاري تثبيت التحديث...'
              : 'جاري سحب التحديث من السيرفر...';
        }
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // ALLOCATE NON-OVERLAPPING SLOTS & DISPATCH REAL BACKEND UPDATE JOBS
  // ══════════════════════════════════════════════════════════════════════════════
  int _allocateFreeSlotIndex() {
    final used = _canvasPullingDevices.map((d) => d.slotIndex).toSet();
    int candidate = 0;
    while (used.contains(candidate)) {
      candidate++;
    }
    return candidate;
  }

  _ActivePullingDevice? _spawnDeviceOnCanvas(
    _FleetUpdateDevice dev, {
    String initialPhase = 'dispatching',
  }) {
    for (final existing in _canvasPullingDevices) {
      if (existing.id == dev.id ||
          (dev.deviceUid.isNotEmpty && existing.deviceUid == dev.deviceUid)) {
        return existing;
      }
    }

    final freeSlot = _allocateFreeSlotIndex();
    final slotPos =
        _computeSlotCoordinate(freeSlot, _lastCanvasWidth, _lastCanvasHeight);

    final activeDev = _ActivePullingDevice(
      id: dev.id,
      deviceUid: dev.deviceUid,
      hostname: dev.hostname,
      cashierName: dev.cashierName,
      username: dev.username,
      branchName: dev.branchName,
      branchCode: dev.branchCode,
      ipAddress: dev.ipAddress,
      originalVersion: dev.currentVersion,
      targetVersion: _targetVersion,
      slotIndex: freeSlot,
      position: slotPos,
      phase: initialPhase,
      progress: initialPhase == 'pulling' ? 0.15 : 0.06,
    );

    setState(() {
      _canvasPullingDevices.add(activeDev);
    });

    return activeDev;
  }

  Future<void> _reloadRealData() async {
    if (_isReloading) return;
    setState(() => _isReloading = true);
    try {
      await widget.onReload?.call();
      _logEvent('INFO', 'Server',
          '🔄 تم تحديث قائمة الأجهزة وحالات التحديث الفعلية من قاعدة البيانات.');
    } finally {
      if (mounted) {
        setState(() => _isReloading = false);
      }
    }
  }

  /// Sends a REAL update job to the backend for a specific device.
  /// NEVER fakes completion or marks `dev.isUpdated = true` locally!
  Future<void> _triggerDevicePull(_FleetUpdateDevice dev) async {
    if (_activeRelease == null || _activeRelease!.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: const Text(
            'يرجى رفع أو تفعيل نسخة تحديث أولاً قبل إرسال أمر السحب للأجهزة.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    final active = _spawnDeviceOnCanvas(dev, initialPhase: 'dispatching');
    if (active == null) return;

    setState(() {
      active.phase = 'dispatching';
      active.hasError = false;
      active.progress = 0.08;
      active.statusMessage = '📡 جاري إرسال أمر التحديث للسيرفر...';
      active.awaitingPullSeconds = 8;
    });

    _logEvent('INFO', dev.hostname,
        '📡 إرسال أمر تحديث فعلي (v$_targetVersion) للجهاز ${dev.hostname} عبر السيرفر...');

    try {
      await ref.read(updateManagementRepositoryProvider).createUpdateJob(
        releaseId: _activeRelease!.id,
        targetType: 'devices',
        targetDeviceIds: [dev.id],
        note: 'Real update dispatch from n8n Topology for ${dev.hostname}',
      );
      if (!mounted) return;
      setState(() {
        if (active.phase == 'dispatching') {
          active.phase = 'awaiting_pull';
          active.progress = 0.14;
          active.statusMessage = dev.isOnline
              ? '⏳ تم تسليم الأمر • بانتظار بدء سحب الحزمة...'
              : '⚪ الجهاز غير متصل حالياً • سيبدأ السحب فور اتصاله';
          active.awaitingPullSeconds = 8;
        }
      });
      _logEvent('SUCCESS', dev.hostname,
          '✅ تم تسجيل مهمة التحديث في السيرفر للجهاز ${dev.hostname} — بانتظار استجابة الجهاز الفعلية.');
      unawaited(widget.onReload?.call());
    } catch (err) {
      if (!mounted) return;
      setState(() {
        active.phase = 'failed';
        active.hasError = true;
        active.statusMessage = 'تعذر إرسال الأمر: $err';
        active.remainingSeconds = 5;
      });
      _logEvent('ERROR', dev.hostname,
          '❌ تعذر إنشاء مهمة التحديث للجهاز ${dev.hostname}: $err');
    }
  }

  /// Sends a REAL fleet-wide update job to the backend for all outdated devices.
  Future<void> _triggerFleetRollout() async {
    if (_isAutoRolloutActive) return;

    if (_activeRelease == null || _activeRelease!.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: const Text(
            'لا توجد حزمة تحديث مرفوعة على السيرفر حالياً لنشرها.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final outdatedList =
        _allFleetDevices.where((d) => !d.isUpdated).toList();
    if (outdatedList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Text(
            _allFleetDevices.isEmpty
                ? 'لا توجد أجهزة مسجلة في المنظومة حالياً.'
                : 'كافة الأجهزة المسجلة محدثة بالفعل للنسخة v$_targetVersion!',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() {
      _isAutoRolloutActive = true;
      _activeTab = 0;
    });

    // Show target devices on canvas in 'dispatching' state
    for (final dev in outdatedList) {
      final card = _spawnDeviceOnCanvas(dev, initialPhase: 'dispatching');
      if (card != null) {
        card.phase = 'dispatching';
        card.statusMessage = '📡 جاري إرسال أمر التحديث الجماعي...';
        card.awaitingPullSeconds = 8;
      }
    }

    _logEvent('INFO', 'Server',
        '🚀 إرسال حملة تحديث فعلية لعدد (${outdatedList.length}) جهاز إلى السيرفر المركزي...');

    try {
      await ref.read(updateManagementRepositoryProvider).createUpdateJob(
        releaseId: _activeRelease!.id,
        targetType: 'devices',
        targetDeviceIds: outdatedList.map((d) => d.id).toList(),
        note: 'Fleet rollout from n8n Update Topology',
      );
      if (!mounted) return;
      setState(() {
        _isAutoRolloutActive = false;
        for (final card in _canvasPullingDevices) {
          if (card.phase == 'dispatching') {
            card.phase = 'awaiting_pull';
            card.progress = 0.14;
            card.statusMessage =
                '⏳ تم إرسال الأمر • بانتظار سحب الجهاز الفعلي...';
            card.awaitingPullSeconds = 8;
          }
        }
      });
      _logEvent('SUCCESS', 'Server',
          '✅ تم إرسال أوامر التحديث الفعلية لجميع الأجهزة المستهدفة — ستتحول للأخضر فور إتمام كل جهاز للتثبيت.');
      unawaited(widget.onReload?.call());
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isAutoRolloutActive = false;
        for (final card in _canvasPullingDevices) {
          if (card.phase == 'dispatching') {
            card.phase = 'failed';
            card.hasError = true;
            card.statusMessage = 'تعذر إرسال الأمر الجماعي';
            card.remainingSeconds = 5;
          }
        }
      });
      _logEvent('ERROR', 'Server', '❌ فشل إرسال حملة التحديث: $err');
    }
  }

  void _tickDeviceCountdowns() {
    bool changed = false;
    final toRemove = <_ActivePullingDevice>[];

    for (final dev in _canvasPullingDevices) {
      if (dev.isCompleted || dev.hasError) {
        if (dev.remainingSeconds > 1) {
          dev.remainingSeconds--;
          changed = true;
        } else {
          toRemove.add(dev);
        }
      } else if (dev.phase == 'awaiting_pull') {
        if (dev.awaitingPullSeconds > 1) {
          dev.awaitingPullSeconds--;
          changed = true;
        } else {
          // Command was sent; device hasn't started live streaming yet, so remove from active canvas
          // while keeping the device in Outdated tab (never faking completion!)
          toRemove.add(dev);
        }
      }
    }

    if (toRemove.isNotEmpty) {
      for (final r in toRemove) {
        _canvasPullingDevices.remove(r);
      }
      changed = true;
    }

    if (changed) {
      setState(() {});
    }
  }

  void _logEvent(String level, String source, String message) {
    final timeStr = _formatTime(DateTime.now());
    setState(() {
      _distributionLogs.insert(0, {
        'time': timeStr,
        'level': level,
        'source': source,
        'message': message,
      });
      if (_distributionLogs.length > 60) {
        _distributionLogs.removeLast();
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // MAIN BUILD METHOD
  // ══════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final outdatedCount = _allFleetDevices.where((d) => !d.isUpdated).length;
    final updatedCount = _allFleetDevices.where((d) => d.isUpdated).length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0F1118) : const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Column(
            children: [
              // 1. TOP HEADER & TABS BAR
              _buildTopHeader(isDark, outdatedCount, updatedCount),

              // 2. MAIN ACTIVE TAB VIEW
              Expanded(
                child: switch (_activeTab) {
                  1 => _buildOutdatedFleetTab(isDark),
                  2 => _buildUpdatedFleetTab(isDark),
                  3 => _buildRolloutLogsTab(isDark),
                  _ => _buildN8nUpdateFlowTab(isDark),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // 1. TOP HEADER & TABS BAR
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildTopHeader(bool isDark, int outdatedCount, int updatedCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.isEmbedded) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                  tooltip: 'العودة',
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0xFF1E2536)
                        : const Color(0xFFF1F5F9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.cloud_sync_rounded,
                    size: 20, color: Color(0xFF10B981)),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'شبكة سحب وتوزيع التحديثات الحقيقية',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF10B981).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'السيرفر: v$_targetVersion 🟢',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace',
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'بيانات فعلية 100%: لا ينتقل أي جهاز للأجهزة المحدثة إلا بعد إتمام سحب وتثبيت التحديث فعلياً',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Tabs Switcher & Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0E1118)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF222938)
                        : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _tabPill(
                      index: 0,
                      label: '⚡ خريطة n8n لسحب التحديثات',
                      icon: Icons.donut_large_rounded,
                      color: const Color(0xFF10B981),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                    _tabPill(
                      index: 1,
                      label: '🔴 غير محدثة ($outdatedCount)',
                      icon: Icons.warning_amber_rounded,
                      color: const Color(0xFFEF4444),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                    _tabPill(
                      index: 2,
                      label: '🟢 محدثة فعلياً ($updatedCount)',
                      icon: Icons.check_circle_rounded,
                      color: const Color(0xFF10B981),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                    _tabPill(
                      index: 3,
                      label: '📜 السجل (${_distributionLogs.length})',
                      icon: Icons.history_rounded,
                      color: const Color(0xFF6366F1),
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Real Rollout Button
              FilledButton.icon(
                onPressed: _isAutoRolloutActive ? null : _triggerFleetRollout,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isAutoRolloutActive
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.rocket_launch_rounded, size: 16),
                label: Text(
                  _isAutoRolloutActive
                      ? 'جارٍ إرسال الأوامر...'
                      : 'نشر التحديث للفروع الآن',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tabPill({
    required int index,
    required String label,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    final isSelected = _activeTab == index;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _activeTab = index);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF1E2536) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? color
                  : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                color: isSelected
                    ? (isDark ? Colors.white : const Color(0xFF0F172A))
                    : (isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 0: AUTHENTIC n8n UPDATE FLOW (CENTER SERVER + REAL PULLING DEVICES)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildN8nUpdateFlowTab(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableW = constraints.maxWidth;
        final availableH = constraints.maxHeight;

        final sideCols = _getSideColumnCount();
        final oneSideWidth = (sideCols * _deviceCardSize.width) +
            ((sideCols - 1) * _colGap) +
            _wireCorridorGap +
            40.0;
        final requiredW = (oneSideWidth * 2) + _serverSize.width;

        final canvasWidth = math.max(availableW, math.max(1150.0, requiredW));
        final canvasHeight = math.max(availableH, 680.0);
        _lastCanvasWidth = canvasWidth;
        _lastCanvasHeight = canvasHeight;

        final serverX = (canvasWidth - _serverSize.width) / 2.0;
        final serverY = (canvasHeight - _serverSize.height) / 2.0;
        _serverPosition = Offset(serverX, serverY);

        for (final dev in _canvasPullingDevices) {
          dev.position = _computeSlotCoordinate(
              dev.slotIndex, canvasWidth, canvasHeight);
        }

        return Stack(
          children: [
            InteractiveViewer(
              transformationController: _interactiveController,
              minScale: 0.45,
              maxScale: 1.8,
              boundaryMargin: const EdgeInsets.all(250),
              constrained: false,
              child: SizedBox(
                width: canvasWidth,
                height: canvasHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Layer 1: Dot Matrix Grid Background
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _N8nUpdateCanvasGridPainter(isDark: isDark),
                      ),
                    ),

                    // Layer 2: Animated Bézier Wires from Server ➔ Pulling Devices
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: _N8nUpdateWiresPainter(
                              serverPosition: _serverPosition,
                              serverSize: _serverSize,
                              devices: _canvasPullingDevices,
                              flowProgress: _pulseController.value,
                              targetVersion: _targetVersion,
                              isDark: isDark,
                            ),
                          );
                        },
                      ),
                    ),

                    // Layer 3: Central Server Node (Strictly Clipped Inside Card)
                    Positioned(
                      left: _serverPosition.dx,
                      top: _serverPosition.dy,
                      child: _buildCentralServerHeroNode(isDark),
                    ),

                    // Layer 4: Symmetrical Non-Overlapping Pulling Device Cards
                    for (final dev in _canvasPullingDevices)
                      Positioned(
                        left: dev.position.dx,
                        top: dev.position.dy,
                        child: _buildPullingDeviceNode(dev, isDark),
                      ),

                    // Layer 5: Resting Banner if no devices pulling right now
                    if (_canvasPullingDevices.isEmpty)
                      Positioned(
                        left: (canvasWidth - 380.0) / 2.0,
                        top: _serverPosition.dy + _serverSize.height + 28.0,
                        child: _buildUpdateIdleBanner(isDark),
                      ),
                  ],
                ),
              ),
            ),

            // Floating Canvas Controls
            Positioned(
              left: 20,
              bottom: 20,
              child: _buildUpdateCanvasFloatingHUD(isDark),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUpdateIdleBanner(bool isDark) {
    final totalRegistered = _allFleetDevices.length;
    final outdatedCount = _allFleetDevices.where((d) => !d.isUpdated).length;

    return Container(
      width: 380,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF141722).withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_done_rounded,
                size: 20, color: Color(0xFF10B981)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  totalRegistered == 0
                      ? 'لا توجد أجهزة مسجلة حالياً في قاعدة البيانات'
                      : 'شبكة سحب التحديثات الحقيقية جاهزة ($outdatedCount جهاز بانتظار التحديث)',
                  style: const TextStyle(
                      fontSize: 11.2, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  'تظهر الأجهزة الفعلية حول السيرفر فور بدء سحب التحديث، وتتحول للأخضر فقط عند تأكيد اكتمال التثبيت من الجهاز.',
                  style: TextStyle(
                    fontSize: 9.5,
                    height: 1.35,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateCanvasFloatingHUD(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF141722).withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.zoom_in_rounded, size: 18),
            tooltip: 'تكبير اللوحة',
            onPressed: () {
              final val = _interactiveController.value.clone()..scale(1.2, 1.2);
              _interactiveController.value = val;
            },
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out_rounded, size: 18),
            tooltip: 'تصغير اللوحة',
            onPressed: () {
              final val = _interactiveController.value.clone()
                ..scale(0.833, 0.833);
              _interactiveController.value = val;
            },
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            tooltip: 'إعادة ضبط العرض',
            onPressed: () {
              _interactiveController.value = Matrix4.identity();
            },
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          Container(
              width: 1,
              height: 20,
              color: isDark ? Colors.white24 : Colors.black12),
          const SizedBox(width: 10),
          Icon(
            _isSocketConnected
                ? Icons.cloud_done_rounded
                : Icons.cloud_off_rounded,
            size: 16,
            color:
                _isSocketConnected ? const Color(0xFF10B981) : Colors.amber,
          ),
          const SizedBox(width: 6),
          Text(
            _isSocketConnected
                ? 'الربط الفعلي للتحديثات: نشط 🟢'
                : 'جاري الاتصال بالسيرفر...',
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _isReloading ? null : _reloadRealData,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.16),
              foregroundColor: const Color(0xFF10B981),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: _isReloading
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF10B981)),
                  )
                : const Icon(Icons.sync_rounded, size: 14),
            label: const Text('تحديث البيانات الحقيقية',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // CENTRAL SERVER HERO NODE (ALL TEXT STRICTLY INSIDE CARD)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildCentralServerHeroNode(bool isDark) {
    const green = Color(0xFF10B981);
    final fileName =
        _activeRelease?.fileName ?? 'iSmartMessenger-Setup-v$_targetVersion.exe';
    final fileSizeMb = _activeRelease != null && _activeRelease!.fileSize > 0
        ? (_activeRelease!.fileSize / (1024 * 1024)).toStringAsFixed(1)
        : null;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: _serverSize.width,
          height: _serverSize.height,
          clipBehavior: Clip.hardEdge,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F241C) : const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: green, width: 2.2),
            boxShadow: [
              BoxShadow(
                color: green.withValues(alpha: isDark ? 0.35 : 0.20),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Row 1: Top Badge strictly INSIDE the card
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: green,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.hub_rounded, color: Colors.white, size: 11),
                        SizedBox(width: 4),
                        Text(
                          'خادم التحديثات المعتمد • ONLINE 🟢',
                          style: TextStyle(
                            fontSize: 9.2,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_allFleetDevices.length} جهاز مسجل',
                    style: TextStyle(
                      fontSize: 9.0,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: isDark ? Colors.white70 : const Color(0xFF065F46),
                    ),
                  ),
                ],
              ),

              // Row 2: Icon + Target Version + File Info
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: green, width: 1.5),
                    ),
                    child: const Icon(Icons.dns_rounded, color: green, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'الإصدار المعتمد: v$_targetVersion',
                          style: TextStyle(
                            fontSize: 13.0,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                            color:
                                isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fileSizeMb != null
                              ? '$fileName ($fileSizeMb MB)'
                              : fileName,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontFamily: 'monospace',
                            height: 1.15,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF475569),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Row 3: Active Status Footer + Real Sync Action
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _canvasPullingDevices.isNotEmpty
                          ? '⚡ يتابع تحديث ${_canvasPullingDevices.length} جهاز حالياً...'
                          : 'جاهز لتوزيع التحديثات الفعلية للفروع',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        color: _canvasPullingDevices.isNotEmpty
                            ? const Color(0xFFF59E0B)
                            : green,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: _reloadRealData,
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: green.withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        '🔄 فحص الحالة',
                        style: TextStyle(
                          fontSize: 9.0,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          color: green,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Left Output Port Dot
        Positioned(
          left: -5,
          top: (_serverSize.height / 2) - 5,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F1118) : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: green, width: 2.5),
            ),
          ),
        ),

        // Right Output Port Dot
        Positioned(
          right: -5,
          top: (_serverSize.height / 2) - 5,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F1118) : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: green, width: 2.5),
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // PULLING DEVICE NODE (ALL TEXT & BADGES STRICTLY INSIDE CARD)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildPullingDeviceNode(_ActivePullingDevice dev, bool isDark) {
    final isDone = dev.isCompleted;
    final isError = dev.hasError;
    final isAwaiting = dev.phase == 'awaiting_pull' || dev.phase == 'dispatching';

    final Color cardColor = isDone
        ? const Color(0xFF10B981)
        : (isError
            ? const Color(0xFFEF4444)
            : (isAwaiting ? const Color(0xFFF59E0B) : const Color(0xFFF43F5E)));

    String topBadgeText;
    IconData topBadgeIcon;
    if (isDone) {
      topBadgeText = 'محدث فعلياً ✓ (يختفي خلال ${dev.remainingSeconds}ث)';
      topBadgeIcon = Icons.check_circle_rounded;
    } else if (isError) {
      topBadgeText = 'تعذر التحديث ❌ (يختفي خلال ${dev.remainingSeconds}ث)';
      topBadgeIcon = Icons.error_outline_rounded;
    } else if (isAwaiting) {
      topBadgeText = 'تم إرسال الأمر 📡 (${dev.awaitingPullSeconds}ث)';
      topBadgeIcon = Icons.schedule_send_rounded;
    } else {
      topBadgeText = 'جارٍ سحب التحديث ${(dev.progress * 100).toInt()}% ⬇️';
      topBadgeIcon = Icons.downloading_rounded;
    }

    return Container(
      width: _deviceCardSize.width,
      height: _deviceCardSize.height,
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cardColor,
          width: isDone ? 2.3 : 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: cardColor.withValues(alpha: isDone ? 0.35 : 0.20),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Row 1: Top Status Badge strictly INSIDE the card
          Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(topBadgeIcon, color: Colors.white, size: 11),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          topBadgeText,
                          style: const TextStyle(
                            fontSize: 8.8,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Row 2: Device Icon + Hostname + Cashier/Branch
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cardColor.withValues(alpha: 0.4)),
                ),
                child: Icon(
                  isDone
                      ? Icons.desktop_windows_rounded
                      : (isError
                          ? Icons.warning_amber_rounded
                          : Icons.downloading_rounded),
                  color: cardColor,
                  size: 17,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dev.hostname,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                        color:
                            isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${dev.cashierName} • ${dev.branchName}',
                      style: TextStyle(
                        fontSize: 9.2,
                        height: 1.15,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Row 3: Progress Bar or Status Message
          if (!isDone && !isError) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dev.statusMessage,
                  style: TextStyle(
                    fontSize: 8.6,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: cardColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: dev.progress.clamp(0.05, 1.0),
                    backgroundColor: cardColor.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(cardColor),
                    minHeight: 4.5,
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    isDone
                        ? 'الإصدار الحالي: v${dev.targetVersion} (معتمد) 🟢'
                        : dev.statusMessage,
                    style: TextStyle(
                      fontSize: 9.0,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                      color: cardColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  dev.ipAddress,
                  style: TextStyle(
                    fontSize: 8.8,
                    fontFamily: 'monospace',
                    height: 1.15,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 1: OUTDATED FLEET DEVICES (🔴 الأجهزة غير المحدثة)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildOutdatedFleetTab(bool isDark) {
    final outdated = _allFleetDevices.where((d) {
      if (d.isUpdated) return false;
      if (_selectedBranch != 'all' && d.branchCode != _selectedBranch) {
        return false;
      }
      if (_searchFilter.isNotEmpty) {
        final q = _searchFilter.toLowerCase();
        if (!d.hostname.toLowerCase().contains(q) &&
            !d.cashierName.toLowerCase().contains(q) &&
            !d.ipAddress.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFleetSearchAndBranchBar(isDark),
          const SizedBox(height: 16),
          if (_allFleetDevices.isEmpty)
            _buildNoRegisteredDevicesNotice(isDark)
          else if (outdated.isEmpty)
            _buildEmptySuccessNotice(isDark)
          else
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: outdated
                  .map((dev) => _buildOutdatedCard(dev, isDark))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildOutdatedCard(_FleetUpdateDevice dev, bool isDark) {
    final isPullingNow = dev.updateStatus.toLowerCase() == 'downloading' ||
        dev.updateStatus.toLowerCase() == 'installing' ||
        dev.updateStatus.toLowerCase() == 'acknowledged';

    return Container(
      width: 325,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.5), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFEF4444), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dev.hostname,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${dev.cashierName} • ${dev.branchName}',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: dev.isOnline
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  dev.isOnline ? 'متصل 🟢' : 'غير متصل ⚪',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color:
                        dev.isOnline ? const Color(0xFF10B981) : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('النسخة الحالية: v${dev.currentVersion}',
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFEF4444))),
                Text('المعتمد: v$_targetVersion',
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF10B981))),
              ],
            ),
          ),
          if (isPullingNow) ...[
            const SizedBox(height: 8),
            Text(
              '⏳ حالة السحب الفعلية: ${dev.updateStatus} (${dev.updateProgress}%)',
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFF59E0B)),
            ),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () {
              _triggerDevicePull(dev);
              setState(() => _activeTab = 0);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              minimumSize: const Size(double.infinity, 36),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.download_rounded, size: 15),
            label: const Text('إرسال أمر سحب التحديث لهذا الجهاز ⬇️',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 2: UPDATED FLEET DEVICES (🟢 الأجهزة المحدثة فعلياً)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildUpdatedFleetTab(bool isDark) {
    final updated = _allFleetDevices.where((d) {
      if (!d.isUpdated) return false;
      if (_selectedBranch != 'all' && d.branchCode != _selectedBranch) {
        return false;
      }
      if (_searchFilter.isNotEmpty) {
        final q = _searchFilter.toLowerCase();
        if (!d.hostname.toLowerCase().contains(q) &&
            !d.cashierName.toLowerCase().contains(q) &&
            !d.ipAddress.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFleetSearchAndBranchBar(isDark),
          const SizedBox(height: 16),
          if (updated.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141722) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isDark
                        ? const Color(0xFF222938)
                        : const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 40, color: Color(0xFF64748B)),
                  const SizedBox(height: 10),
                  Text(
                    'لا توجد أجهزة على الإصدار v$_targetVersion حتى الآن',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'لا يظهر هنا أي جهاز إلا بعد أن يقوم بسحب وتثبيت التحديث فعلياً وإرسال تأكيد المطابقة للسيرفر.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: updated
                  .map((dev) => _buildUpdatedCard(dev, isDark))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildUpdatedCard(_FleetUpdateDevice dev, bool isDark) {
    return Container(
      width: 325,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.5), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF10B981), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dev.hostname,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${dev.cashierName} • ${dev.branchName}',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text('محدث فعلياً ✓',
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF10B981))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإصدار: v${dev.currentVersion} 🟢',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF10B981))),
              Text(dev.ipAddress,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: isDark ? Colors.white60 : Colors.black54)),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 3: ROLLOUT LOGS
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildRolloutLogsTab(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _distributionLogs.length,
      itemBuilder: (context, idx) {
        final item = _distributionLogs[idx];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141722) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color:
                    isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Text(
                '[${item['time']}]',
                style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: item['level'] == 'SUCCESS'
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : (item['level'] == 'ERROR'
                          ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                          : const Color(0xFF38BDF8).withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item['source'] as String? ?? 'Hub',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: item['level'] == 'SUCCESS'
                        ? const Color(0xFF10B981)
                        : (item['level'] == 'ERROR'
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF38BDF8)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item['message'] as String? ?? '',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFleetSearchAndBranchBar(bool isDark) {
    final branchOptions = <String, String>{'all': 'كل الفروع'};
    for (final d in _allFleetDevices) {
      branchOptions[d.branchCode] = '${d.branchName} (${d.branchCode})';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color:
                  isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: isDark
                      ? const Color(0xFF222938)
                      : const Color(0xFFCBD5E1)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: branchOptions.containsKey(_selectedBranch)
                    ? _selectedBranch
                    : 'all',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A)),
                dropdownColor:
                    isDark ? const Color(0xFF141824) : Colors.white,
                items: branchOptions.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() => _selectedBranch = val);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: (val) =>
                    setState(() => _searchFilter = val.trim()),
                style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'بحث باسم الجهاز أو الموظف أو IP...',
                  hintStyle: const TextStyle(fontSize: 10.5),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF0D1117)
                      : const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoRegisteredDevicesNotice(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const Icon(Icons.devices_other_rounded,
              size: 46, color: Color(0xFF64748B)),
          const SizedBox(height: 12),
          const Text('لا توجد أجهزة مسجلة في قاعدة البيانات حالياً',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            'تظهر الأجهزة الحقيقية تلقائياً فور اتصالها بالسيرفر وإرسال نبضة التعريف (Heartbeat).',
            style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySuccessNotice(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const Icon(Icons.verified_rounded,
              size: 48, color: Color(0xFF10B981)),
          const SizedBox(height: 12),
          const Text('رائع! جميع الأجهزة المسجلة محدثة بالكامل 🟢',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
              'كافة أجهزة الفروع المسجلة تعمل الآن بالنسخة المعتمدة v$_targetVersion.',
              style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B))),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CANVAS PAINTERS FOR n8n UPDATE WIRES & PACKETS
// ══════════════════════════════════════════════════════════════════════════════

class _N8nUpdateCanvasGridPainter extends CustomPainter {
  const _N8nUpdateCanvasGridPainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = isDark ? const Color(0xFF1E2433) : const Color(0xFFCBD5E1)
      ..style = PaintingStyle.fill;

    const spacing = 28.0;
    for (double x = 14; x < size.width; x += spacing) {
      for (double y = 14; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _N8nUpdateCanvasGridPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

class _N8nUpdateWiresPainter extends CustomPainter {
  const _N8nUpdateWiresPainter({
    required this.serverPosition,
    required this.serverSize,
    required this.devices,
    required this.flowProgress,
    required this.targetVersion,
    required this.isDark,
  });

  final Offset serverPosition;
  final Size serverSize;
  final List<_ActivePullingDevice> devices;
  final double flowProgress;
  final String targetVersion;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (devices.isEmpty) return;

    final serverCenter = Offset(serverPosition.dx + (serverSize.width / 2),
        serverPosition.dy + (serverSize.height / 2));
    final serverLeftPort = Offset(serverPosition.dx, serverCenter.dy);
    final serverRightPort =
        Offset(serverPosition.dx + serverSize.width, serverCenter.dy);

    final wirePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()..style = PaintingStyle.fill;
    final corePaint = Paint()..style = PaintingStyle.fill;

    for (final dev in devices) {
      final isLeft = dev.position.dx < serverCenter.dx;
      final serverPort = isLeft ? serverLeftPort : serverRightPort;
      final devPort = isLeft
          ? Offset(dev.position.dx + 285.0, dev.position.dy + 59.0)
          : Offset(dev.position.dx, dev.position.dy + 59.0);

      final isAwaiting =
          dev.phase == 'awaiting_pull' || dev.phase == 'dispatching';
      final lineColor = dev.isCompleted
          ? const Color(0xFF10B981)
          : (dev.hasError
              ? const Color(0xFFEF4444)
              : (isAwaiting
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFF43F5E)));

      wirePaint.color =
          lineColor.withValues(alpha: dev.isCompleted ? 0.50 : 0.85);

      final midX = (serverPort.dx + devPort.dx) / 2.0;
      final path = Path()
        ..moveTo(serverPort.dx, serverPort.dy)
        ..cubicTo(
            midX, serverPort.dy, midX, devPort.dy, devPort.dx, devPort.dy);

      canvas.drawPath(path, wirePaint);

      final metrics = path.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final metric = metrics.first;
        final tangent =
            metric.getTangentForOffset(metric.length * flowProgress);

        if (tangent != null) {
          glowPaint.color = lineColor.withValues(alpha: 0.45);
          canvas.drawCircle(tangent.position, 8.5, glowPaint);

          corePaint.color = Colors.white;
          canvas.drawCircle(tangent.position, 3.8, corePaint);

          final String label = dev.isCompleted
              ? '✓ v$targetVersion'
              : (dev.hasError
                  ? '❌ خطأ'
                  : (isAwaiting
                      ? '📡 إشعار التحديث'
                      : '📦 سحب ${(dev.progress * 100).toInt()}%'));

          final tp = TextPainter(
            text: TextSpan(
              text: label,
              style: const TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white),
            ),
            textDirection: TextDirection.rtl,
            maxLines: 1,
          )..layout(maxWidth: 140);

          final chipRect = RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(tangent.position.dx, tangent.position.dy - 14),
              width: tp.width + 12,
              height: tp.height + 5,
            ),
            const Radius.circular(5),
          );

          final bgPaint = Paint()..color = lineColor.withValues(alpha: 0.92);
          canvas.drawRRect(chipRect, bgPaint);
          tp.paint(
            canvas,
            Offset(
              tangent.position.dx - (tp.width / 2),
              tangent.position.dy - 14 - (tp.height / 2),
            ),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _N8nUpdateWiresPainter oldDelegate) => true;
}
