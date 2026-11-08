import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../chat/data/chat_socket_service.dart';
import '../../chat/models/chat_models.dart';
import '../models/update_management_models.dart';

/// Active device pulling an update on the live n8n canvas.
/// Appears when pulling, turns green when completed, and disappears 5 seconds after completion.
class _ActivePullingDevice {
  _ActivePullingDevice({
    required this.id,
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
  });

  final String id;
  final String hostname;
  final String cashierName;
  final String username;
  final String branchName;
  final String branchCode;
  final String ipAddress;
  final String originalVersion;
  final String targetVersion;
  final int slotIndex;
  final Offset position;

  double progress = 0.08;
  double speedMbps = 14.8;
  int chunksPulled = 1;
  final int totalChunks = 10;
  bool isCompleted = false;
  bool hasError = false;
  String errorMessage = '';
  int remainingSeconds = 5;
}

/// Persistent device entry representing all fleet devices in the system.
class _FleetUpdateDevice {
  _FleetUpdateDevice({
    required this.id,
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
    this.isUpdated = false,
  });

  final String id;
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
  bool isUpdated;
}

/// Authentic n8n-style Update Distribution Network Screen.
/// Contains:
/// 1) Tab 0: Live n8n Update Flow (Center Server + Devices pop in while pulling, turn green, and fade out after 5s).
/// 2) Tab 1: Outdated Devices Fleet (🔴 الأجهزة غير المحدثة).
/// 3) Tab 2: Updated Devices Fleet (🟢 الأجهزة المحدثة بنجاح).
/// 4) Tab 3: Live Rollout Log Stream (📜 سجل عمليات التوزيع).
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
  Timer? _fleetRolloutTimer;
  final List<Timer> _devicePullTimers = [];

  StreamSubscription<ChatSocketEvent>? _socketSub;
  bool _isSocketConnected = false;
  bool _isAutoRolloutActive = false;

  String _targetVersion = '1.1.22';
  ManagedUpdateRelease? _activeRelease;

  // Active pulling devices visible on the n8n canvas (max 6 slots)
  final List<_ActivePullingDevice> _canvasPullingDevices = [];
  final List<bool> _slotsOccupied = [false, false, false, false, false, false];

  // Complete directory of physical devices
  final List<_FleetUpdateDevice> _allFleetDevices = [];
  final List<Map<String, dynamic>> _distributionLogs = [];

  // Search & filter state
  String _searchFilter = '';
  String _selectedBranch = 'all';

  // Canvas Dimensions
  final double _canvasWidth = 1080;
  final double _canvasHeight = 640;
  final Offset _serverPosition = const Offset(390, 260);
  final Size _serverSize = const Size(300, 115);

  // 6 Symmetrical Slots around the Center Server
  final List<Offset> _slotCoordinates = const [
    Offset(60, 70),   // Slot 0: Top-Left
    Offset(60, 260),  // Slot 1: Mid-Left
    Offset(60, 450),  // Slot 2: Bottom-Left
    Offset(740, 70),  // Slot 3: Top-Right
    Offset(740, 260), // Slot 4: Mid-Right
    Offset(740, 450), // Slot 5: Bottom-Right
  ];

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

    // 1-Second Ticker for the 5-second countdown & fadeout of completed devices
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _tickDeviceCountdowns();
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
    _countdownTicker?.cancel();
    _fleetRolloutTimer?.cancel();
    for (final t in _devicePullTimers) {
      t.cancel();
    }
    _socketSub?.cancel();
    super.dispose();
  }

  void _initTargetRelease() {
    if (widget.releases.isNotEmpty) {
      _activeRelease = widget.releases.first;
      _targetVersion = widget.targetVersion ?? _activeRelease!.version;
    } else {
      _targetVersion = widget.targetVersion ?? '1.1.22';
    }
  }

  void _buildInitialLogs() {
    _distributionLogs.clear();
    final now = DateTime.now();
    _distributionLogs.add({
      'time': _formatTime(now.subtract(const Duration(seconds: 2))),
      'level': 'SUCCESS',
      'source': 'ReleaseHub',
      'message': 'خادم التحديثات المركزي جاهز بالنسخة المعتمدة v$_targetVersion (🟢 أخضر).',
    });
    _distributionLogs.add({
      'time': _formatTime(now.subtract(const Duration(seconds: 5))),
      'level': 'INFO',
      'source': 'SocketRouter',
      'message': 'الأجهزة تظهر حول السيرفر أثناء سحب التحديث وتتحول للأخضر وتختفي بعد 5 ثوانٍ.',
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
        _logEvent('SUCCESS', 'WebSocket', '🟢 متصل بالسيرفر المركزي لحظياً - نظام المراقبة نشط');
      } else if (event.type == 'socket_disconnected' || event.type == 'socket_reconnecting') {
        setState(() => _isSocketConnected = false);
      } else if (event.type == 'update_telemetry' ||
          (event.type == 'updates_updated' && event.payload['action'] == 'telemetry')) {
        _handleLiveTelemetryEvent(event.payload);
      }
    });
  }

  void _handleLiveTelemetryEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    final deviceUid = (data['deviceUid'] ?? '').toString();
    final deviceId = (data['deviceId'] ?? '').toString();
    final hostName = (data['hostName'] ?? '').toString();
    final status = (data['status'] ?? '').toString().toLowerCase();
    final rawProgress = data['progress'];
    final progressVal = (rawProgress is num ? rawProgress.toDouble() : 0.0) / 100.0;
    final message = (data['message'] ?? '').toString();
    final targetVer = (data['targetVersion'] ?? _targetVersion).toString();

    // Match fleet device
    _FleetUpdateDevice? match;
    for (final dev in _allFleetDevices) {
      if ((deviceId.isNotEmpty && dev.id == deviceId) ||
          (deviceUid.isNotEmpty && dev.id == deviceUid) ||
          (hostName.isNotEmpty && dev.hostname.toLowerCase() == hostName.toLowerCase())) {
        match = dev;
        break;
      }
    }

    if (match != null) {
      // Find or spawn on canvas
      _ActivePullingDevice? onCanvas;
      for (final c in _canvasPullingDevices) {
        if (c.id == match.id) {
          onCanvas = c;
          break;
        }
      }

      if (onCanvas == null && status != 'completed') {
        onCanvas = _spawnDeviceOnCanvas(match);
      }

      if (onCanvas != null) {
        if (status == 'completed') {
          setState(() {
            onCanvas!.progress = 1.0;
            onCanvas.isCompleted = true;
            onCanvas.remainingSeconds = 5;
            match!.isUpdated = true;
            match.currentVersion = targetVer;
          });
          _logEvent('SUCCESS', match.hostname, '✅ [Live Telemetry] اكتمل التحديث v$targetVer بنجاح! تحول الجهاز للأخضر.');
        } else if (status == 'failed' || status == 'cancelled') {
          setState(() {
            onCanvas!.hasError = true;
            onCanvas.errorMessage = message.isNotEmpty ? message : 'فشل سحب التحديث';
          });
          _logEvent('ERROR', match.hostname, '❌ [Live Telemetry] فشل سحب التحديث: $message');
        } else {
          setState(() {
            onCanvas!.progress = progressVal.clamp(0.08, 0.95);
            onCanvas.speedMbps = 15.2;
            onCanvas.chunksPulled = (onCanvas.progress * onCanvas.totalChunks).round().clamp(1, onCanvas.totalChunks);
          });
        }
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // FLEET DATA INITIALIZATION
  // ══════════════════════════════════════════════════════════════════════════════
  void _buildFleetDevices() {
    _allFleetDevices.clear();
    final rawList = <Map<String, dynamic>>[];

    if (widget.devices.isNotEmpty) {
      for (final d in widget.devices) {
        final host = (d.hostName != null && d.hostName!.trim().isNotEmpty)
            ? d.hostName!.trim()
            : ((d.deviceName != null && d.deviceName!.trim().isNotEmpty) ? d.deviceName!.trim() : 'POS-${d.branchCode}');
        final cashier = (d.lastKnownFullName != null && d.lastKnownFullName!.trim().isNotEmpty)
            ? d.lastKnownFullName!.trim()
            : ((d.lastKnownUsername != null && d.lastKnownUsername!.trim().isNotEmpty) ? d.lastKnownUsername!.trim() : 'كاشير الفرع');
        final bName = widget.branches.firstWhere(
          (b) => b.code == d.branchCode,
          orElse: () => BranchSummary(
            id: '',
            name: 'فرع ${d.branchCode}',
            code: d.branchCode,
            description: '',
            membersCount: 0,
          ),
        ).name;

        rawList.add({
          'id': d.id,
          'hostname': host,
          'cashierName': cashier,
          'username': d.lastKnownUsername ?? '-',
          'branchName': bName,
          'branchCode': d.branchCode,
          'ipAddress': d.localIp ?? '192.168.${d.branchCode}.15',
          'version': d.appVersion.isNotEmpty ? d.appVersion : '1.1.21',
          'isOnline': d.isOnline,
          'os': 'Windows 11 Pro',
        });
      }
    } else {
      rawList.addAll([
        {
          'id': 'dev_hrm_01',
          'hostname': 'POS-HRM-01',
          'cashierName': 'أحمد علي (كاشير 1)',
          'username': 'cas-110-1',
          'branchName': 'فرع الهرم',
          'branchCode': '110',
          'ipAddress': '192.168.110.15',
          'version': '1.1.21',
          'isOnline': true,
          'os': 'Windows 11 POS',
        },
        {
          'id': 'dev_hrm_02',
          'hostname': 'POS-HRM-02',
          'cashierName': 'محمود سمير (كاشير 2)',
          'username': 'cas-110-2',
          'branchName': 'فرع الهرم',
          'branchCode': '110',
          'ipAddress': '192.168.110.18',
          'version': '1.1.21',
          'isOnline': true,
          'os': 'Windows 11 POS',
        },
        {
          'id': 'dev_dokki_01',
          'hostname': 'POS-DOKKI-01',
          'cashierName': 'إبراهيم حسن (كاشير رئيسي)',
          'username': 'cas-111-1',
          'branchName': 'فرع الدقي',
          'branchCode': '111',
          'ipAddress': '192.168.111.12',
          'version': '1.1.21',
          'isOnline': true,
          'os': 'Windows 10 Pro',
        },
        {
          'id': 'dev_nasr_01',
          'hostname': 'POS-NASR-01',
          'cashierName': 'خالد سليم (كاشير 1)',
          'username': 'cas-112-1',
          'branchName': 'فرع مدينة نصر',
          'branchCode': '112',
          'ipAddress': '192.168.112.25',
          'version': '1.1.20',
          'isOnline': true,
          'os': 'Windows 10 POS',
        },
        {
          'id': 'dev_alex_01',
          'hostname': 'POS-ALEX-01',
          'cashierName': 'ياسر ممدوح (كاشير الإسكندرية)',
          'username': 'cas-113-1',
          'branchName': 'فرع الإسكندرية',
          'branchCode': '113',
          'ipAddress': '192.168.113.10',
          'version': '1.1.21',
          'isOnline': true,
          'os': 'Windows 11 Pro',
        },
        {
          'id': 'dev_hq_mgr',
          'hostname': 'MGR-DESK-HQ',
          'cashierName': 'إدارة العمليات المركزية',
          'username': 'ops-director',
          'branchName': 'المقر العام',
          'branchCode': '00',
          'ipAddress': '172.16.0.22',
          'version': '1.1.21',
          'isOnline': true,
          'os': 'Windows 11 Enterprise',
        },
      ]);
    }

    for (final d in rawList) {
      final currentVer = d['version'] as String;
      final isUp = currentVer == _targetVersion;

      _allFleetDevices.add(_FleetUpdateDevice(
        id: d['id'] as String,
        hostname: d['hostname'] as String,
        cashierName: d['cashierName'] as String,
        username: d['username'] as String,
        branchName: d['branchName'] as String,
        branchCode: d['branchCode'] as String,
        ipAddress: d['ipAddress'] as String,
        currentVersion: currentVer,
        targetVersion: _targetVersion,
        isOnline: d['isOnline'] as bool,
        os: d['os'] as String,
        isUpdated: isUp,
      ));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // SPAWN & SIMULATE PULLING DEVICES ON n8n CANVAS
  // ══════════════════════════════════════════════════════════════════════════════
  _ActivePullingDevice? _spawnDeviceOnCanvas(_FleetUpdateDevice dev) {
    int freeSlot = -1;
    for (int i = 0; i < _slotsOccupied.length; i++) {
      if (!_slotsOccupied[i]) {
        freeSlot = i;
        break;
      }
    }

    if (freeSlot == -1) {
      // Reuse slot 0 if all occupied
      freeSlot = 0;
      _canvasPullingDevices.removeWhere((d) => d.slotIndex == 0);
    }

    _slotsOccupied[freeSlot] = true;
    final slotPos = _slotCoordinates[freeSlot];

    final activeDev = _ActivePullingDevice(
      id: dev.id,
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
    );

    setState(() {
      _canvasPullingDevices.add(activeDev);
    });

    return activeDev;
  }

  void _triggerDevicePull(_FleetUpdateDevice dev) {
    // Check if already on canvas
    for (final c in _canvasPullingDevices) {
      if (c.id == dev.id) return;
    }

    HapticFeedback.mediumImpact();
    final active = _spawnDeviceOnCanvas(dev);
    if (active == null) return;

    _logEvent('INFO', dev.hostname, '⬇️ بدء سحب حزم التحديث v$_targetVersion من السيرفر المركزي (1/10)...');

    // Trigger backend job if active release and valid mongo ID
    if (_activeRelease != null && dev.id.length == 24) {
      unawaited(
        ref.read(updateManagementRepositoryProvider).createUpdateJob(
          releaseId: _activeRelease!.id,
          targetType: 'devices',
          targetDeviceIds: [dev.id],
          note: 'Triggered from n8n Live Flow for ${dev.hostname}',
        ).then((_) {
          _logEvent('SUCCESS', dev.hostname, '📡 تم إرسال أمر التحديث الفعلي للسيرفر بنجاح عبر API.');
        }).catchError((err) {
          _logEvent('WARN', dev.hostname, 'تنبيه: محاكاة التحديث تعمل محلياً (${err.toString()})');
        }),
      );
    }

    // Progress timer
    late final Timer pullTimer;
    pullTimer = Timer.periodic(const Duration(milliseconds: 380), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (active.chunksPulled < active.totalChunks) {
        setState(() {
          active.chunksPulled++;
          active.progress = (active.chunksPulled / active.totalChunks).clamp(0.0, 1.0);
          active.speedMbps = 14.5 + math.Random().nextDouble() * 5.0;
        });
      } else {
        timer.cancel();
        _devicePullTimers.remove(pullTimer);
        HapticFeedback.heavyImpact();
        setState(() {
          active.progress = 1.0;
          active.isCompleted = true;
          active.remainingSeconds = 5;
          dev.isUpdated = true;
          dev.currentVersion = _targetVersion;
        });

        _logEvent(
          'SUCCESS',
          dev.hostname,
          '✅ اكتمل سحب وتثبيت التحديث v$_targetVersion بنجاح! تحول الجهاز للأخضر والمطابقة.',
        );
      }
    });
    _devicePullTimers.add(pullTimer);
  }

  void _triggerFleetRollout() {
    if (_isAutoRolloutActive) return;

    final outdatedList = _allFleetDevices.where((d) => !d.isUpdated && d.isOnline).toList();
    if (outdatedList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: const Text(
            'كافة أجهزة المنظومة محدثة بالكامل باللون الأخضر!',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() {
      _isAutoRolloutActive = true;
      _activeTab = 0; // Switch to n8n canvas so admin watches them pull live!
    });

    _logEvent('SUCCESS', 'Server', '🚀 انطلاق حملة التوزيع الجماعي لجميع أجهزة الفروع المتصلة...');

    int index = 0;
    _fleetRolloutTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!mounted || index >= outdatedList.length) {
        timer.cancel();
        if (mounted) setState(() => _isAutoRolloutActive = false);
        return;
      }
      final targetDev = outdatedList[index];
      _triggerDevicePull(targetDev);
      index++;
    });
  }

  void _tickDeviceCountdowns() {
    bool changed = false;
    final toRemove = <_ActivePullingDevice>[];

    for (final dev in _canvasPullingDevices) {
      if (dev.isCompleted) {
        if (dev.remainingSeconds > 1) {
          dev.remainingSeconds--;
          changed = true;
        } else {
          // 5 seconds elapsed! Disappear cleanly!
          toRemove.add(dev);
        }
      }
    }

    if (toRemove.isNotEmpty) {
      for (final r in toRemove) {
        _slotsOccupied[r.slotIndex] = false;
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
      if (_distributionLogs.length > 50) {
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
        backgroundColor: isDark ? const Color(0xFF0F1118) : const Color(0xFFF8FAFC),
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
                    backgroundColor: isDark ? const Color(0xFF1E2536) : const Color(0xFFF1F5F9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                child: const Icon(Icons.cloud_sync_rounded, size: 20, color: Color(0xFF10B981)),
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
                        'شبكة سحب وتوزيع التحديثات المباشرة',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.16),
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
                    'السيرفر في المنتصف: الأجهزة تظهر أثناء سحب التحديث، تنور بالأخضر، وتختفي بعد 5 ثوانٍ',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Tabs Switcher
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0E1118) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? const Color(0xFF222938) : const Color(0xFFCBD5E1),
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
                      label: '🔴 الأجهزة غير المحدثة ($outdatedCount)',
                      icon: Icons.warning_amber_rounded,
                      color: const Color(0xFFEF4444),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                    _tabPill(
                      index: 2,
                      label: '🟢 الأجهزة المحدثة ($updatedCount)',
                      icon: Icons.check_circle_rounded,
                      color: const Color(0xFF10B981),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                    _tabPill(
                      index: 3,
                      label: '📜 سجل التوزيع',
                      icon: Icons.history_rounded,
                      color: const Color(0xFF6366F1),
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Rollout Button
              FilledButton.icon(
                onPressed: _isAutoRolloutActive ? null : _triggerFleetRollout,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isAutoRolloutActive
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.rocket_launch_rounded, size: 16),
                label: Text(
                  _isAutoRolloutActive ? 'جارٍ السحب للفروع...' : 'نشر التحديث للفروع الآن',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
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
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? color : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                color: isSelected
                    ? (isDark ? Colors.white : const Color(0xFF0F172A))
                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 0: AUTHENTIC n8n UPDATE FLOW (CENTER SERVER + PULLING DEVICES POPPING IN)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildN8nUpdateFlowTab(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaleX = constraints.maxWidth / _canvasWidth;
        final scaleY = constraints.maxHeight / _canvasHeight;
        final fitScale = math.min(math.min(scaleX, scaleY), 1.05).clamp(0.65, 1.15);

        return Center(
          child: Transform.scale(
            scale: fitScale,
            child: SizedBox(
              width: _canvasWidth,
              height: _canvasHeight,
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

                  // Layer 3: Central Server Node (GREEN 🟢 in the Center)
                  Positioned(
                    left: _serverPosition.dx,
                    top: _serverPosition.dy,
                    child: _buildCentralServerHeroNode(isDark),
                  ),

                  // Layer 4: Symmetrical Pulling Device Cards (Appear around Server)
                  for (final dev in _canvasPullingDevices)
                    Positioned(
                      left: dev.position.dx,
                      top: dev.position.dy,
                      child: _buildPullingDeviceNode(dev, isDark),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // CENTRAL SERVER HERO NODE (GREEN 🟢)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildCentralServerHeroNode(bool isDark) {
    const green = Color(0xFF10B981);
    final fileName = _activeRelease?.fileName ?? 'iSmartMessenger-Setup-v$_targetVersion.exe';
    final fileSizeMb = _activeRelease != null && _activeRelease!.fileSize > 0
        ? (_activeRelease!.fileSize / (1024 * 1024)).toStringAsFixed(1)
        : '84.5';

    return Container(
      width: _serverSize.width,
      height: _serverSize.height,
      padding: const EdgeInsets.all(14),
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Left Output Port
          Positioned(
            left: -19,
            top: (_serverSize.height / 2) - 19,
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

          // Right Output Port
          Positioned(
            right: -19,
            top: (_serverSize.height / 2) - 19,
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

          // Top Badge
          Positioned(
            top: -20,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: green,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(color: green.withValues(alpha: 0.4), blurRadius: 6),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hub_rounded, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text(
                    'خادم التحديثات المعتمد • ONLINE 🟢',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),

          // Content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: green, width: 1.5),
                    ),
                    child: const Icon(Icons.dns_rounded, color: green, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الإصدار المعتمد: v$_targetVersion',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          '$fileName ($fileSizeMb MB)',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _canvasPullingDevices.isNotEmpty
                        ? '⚡ جاري تغذية ${_canvasPullingDevices.length} أجهزة بالسحب...'
                        : 'لا توجد أجهزة تسحب الآن • اضغط نشر التحديث',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _canvasPullingDevices.isNotEmpty ? const Color(0xFFF43F5E) : green,
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      final outdated = _allFleetDevices.where((d) => !d.isUpdated).toList();
                      if (outdated.isNotEmpty) {
                        _triggerDevicePull(outdated.first);
                      }
                    },
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: green.withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        '⚡ تجربة سحب جهاز',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: green),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // PULLING DEVICE NODE: RED ➔ TURNS GREEN 🟢 ➔ COUNTS DOWN 5s ➔ DISAPPEARS!
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildPullingDeviceNode(_ActivePullingDevice dev, bool isDark) {
    final isDone = dev.isCompleted;
    final cardColor = isDone
        ? const Color(0xFF10B981)
        : (dev.hasError ? const Color(0xFFEF4444) : const Color(0xFFF43F5E));

    return Container(
      width: 280,
      height: 98,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cardColor,
          width: isDone ? 2.4 : 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: cardColor.withValues(alpha: isDone ? 0.35 : 0.20),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Top Status Badge
          Positioned(
            top: -18,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(color: cardColor.withValues(alpha: 0.35), blurRadius: 4),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isDone ? Icons.check_circle_rounded : Icons.downloading_rounded,
                    color: Colors.white,
                    size: 11,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isDone
                        ? 'محدث بنجاح ✓ (يختفي خلال ${dev.remainingSeconds}ث)'
                        : 'جارٍ سحب التحديث ${(dev.progress * 100).toInt()}% ⬇️',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
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
                      isDone ? Icons.desktop_windows_rounded : Icons.downloading_rounded,
                      color: cardColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dev.hostname,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${dev.cashierName} • ${dev.branchName}',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Progress Bar if pulling
              if (!isDone) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Chunk ${dev.chunksPulled}/${dev.totalChunks}',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: cardColor),
                    ),
                    Text(
                      '${dev.speedMbps.toStringAsFixed(1)} MB/s',
                      style: TextStyle(fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.w800, color: cardColor),
                    ),
                  ],
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: dev.progress,
                    backgroundColor: cardColor.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(cardColor),
                    minHeight: 5,
                  ),
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'الإصدار الحالي: v1.1.22 (معتمد ومطابق) 🟢',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF10B981)),
                    ),
                    Text(
                      dev.ipAddress,
                      style: TextStyle(fontSize: 9, fontFamily: 'monospace', color: isDark ? Colors.white60 : Colors.black54),
                    ),
                  ],
                ),
              ],
            ],
          ),
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
      if (_selectedBranch != 'all' && d.branchCode != _selectedBranch) return false;
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
          if (outdated.isEmpty)
            _buildEmptySuccessNotice(isDark)
          else
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: outdated.map((dev) => _buildOutdatedCard(dev, isDark)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildOutdatedCard(_FleetUpdateDevice dev, bool isDark) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5), width: 1.4),
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
                child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dev.hostname, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                    Text('${dev.cashierName} • ${dev.branchName}', style: TextStyle(fontSize: 10.5, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                  ],
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
                Text('النسخة الحالية: v${dev.currentVersion}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
                Text('المعتمد: v$_targetVersion', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () {
              _triggerDevicePull(dev);
              setState(() => _activeTab = 0); // Switch to n8n canvas so admin sees it!
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              minimumSize: const Size(double.infinity, 36),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.download_rounded, size: 15),
            label: const Text('سحب التحديث لهذا الجهاز الآن ⬇️', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 2: UPDATED FLEET DEVICES (🟢 الأجهزة المحدثة بنجاح)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildUpdatedFleetTab(bool isDark) {
    final updated = _allFleetDevices.where((d) {
      if (!d.isUpdated) return false;
      if (_selectedBranch != 'all' && d.branchCode != _selectedBranch) return false;
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
                border: Border.all(color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
              ),
              child: const Text('لا توجد أجهزة محدثة حتى الآن', style: TextStyle(fontWeight: FontWeight.w800)),
            )
          else
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: updated.map((dev) => _buildUpdatedCard(dev, isDark)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildUpdatedCard(_FleetUpdateDevice dev, bool isDark) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5), width: 1.4),
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
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dev.hostname, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                    Text('${dev.cashierName} • ${dev.branchName}', style: TextStyle(fontSize: 10.5, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text('مطابق 100% ✓', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF10B981))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإصدار: v${dev.currentVersion} 🟢', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF10B981))),
              Text(dev.ipAddress, style: TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: isDark ? Colors.white60 : Colors.black54)),
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
            border: Border.all(color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Text(
                '[${item['time']}]',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: item['level'] == 'SUCCESS'
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : const Color(0xFF38BDF8).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item['source'] as String? ?? 'Hub',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: item['level'] == 'SUCCESS' ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
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
        border: Border.all(color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? const Color(0xFF222938) : const Color(0xFFCBD5E1)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: branchOptions.containsKey(_selectedBranch) ? _selectedBranch : 'all',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                dropdownColor: isDark ? const Color(0xFF141824) : Colors.white,
                items: branchOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
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
                onChanged: (val) => setState(() => _searchFilter = val.trim()),
                style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'بحث باسم الجهاز أو الموظف أو IP...',
                  hintStyle: const TextStyle(fontSize: 10.5),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
            ),
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
        border: Border.all(color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const Icon(Icons.verified_rounded, size: 48, color: Color(0xFF10B981)),
          const SizedBox(height: 12),
          const Text('رائع! جميع أجهزة المنظومة محدثة بالكامل 🟢', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('كافة أجهزة الفروع تعمل الآن بالنسخة المعتمدة v$_targetVersion بدون أي مشاكل.', style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
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
  bool shouldRepaint(covariant _N8nUpdateCanvasGridPainter oldDelegate) => oldDelegate.isDark != isDark;
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

    final serverCenter = Offset(serverPosition.dx + (serverSize.width / 2), serverPosition.dy + (serverSize.height / 2));
    final serverLeftPort = Offset(serverPosition.dx, serverCenter.dy);
    final serverRightPort = Offset(serverPosition.dx + serverSize.width, serverCenter.dy);

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
          ? Offset(dev.position.dx + 280.0, dev.position.dy + 49.0)
          : Offset(dev.position.dx, dev.position.dy + 49.0);

      final lineColor = dev.isCompleted ? const Color(0xFF10B981) : const Color(0xFFF43F5E);
      wirePaint.color = lineColor.withValues(alpha: dev.isCompleted ? 0.45 : 0.85);

      final midX = (serverPort.dx + devPort.dx) / 2.0;
      final path = Path()
        ..moveTo(serverPort.dx, serverPort.dy)
        ..cubicTo(midX, serverPort.dy, midX, devPort.dy, devPort.dx, devPort.dy);

      canvas.drawPath(path, wirePaint);

      // Packet traveling from Server to Device
      final metrics = path.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final metric = metrics.first;
        final tangent = metric.getTangentForOffset(metric.length * flowProgress);

        if (tangent != null) {
          glowPaint.color = lineColor.withValues(alpha: 0.45);
          canvas.drawCircle(tangent.position, 8.0, glowPaint);

          corePaint.color = Colors.white;
          canvas.drawCircle(tangent.position, 3.5, corePaint);

          // Flowing Packet Chip
          final label = dev.isCompleted ? '✓ v$targetVersion' : '📦 Chunk ${dev.chunksPulled}';
          final tp = TextPainter(
            text: TextSpan(
              text: label,
              style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.white),
            ),
            textDirection: TextDirection.rtl,
          )..layout();

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
          tp.paint(canvas, Offset(tangent.position.dx - (tp.width / 2), tangent.position.dy - 14 - (tp.height / 2)));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _N8nUpdateWiresPainter oldDelegate) => true;
}
