import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/update_management_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/providers.dart';
import '../../chat/data/chat_socket_service.dart';
import '../../chat/models/chat_models.dart';

/// State of an individual device in the update distribution mesh.
enum _UpdateDevicePhase {
  outdated,    // 🔴 Red: Outdated version, waiting for update
  pulling,     // 🔴 Pulse: Actively pulling/downloading update chunks from server
  completed,   // 🟢 Green: Successfully updated to target version!
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

/// Data packet streaming update chunks from Server to Device.
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

  final List<_UpdateTopologyDevice> _canvasDevices = [];
  final Map<String, _UpdateTopologyDevice> _devicesMap = {};
  final List<_UpdateDataPacket> _packets = [];
  final List<Map<String, dynamic>> _distributionLogs = [];

  // Server Node Coordinates
  late Offset _serverPosition;
  final Size _serverSize = const Size(340, 136);

  String _targetVersion = '1.1.22';
  ManagedUpdateRelease? _activeRelease;

  bool _isAutoRolloutActive = false;
  String _searchFilter = '';
  String _selectedBranch = 'all';
  String? _selectedDeviceId;

  double _canvasWidth = 2200;
  double _canvasHeight = 900;

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
      duration: const Duration(milliseconds: 400),
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
      _fitCanvasToScreen(animated: false);
      _listenToLiveSocket();
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
  // MESH BUILDER: SERVER (GREEN) + DEVICES (RED ➔ GREEN)
  // ══════════════════════════════════════════════════════════════════════════════
  void _buildDistributionMesh() {
    _canvasDevices.clear();
    _devicesMap.clear();

    // 1. Extract devices from real props or fallback to realistic enterprise demo fleet
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

    const cardWidth = 310.0;
    const cardHeight = 104.0;
    const gapY = 16.0;
    final devCount = filtered.length;

    final isDualCol = devCount > 5;
    final totalRows = isDualCol ? ((devCount + 1) ~/ 2) : devCount;
    final devicesRackHeight = math.max(680.0, totalRows * (cardHeight + gapY) + 120.0);

    _canvasHeight = math.max(850.0, devicesRackHeight);

    // SERVER POSITION (On the Left Side, Green)
    _serverPosition = Offset(60.0, (_canvasHeight / 2.0) - (_serverSize.height / 2.0));

    // DEVICES POSITION (On the Right Side, Red by default until updated)
    final devicesStartX = _serverPosition.dx + _serverSize.width + 240.0;

    for (int i = 0; i < filtered.length; i++) {
      final d = filtered[i];
      final col = isDualCol ? (i % 2) : 0;
      final row = isDualCol ? (i ~/ 2) : i;

      final posX = devicesStartX + col * (cardWidth + 30.0);
      final posY = 60.0 + row * (cardHeight + gapY);

      final portRatio = devCount <= 1 ? 0.5 : (i / (devCount - 1)).clamp(0.12, 0.88);
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
        position: Offset(posX, posY),
        size: const Size(cardWidth, cardHeight),
        portOffset: portRatio,
        phase: isAlreadyTarget ? _UpdateDevicePhase.completed : _UpdateDevicePhase.outdated,
        progress: isAlreadyTarget ? 1.0 : 0.0,
      );

      _canvasDevices.add(dev);
      _devicesMap[dev.id] = dev;
    }

    final totalWidth = devicesStartX + (isDualCol ? cardWidth * 2 + 80 : cardWidth + 80) + 100;
    _canvasWidth = math.max(1900.0, totalWidth);
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

    // Launch moving update packet from Server to this Device
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

  void _launchUpdatePacket(_UpdateTopologyDevice dev, String label) {
    setState(() {
      _packets.add(_UpdateDataPacket(
        id: 'pkt_upd_${DateTime.now().microsecondsSinceEpoch}',
        targetDeviceId: dev.id,
        label: label,
        color: dev.accentColor,
        startedAt: DateTime.now(),
        duration: const Duration(milliseconds: 750),
        portOffset: dev.portOffset,
      ));
    });
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
  // RESPONSIVE AUTO-FIT & ZOOM
  // ══════════════════════════════════════════════════════════════════════════════
  void _fitCanvasToScreen({bool animated = true}) {
    final mediaSize = MediaQuery.of(context).size;
    final availableWidth = mediaSize.width - (_selectedDeviceId != null && mediaSize.width >= 1150 ? 380 : 0);
    final scale = (availableWidth / _canvasWidth).clamp(0.40, 1.05);

    final targetX = (availableWidth - (_canvasWidth * scale)) / 2;
    final targetY = (mediaSize.height - (_canvasHeight * scale)) / 2 - 20;

    final targetMatrix = Matrix4.identity()
      ..translate(targetX.clamp(-350.0, 100.0), targetY.clamp(-180.0, 100.0))
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
    final mediaSize = MediaQuery.of(context).size;
    final center = Offset(mediaSize.width / 2, mediaSize.height / 2);

    final newMatrix = curMatrix.clone()
      ..translate(center.dx, center.dy)
      ..scale(factor)
      ..translate(-center.dx, -center.dy);

    _transController.value = newMatrix;
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // MAIN BUILD
  // ══════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    _packets.removeWhere((p) => p.isFinished(now));

    final totalCount = _canvasDevices.length;
    final completedCount = _canvasDevices.where((d) => d.isCompleted).length;
    final outdatedCount = _canvasDevices.where((d) => d.isOutdated).length;
    final pullingCount = _canvasDevices.where((d) => d.isPulling).length;

    final content = LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 1150;

        return Column(
          children: [
            // 1. TOP HEADER & TELEMETRY STRIP
            _buildTopToolbar(isDark, totalCount, completedCount, outdatedCount, pullingCount),

            // 2. MAIN 2D n8n CANVAS
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        _buildN8nCanvas(isDark),

                        // Floating HUD Navigation
                        Positioned(
                          left: 20,
                          bottom: _showConsole ? 220 : 20,
                          child: _buildFloatingControls(isDark),
                        ),

                        // Bottom Live Distribution Terminal
                        Positioned(
                          bottom: 16,
                          left: 250,
                          right: 16,
                          child: _buildBottomConsole(isDark),
                        ),
                      ],
                    ),
                  ),

                  // Side Inspector
                  if (_selectedDeviceId != null && isWideScreen)
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

    if (widget.isEmbedded) {
      return Container(
        color: isDark ? const Color(0xFF10131A) : const Color(0xFFF8FAFC),
        child: content,
      );
    }

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
                'مراقبة فورية لأجهزة الكاشير أثناء سحب التحديث من السيرفر وتحولها للأخضر بعد اكتمال النشر',
                style: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const Spacer(),

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
                fillColor: isDark ? const Color(0xFF0E1118) : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF222938) : const Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF222938) : const Color(0xFFCBD5E1)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Branch Filter Dropdown
          if (widget.branches.isNotEmpty) ...[
            PopupMenuButton<String>(
              initialValue: _selectedBranch,
              tooltip: 'تصفية حسب الفرع',
              onSelected: (code) {
                setState(() {
                  _selectedBranch = code;
                  _buildDistributionMesh();
                });
                _fitCanvasToScreen();
              },
              color: isDark ? const Color(0xFF1A1F2C) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'all',
                  child: Text('جميع الفروع', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                ...widget.branches.map((b) => PopupMenuItem(
                  value: b.code,
                  child: Text(b.name, style: const TextStyle(fontSize: 11)),
                )),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2536) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _selectedBranch != 'all'
                        ? const Color(0xFF10B981)
                        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storefront_rounded, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      _selectedBranch == 'all'
                          ? 'الفروع'
                          : widget.branches.firstWhere((b) => b.code == _selectedBranch, orElse: () => widget.branches.first).name,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _selectedBranch != 'all' ? const Color(0xFF10B981) : null,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down_rounded, size: 14),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Live Telemetry Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: _isSocketConnected
                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isSocketConnected
                    ? const Color(0xFF10B981).withValues(alpha: 0.4)
                    : const Color(0xFFF59E0B).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, _) {
                    final alpha = _isSocketConnected
                        ? (0.4 + 0.6 * _pulseController.value)
                        : 0.8;
                    return Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (_isSocketConnected
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF59E0B))
                            .withValues(alpha: alpha),
                        boxShadow: [
                          BoxShadow(
                            color: (_isSocketConnected
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFF59E0B))
                                .withValues(alpha: 0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 7),
                Text(
                  _isSocketConnected ? 'Live Telemetry: متصل لحظياً' : 'Live Telemetry: جاري الاتصال...',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: _isSocketConnected
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Status Counters
          _metricPill(
            label: 'إجمالي المحطات',
            value: '$totalCount',
            color: const Color(0xFF38BDF8),
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _metricPill(
            label: '🔴 بحاجة لتحديث / تسحب',
            value: '${outdatedCount + pullingCount}',
            color: const Color(0xFFEF4444),
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _metricPill(
            label: '🟢 محدث بنجاح',
            value: '$completedCount',
            color: const Color(0xFF10B981),
            isDark: isDark,
          ),
          const SizedBox(width: 14),

          // Actions
          OutlinedButton.icon(
            onPressed: _resetSimulation,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('إعادة ضبط', style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _isAutoRolloutActive ? null : _triggerFleetRollout,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981), // Green button
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: _isAutoRolloutActive
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.rocket_launch_rounded, size: 16),
            label: Text(
              _isAutoRolloutActive ? 'جارٍ بث التحديث...' : '🚀 نشر التحديث للأسطول',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricPill({
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // 2. THE 2D n8n CANVAS
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildN8nCanvas(bool isDark) {
    return InteractiveViewer(
      transformationController: _transController,
      constrained: false,
      boundaryMargin: const EdgeInsets.all(800),
      minScale: 0.30,
      maxScale: 2.5,
      child: SizedBox(
        width: _canvasWidth,
        height: _canvasHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Layer A: n8n Dot Matrix Grid
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size(_canvasWidth, _canvasHeight),
                  painter: _UpdateGridPainter(isDark: isDark),
                ),
              ),
            ),

            // Layer B: Cubic Bezier Connection Wires (Server ➔ Devices)
            Positioned.fill(
              child: CustomPaint(
                painter: _UpdateWiresPainter(
                  serverPosition: _serverPosition,
                  serverSize: _serverSize,
                  devices: _canvasDevices,
                  selectedDeviceId: _selectedDeviceId,
                  isDark: isDark,
                ),
              ),
            ),

            // Layer C: Flowing Update Packets
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _UpdatePacketsPainter(
                      serverPosition: _serverPosition,
                      serverSize: _serverSize,
                      devicesMap: _devicesMap,
                      packets: _packets,
                      now: DateTime.now(),
                    ),
                  );
                },
              ),
            ),

            // Layer D1: CENTRAL SERVER NODE (GREEN)
            Positioned(
              left: _serverPosition.dx,
              top: _serverPosition.dy,
              child: _buildCentralServerNode(isDark),
            ),

            // Layer D2: DEVICE WORKSTATIONS (RED ➔ GREEN)
            ..._canvasDevices.map((dev) {
              final isSelected = _selectedDeviceId == dev.id;
              return Positioned(
                left: dev.position.dx,
                top: dev.position.dy,
                child: _buildDeviceNodeCard(dev, isSelected, isDark),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // CENTRAL SERVER NODE (ALWAYS GREEN WITH TARGET VERSION)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildCentralServerNode(bool isDark) {
    const greenColor = Color(0xFF10B981);
    final fileName = _activeRelease?.fileName ?? 'iSmartMessenger-Setup-v$_targetVersion.exe';
    final fileSizeMb = _activeRelease != null && _activeRelease!.fileSize > 0
        ? (_activeRelease!.fileSize / (1024 * 1024)).toStringAsFixed(1)
        : '68.4';

    return Container(
      width: _serverSize.width,
      height: _serverSize.height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141D22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: greenColor, width: 2.2),
        boxShadow: [
          BoxShadow(
            color: greenColor.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Right Output Port Handle
          Positioned(
            right: -6,
            top: (_serverSize.height / 2) - 6,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF10131A) : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: greenColor, width: 2.5),
              ),
            ),
          ),

          // Header Badge (GREEN TARGET VERSION)
          Positioned(
            top: -10,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: greenColor,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: greenColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'الإصدار المعتمد للنشر v$_targetVersion ✓',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Interior content
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: greenColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: greenColor.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.cloud_upload_rounded, color: greenColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'سيرفر التحديثات المركزي (Release Hub)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: greenColor,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'مستودع نشر الحزم والتحديثات التلقائية المعتمدة',
                            style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0E1418) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: greenColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file_rounded, size: 14, color: greenColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$fileName ($fileSizeMb MB)',
                          style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: greenColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'جاهز للبث 100%',
                          style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: greenColor),
                        ),
                      ),
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

  // ══════════════════════════════════════════════════════════════════════════════
  // DEVICE NODE CARD (RED ➔ GREEN DYNAMIC TRANSITION)
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
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: dev.size.width,
        height: dev.size.height,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B26) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? cardColor : (dev.isPulling ? const Color(0xFFF43F5E) : cardColor.withValues(alpha: 0.6)),
            width: isSelected || dev.isPulling ? 2.4 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: cardColor.withValues(alpha: dev.isPulling ? 0.35 : (dev.isCompleted ? 0.25 : 0.15)),
              blurRadius: isSelected || dev.isPulling ? 18 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Left Input Port Handle
            Positioned(
              left: -6,
              top: (dev.size.height / 2) - 6,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF10131A) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: cardColor, width: 2.5),
                ),
              ),
            ),

            // Top Status Badge (RED when outdated, GREEN when completed)
            Positioned(
              top: -8,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: cardColor.withValues(alpha: 0.4), blurRadius: 6),
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
                      size: 11,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      dev.statusBadgeLabel,
                      style: const TextStyle(
                        fontSize: 9.5,
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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: cardColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cardColor.withValues(alpha: 0.4)),
                        ),
                        child: Icon(
                          dev.isCompleted ? Icons.desktop_windows_rounded : Icons.desktop_access_disabled_rounded,
                          color: cardColor,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dev.hostname,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${dev.cashierName} • ${dev.branchName}',
                              style: TextStyle(
                                fontSize: 10,
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
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: dev.progress,
                        backgroundColor: cardColor.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(cardColor),
                        minHeight: 5,
                      ),
                    ),
                  ],

                  // Bottom info row + Pull Trigger button
                  Row(
                    children: [
                      Text(
                        dev.ipAddress,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                        ),
                      ),
                      const Spacer(),

                      // Action button if not completed
                      if (!dev.isCompleted && !dev.isPulling)
                        InkWell(
                          onTap: () => _triggerDevicePull(dev),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.download_rounded, size: 11, color: Color(0xFFEF4444)),
                                SizedBox(width: 3),
                                Text(
                                  'سحب التحديث',
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFEF4444)),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (dev.isCompleted)
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_rounded, size: 12, color: Color(0xFF10B981)),
                            SizedBox(width: 3),
                            Text(
                              'متوافق 100%',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
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
  // FLOATING CANVAS CONTROLS (Zoom, Fit)
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
            tooltip: 'ملاءمة الشاشة',
            onPressed: () => _fitCanvasToScreen(),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
              const SizedBox(width: 9),
              const Text(
                'حركة توزيع وسحب الحزم:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  latestLog != null ? '${latestLog['time']} • ${latestLog['message']}' : 'الشبكة جاهزة للبث...',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 190,
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1E2536))),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded, size: 16, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                const Text(
                  'سجل عمليات سحب وتثبيت التحديثات بالفروع (Live Rollout Stream)',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                  onPressed: () => setState(() => _showConsole = false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _distributionLogs.length,
              itemBuilder: (context, index) {
                final item = _distributionLogs[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '[${item['time']}]',
                        style: const TextStyle(
                          fontSize: 10,
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
                            color: item['level'] == 'SUCCESS' ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item['message'] as String? ?? '',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            color: Color(0xFFE2E8F0),
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
  // DEVICE INSPECTOR
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
// CANVAS PAINTERS FOR UPDATE TOPOLOGY
// ══════════════════════════════════════════════════════════════════════════════
class _UpdateGridPainter extends CustomPainter {
  const _UpdateGridPainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = isDark ? const Color(0xFF222938) : const Color(0xFFCBD5E1)
      ..style = PaintingStyle.fill;

    const spacing = 24.0;
    for (double x = 12; x < size.width; x += spacing) {
      for (double y = 12; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _UpdateGridPainter oldDelegate) => oldDelegate.isDark != isDark;
}

class _UpdateWiresPainter extends CustomPainter {
  const _UpdateWiresPainter({
    required this.serverPosition,
    required this.serverSize,
    required this.devices,
    required this.selectedDeviceId,
    required this.isDark,
  });

  final Offset serverPosition;
  final Size serverSize;
  final List<_UpdateTopologyDevice> devices;
  final String? selectedDeviceId;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final wirePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final serverOutput = Offset(
      serverPosition.dx + serverSize.width,
      serverPosition.dy + (serverSize.height / 2),
    );

    for (final dev in devices) {
      final p2 = Offset(
        dev.position.dx,
        dev.position.dy + (dev.size.height / 2),
      );

      final isHighlighted = selectedDeviceId == dev.id || dev.isPulling;

      // Color matches device phase (Red while outdated/pulling, Green when completed!)
      wirePaint.color = dev.accentColor.withValues(alpha: isHighlighted ? 0.9 : 0.45);
      wirePaint.strokeWidth = isHighlighted ? 2.6 : 1.8;

      final path = Path()..moveTo(serverOutput.dx, serverOutput.dy);
      final deltaX = (p2.dx - serverOutput.dx).abs() * 0.5;
      final c1 = Offset(serverOutput.dx + math.max(60.0, deltaX), serverOutput.dy);
      final c2 = Offset(p2.dx - math.max(60.0, deltaX), p2.dy);

      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
      canvas.drawPath(path, wirePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _UpdateWiresPainter oldDelegate) => true;
}

class _UpdatePacketsPainter extends CustomPainter {
  const _UpdatePacketsPainter({
    required this.serverPosition,
    required this.serverSize,
    required this.devicesMap,
    required this.packets,
    required this.now,
  });

  final Offset serverPosition;
  final Size serverSize;
  final Map<String, _UpdateTopologyDevice> devicesMap;
  final List<_UpdateDataPacket> packets;
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()..style = PaintingStyle.fill;

    final p1 = Offset(
      serverPosition.dx + serverSize.width,
      serverPosition.dy + (serverSize.height / 2),
    );

    for (final pkt in packets) {
      final dev = devicesMap[pkt.targetDeviceId];
      if (dev == null) continue;

      final p2 = Offset(
        dev.position.dx,
        dev.position.dy + (dev.size.height / 2),
      );

      final t = pkt.progress(now);
      final deltaX = (p2.dx - p1.dx).abs() * 0.5;
      final c1 = Offset(p1.dx + math.max(60.0, deltaX), p1.dy);
      final c2 = Offset(p2.dx - math.max(60.0, deltaX), p2.dy);

      // Comet trail
      for (int i = 3; i >= 1; i--) {
        final trailT = (t - (i * 0.04)).clamp(0.0, 1.0);
        if (trailT > 0.0) {
          final trailPt = _evalCubicBezier(p1, c1, c2, p2, trailT);
          final trailPaint = Paint()
            ..color = pkt.color.withValues(alpha: 0.28 / i)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(trailPt, 3.2 - (i * 0.6), trailPaint);
        }
      }

      final pt = _evalCubicBezier(p1, c1, c2, p2, t);

      // 1. Halo
      glowPaint.color = pkt.color.withValues(alpha: 0.45);
      canvas.drawCircle(pt, 9.0, glowPaint);

      // 2. White Core
      dotPaint.color = Colors.white;
      canvas.drawCircle(pt, 3.8, dotPaint);

      // 3. Colored Core
      final corePaint = Paint()..color = pkt.color;
      canvas.drawCircle(pt, 2.3, corePaint);

      // 4. Floating Action Chip Label Above Packet
      if (pkt.label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: pkt.label,
            style: const TextStyle(
              fontSize: 9.0,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          textDirection: TextDirection.rtl,
        )..layout();

        final labelBg = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(pt.dx, pt.dy - 16),
            width: tp.width + 12,
            height: tp.height + 6,
          ),
          const Radius.circular(6),
        );
        final bgPaint = Paint()..color = pkt.color.withValues(alpha: 0.92);
        canvas.drawRRect(labelBg, bgPaint);
        tp.paint(canvas, Offset(pt.dx - (tp.width / 2), pt.dy - 16 - (tp.height / 2)));
      }
    }
  }

  Offset _evalCubicBezier(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final u = 1.0 - t;
    final tt = t * t;
    final uu = u * u;
    final uuu = uu * u;
    final ttt = tt * t;

    final x = uuu * p0.dx + 3 * uu * t * p1.dx + 3 * u * tt * p2.dx + ttt * p3.dx;
    final y = uuu * p0.dy + 3 * uu * t * p1.dy + 3 * u * tt * p2.dy + ttt * p3.dy;
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant _UpdatePacketsPainter oldDelegate) => true;
}
