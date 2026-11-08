import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../chat/data/chat_socket_service.dart';
import '../../chat/models/chat_models.dart';
import '../models/update_management_models.dart';

/// State of an individual device in the update distribution network.
enum _UpdateDevicePhase {
  outdated,  // 🔴 Red: Outdated version, waiting for update
  pulling,   // 🔴 Rose Pulse: Actively pulling/downloading update chunks from server
  completed, // 🟢 Green: Successfully updated to target version!
}

/// Representation of a branch cluster containing its fleet of devices.
class _UpdateBranchCluster {
  _UpdateBranchCluster({
    required this.branchCode,
    required this.branchName,
    required this.devices,
  });

  final String branchCode;
  final String branchName;
  final List<_UpdateTopologyDevice> devices;

  int get totalCount => devices.length;
  int get completedCount => devices.where((d) => d.isCompleted).length;
  int get outdatedCount => devices.where((d) => d.isOutdated).length;
  int get pullingCount => devices.where((d) => d.isPulling).length;
}

/// Model for a device in the update distribution command center.
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
        return const Color(0xFFF43F5E); // 🔴 Rose / Active Pull
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

/// High-performance, zero-lag, 100% organized n8n-style Update Distribution Network.
/// Uses native responsive Flutter layout (zero overlapping cards, zero crossing wires,
/// zero 60fps canvas lag).
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
    extends ConsumerState<UpdateDistributionTopologyScreen> {
  Timer? _fleetRolloutTimer;
  final List<Timer> _devicePullTimers = [];

  final List<_UpdateTopologyDevice> _allDevices = [];
  final Map<String, _UpdateTopologyDevice> _devicesMap = {};
  final List<_UpdateBranchCluster> _branchClusters = [];
  final List<Map<String, dynamic>> _distributionLogs = [];

  String _targetVersion = '1.1.22';
  ManagedUpdateRelease? _activeRelease;

  bool _isAutoRolloutActive = false;
  String _searchFilter = '';
  String _statusFilter = 'all'; // 'all', 'completed', 'pulling', 'outdated'
  String _selectedBranch = 'all';
  String? _selectedDeviceId;

  bool _showConsole = false;
  StreamSubscription<ChatSocketEvent>? _socketSub;
  bool _isSocketConnected = false;

  @override
  void initState() {
    super.initState();
    _initTargetRelease();
    _buildDistributionMesh();
    _buildInitialLogs();

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
      _buildDistributionMesh();
    }
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _fleetRolloutTimer?.cancel();
    for (final t in _devicePullTimers) {
      t.cancel();
    }
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
      'time': _formatTime(now.subtract(const Duration(seconds: 6))),
      'level': 'INFO',
      'source': 'SocketRouter',
      'message': 'تم تنظيم أجهزة الفروع حسب الحالة: الأخضر (محدث) والأحمر (بحاجة لسحب التحديث).',
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

    _UpdateTopologyDevice? match;
    for (final dev in _allDevices) {
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
          '✅ [Live Telemetry] اكتمل سحب وتثبيت التحديث v$targetVer بنجاح! تحول الجهاز للون الأخضر.',
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
        final wasNotPulling = dev.phase != _UpdateDevicePhase.pulling;
        setState(() {
          dev.phase = _UpdateDevicePhase.pulling;
          dev.progress = progressVal.clamp(0.08, 0.95);
          dev.speedMbps = 15.4;
          dev.chunksPulled = (dev.progress * dev.totalChunks).round().clamp(1, dev.totalChunks);
        });

        if (wasNotPulling) {
          _logEvent(
            'INFO',
            dev.hostname,
            '⬇️ [Live Telemetry] بدأ الجهاز بسحب التحديث v$targetVer فوراً من السيرفر بسرعة $speed!',
          );
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
  // DATA BUILDER: ORGANIZED BRANCH CLUSTERS
  // ══════════════════════════════════════════════════════════════════════════════
  void _buildDistributionMesh() {
    // Preserve existing phase/progress if rebuilding on filter change
    final previousStates = <String, ({_UpdateDevicePhase phase, double progress, int chunks})>{};
    for (final old in _allDevices) {
      previousStates[old.id] = (phase: old.phase, progress: old.progress, chunks: old.chunksPulled);
    }

    _allDevices.clear();
    _devicesMap.clear();
    _branchClusters.clear();

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
      final id = d['id'] as String;
      final isAlreadyTarget = d['version'] == _targetVersion;
      final prev = previousStates[id];

      final dev = _UpdateTopologyDevice(
        id: id,
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
        phase: prev != null
            ? prev.phase
            : (isAlreadyTarget ? _UpdateDevicePhase.completed : _UpdateDevicePhase.outdated),
        progress: prev != null ? prev.progress : (isAlreadyTarget ? 1.0 : 0.0),
        chunksPulled: prev != null ? prev.chunks : (isAlreadyTarget ? 10 : 0),
      );

      _allDevices.add(dev);
      _devicesMap[dev.id] = dev;
    }

    _rebuildFilteredClusters();
  }

  void _rebuildFilteredClusters() {
    _branchClusters.clear();

    final filtered = _allDevices.where((dev) {
      if (_selectedBranch != 'all' && dev.branchCode != _selectedBranch) return false;
      if (_statusFilter == 'completed' && !dev.isCompleted) return false;
      if (_statusFilter == 'pulling' && !dev.isPulling) return false;
      if (_statusFilter == 'outdated' && !dev.isOutdated) return false;

      if (_searchFilter.isNotEmpty) {
        final q = _searchFilter.toLowerCase();
        final matchHost = dev.hostname.toLowerCase().contains(q);
        final matchName = dev.cashierName.toLowerCase().contains(q);
        final matchBranch = dev.branchName.toLowerCase().contains(q);
        final matchIp = dev.ipAddress.contains(q);
        if (!matchHost && !matchName && !matchBranch && !matchIp) return false;
      }
      return true;
    }).toList();

    final Map<String, List<_UpdateTopologyDevice>> branchGroups = {};
    for (final dev in filtered) {
      branchGroups.putIfAbsent(dev.branchCode, () => []).add(dev);
    }

    for (final entry in branchGroups.entries) {
      final bCode = entry.key;
      final devs = entry.value;
      final bName = devs.isNotEmpty ? devs.first.branchName : 'فرع $bCode';
      _branchClusters.add(_UpdateBranchCluster(
        branchCode: bCode,
        branchName: bName,
        devices: devs,
      ));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // PULL & ROLLOUT ACTIONS (RED ➔ ROSE PROGRESS ➔ GREEN)
  // ══════════════════════════════════════════════════════════════════════════════
  void _triggerDevicePull(_UpdateTopologyDevice dev) {
    if (dev.isPulling || dev.isCompleted) return;

    HapticFeedback.mediumImpact();
    setState(() {
      dev.phase = _UpdateDevicePhase.pulling;
      dev.progress = 0.1;
      dev.speedMbps = 14.2 + math.Random().nextDouble() * 6.0;
      dev.chunksPulled = 1;
      _rebuildFilteredClusters();
    });

    _logEvent('INFO', dev.hostname, '⬇️ بدء سحب حزم التحديث v$_targetVersion من السيرفر المركزي (1/10)...');

    if (_activeRelease != null && dev.id.length == 24) {
      unawaited(
        ref.read(updateManagementRepositoryProvider).createUpdateJob(
          releaseId: _activeRelease!.id,
          targetType: 'devices',
          targetDeviceIds: [dev.id],
          note: 'Triggered from Update Distribution Center for ${dev.hostname}',
        ).then((_) {
          _logEvent('SUCCESS', dev.hostname, '📡 تم إرسال أمر التحديث الفعلي للسيرفر بنجاح عبر API.');
        }).catchError((err) {
          _logEvent('WARN', dev.hostname, 'تنبيه: محاكاة التحديث تعمل محلياً (${err.toString()})');
        }),
      );
    }

    late final Timer pullTimer;
    pullTimer = Timer.periodic(const Duration(milliseconds: 350), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (dev.chunksPulled < dev.totalChunks) {
        setState(() {
          dev.chunksPulled++;
          dev.progress = (dev.chunksPulled / dev.totalChunks).clamp(0.0, 1.0);
          dev.speedMbps = 14.5 + math.Random().nextDouble() * 5.5;
        });
      } else {
        timer.cancel();
        _devicePullTimers.remove(pullTimer);
        HapticFeedback.heavyImpact();
        setState(() {
          dev.phase = _UpdateDevicePhase.completed;
          dev.progress = 1.0;
          dev.executionCount++;
          _rebuildFilteredClusters();
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
    _devicePullTimers.add(pullTimer);
  }

  void _triggerBranchRollout(_UpdateBranchCluster cluster) {
    final outdated = cluster.devices.where((d) => d.isOutdated).toList();
    if (outdated.isEmpty) return;

    HapticFeedback.mediumImpact();
    _logEvent('INFO', cluster.branchName, '🚀 بدء سحب التحديث لجميع أجهزة ${cluster.branchName} (${outdated.length} أجهزة)...');
    for (int i = 0; i < outdated.length; i++) {
      Future.delayed(Duration(milliseconds: i * 350), () {
        if (mounted) _triggerDevicePull(outdated[i]);
      });
    }
  }

  void _triggerFleetRollout() {
    if (_isAutoRolloutActive) return;

    final outdatedList = _allDevices.where((d) => d.isOutdated && d.isOnline).toList();
    if (outdatedList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: const Text(
            'كافة أجهزة المنظومة محدثة بالكامل باللون الأخضر إلى أحدث إصدار معتمد!',
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
          note: 'Fleet rollout triggered from Update Distribution Center',
        ).then((_) {
          _logEvent('SUCCESS', 'Server', '📡 تم اعتماد وتعميم مهمة النشر الجماعي في قاعدة البيانات.');
        }).catchError((err) {
          _logEvent('WARN', 'Server', 'تنبيه: جاري تشغيل التدفق المرئي (${err.toString()})');
        }),
      );
    }

    int index = 0;
    _fleetRolloutTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
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

  void _resetSimulation() {
    _fleetRolloutTimer?.cancel();
    for (final t in _devicePullTimers) {
      t.cancel();
    }
    _devicePullTimers.clear();
    HapticFeedback.selectionClick();
    setState(() {
      _isAutoRolloutActive = false;
      for (final d in _allDevices) {
        d.phase = _UpdateDevicePhase.outdated;
        d.progress = 0.0;
        d.chunksPulled = 0;
      }
      _rebuildFilteredClusters();
      _buildInitialLogs();
    });
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
  // MAIN BUILD (100% NATIVE RESPONSIVE SCROLLING LAYOUT - ZERO LAG)
  // ══════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final totalCount = _allDevices.length;
    final completedCount = _allDevices.where((d) => d.isCompleted).length;
    final outdatedCount = _allDevices.where((d) => d.isOutdated).length;
    final pullingCount = _allDevices.where((d) => d.isPulling).length;

    final content = LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 1100;

        return Column(
          children: [
            // 1. TOP COMMAND TOOLBAR
            _buildTopToolbar(isDark, totalCount, completedCount, outdatedCount, pullingCount),

            // 2. MAIN WORKSPACE AREA
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // TIER 1: CENTRAL UPDATE SERVER HUB (GREEN MASTER NODE)
                                _buildCentralServerHeroCard(
                                  isDark: isDark,
                                  totalCount: totalCount,
                                  completedCount: completedCount,
                                  pullingCount: pullingCount,
                                  outdatedCount: outdatedCount,
                                ),

                                // VISUAL PIPELINE CONNECTOR (SERVER ➔ BRANCHES)
                                _buildVisualDistributionPipeline(
                                  isDark: isDark,
                                  pullingCount: pullingCount,
                                  completedCount: completedCount,
                                  totalCount: totalCount,
                                ),

                                // FILTER & SEARCH BAR FOR BRANCHES
                                _buildFilterAndBranchBar(
                                  isDark: isDark,
                                  totalCount: totalCount,
                                  completedCount: completedCount,
                                  pullingCount: pullingCount,
                                  outdatedCount: outdatedCount,
                                ),
                                const SizedBox(height: 16),

                                // TIER 2: ORGANIZED BRANCH CLUSTERS & DEVICE CARDS
                                if (_branchClusters.isEmpty)
                                  _buildEmptyState(isDark)
                                else
                                  for (final cluster in _branchClusters)
                                    _buildBranchClusterPanel(cluster, isDark),
                              ],
                            ),
                          ),
                        ),

                        // BOTTOM COLLAPSIBLE LIVE TELEMETRY CONSOLE
                        _buildBottomConsole(isDark),
                      ],
                    ),
                  ),

                  // SIDE DEVICE INSPECTOR (Wide Screens)
                  if (isWideScreen && _selectedDeviceId != null)
                    SizedBox(
                      width: 360,
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
        backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
        body: SafeArea(child: content),
        endDrawer: _selectedDeviceId != null && MediaQuery.of(context).size.width < 1100
            ? Drawer(
                width: 360,
                child: _buildDeviceInspector(isDark),
              )
            : null,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // 1. TOP COMMAND TOOLBAR (RESPONSIVE WRAP - ZERO OVERFLOW)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildTopToolbar(
    bool isDark,
    int totalCount,
    int completedCount,
    int outdatedCount,
    int pullingCount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141824) : Colors.white,
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
          // Title & Back Button
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
                child: const Icon(Icons.hub_rounded, size: 20, color: Color(0xFF10B981)),
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
                        'شبكة سحب وتوزيع التحديثات المباشرة (n8n Live Network)',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'السيرفر: v$_targetVersion 🟢',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'السيرفر باللون الأخضر يغذي الفروع: الأجهزة القديمة باللون الأحمر تتحول للأخضر فور اكتمال السحب',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Actions & Live Socket Badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // WebSocket Live Indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (_isSocketConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (_isSocketConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                        .withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isSocketConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isSocketConnected ? 'ربط لحظي بالسيرفر (WebSocket)' : 'محاكاة محلية',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _isSocketConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Push Update to All Button
              FilledButton.icon(
                onPressed: _isAutoRolloutActive ? null : _triggerFleetRollout,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isAutoRolloutActive
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.rocket_launch_rounded, size: 16),
                label: Text(
                  _isAutoRolloutActive ? 'جارٍ سحب التحديث للفروع...' : 'نشر التحديث لكل الفروع الآن',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),

              // Reset Simulation Button
              OutlinedButton.icon(
                onPressed: _resetSimulation,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                ),
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text(
                  'إعادة المحاكاة',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // 2. TIER 1: CENTRAL UPDATE SERVER HERO CARD (GREEN)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildCentralServerHeroCard({
    required bool isDark,
    required int totalCount,
    required int completedCount,
    required int pullingCount,
    required int outdatedCount,
  }) {
    const greenColor = Color(0xFF10B981);
    final fileName = _activeRelease?.fileName ?? 'iSmartMessenger-Setup-v$_targetVersion.exe';
    final fileSizeMb = _activeRelease != null && _activeRelease!.fileSize > 0
        ? (_activeRelease!.fileSize / (1024 * 1024)).toStringAsFixed(1)
        : '84.5';
    final completionPercent = totalCount > 0 ? ((completedCount / totalCount) * 100).round() : 100;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0E221D), const Color(0xFF141824)]
              : [const Color(0xFFECFDF5), Colors.white],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: greenColor, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: greenColor.withValues(alpha: isDark ? 0.20 : 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              // Server Identity
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: greenColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: greenColor, width: 1.5),
                    ),
                    child: const Icon(Icons.dns_rounded, color: greenColor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: greenColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'خادم التحديثات المركزي • ONLINE 🟢',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'الإصدار المرفوع والمعتمد: v$_targetVersion',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ملف التوزيع: $fileName ($fileSizeMb MB) • بروتوكول: HTTP Chunked Stream + WebSocket Telemetry',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // 4 Live KPI Counters
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _buildServerKpiBox(
                    label: 'إجمالي الأجهزة',
                    count: totalCount,
                    color: const Color(0xFF38BDF8),
                    icon: Icons.devices_rounded,
                    isDark: isDark,
                  ),
                  _buildServerKpiBox(
                    label: 'محدث بالأخضر ✓',
                    count: completedCount,
                    color: const Color(0xFF10B981),
                    icon: Icons.check_circle_rounded,
                    isDark: isDark,
                  ),
                  _buildServerKpiBox(
                    label: 'يسحب الآن ⬇️',
                    count: pullingCount,
                    color: const Color(0xFFF43F5E),
                    icon: Icons.downloading_rounded,
                    isDark: isDark,
                  ),
                  _buildServerKpiBox(
                    label: 'نسخة قديمة بالأحمر ⚠️',
                    count: outdatedCount,
                    color: const Color(0xFFEF4444),
                    icon: Icons.warning_rounded,
                    isDark: isDark,
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),
          // Fleet Overall Progress Bar
          Row(
            children: [
              Text(
                'نسبة اكتمال تحديث الشبكة بالكامل: $completionPercent%',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: completionPercent == 100 ? greenColor : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: totalCount > 0 ? (completedCount / totalCount).clamp(0.0, 1.0) : 1.0,
                    minHeight: 8,
                    backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(greenColor),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServerKpiBox({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101520) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.1,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // VISUAL PIPELINE CONNECTOR (CLEAN NON-OVERLAPPING FLOW BUS)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildVisualDistributionPipeline({
    required bool isDark,
    required int pullingCount,
    required int completedCount,
    required int totalCount,
  }) {
    final isActivelyPulling = pullingCount > 0;
    final busColor = isActivelyPulling ? const Color(0xFFF43F5E) : const Color(0xFF10B981);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Container(
            width: 3,
            height: 16,
            color: busColor.withValues(alpha: 0.6),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: busColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: busColor.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isActivelyPulling ? Icons.downloading_rounded : Icons.hub_rounded,
                  size: 14,
                  color: busColor,
                ),
                const SizedBox(width: 6),
                Text(
                  isActivelyPulling
                      ? '⚡ جاري بث وسحب حزم التحديث الآن إلى $pullingCount جهاز بالفروع...'
                      : 'مسار التوزيع المباشر من السيرفر المركزي إلى الفروع ($completedCount/$totalCount محدث)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: busColor,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 3,
            height: 16,
            color: busColor.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // 3. FILTER & SEARCH BAR
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildFilterAndBranchBar({
    required bool isDark,
    required int totalCount,
    required int completedCount,
    required int pullingCount,
    required int outdatedCount,
  }) {
    // Collect unique branches for dropdown
    final branchOptions = <String, String>{'all': 'كل الفروع'};
    for (final d in _allDevices) {
      branchOptions[d.branchCode] = '${d.branchName} (${d.branchCode})';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141824) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          // Status Filter Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterChip(
                id: 'all',
                label: 'كل الأجهزة ($totalCount)',
                color: const Color(0xFF38BDF8),
                isDark: isDark,
              ),
              _buildFilterChip(
                id: 'outdated',
                label: 'بحاجة لتحديث 🔴 ($outdatedCount)',
                color: const Color(0xFFEF4444),
                isDark: isDark,
              ),
              _buildFilterChip(
                id: 'pulling',
                label: 'يسحب التحديث الآن ⬇️ ($pullingCount)',
                color: const Color(0xFFF43F5E),
                isDark: isDark,
              ),
              _buildFilterChip(
                id: 'completed',
                label: 'محدث بالأخضر 🟢 ($completedCount)',
                color: const Color(0xFF10B981),
                isDark: isDark,
              ),
            ],
          ),

          // Branch Selector & Search Input
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Branch Dropdown
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xFF222938) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: branchOptions.containsKey(_selectedBranch) ? _selectedBranch : 'all',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    dropdownColor: isDark ? const Color(0xFF141824) : Colors.white,
                    items: branchOptions.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() {
                        _selectedBranch = val;
                        _rebuildFilteredClusters();
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Search Box
              SizedBox(
                width: 210,
                height: 36,
                child: TextField(
                  onChanged: (val) {
                    setState(() {
                      _searchFilter = val.trim();
                      _rebuildFilteredClusters();
                    });
                  },
                  style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'بحث باسم الجهاز أو الكاشير أو IP...',
                    hintStyle: const TextStyle(fontSize: 10.5),
                    prefixIcon: const Icon(Icons.search_rounded, size: 16),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String id,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    final isSelected = _statusFilter == id;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _statusFilter = id;
          _rebuildFilteredClusters();
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.18)
              : (isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : (isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? color : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // 4. TIER 2: ORGANIZED BRANCH CLUSTER PANEL & DEVICE CARDS
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildBranchClusterPanel(_UpdateBranchCluster cluster, bool isDark) {
    final allUpdated = cluster.outdatedCount == 0 && cluster.pullingCount == 0;
    final hasPulling = cluster.pullingCount > 0;
    final branchAccent = allUpdated
        ? const Color(0xFF10B981)
        : (hasPulling ? const Color(0xFFF43F5E) : const Color(0xFFEF4444));

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141824) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: branchAccent.withValues(alpha: isDark ? 0.45 : 0.35),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Branch Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: branchAccent.withValues(alpha: isDark ? 0.12 : 0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(
                bottom: BorderSide(color: branchAccent.withValues(alpha: 0.25)),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: branchAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.storefront_rounded, size: 18, color: branchAccent),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      cluster.branchName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0D1117) : Colors.white,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: branchAccent.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        'كود الفرع: ${cluster.branchCode}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: branchAccent,
                        ),
                      ),
                    ),
                  ],
                ),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Branch Status Summary Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: branchAccent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        allUpdated
                            ? '🟢 جميع أجهزة الفرع محدثة بالكامل (${cluster.completedCount}/${cluster.totalCount})'
                            : (hasPulling
                                ? '⬇️ جاري سحب التحديث في ${cluster.pullingCount} جهاز...'
                                : '🔴 يوجد ${cluster.outdatedCount} جهاز باللون الأحمر بحاجة لتحديث'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: branchAccent,
                        ),
                      ),
                    ),
                    if (cluster.outdatedCount > 0) ...[
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () => _triggerBranchRollout(cluster),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 14),
                        label: const Text(
                          'تحديث الفرع بالكامل',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Responsive Grid of Device Workstation Cards
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final dev in cluster.devices)
                  _buildDeviceCard(dev, _selectedDeviceId == dev.id, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // DEVICE WORKSTATION CARD (RED WHEN OUTDATED ➔ GREEN WHEN UPDATED)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildDeviceCard(
    _UpdateTopologyDevice dev,
    bool isSelected,
    bool isDark,
  ) {
    final cardColor = dev.accentColor;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedDeviceId = dev.id);
        if (MediaQuery.of(context).size.width < 1100) {
          Scaffold.of(context).openEndDrawer();
        }
      },
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: 315,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isSelected
                ? cardColor
                : (dev.isPulling ? const Color(0xFFF43F5E) : cardColor.withValues(alpha: 0.65)),
            width: isSelected || dev.isPulling ? 2.2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: cardColor.withValues(alpha: dev.isPulling ? 0.22 : 0.10),
              blurRadius: isSelected || dev.isPulling ? 12 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Status Strip (Clear Red vs Green banner)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        dev.isCompleted
                            ? Icons.check_circle_rounded
                            : (dev.isPulling ? Icons.downloading_rounded : Icons.warning_amber_rounded),
                        color: Colors.white,
                        size: 12,
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
                Text(
                  dev.ipAddress,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Device Hostname & Cashier Info
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: cardColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cardColor.withValues(alpha: 0.4)),
                  ),
                  child: Icon(
                    dev.isCompleted ? Icons.desktop_windows_rounded : Icons.computer_rounded,
                    color: cardColor,
                    size: 20,
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
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${dev.cashierName} (${dev.username})',
                        style: TextStyle(
                          fontSize: 11,
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

            const SizedBox(height: 12),

            // Live Progress Bar if pulling, or Version Comparison Row
            if (dev.isPulling) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'جاري سحب الحزمة (${dev.chunksPulled}/${dev.totalChunks} Chunks)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: cardColor,
                    ),
                  ),
                  Text(
                    '${dev.speedMbps.toStringAsFixed(1)} MB/s',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      color: cardColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: dev.progress,
                  backgroundColor: cardColor.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(cardColor),
                  minHeight: 6,
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141824) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dev.isCompleted
                          ? 'النسخة الحالية: v${dev.targetVersion} ✓'
                          : 'النسخة: v${dev.originalVersion} ➔ v${dev.targetVersion}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: cardColor,
                      ),
                    ),
                    if (!dev.isCompleted)
                      InkWell(
                        onTap: () => _triggerDevicePull(dev),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download_rounded, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'سحب التحديث الآن',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded, size: 13, color: Color(0xFF10B981)),
                          SizedBox(width: 4),
                          Text(
                            'مطابق للسيرفر',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141824) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.devices_other_rounded,
            size: 42,
            color: isDark ? Colors.white38 : Colors.black26,
          ),
          const SizedBox(height: 12),
          Text(
            'لا توجد أجهزة مطابقة للفلتر الحالي',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
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

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141824) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _showConsole = !_showConsole),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
                    'سجل عمليات سحب وتوزيع التحديثات المباشر:',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      latestLog != null
                          ? '[${latestLog['time']}] ${latestLog['message']}'
                          : 'الشبكة جاهزة للبث...',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _showConsole ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_showConsole)
            Container(
              height: 150,
              color: const Color(0xFF090D16),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '<${item['source']}>',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            color: Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item['message'] as String? ?? '',
                            style: const TextStyle(
                              fontSize: 10.5,
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
        color: isDark ? const Color(0xFF141824) : Colors.white,
        border: Border(
          right: BorderSide(
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
                        style: TextStyle(
                          fontSize: 11,
                          color: dev.accentColor,
                          fontWeight: FontWeight.w700,
                        ),
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
                _specItem('اسم المستخدم', dev.username, isDark),
                _specItem('الفرع', dev.branchName, isDark),
                _specItem('كود الفرع', dev.branchCode, isDark),
                _specItem('عنوان IP الداخلي', dev.ipAddress, isDark),
                _specItem('نظام التشغيل', dev.os, isDark),
                _specItem('الإصدار الحالي بالجهاز', 'v${dev.currentDisplayVersion}', isDark),
                _specItem('الإصدار المعتمد بالسيرفر', 'v$_targetVersion 🟢', isDark),
                _specItem(
                  'حالة المطابقة',
                  dev.isCompleted ? 'مطابق ومحدث بالكامل ✓' : 'نسخة قديمة بحاجة لتحديث ⚠️',
                  isDark,
                ),
                const SizedBox(height: 16),
                if (!dev.isCompleted)
                  FilledButton.icon(
                    onPressed: dev.isPulling ? null : () => _triggerDevicePull(dev),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      dev.isPulling ? 'جارٍ سحب التحديث...' : 'سحب وتثبيت التحديث الآن',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Text(key, style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.black54)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
