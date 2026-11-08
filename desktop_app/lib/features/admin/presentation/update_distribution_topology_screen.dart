import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../chat/data/chat_socket_service.dart';
import '../../chat/models/chat_models.dart';
import '../models/update_management_models.dart';

/// Supported view modes for update distribution.
enum _UpdateTopologyViewMode {
  flowMap,   // Structured 3-Tier Enterprise Flow Map (Zero overlap, clean bus routing)
  fleetGrid, // High-speed responsive cards matrix by branch
}

/// State of an individual device in the update distribution mesh.
enum _UpdateDevicePhase {
  outdated,    // 🔴 Red: Outdated version, waiting for update
  pulling,     // 🔴 Pulse: Actively pulling/downloading update chunks from server
  completed,   // 🟢 Green: Successfully updated to target version!
}

/// Representation of a branch cluster containing its fleet of devices.
class _UpdateBranchCluster {
  _UpdateBranchCluster({
    required this.branchCode,
    required this.branchName,
    required this.x,
    required this.y,
    required this.width,
    required this.devices,
  });

  final String branchCode;
  final String branchName;
  final double x;
  final double y;
  final double width;
  final List<_UpdateTopologyDevice> devices;

  int get totalCount => devices.length;
  int get completedCount => devices.where((d) => d.isCompleted).length;
  int get outdatedCount => devices.where((d) => d.isOutdated).length;
  int get pullingCount => devices.where((d) => d.isPulling).length;
}

/// Dynamic simulation model for a device on the update canvas.
class _UpdateTopologyDevice {
  _UpdateTopologyDevice({
    required this.id,
    required this.hostname,
    required this.cashierName,
    required this.username,
    required this.branchName,
    required this.branchCode,
    required this.ipAddress,
    required this.originalVersion,
    required this.targetVersion,
    required this.isOnline,
    required this.os,
    required this.position,
    required this.size,
    required this.portOffset,
    this.phase = _UpdateDevicePhase.outdated,
    this.progress = 0.0,
    this.speedMbps = 0.0,
    this.chunksPulled = 0,
    this.totalChunks = 10,
    this.executionCount = 0,
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
  final bool isOnline;
  final String os;
  Offset position;
  final Size size;
  final double portOffset;

  _UpdateDevicePhase phase;
  double progress; // 0.0 to 1.0
  double speedMbps;
  int chunksPulled;
  final int totalChunks;
  int executionCount;

  bool get isCompleted => phase == _UpdateDevicePhase.completed;
  bool get isPulling => phase == _UpdateDevicePhase.pulling;
  bool get isOutdated => phase == _UpdateDevicePhase.outdated;

  Color get accentColor {
    switch (phase) {
      case _UpdateDevicePhase.completed:
        return const Color(0xFF10B981); // 🟢 Green
      case _UpdateDevicePhase.pulling:
        return const Color(0xFFF43F5E); // 🔴 Rose / Pulse Red
      case _UpdateDevicePhase.outdated:
        return const Color(0xFFEF4444); // 🔴 Red
    }
  }

  String get currentDisplayVersion => isCompleted ? targetVersion : originalVersion;

  String get statusBadgeLabel {
    switch (phase) {
      case _UpdateDevicePhase.completed:
        return 'محدث بنجاح (v$targetVersion) ✓';
      case _UpdateDevicePhase.pulling:
        return 'جارٍ سحب التحديث ${(progress * 100).toInt()}% ⬇️';
      case _UpdateDevicePhase.outdated:
        return 'نسخة قديمة (v$originalVersion) ⚠️';
    }
  }
}

/// Data packet streaming update chunks from Server to Device along structured bus wires.
class _UpdateDataPacket {
  _UpdateDataPacket({
    required this.id,
    required this.targetDeviceId,
    required this.label,
    required this.color,
    required this.startedAt,
    required this.duration,
    required this.portOffset,
  });

  final String id;
  final String targetDeviceId;
  final String label;
  final Color color;
  final DateTime startedAt;
  final Duration duration;
  final double portOffset;

  double progress(DateTime now) {
    final elapsed = now.difference(startedAt).inMilliseconds;
    return (elapsed / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  bool isFinished(DateTime now) => progress(now) >= 1.0;
}

/// Dedicated full screen or embedded widget for the n8n-style update distribution network.
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
    with TickerProviderStateMixin {
  late final TransformationController _transController;
  late final AnimationController _pulseController;
  late final AnimationController _flyAnimController;
  Animation<Matrix4>? _flyMatrixAnimation;

  Timer? _livePullTicker;
  Timer? _fleetRolloutTimer;
  Timer? _packetCleanTimer;

  _UpdateTopologyViewMode _viewMode = _UpdateTopologyViewMode.flowMap;

  final List<_UpdateTopologyDevice> _canvasDevices = [];
  final Map<String, _UpdateTopologyDevice> _devicesMap = {};
  final List<_UpdateBranchCluster> _branchClusters = [];
  final List<_UpdateDataPacket> _packets = [];
  final List<Map<String, dynamic>> _distributionLogs = [];

  // Server Node Coordinates
  late Offset _serverPosition;
  final Size _serverSize = const Size(380, 116);

  String _targetVersion = '1.1.22';
  ManagedUpdateRelease? _activeRelease;

  bool _isAutoRolloutActive = false;
  String _searchFilter = '';
  final String _selectedBranch = 'all';
  String? _selectedDeviceId;

  double _canvasWidth = 1600;
  double _canvasHeight = 900;
  Size _viewportSize = Size.zero;

  bool _showConsole = false;
  StreamSubscription<ChatSocketEvent>? _socketSub;
  bool _isSocketConnected = false;

  @override
  void initState() {
    super.initState();
    _transController = TransformationController();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    _flyAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _flyAnimController.addListener(() {
      if (_flyMatrixAnimation != null) {
        _transController.value = _flyMatrixAnimation!.value;
      }
    });

    _initTargetRelease();
    _buildDistributionMesh();
    _buildInitialLogs();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fitCanvasToScreen(animated: false);
        _listenToLiveSocket();
      }
    });

    // Dedicated packet cleaner timer: removes completed packets cleanly without setState churn
    _packetCleanTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      _packets.removeWhere((p) => p.isFinished(now));
    });

    // Start background traffic ticker (natural background packet movements)
    _livePullTicker = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!mounted) return;
      _spawnBackgroundUpdatePacket();
    });
  }

  @override
  void didUpdateWidget(covariant UpdateDistributionTopologyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.releases != widget.releases ||
        oldWidget.devices != widget.devices ||
        oldWidget.targetVersion != widget.targetVersion) {
      _initTargetRelease();
      _buildDistributionMesh();
    }
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _livePullTicker?.cancel();
    _fleetRolloutTimer?.cancel();
    _packetCleanTimer?.cancel();
    _pulseController.dispose();
    _flyAnimController.dispose();
    _transController.dispose();
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
      'message': 'خادم التحديثات المركزي: الإصدار v$_targetVersion معتمد ومتاح بنظام التجزئة (Chunked Deployment).',
    });
    _distributionLogs.add({
      'time': _formatTime(now.subtract(const Duration(seconds: 6))),
      'level': 'INFO',
      'source': 'SocketRouter',
      'message': 'تم فحص أجهزة الفروع، تم العثور على أجهزة تعمل بإصدارات سابقة وبحاجة للتحديث.',
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
      } else if (event.type == 'updates_updated') {
        if (event.payload['action'] == 'job_created' || event.payload['action'] == 'release_created') {
          if (widget.onReload != null) {
            widget.onReload!();
          }
        }
      }
    });
  }

  void _handleLiveTelemetryEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    final deviceUid = (data['deviceUid'] ?? '').toString();
    final deviceId = (data['deviceId'] ?? '').toString();
    final hostName = (data['hostName'] ?? '').toString();
    final deviceName = (data['deviceName'] ?? '').toString();
    final status = (data['status'] ?? '').toString().toLowerCase();
    final rawProgress = data['progress'];
    final progressVal = (rawProgress is num ? rawProgress.toDouble() : 0.0) / 100.0;
    final message = (data['message'] ?? '').toString();
    final targetVer = (data['targetVersion'] ?? _targetVersion).toString();
    final speed = (data['speed'] ?? '15.2 MB/s').toString();

    // 1. Locate existing device in _canvasDevices
    _UpdateTopologyDevice? match;
    for (final dev in _canvasDevices) {
      if ((deviceId.isNotEmpty && dev.id == deviceId) ||
          (deviceUid.isNotEmpty && dev.id == deviceUid) ||
          (hostName.isNotEmpty && dev.hostname.toLowerCase() == hostName.toLowerCase()) ||
          (deviceName.isNotEmpty && dev.cashierName.toLowerCase().contains(deviceName.toLowerCase()))) {
        match = dev;
        break;
      }
    }

    if (match != null) {
      final dev = match;
      if (status == 'completed') {
        HapticFeedback.heavyImpact();
        setState(() {
          dev.phase = _UpdateDevicePhase.completed;
          dev.progress = 1.0;
          dev.chunksPulled = dev.totalChunks;
          dev.executionCount++;
        });

        _logEvent(
          'SUCCESS',
          dev.hostname,
          '✅ [Live Telemetry] اكتمل سحب وتثبيت التحديث v$targetVer بنجاح! تحول الجهاز للون الأخضر والمطابقة.',
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تم تحديث جهاز ${dev.hostname} (${dev.branchName}) بنجاح إلى النسخة v$targetVer!',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (status == 'failed' || status == 'cancelled') {
        setState(() {
          dev.phase = _UpdateDevicePhase.outdated;
        });
        _logEvent('ERROR', dev.hostname, '❌ [Live Telemetry] فشل سحب التحديث: $message');
      } else {
        // downloading, acknowledged, installing, pulling
        final wasNotPulling = dev.phase != _UpdateDevicePhase.pulling;
        setState(() {
          dev.phase = _UpdateDevicePhase.pulling;
          dev.progress = progressVal.clamp(0.08, 0.95);
          dev.speedMbps = 15.0;
          dev.chunksPulled = (dev.progress * dev.totalChunks).round().clamp(1, dev.totalChunks);
        });

        if (wasNotPulling) {
          _logEvent(
            'INFO',
            dev.hostname,
            '⬇️ [Live Telemetry] بدأ الجهاز بسحب التحديث v$targetVer فوراً من السيرفر بسرعة $speed!',
          );
          _launchUpdatePacket(dev, '📦 حزمة تحديث v$targetVer');
        } else {
          _launchUpdatePacket(dev, '⬇️ سحب ${(dev.progress * 100).toInt()}% ($speed)');
        }
      }
    } else if (deviceUid.isNotEmpty || hostName.isNotEmpty) {
      _logEvent('INFO', hostName.isNotEmpty ? hostName : 'NewDevice', '📡 رصد جهاز جديد يبدأ سحب التحديث...');
      if (widget.onReload != null) {
        widget.onReload!();
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // MESH BUILDER: STRUCTURED 3-TIER ENTERPRISE TOPOLOGY (ZERO COLLISION)
  // ══════════════════════════════════════════════════════════════════════════════
  void _buildDistributionMesh() {
    _canvasDevices.clear();
    _devicesMap.clear();
    _branchClusters.clear();

    // 1. Gather devices from props or demo fallback
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
          'username': d.lastKnownUsername,
          'branchName': bName,
          'branchCode': d.branchCode,
          'ipAddress': d.localIp ?? '192.168.${d.branchCode}.15',
          'version': d.appVersion.isNotEmpty ? d.appVersion : '1.1.21',
          'isOnline': d.isOnline,
          'os': 'Windows 11 Pro',
        });
      }
    } else {
      // Fallback fleet representing real multi-branch workstations
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

    // Filter devices
    final filtered = rawList.where((d) {
      if (_selectedBranch != 'all' && d['branchCode'] != _selectedBranch) return false;
      if (_searchFilter.isNotEmpty) {
        final q = _searchFilter.toLowerCase();
        final matchHost = (d['hostname'] as String).toLowerCase().contains(q);
        final matchName = (d['cashierName'] as String).toLowerCase().contains(q);
        final matchBranch = (d['branchName'] as String).toLowerCase().contains(q);
        final matchIp = (d['ipAddress'] as String).contains(q);
        if (!matchHost && !matchName && !matchBranch && !matchIp) return false;
      }
      return true;
    }).toList();

    // 2. Group devices by branch
    final Map<String, List<Map<String, dynamic>>> branchGroups = {};
    for (final d in filtered) {
      final bCode = d['branchCode'] as String;
      branchGroups.putIfAbsent(bCode, () => []).add(d);
    }

    // 3. Layout geometry calculations:
    // Top Server Node: Top Center (X_center, Y=36)
    // Horizontal Distribution Bus at Y=190
    // Branch Column Headers at Y=230
    // Device Cards stack neatly at Y=290, 396, 502...
    const cardWidth = 280.0;
    const cardHeight = 90.0;
    const colWidth = 280.0;
    const colGap = 36.0;

    final branchCodes = branchGroups.keys.toList();
    final totalCols = math.max(branchCodes.length, 1);
    final totalColumnsWidth = totalCols * colWidth + (totalCols - 1) * colGap;

    _canvasWidth = math.max(totalColumnsWidth + 160.0, 1500.0);

    // Calculate max height based on the branch with the most devices
    int maxDevicesInBranch = 1;
    for (final list in branchGroups.values) {
      if (list.length > maxDevicesInBranch) {
        maxDevicesInBranch = list.length;
      }
    }
    _canvasHeight = math.max(300.0 + (maxDevicesInBranch * (cardHeight + 16.0)) + 120.0, 780.0);

    final centerX = _canvasWidth / 2.0;
    _serverPosition = Offset(centerX - (_serverSize.width / 2.0), 36.0);

    final startX = (centerX - (totalColumnsWidth / 2.0)).clamp(40.0, double.infinity);

    // Build branch clusters and place devices with ZERO collision
    for (int col = 0; col < branchCodes.length; col++) {
      final bCode = branchCodes[col];
      final devList = branchGroups[bCode]!;
      final colX = startX + col * (colWidth + colGap);
      final colY = 230.0;

      final clusterDevs = <_UpdateTopologyDevice>[];

      for (int row = 0; row < devList.length; row++) {
        final d = devList[row];
        final devX = colX;
        final devY = 290.0 + (row * (cardHeight + 14.0));
        final isAlreadyTarget = d['version'] == _targetVersion;

        final dev = _UpdateTopologyDevice(
          id: d['id'] as String,
          hostname: d['hostname'] as String,
          cashierName: d['cashierName'] as String,
          username: d['username'] as String,
          branchName: d['branchName'] as String,
          branchCode: d['branchCode'] as String,
          ipAddress: d['ipAddress'] as String,
          originalVersion: d['version'] as String,
          targetVersion: _targetVersion,
          isOnline: d['isOnline'] as bool,
          os: d['os'] as String,
          position: Offset(devX, devY),
          size: const Size(cardWidth, cardHeight),
          portOffset: 0.5,
          phase: isAlreadyTarget ? _UpdateDevicePhase.completed : _UpdateDevicePhase.outdated,
          progress: isAlreadyTarget ? 1.0 : 0.0,
        );

        _canvasDevices.add(dev);
        _devicesMap[dev.id] = dev;
        clusterDevs.add(dev);
      }

      final bName = devList.isNotEmpty ? (devList.first['branchName'] as String) : 'فرع $bCode';
      _branchClusters.add(_UpdateBranchCluster(
        branchCode: bCode,
        branchName: bName,
        x: colX,
        y: colY,
        width: colWidth,
        devices: clusterDevs,
      ));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // SIMULATION & PULL ACTIONS (Device transitions Red ➔ Green)
  // ══════════════════════════════════════════════════════════════════════════════
  void _triggerDevicePull(_UpdateTopologyDevice dev) {
    if (dev.isPulling || dev.isCompleted) return;

    HapticFeedback.mediumImpact();
    setState(() {
      dev.phase = _UpdateDevicePhase.pulling;
      dev.progress = 0.1;
      dev.speedMbps = 12.4 + math.Random().nextDouble() * 8.0;
      dev.chunksPulled = 1;
    });

    _logEvent('INFO', dev.hostname, 'بدء سحب حزم التحديث v$_targetVersion من السيرفر المركزي (1/10)...');

    // Trigger real backend job if active release and real device ID
    if (_activeRelease != null && dev.id.length == 24) {
      unawaited(
        ref.read(updateManagementRepositoryProvider).createUpdateJob(
          releaseId: _activeRelease!.id,
          targetType: 'devices',
          targetDeviceIds: [dev.id],
          note: 'Triggered from n8n Live Map for ${dev.hostname}',
        ).then((_) {
          _logEvent('SUCCESS', dev.hostname, '📡 تم إرسال أمر التحديث للسيرفر بنجاح عبر API.');
        }).catchError((err) {
          _logEvent('WARN', dev.hostname, 'تنبيه: محاكاة التحديث تعمل محلياً (${err.toString()})');
        }),
      );
    }

    // Launch moving update packet from Server to this Device along bus wires
    _launchUpdatePacket(dev, '📦 حزمة تحديث v$_targetVersion');

    Timer.periodic(const Duration(milliseconds: 380), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (dev.chunksPulled < dev.totalChunks) {
        setState(() {
          dev.chunksPulled++;
          dev.progress = (dev.chunksPulled / dev.totalChunks).clamp(0.0, 1.0);
          dev.speedMbps = 14.0 + math.Random().nextDouble() * 6.0;
        });
        _launchUpdatePacket(dev, '⬇️ سحب Chunk ${dev.chunksPulled}/10');
      } else {
        timer.cancel();
        // Completed! Turn from Red to Green!
        HapticFeedback.heavyImpact();
        setState(() {
          dev.phase = _UpdateDevicePhase.completed;
          dev.progress = 1.0;
          dev.executionCount++;
        });

        _logEvent(
          'SUCCESS',
          dev.hostname,
          '✅ اكتمل سحب وتثبيت التحديث v$_targetVersion بنجاح! تحول الجهاز للون الأخضر والمطابقة التامة.',
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تم تحديث جهاز ${dev.hostname} (${dev.branchName}) بنجاح إلى النسخة v$_targetVersion!',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    });
  }

  void _triggerFleetRollout() {
    if (_isAutoRolloutActive) return;

    final outdatedList = _canvasDevices.where((d) => d.isOutdated && d.isOnline).toList();
    if (outdatedList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: const Text(
            'كافة أجهزة المنظومة محدثة بالكامل إلى أحدث إصدار معتمد!',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() {
      _isAutoRolloutActive = true;
    });

    _logEvent('SUCCESS', 'Server', '🚀 انطلاق حملة التوزيع الجماعي لجميع أجهزة الفروع المتصلة...');

    if (_activeRelease != null) {
      unawaited(
        ref.read(updateManagementRepositoryProvider).createUpdateJob(
          releaseId: _activeRelease!.id,
          targetType: 'all',
          note: 'Fleet rollout triggered from n8n Live Map',
        ).then((_) {
          _logEvent('SUCCESS', 'Server', '📡 تم اعتماد وتعميم مهمة النشر الجماعي في قاعدة البيانات.');
        }).catchError((err) {
          _logEvent('WARN', 'Server', 'تنبيه: جاري تشغيل التدفق المرئي (${err.toString()})');
        }),
      );
    }

    int index = 0;
    _fleetRolloutTimer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (!mounted || index >= outdatedList.length) {
        timer.cancel();
        setState(() => _isAutoRolloutActive = false);
        return;
      }
      final targetDev = outdatedList[index];
      _triggerDevicePull(targetDev);
      index++;
    });
  }

  void _resetSimulation() {
    _fleetRolloutTimer?.cancel();
    HapticFeedback.selectionClick();
    setState(() {
      _isAutoRolloutActive = false;
      for (final d in _canvasDevices) {
        d.phase = _UpdateDevicePhase.outdated;
        d.progress = 0.0;
        d.chunksPulled = 0;
      }
      _packets.clear();
      _buildInitialLogs();
    });
  }

  /// Launch moving update packet from Server to Device WITHOUT calling setState churn.
  /// The pulse AnimatedBuilder handles rendering smoothly at 60fps.
  void _launchUpdatePacket(_UpdateTopologyDevice dev, String label) {
    _packets.add(_UpdateDataPacket(
      id: 'pkt_upd_${DateTime.now().microsecondsSinceEpoch}',
      targetDeviceId: dev.id,
      label: label,
      color: dev.accentColor,
      startedAt: DateTime.now(),
      duration: const Duration(milliseconds: 750),
      portOffset: dev.portOffset,
    ));
  }

  void _spawnBackgroundUpdatePacket() {
    final activeOrPulling = _canvasDevices.where((d) => d.isPulling).toList();
    if (activeOrPulling.isNotEmpty) {
      final dev = activeOrPulling[math.Random().nextInt(activeOrPulling.length)];
      _launchUpdatePacket(dev, '📦 حزمة تحديث (${(dev.progress * 100).toInt()}%)');
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
  // RESPONSIVE AUTO-FIT & ZOOM (WORKS SMOOTHLY IN BOTH FULLSCREEN & EMBEDDED)
  // ══════════════════════════════════════════════════════════════════════════════
  void _fitCanvasToScreen({bool animated = true}) {
    final mediaWidth = _viewportSize.width > 0 ? _viewportSize.width : MediaQuery.of(context).size.width;
    final mediaHeight = _viewportSize.height > 0 ? _viewportSize.height : MediaQuery.of(context).size.height;

    final availableWidth = mediaWidth - (_selectedDeviceId != null && mediaWidth >= 1150 ? 380 : 0);
    final availableHeight = mediaHeight - (widget.isEmbedded ? 20 : 100);

    final scaleW = availableWidth / _canvasWidth;
    final scaleH = availableHeight / _canvasHeight;
    final scale = (math.min(scaleW, scaleH) * 0.96).clamp(0.35, 1.15);

    final targetX = (availableWidth - (_canvasWidth * scale)) / 2;
    final targetY = (availableHeight - (_canvasHeight * scale)) / 2;

    final targetMatrix = Matrix4.identity()
      ..translate(targetX, targetY)
      ..scale(scale);

    if (animated) {
      _flyMatrixAnimation = Matrix4Tween(
        begin: _transController.value,
        end: targetMatrix,
      ).animate(CurvedAnimation(
        parent: _flyAnimController,
        curve: Curves.easeOutCubic,
      ));
      _flyAnimController.forward(from: 0.0);
    } else {
      _transController.value = targetMatrix;
    }
  }

  void _zoomBy(double factor) {
    final curMatrix = _transController.value;
    final mediaWidth = _viewportSize.width > 0 ? _viewportSize.width : MediaQuery.of(context).size.width;
    final mediaHeight = _viewportSize.height > 0 ? _viewportSize.height : MediaQuery.of(context).size.height;
    final center = Offset(mediaWidth / 2, mediaHeight / 2);

    final newMatrix = curMatrix.clone()
      ..translate(center.dx, center.dy)
      ..scale(factor)
      ..translate(-center.dx, -center.dy);

    _transController.value = newMatrix;
  }

  void _resetZoom() {
    _fitCanvasToScreen(animated: true);
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // MAIN BUILD
  // ══════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final totalCount = _canvasDevices.length;
    final completedCount = _canvasDevices.where((d) => d.isCompleted).length;
    final outdatedCount = _canvasDevices.where((d) => d.isOutdated).length;
    final pullingCount = _canvasDevices.where((d) => d.isPulling).length;

    final content = LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final isWideScreen = constraints.maxWidth >= 1150;

        return Column(
          children: [
            // 1. TOP HEADER & TELEMETRY STRIP
            _buildTopToolbar(isDark, totalCount, completedCount, outdatedCount, pullingCount),

            // 2. MAIN WORKSPACE VIEW
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        if (_viewMode == _UpdateTopologyViewMode.flowMap)
                          _buildStructuredFlowMap(isDark)
                        else
                          _buildBranchFleetMatrix(isDark),

                        // Floating HUD Navigation (Zoom Controls in Map Mode)
                        if (_viewMode == _UpdateTopologyViewMode.flowMap)
                          Positioned(
                            left: 20,
                            bottom: _showConsole ? 220 : 20,
                            child: _buildFloatingControls(isDark),
                          ),

                        // Bottom Live Distribution Terminal
                        Positioned(
                          bottom: 16,
                          left: _viewMode == _UpdateTopologyViewMode.flowMap ? 180 : 16,
                          right: 16,
                          child: _buildBottomConsole(isDark),
                        ),
                      ],
                    ),
                  ),

                  // Side Device Inspector (Wide Screens)
                  if (isWideScreen && _selectedDeviceId != null)
                    SizedBox(
                      width: 380,
                      child: _buildDeviceInspector(isDark),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF10131A) : const Color(0xFFF8FAFC),
        body: SafeArea(child: content),
        endDrawer: _selectedDeviceId != null && MediaQuery.of(context).size.width < 1150
            ? Drawer(
                width: 380,
                child: _buildDeviceInspector(isDark),
              )
            : null,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // 1. TOP HEADER & TELEMETRY STRIP
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildTopToolbar(
    bool isDark,
    int totalCount,
    int completedCount,
    int outdatedCount,
    int pullingCount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      child: Row(
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
          // Title
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.cloud_sync_rounded, size: 18, color: Color(0xFF10B981)),
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
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'v$_targetVersion معتمد',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                'مراقبة فورية منظمة: السيرفر يغذي الفروع عبر مسارات توزيع ذكية بدون أي تداخل',
                style: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const Spacer(),

          // View Mode Switcher Pills
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2536) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _viewModeButton(
                  mode: _UpdateTopologyViewMode.flowMap,
                  icon: Icons.account_tree_rounded,
                  label: 'مخطط التوزيع',
                  isDark: isDark,
                ),
                _viewModeButton(
                  mode: _UpdateTopologyViewMode.fleetGrid,
                  icon: Icons.grid_view_rounded,
                  label: 'مصفوفة الأجهزة',
                  isDark: isDark,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Search Field
          SizedBox(
            width: 140,
            height: 32,
            child: TextField(
              onChanged: (val) {
                setState(() {
                  _searchFilter = val.trim();
                  _buildDistributionMesh();
                });
              },
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: 'بحث بالجهاز...',
                hintStyle: const TextStyle(fontSize: 10.5),
                prefixIcon: const Icon(Icons.search_rounded, size: 14),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E2536) : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // WebSocket Live Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (_isSocketConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: (_isSocketConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _isSocketConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isSocketConnected ? 'بث لحظي' : 'غير متصل',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _isSocketConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Status Counters
          _statusPill('إجمالي', totalCount, const Color(0xFF64748B), isDark),
          const SizedBox(width: 6),
          _statusPill('محدث ✓', completedCount, const Color(0xFF10B981), isDark),
          const SizedBox(width: 6),
          _statusPill('يسحب ⬇️', pullingCount, const Color(0xFFF43F5E), isDark),
          const SizedBox(width: 6),
          _statusPill('قديم ⚠️', outdatedCount, const Color(0xFFEF4444), isDark),

          const SizedBox(width: 12),

          // Action: Fleet Rollout (Push to all outdated)
          FilledButton.icon(
            onPressed: _isAutoRolloutActive ? null : _triggerFleetRollout,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: _isAutoRolloutActive
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.rocket_launch_rounded, size: 15),
            label: Text(
              _isAutoRolloutActive ? 'جارٍ النشر...' : 'نشر التحديث للفروع',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),

          // Reset Simulation
          IconButton(
            onPressed: _resetSimulation,
            tooltip: 'إعادة المحاكاة',
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF1E2536) : const Color(0xFFF1F5F9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewModeButton({
    required _UpdateTopologyViewMode mode,
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    final isSelected = _viewMode == mode;
    return InkWell(
      onTap: () {
        setState(() => _viewMode = mode);
        if (mode == _UpdateTopologyViewMode.flowMap) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitCanvasToScreen(animated: false));
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF2E384D) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
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
              color: isSelected ? const Color(0xFF10B981) : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? (isDark ? Colors.white : Colors.black87) : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String label, int count, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 9.5, color: isDark ? Colors.white70 : Colors.black87)),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // VIEW MODE 1: STRUCTURED 3-TIER FLOW MAP (ZERO OVERLAP, CLEAN BUS LINES)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildStructuredFlowMap(bool isDark) {
    return InteractiveViewer(
      transformationController: _transController,
      constrained: false,
      boundaryMargin: const EdgeInsets.all(400),
      minScale: 0.35,
      maxScale: 2.2,
      child: SizedBox(
        width: _canvasWidth,
        height: _canvasHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Layer A: Static Grid (Cached)
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size(_canvasWidth, _canvasHeight),
                  painter: _UpdateGridPainter(isDark: isDark),
                ),
              ),
            ),

            // Layer B: Clean Bus & Feeder Distribution Lines (Cached)
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _UpdateBusWiresPainter(
                    serverPosition: _serverPosition,
                    serverSize: _serverSize,
                    branchClusters: _branchClusters,
                    selectedDeviceId: _selectedDeviceId,
                    isDark: isDark,
                  ),
                ),
              ),
            ),

            // Layer C: Flowing Animated Update Packets
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _UpdateFlowPacketsPainter(
                      serverPosition: _serverPosition,
                      serverSize: _serverSize,
                      branchClusters: _branchClusters,
                      devicesMap: _devicesMap,
                      packets: _packets,
                      now: DateTime.now(),
                    ),
                  );
                },
              ),
            ),

            // Layer D1: CENTRAL SERVER NODE (TOP CENTER)
            Positioned(
              left: _serverPosition.dx,
              top: _serverPosition.dy,
              child: _buildCentralServerNode(isDark),
            ),

            // Layer D2: BRANCH CLUSTER HEADERS & DEVICE CARDS (COLLISION-FREE)
            for (final cluster in _branchClusters) ...[
              // Branch Header Badge
              Positioned(
                left: cluster.x,
                top: cluster.y,
                child: _buildBranchHeaderBadge(cluster, isDark),
              ),

              // Device Cards
              for (final dev in cluster.devices) ...[
                Positioned(
                  left: dev.position.dx,
                  top: dev.position.dy,
                  child: _buildDeviceNodeCard(dev, _selectedDeviceId == dev.id, isDark),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // VIEW MODE 2: HIGH-SPEED RESPONSIVE FLEET MATRIX (ZERO PANNING NEEDED)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildBranchFleetMatrix(bool isDark) {
    if (_branchClusters.isEmpty) {
      return Center(
        child: Text(
          'لا توجد أجهزة مطابقة للبحث',
          style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final cluster in _branchClusters) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141722) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Branch Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1F2E) : const Color(0xFFF1F5F9),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.storefront_rounded, size: 18, color: Color(0xFF10B981)),
                        const SizedBox(width: 8),
                        Text(
                          cluster.branchName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'كود ${cluster.branchCode}',
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${cluster.completedCount} محدث • ${cluster.outdatedCount} قديم',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: cluster.outdatedCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Device Cards Grid
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        for (final dev in cluster.devices)
                          _buildDeviceNodeCard(dev, _selectedDeviceId == dev.id, isDark),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // CENTRAL SERVER NODE (TOP CENTER)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildCentralServerNode(bool isDark) {
    const greenColor = Color(0xFF10B981);
    final fileName = _activeRelease?.fileName ?? 'iSmartMessenger-Setup-v$_targetVersion.exe';
    final fileSizeMb = _activeRelease != null && _activeRelease!.fileSize > 0
        ? (_activeRelease!.fileSize / (1024 * 1024)).toStringAsFixed(1)
        : '84.5';

    return Container(
      width: _serverSize.width,
      height: _serverSize.height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B26) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: greenColor, width: 2.2),
        boxShadow: [
          BoxShadow(
            color: greenColor.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Top Hub Status Tag
          Positioned(
            top: -10,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: greenColor,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: greenColor.withValues(alpha: 0.45), blurRadius: 8),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hub_rounded, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text(
                    'خادم التحديثات المركزي • READY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Output Trunk Port Center (Bottom)
          Positioned(
            left: (_serverSize.width / 2) - 6,
            bottom: -6,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: greenColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: greenColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: greenColor.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.dns_rounded, color: greenColor, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'حزمة التحديث المعتمدة v$_targetVersion',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: greenColor.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'معتمد',
                                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: greenColor),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            fileName,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontFamily: 'monospace',
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

                // Metrics Pill Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF10131A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _serverMetric('الحجم', '$fileSizeMb MB', isDark),
                      _serverMetric('البيئة', 'Windows x64', isDark),
                      _serverMetric('البروتوكول', 'HTTP Stream / WS', isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _serverMetric(String label, String value, bool isDark) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 8.5, color: isDark ? Colors.white54 : Colors.black45)),
        const SizedBox(height: 1),
        Text(
          value,
          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF10B981)),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // BRANCH CLUSTER HEADER BADGE
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildBranchHeaderBadge(_UpdateBranchCluster cluster, bool isDark) {
    final hasOutdated = cluster.outdatedCount > 0;
    final color = hasOutdated ? const Color(0xFFEF4444) : const Color(0xFF10B981);

    return Container(
      width: cluster.width,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B26) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.storefront_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  cluster.branchName,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'كود ${cluster.branchCode} • ${cluster.totalCount} كاشيرات',
                  style: TextStyle(
                    fontSize: 8.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              hasOutdated ? '${cluster.outdatedCount} بحاجة لتحديث' : 'محدث بالكامل ✓',
              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: color),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // DEVICE WORKSTATION NODE CARD (RED ➔ ROSE PULSE ➔ GREEN)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildDeviceNodeCard(
    _UpdateTopologyDevice dev,
    bool isSelected,
    bool isDark,
  ) {
    final cardColor = dev.accentColor;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedDeviceId = dev.id);
        if (MediaQuery.of(context).size.width < 1150) {
          Scaffold.of(context).openEndDrawer();
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: dev.size.width,
        height: dev.size.height,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B26) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? cardColor : (dev.isPulling ? const Color(0xFFF43F5E) : cardColor.withValues(alpha: 0.55)),
            width: isSelected || dev.isPulling ? 2.2 : 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: cardColor.withValues(alpha: dev.isPulling ? 0.35 : (dev.isCompleted ? 0.2 : 0.12)),
              blurRadius: isSelected || dev.isPulling ? 14 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Top Input Port Handle (facing the branch bus)
            Positioned(
              left: (dev.size.width / 2) - 5,
              top: -5,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF10131A) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: cardColor, width: 2),
                ),
              ),
            ),

            // Top Status Badge (RED when outdated, GREEN when completed)
            Positioned(
              top: -8,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
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
                      dev.isCompleted
                          ? Icons.check_circle_rounded
                          : (dev.isPulling ? Icons.downloading_rounded : Icons.warning_amber_rounded),
                      color: Colors.white,
                      size: 10,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      dev.statusBadgeLabel,
                      style: const TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: cardColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cardColor.withValues(alpha: 0.35)),
                        ),
                        child: Icon(
                          dev.isCompleted ? Icons.desktop_windows_rounded : Icons.desktop_access_disabled_rounded,
                          color: cardColor,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dev.hostname,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              dev.cashierName,
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

                  // Middle Progress Bar if pulling
                  if (dev.isPulling) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: dev.progress,
                        backgroundColor: cardColor.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(cardColor),
                        minHeight: 4,
                      ),
                    ),
                  ],

                  // Bottom info row + Pull Trigger button
                  Row(
                    children: [
                      Text(
                        dev.ipAddress,
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                        ),
                      ),
                      const Spacer(),

                      // Action button if not completed
                      if (!dev.isCompleted && !dev.isPulling)
                        InkWell(
                          onTap: () => _triggerDevicePull(dev),
                          borderRadius: BorderRadius.circular(5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.download_rounded, size: 10, color: Color(0xFFEF4444)),
                                SizedBox(width: 3),
                                Text(
                                  'سحب التحديث',
                                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFFEF4444)),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (dev.isCompleted)
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_rounded, size: 11, color: Color(0xFF10B981)),
                            SizedBox(width: 3),
                            Text(
                              'متوافق 100%',
                              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // FLOATING CANVAS CONTROLS (ZOOM & FIT)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildFloatingControls(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.zoom_in_rounded, size: 18),
            tooltip: 'تكبير (+)',
            onPressed: () => _zoomBy(1.2),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out_rounded, size: 18),
            tooltip: 'تصغير (-)',
            onPressed: () => _zoomBy(0.8),
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen_rounded, size: 18),
            tooltip: 'ملاءمة المخطط',
            onPressed: () => _fitCanvasToScreen(),
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            tooltip: 'إعادة الضبط',
            onPressed: () => _resetZoom(),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // BOTTOM LIVE DISTRIBUTION CONSOLE
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildBottomConsole(bool isDark) {
    final latestLog = _distributionLogs.isNotEmpty ? _distributionLogs.first : null;

    if (!_showConsole) {
      return InkWell(
        onTap: () => setState(() => _showConsole = true),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141722).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'حركة توزيع وسحب الحزم:',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  latestLog != null ? '${latestLog['time']} • ${latestLog['message']}' : 'الشبكة جاهزة للبث...',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_up_rounded, size: 16),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0E1118) : const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF222938) : const Color(0xFF334155),
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1E2536))),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded, size: 15, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                const Text(
                  'سجل عمليات سحب وتثبيت التحديثات بالفروع (Live Rollout Stream)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 15, color: Colors.white70),
                  onPressed: () => setState(() => _showConsole = false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: _distributionLogs.length,
              itemBuilder: (context, index) {
                final item = _distributionLogs[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '[${item['time']}]',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: item['level'] == 'SUCCESS'
                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                              : const Color(0xFF38BDF8).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          item['level'] as String? ?? 'INFO',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: item['level'] == 'SUCCESS'
                                ? const Color(0xFF10B981)
                                : const Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '<${item['source']}>',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item['message'] as String? ?? '',
                          style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // SIDE DEVICE INSPECTOR
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildDeviceInspector(bool isDark) {
    final dev = _devicesMap[_selectedDeviceId];
    if (dev == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        border: Border(
          left: BorderSide(
            color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: dev.accentColor.withValues(alpha: 0.12),
              border: Border(bottom: BorderSide(color: dev.accentColor.withValues(alpha: 0.25))),
            ),
            child: Row(
              children: [
                Icon(Icons.desktop_windows_rounded, color: dev.accentColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dev.hostname,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        dev.statusBadgeLabel,
                        style: TextStyle(fontSize: 10.5, color: dev.accentColor, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => _selectedDeviceId = null),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _specItem('الموظف المسؤول', dev.cashierName, isDark),
                _specItem('الفرع', dev.branchName, isDark),
                _specItem('كود الفرع', dev.branchCode, isDark),
                _specItem('عنوان IP', dev.ipAddress, isDark),
                _specItem('نظام التشغيل', dev.os, isDark),
                _specItem('الإصدار الحالي بالجهاز', 'v${dev.currentDisplayVersion}', isDark),
                _specItem('الإصدار المعتمد بالسيرفر', 'v$_targetVersion', isDark),
                _specItem('حالة المطابقة', dev.isCompleted ? 'مطابق ومحدث بالكامل ✓' : 'بحاجة لتحديث ⚠️', isDark),
                const SizedBox(height: 16),
                if (!dev.isCompleted)
                  FilledButton.icon(
                    onPressed: () => _triggerDevicePull(dev),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('سحب وتثبيت التحديث الآن', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _specItem(String key, String value, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0E1118) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Text(key, style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CANVAS PAINTERS FOR STRUCTURED ENTERPRISE FLOW MAP
// ══════════════════════════════════════════════════════════════════════════════

/// Static painter for the background dot matrix.
class _UpdateGridPainter extends CustomPainter {
  const _UpdateGridPainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = isDark ? const Color(0xFF1E2433) : const Color(0xFFE2E8F0)
      ..style = PaintingStyle.fill;

    const spacing = 28.0;
    for (double x = 14; x < size.width; x += spacing) {
      for (double y = 14; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _UpdateGridPainter oldDelegate) => oldDelegate.isDark != isDark;
}

/// Clean bus lines connecting Server ➔ Main Bus ➔ Branch Headers ➔ Device Cards.
/// No wire ever cuts across or obscures any card!
class _UpdateBusWiresPainter extends CustomPainter {
  const _UpdateBusWiresPainter({
    required this.serverPosition,
    required this.serverSize,
    required this.branchClusters,
    required this.selectedDeviceId,
    required this.isDark,
  });

  final Offset serverPosition;
  final Size serverSize;
  final List<_UpdateBranchCluster> branchClusters;
  final String? selectedDeviceId;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (branchClusters.isEmpty) return;

    final trunkPaint = Paint()
      ..color = (isDark ? const Color(0xFF10B981) : const Color(0xFF059669)).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final branchLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final serverBottom = Offset(
      serverPosition.dx + (serverSize.width / 2.0),
      serverPosition.dy + serverSize.height,
    );

    const busY = 190.0;

    // 1. Vertical trunk from server down to bus
    final trunkPath = Path()
      ..moveTo(serverBottom.dx, serverBottom.dy)
      ..lineTo(serverBottom.dx, busY);
    canvas.drawPath(trunkPath, trunkPaint);

    // 2. Horizontal bus spanning across active branches
    final minColX = branchClusters.first.x + (branchClusters.first.width / 2.0);
    final maxColX = branchClusters.last.x + (branchClusters.last.width / 2.0);

    final busPath = Path()
      ..moveTo(math.min(minColX, serverBottom.dx), busY)
      ..lineTo(math.max(maxColX, serverBottom.dx), busY);
    canvas.drawPath(busPath, trunkPaint);

    // 3. Drop lines from bus down to each branch header and then to each device
    for (final cluster in branchClusters) {
      final clusterCenterX = cluster.x + (cluster.width / 2.0);

      // Drop from bus to branch header top
      final dropPath = Path()
        ..moveTo(clusterCenterX, busY)
        ..lineTo(clusterCenterX, cluster.y);
      canvas.drawPath(dropPath, trunkPaint);

      // Spine from branch header bottom down to devices
      final branchBottom = Offset(clusterCenterX, cluster.y + 44.0);
      if (cluster.devices.isNotEmpty) {
        final lastDev = cluster.devices.last;
        final spineEndY = lastDev.position.dy + 8.0;

        final spinePath = Path()
          ..moveTo(branchBottom.dx, branchBottom.dy)
          ..lineTo(branchBottom.dx, spineEndY);

        branchLinePaint.color = (isDark ? const Color(0xFF2E384D) : const Color(0xFFCBD5E1));
        canvas.drawPath(spinePath, branchLinePaint);

        // Feed each device at top input port
        for (final dev in cluster.devices) {
          final isHighlighted = selectedDeviceId == dev.id || dev.isPulling;
          final devPort = Offset(dev.position.dx + (dev.size.width / 2.0), dev.position.dy);

          final feederPath = Path()
            ..moveTo(branchBottom.dx, devPort.dy - 6.0)
            ..lineTo(devPort.dx, devPort.dy);

          branchLinePaint.color = isHighlighted
              ? dev.accentColor
              : (isDark ? const Color(0xFF2E384D) : const Color(0xFFCBD5E1));
          branchLinePaint.strokeWidth = isHighlighted ? 2.2 : 1.4;

          if (isHighlighted) {
            glowPaint.color = dev.accentColor.withValues(alpha: 0.35);
            canvas.drawPath(feederPath, glowPaint);
          }

          canvas.drawPath(feederPath, branchLinePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _UpdateBusWiresPainter oldDelegate) {
    return oldDelegate.selectedDeviceId != selectedDeviceId ||
        oldDelegate.isDark != isDark ||
        oldDelegate.branchClusters.length != branchClusters.length;
  }
}

/// Flowing animated data packets traveling along the exact structured bus path.
class _UpdateFlowPacketsPainter extends CustomPainter {
  const _UpdateFlowPacketsPainter({
    required this.serverPosition,
    required this.serverSize,
    required this.branchClusters,
    required this.devicesMap,
    required this.packets,
    required this.now,
  });

  final Offset serverPosition;
  final Size serverSize;
  final List<_UpdateBranchCluster> branchClusters;
  final Map<String, _UpdateTopologyDevice> devicesMap;
  final List<_UpdateDataPacket> packets;
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()..style = PaintingStyle.fill;

    final serverBottom = Offset(
      serverPosition.dx + (serverSize.width / 2.0),
      serverPosition.dy + serverSize.height,
    );
    const busY = 190.0;

    for (final pkt in packets) {
      final dev = devicesMap[pkt.targetDeviceId];
      if (dev == null) continue;

      final devPort = Offset(dev.position.dx + (dev.size.width / 2.0), dev.position.dy);
      final branchCenterX = devPort.dx;

      // 4-segment path:
      // Segment 1: Server Bottom (0.0) -> Bus (0.25)
      // Segment 2: Bus X_server -> Bus X_branch (0.25 -> 0.50)
      // Segment 3: Bus -> Branch Header (0.50 -> 0.70)
      // Segment 4: Branch Header -> Device Port (0.70 -> 1.0)
      final t = pkt.progress(now);

      final Offset pt;
      if (t < 0.25) {
        final subT = t / 0.25;
        pt = Offset(serverBottom.dx, serverBottom.dy + (busY - serverBottom.dy) * subT);
      } else if (t < 0.50) {
        final subT = (t - 0.25) / 0.25;
        pt = Offset(serverBottom.dx + (branchCenterX - serverBottom.dx) * subT, busY);
      } else if (t < 0.70) {
        final subT = (t - 0.50) / 0.20;
        pt = Offset(branchCenterX, busY + (230.0 - busY) * subT);
      } else {
        final subT = (t - 0.70) / 0.30;
        pt = Offset(branchCenterX, 274.0 + (devPort.dy - 274.0) * subT);
      }

      // Comet trail
      for (int i = 3; i >= 1; i--) {
        final trailPaint = Paint()
          ..color = pkt.color.withValues(alpha: 0.25 / i)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(pt.dx, pt.dy - (i * 2.5)), 2.8 - (i * 0.5), trailPaint);
      }

      // Glowing Halo
      glowPaint.color = pkt.color.withValues(alpha: 0.45);
      canvas.drawCircle(pt, 8.5, glowPaint);

      // White Core
      dotPaint.color = Colors.white;
      canvas.drawCircle(pt, 3.5, dotPaint);

      // Colored Center
      final corePaint = Paint()..color = pkt.color;
      canvas.drawCircle(pt, 2.0, corePaint);

      // Floating Action Chip Label Above Packet
      if (pkt.label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: pkt.label,
            style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          textDirection: TextDirection.rtl,
        )..layout();

        final labelBg = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(pt.dx, pt.dy - 14),
            width: tp.width + 10,
            height: tp.height + 5,
          ),
          const Radius.circular(5),
        );
        final bgPaint = Paint()..color = pkt.color.withValues(alpha: 0.92);
        canvas.drawRRect(labelBg, bgPaint);
        tp.paint(canvas, Offset(pt.dx - (tp.width / 2), pt.dy - 14 - (tp.height / 2)));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _UpdateFlowPacketsPainter oldDelegate) => true;
}
