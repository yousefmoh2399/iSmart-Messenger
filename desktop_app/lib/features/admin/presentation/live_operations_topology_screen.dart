import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/providers.dart';
import '../../chat/data/chat_socket_service.dart';
import 'system_monitor_controller.dart';

/// Representation of an active branch device currently performing a live action on the n8n canvas.
/// Animates through 3 stages:
///   Stage 1 (0..750ms):    Device ➔ Central Server (Gateway)
///   Stage 2 (750..1500ms): Central Server ➔ Target Service Engine
///   Stage 3 (1500..2250ms): Target Service Engine ➔ Central Server ➔ Device (Response)
///   Stage 4 (>= 2250ms):   Completed (turns green, counts down 5s, and disappears)
class _ActiveCanvasDevice {
  _ActiveCanvasDevice({
    required this.id,
    required this.deviceId,
    required this.username,
    required this.hostname,
    required this.cashierName,
    required this.branchName,
    required this.branchCode,
    required this.ipAddress,
    required this.actionLabel,
    required this.targetEngineId,
    required this.targetEngineName,
    required this.slotIndex,
    required this.position,
    required this.color,
    required this.icon,
    required this.requestStartedAt,
    this.deviceUid = '',
    this.clientType = 'desktop',
    this.method = 'GET',
    this.endpoint = '',
    this.latencyMs = 12,
    this.statusCode = 200,
  });

  final String id;
  final String deviceId;
  String deviceUid;
  String clientType;
  final String username;
  String hostname;
  String cashierName;
  String branchName;
  String branchCode;
  String ipAddress;
  String actionLabel;
  String targetEngineId;
  String targetEngineName;
  final int slotIndex;
  Offset position;
  Color color;
  IconData icon;
  DateTime requestStartedAt;
  String method;
  String endpoint;

  int latencyMs;
  int statusCode;
  int requestCount = 1;
  bool isCompleted = false;
  int remainingSeconds = 25;

  static const int stage1DurationMs = 750;
  static const int stage2DurationMs = 750;
  static const int stage3DurationMs = 750;
  static const int totalRoutingMs =
      stage1DurationMs + stage2DurationMs + stage3DurationMs; // 2250ms

  int get elapsedMs =>
      DateTime.now().difference(requestStartedAt).inMilliseconds;

  /// 1 = Device ➔ Server
  /// 2 = Server ➔ Service Engine
  /// 3 = Service Engine ➔ Server ➔ Device (Response)
  /// 4 = Completed (5s countdown)
  int get routingStage {
    final ms = elapsedMs;
    if (ms < stage1DurationMs) return 1;
    if (ms < stage1DurationMs + stage2DurationMs) return 2;
    if (ms < totalRoutingMs) return 3;
    return 4;
  }

  double get stageProgress {
    final ms = elapsedMs;
    if (ms < stage1DurationMs) {
      return (ms / stage1DurationMs).clamp(0.0, 1.0);
    }
    if (ms < stage1DurationMs + stage2DurationMs) {
      return ((ms - stage1DurationMs) / stage2DurationMs).clamp(0.0, 1.0);
    }
    if (ms < totalRoutingMs) {
      return ((ms - stage1DurationMs - stage2DurationMs) / stage3DurationMs)
          .clamp(0.0, 1.0);
    }
    return 1.0;
  }
}

/// Device model extracted from real database branches and active sessions.
class _FleetDeviceModel {
  _FleetDeviceModel({
    required this.id,
    required this.hostname,
    required this.fullName,
    required this.username,
    required this.branchName,
    required this.branchCode,
    required this.ipAddress,
    required this.appVersion,
    required this.isOutdated,
    required this.isOnline,
    required this.clientType,
    required this.os,
    this.deviceUid = '',
    this.lastSeenAt,
  });

  final String id;
  final String deviceUid;
  final String hostname;
  final String fullName;
  final String username;
  final String branchName;
  final String branchCode;
  final String ipAddress;
  final String appVersion;
  final bool isOutdated;
  final bool isOnline;
  final String clientType;
  final String os;
  final DateTime? lastSeenAt;
}

/// Fixed n8n Core Service Block (Gateway, Chat Engine, Docs, Printer, Release Hub, DB).
class _CoreServiceNode {
  _CoreServiceNode({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.category,
    required this.description,
    required this.color,
    required this.icon,
    required this.position,
    required this.size,
    required this.metrics,
    required this.details,
    required this.inputPayload,
    required this.outputPayload,
    this.executionCount = 0,
  });

  final String id;
  final String name;
  final String subtitle;
  final String category;
  final String description;
  final Color color;
  final IconData icon;
  Offset position;
  final Size size;
  final Map<String, String> metrics;
  final Map<String, dynamic> details;
  final Map<String, dynamic> inputPayload;
  final Map<String, dynamic> outputPayload;
  int executionCount;
}

/// Authentic n8n Live Operations Topology Screen.
/// Core Server is in the middle, services are on the right.
/// Branch devices appear dynamically on the left when they send an action,
/// route their request: Device ➔ Server ➔ Service Engine ➔ Server ➔ Device,
/// and disappear 5 seconds after completion.
class LiveOperationsTopologyScreen extends ConsumerStatefulWidget {
  const LiveOperationsTopologyScreen({
    super.key,
    required this.state,
    required this.notifier,
    required this.isDark,
    required this.cs,
  });

  final SystemMonitorState state;
  final SystemMonitorController notifier;
  final bool isDark;
  final ColorScheme cs;

  @override
  ConsumerState<LiveOperationsTopologyScreen> createState() =>
      _LiveOperationsTopologyScreenState();
}

class _LiveOperationsTopologyScreenState
    extends ConsumerState<LiveOperationsTopologyScreen>
    with SingleTickerProviderStateMixin {
  int _activeTab = 0; // 0 = n8n Live Flow, 1 = Fleet Directory, 2 = Event Log

  late final AnimationController _wireFlowController;
  final TransformationController _interactiveController =
      TransformationController();
  StreamSubscription<ChatSocketEvent>? _socketSub;
  Timer? _countdownTicker;

  String? _selectedNodeId;

  // Active dynamically appearing devices on the n8n canvas (unlimited non-overlapping slots)
  final List<_ActiveCanvasDevice> _activeDevices = [];

  // Fixed Core Nodes (Gateway in center, 5 Service Engines on right)
  final List<_CoreServiceNode> _coreNodes = [];
  final Map<String, _CoreServiceNode> _coreNodesMap = {};

  // Complete directory of physical branch devices (100% real data)
  final List<_FleetDeviceModel> _allFleetDevices = [];
  final List<Map<String, dynamic>> _liveLogs = [];

  // Filter state for Fleet Directory tab
  String _deviceFilter = 'all'; // 'all', 'online', 'outdated', 'offline'
  String _selectedBranchCode = 'all';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  double _lastCanvasWidth = 1220.0;
  double _lastCanvasHeight = 740.0;
  bool _isSocketConnected = false;

  // Card layout constants (sized generously so text NEVER overflows outside cards)
  static const Size _gatewayCardSize = Size(290, 126);
  static const Size _engineCardSize = Size(265, 108);
  static const Size _deviceCardSize = Size(275, 114);
  static const int _rowsPerDeviceColumn = 5;
  static const double _deviceRowGap = 18.0;
  static const double _deviceColGap = 38.0;
  static const double _wireCorridorGap = 115.0;

  @override
  void initState() {
    super.initState();

    _wireFlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addListener(_onAnimationFrame)
     ..repeat();

    _initCoreNodesAndFleet();
    _buildInitialLogs();

    // 1-Second Ticker for active devices 5-second countdown & fadeout after completion
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _tickDeviceCountdowns();
    });

    // Start listening to real WebSocket telemetry from backend
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _listenToLiveSocket();
      }
    });
  }

  void _onAnimationFrame() {
    if (!mounted || _activeDevices.isEmpty) return;
    bool stateChanged = false;
    for (final dev in _activeDevices) {
      if (!dev.isCompleted && dev.routingStage >= 4) {
        dev.isCompleted = true;
        dev.remainingSeconds = 25;
        stateChanged = true;
      }
    }
    if (stateChanged) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant LiveOperationsTopologyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.deploymentData != widget.state.deploymentData ||
        oldWidget.state.sessions != widget.state.sessions ||
        oldWidget.state.stats != widget.state.stats) {
      _initCoreNodesAndFleet();
    }
  }

  @override
  void dispose() {
    _wireFlowController.removeListener(_onAnimationFrame);
    _wireFlowController.dispose();
    _interactiveController.dispose();
    _socketSub?.cancel();
    _countdownTicker?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // CORE NODES & REAL FLEET DATA INITIALIZATION
  // ══════════════════════════════════════════════════════════════════════════════
  void _initCoreNodesAndFleet() {
    final stats = widget.state.stats;
    final telemetry = widget.state.requestTelemetry;
    final summary = widget.state.deploymentData?.summary;
    final targetVer =
        summary?.targetAppVersion ?? summary?.currentAppVersion ?? '1.1.22';

    final rps = telemetry?.rps ?? 0.0;
    final latency = telemetry?.avgLatencyMs ?? (stats != null ? 14 : 0);
    final activeReqs = telemetry?.activeRequests ?? 0;
    final dbStatus = stats?.databaseStatus ?? 'connected';
    final dbHost = stats?.databaseHost ?? 'cluster0.ismart';
    final dbName = stats?.databaseName ?? 'ismart-prod';
    final cpuCores = stats?.cpuCores ?? 8;
    final memUsedGb = stats != null
        ? (stats.usedMemoryBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)
        : '2.4';
    final memTotalGb = stats != null
        ? (stats.totalMemoryBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)
        : '16.0';
    final uptimeHours =
        stats != null ? (stats.uptimeSeconds / 3600).toStringAsFixed(1) : '24.0';

    // Preserve execution counts
    final prevCounts = <String, int>{};
    for (final node in _coreNodes) {
      prevCounts[node.id] = node.executionCount;
    }

    _coreNodes.clear();
    _coreNodesMap.clear();

    // 1. Gateway Node in Center
    final gatewayNode = _CoreServiceNode(
      id: 'node_gateway',
      name: 'خادم المنظومة وبوابة الاتصال',
      subtitle: 'Express Gateway & Socket.IO Router',
      category: 'GATEWAY / ROUTER',
      description:
          'استقبال وفحص طلبات الشبكة من الفروع، وتوزيعها على المحركات المختصة ثم إعادة الرد للأجهزة.',
      color: const Color(0xFF06B6D4), // Cyan
      icon: Icons.router_rounded,
      position: const Offset(430, 280),
      size: _gatewayCardSize,
      executionCount: prevCounts['node_gateway'] ?? 0,
      metrics: {
        'معدل الطلبات': '$rps req/s',
        'زمن الاستجابة': '$latency ms',
        'العمليات الجارية': '$activeReqs طلب نشط',
        'حالة الاتصال': 'متصل 🟢 100%',
      },
      details: {
        'Gateway Host': stats?.hostname ?? 'iSmart-Gateway-01',
        'Node Version': stats?.nodeVersion ?? 'v22.x',
        'Sockets Cluster': 'Active',
      },
      inputPayload: {'auth': 'Bearer token', 'route': '/api/v1/dispatch'},
      outputPayload: {'authorized': true, 'dispatched': true},
    );

    // 2. Core Engines on the Right Column
    final chatEngineNode = _CoreServiceNode(
      id: 'node_chat_engine',
      name: 'محرك المحادثات والرسائل',
      subtitle: 'Real-time Messaging & Event Bus',
      category: 'CHAT ENGINE',
      description:
          'معالجة الرسائل والملفات، توزيع الإشعارات اللحظية، وتحديث مؤشرات القراءة.',
      color: const Color(0xFF6366F1), // Indigo
      icon: Icons.chat_bubble_outline_rounded,
      position: const Offset(835, 40),
      size: _engineCardSize,
      executionCount: prevCounts['node_chat_engine'] ?? 0,
      metrics: {
        'بيئة التشغيل': 'Node.js ${stats?.nodeVersion ?? "v22"}',
        'استهلاك الرام': '$memUsedGb / $memTotalGb GB',
        'وقت التشغيل': '$uptimeHours ساعة',
      },
      details: {
        'Engine': 'iSmart Chat Orchestrator',
        'CPU Cores': '$cpuCores Cores',
      },
      inputPayload: {'type': 'chat_message', 'channel': 'pos_cashiers'},
      outputPayload: {'status': 'broadcast_delivered', 'timeMs': 8},
    );

    final docEngineNode = _CoreServiceNode(
      id: 'node_doc_engine',
      name: 'محرك المستندات والطلبات',
      subtitle: 'Documents & Orders Pipeline',
      category: 'DOCS ENGINE',
      description:
          'معالجة تحويلات الفروع، فواتير الشراء، وأوامر الصرف مع تدقيق الصلاحيات.',
      color: const Color(0xFF8B5CF6), // Purple
      icon: Icons.inventory_2_outlined,
      position: const Offset(835, 164),
      size: _engineCardSize,
      executionCount: prevCounts['node_doc_engine'] ?? 0,
      metrics: {
        'حالة النظام': 'مستقر 100%',
        'التزامن': 'فوري Realtime',
        'الأخطاء': '${stats?.unresolvedErrors ?? 0}',
      },
      details: {'Worker': 'Document Workflow Processor', 'Queue': 'Empty'},
      inputPayload: {'docType': 'order_transfer', 'branchCode': '110'},
      outputPayload: {'status': 'processed', 'timeMs': 12},
    );

    final printerEngineNode = _CoreServiceNode(
      id: 'node_printer_engine',
      name: 'سيرفر الطباعة والفواتير',
      subtitle: 'Print Spooler & ESC/POS',
      category: 'PRINT SPOOLER',
      description:
          'إدارة طابعات الباركود والإيصالات بالفروع وجدولة أوامر الطباعة.',
      color: const Color(0xFFEC4899), // Pink
      icon: Icons.print_rounded,
      position: const Offset(835, 288),
      size: _engineCardSize,
      executionCount: prevCounts['node_printer_engine'] ?? 0,
      metrics: {
        'بروتوكول الطباعة': 'ESC/POS Network',
        'حالة الطابعات': 'جاهزة للطباعة',
        'زمن الإرسال': '4ms',
      },
      details: {'Driver': 'Thermal POS Spooler', 'Status': 'Ready'},
      inputPayload: {'printJob': 'receipt_80mm', 'copies': 1},
      outputPayload: {'printed': true, 'timeMs': 4},
    );

    final releaseEngineNode = _CoreServiceNode(
      id: 'node_release_engine',
      name: 'سيرفر التحديثات ونشر الحزم',
      subtitle: 'Auto-Update & Version Cache',
      category: 'UPDATE HUB',
      description:
          'مقارنة إصدارات الأجهزة بالنسخة المعتمدة v$targetVer وتوفير التحديث التلقائي.',
      color: const Color(0xFFF59E0B), // Amber
      icon: Icons.system_update_alt_rounded,
      position: const Offset(835, 412),
      size: _engineCardSize,
      executionCount: prevCounts['node_release_engine'] ?? 0,
      metrics: {
        'الإصدار المعتمد': 'v$targetVer 🟢',
        'حزم التحديث': 'Windows x64 / Android',
        'نظام النشر': 'HTTP Chunked Stream',
      },
      details: {'Release': 'v$targetVer', 'Protocol': 'HTTP Stream'},
      inputPayload: {'checkVersion': 'v$targetVer'},
      outputPayload: {'status': 'up_to_date'},
    );

    final databaseNode = _CoreServiceNode(
      id: 'node_database',
      name: 'عنقود قاعدة بيانات MongoDB',
      subtitle: 'Primary Cluster ReplicaSet',
      category: 'MONGODB',
      description:
          'الحفظ الدائم لسجلات المحادثات، بيانات الفروع، الجلسات، والمستخدمين.',
      color: const Color(0xFF10B981), // Emerald
      icon: Icons.storage_rounded,
      position: const Offset(835, 536),
      size: _engineCardSize,
      executionCount: prevCounts['node_database'] ?? 0,
      metrics: {
        'الحالة': dbStatus == 'connected' ? 'متصل ومستقر 🟢' : dbStatus,
        'اسم القاعدة': dbName,
        'المضيف': dbHost,
      },
      details: {'Engine': 'MongoDB ReplicaSet', 'Host': dbHost},
      inputPayload: {'op': 'write_audit_log'},
      outputPayload: {'acknowledged': true, 'timeMs': 3.4},
    );

    _coreNodes.addAll([
      gatewayNode,
      chatEngineNode,
      docEngineNode,
      printerEngineNode,
      releaseEngineNode,
      databaseNode,
    ]);

    for (final node in _coreNodes) {
      _coreNodesMap[node.id] = node;
    }

    // 3. Extract all physical devices strictly from REAL data (branches & sessions)
    _allFleetDevices.clear();
    final allBranches = widget.state.deploymentData?.branches ?? [];
    final allSessions = widget.state.sessions;

    for (final branch in allBranches) {
      if (branch.devices.isNotEmpty) {
        for (final d in branch.devices) {
          _allFleetDevices.add(_FleetDeviceModel(
            id: 'dev_${branch.branchCode}_${d.hostname.replaceAll(RegExp(r"[^a-zA-Z0-9_]"), "_")}',
            hostname: d.hostname.trim().isNotEmpty
                ? d.hostname.trim()
                : 'كاشير-${branch.branchCode}',
            fullName: d.fullName.trim().isNotEmpty
                ? d.fullName.trim()
                : (d.username.trim().isNotEmpty
                    ? d.username.trim()
                    : 'كاشير الفرع'),
            username: d.username,
            branchName: branch.branchName,
            branchCode: branch.branchCode,
            ipAddress: d.ipAddress.isNotEmpty ? d.ipAddress : '-',
            appVersion: d.appVersion.isNotEmpty ? d.appVersion : targetVer,
            isOutdated: d.isOutdated,
            isOnline: d.isOnline,
            clientType: d.clientType,
            os: d.os.isNotEmpty ? d.os : 'Windows 11',
            lastSeenAt: d.lastSeenAt,
          ));
        }
      } else if (branch.installedUsers.isNotEmpty) {
        for (final u in branch.installedUsers) {
          _allFleetDevices.add(_FleetDeviceModel(
            id: 'dev_user_${branch.branchCode}_${u.username}',
            hostname: 'محطة ${u.fullName}',
            fullName: u.fullName,
            username: u.username,
            branchName: branch.branchName,
            branchCode: branch.branchCode,
            ipAddress: '-',
            appVersion: targetVer,
            isOutdated: false,
            isOnline: u.isOnline,
            clientType: 'desktop',
            os: 'Windows Desktop',
            lastSeenAt: u.lastActiveAt,
          ));
        }
      }
    }

    for (final s in allSessions) {
      final exists = _allFleetDevices.any((d) =>
          (s.username.isNotEmpty &&
              d.username.toLowerCase() == s.username.toLowerCase()) ||
          (s.ipAddress != null &&
              s.ipAddress!.isNotEmpty &&
              d.ipAddress == s.ipAddress));
      if (!exists && s.username.isNotEmpty) {
        _allFleetDevices.add(_FleetDeviceModel(
          id: 'session_${s.id}',
          hostname:
              s.fullName.trim().isNotEmpty ? s.fullName.trim() : s.username,
          fullName: s.fullName,
          username: s.username,
          branchName: s.jobTitleBranch ?? s.department ?? 'المقر العام',
          branchCode: '00',
          ipAddress: s.ipAddress ?? '-',
          appVersion: targetVer,
          isOutdated: false,
          isOnline: s.isOnline,
          clientType: s.clientType,
          os: s.clientType == 'mobile' ? 'Android / iOS' : 'Windows Desktop',
          lastSeenAt: s.lastSeenAt,
        ));
      }
    }
  }

  void _buildInitialLogs() {
    _liveLogs.clear();
    final recent = widget.state.requestTelemetry?.recentRequests ?? [];
    if (recent.isNotEmpty) {
      for (final req in recent.take(15)) {
        final timeStr = _formatTime(req.timestamp);
        final visuals = _mapEndpointVisuals(req.method, req.path);
        final userOrHost = (req.fullName != null && req.fullName!.isNotEmpty)
            ? req.fullName!
            : ((req.username != null && req.username!.isNotEmpty)
                ? req.username!
                : req.clientIp);
        final engId = _mapEndpointToEngine(req.path);
        final engName = _coreNodesMap[engId]?.name ?? 'قاعدة البيانات';
        _liveLogs.add({
          'time': timeStr,
          'level': req.statusCode >= 400 ? 'WARN' : 'SUCCESS',
          'source': userOrHost,
          'message':
              '${visuals.label} [${req.method} ${req.path}] من $userOrHost ➔ السيرفر ➔ $engName ➔ رد [${req.statusCode} • ${req.durationMs}ms]',
        });
      }
    }

    if (_liveLogs.isEmpty) {
      final now = DateTime.now();
      _liveLogs.add({
        'time': _formatTime(now),
        'level': 'SUCCESS',
        'source': 'Gateway',
        'message':
            'شبكة n8n في وضع المراقبة اللحظية: كل طلب يدخل للسيرفر ثم يُوزع للخدمة المختصة ويرد على الجهاز بأنيميشن مباشر.',
      });
    }
    _populateInitialCanvasFromRecent();
  }

  void _populateInitialCanvasFromRecent() {
    if (_activeDevices.isNotEmpty) return;
    final recent = widget.state.requestTelemetry?.recentRequests ?? [];
    if (recent.isEmpty) return;

    final targetVer = widget.state.deploymentData?.summary.targetAppVersion ?? '1.1.22';
    // Display up to 3 most recent real requests initially in completed state
    for (final req in recent.take(3)) {
      final userOrHost = (req.fullName != null && req.fullName!.isNotEmpty)
          ? req.fullName!
          : ((req.username != null && req.username!.isNotEmpty && !req.username!.startsWith('host:'))
              ? req.username!
              : (req.hostName != null && req.hostName!.isNotEmpty
                  ? req.hostName!
                  : (req.clientIp != '-' ? 'جهاز ${req.clientIp}' : 'محطة فرع')));

      final bCode = req.branchCode ?? '00';
      final engId = _mapEndpointToEngine(req.path);
      final engName = _coreNodesMap[engId]?.name ?? 'قاعدة البيانات';
      final visuals = _mapEndpointVisuals(req.method, req.path, customLabel: req.actionLabel);

      _FleetDeviceModel? matched;
      for (final d in _allFleetDevices) {
        if (req.username != null &&
            req.username!.isNotEmpty &&
            d.username.toLowerCase() == req.username!.toLowerCase()) {
          matched = d;
          break;
        }
        if (req.hostName != null &&
            req.hostName!.isNotEmpty &&
            d.hostname.toLowerCase() == req.hostName!.toLowerCase()) {
          matched = d;
          break;
        }
      }

      matched ??= _FleetDeviceModel(
        id: 'rec_${req.id}',
        hostname: userOrHost,
        fullName: userOrHost,
        username: req.username ?? userOrHost,
        branchName: bCode != '00' && bCode != 'MAIN' ? 'فرع $bCode' : 'المقر الرئيسي',
        branchCode: bCode,
        ipAddress: req.clientIp,
        appVersion: targetVer,
        isOutdated: false,
        isOnline: true,
        clientType: 'desktop',
        os: 'Windows',
        lastSeenAt: req.timestamp,
      );

      final freeSlot = _allocateFreeSlotIndex();
      final slotPos = _computeDeviceSlotPosition(freeSlot, _lastCanvasWidth, _lastCanvasHeight);

      final activeDev = _ActiveCanvasDevice(
        id: 'act_init_${req.id}',
        deviceId: matched.id,
        username: matched.username,
        hostname: matched.hostname,
        cashierName: matched.fullName,
        branchName: matched.branchName,
        branchCode: matched.branchCode,
        ipAddress: matched.ipAddress,
        actionLabel: visuals.label,
        targetEngineId: engId,
        targetEngineName: engName,
        slotIndex: freeSlot,
        position: slotPos,
        color: visuals.color,
        icon: visuals.icon,
        requestStartedAt: req.timestamp.subtract(const Duration(seconds: 4)),
        method: req.method,
        endpoint: req.path,
        latencyMs: req.durationMs,
        statusCode: req.statusCode,
      );
      activeDev.isCompleted = true;
      activeDev.remainingSeconds = 12;
      _activeDevices.add(activeDev);
    }
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
        _logSystemEvent('SUCCESS', 'WebSocket',
            '🟢 متصل بالسيرفر المركزي لحظياً - نظام المراقبة نشط');
      } else if (event.type == 'socket_disconnected' ||
          event.type == 'socket_reconnecting') {
        setState(() => _isSocketConnected = false);
      } else if (event.type == 'api_request_telemetry') {
        _handleRealApiRequest(event.payload);
      } else if (event.type == 'receive_message') {
        _handleRealChatMessage(event.payload);
      } else if (event.type == 'update_telemetry') {
        _handleRealUpdateTelemetry(event.payload);
      }
    });
  }

  void _logSystemEvent(String level, String source, String message) {
    setState(() {
      _liveLogs.insert(0, {
        'time': _formatTime(DateTime.now()),
        'level': level,
        'source': source,
        'message': message,
      });
      if (_liveLogs.length > 80) _liveLogs.removeLast();
    });
  }

  void _handleRealApiRequest(Map<String, dynamic> data) {
    if (!mounted) return;

    final clientIp = (data['clientIp'] ?? '-').toString();
    final method = (data['method'] ?? 'GET').toString().toUpperCase();
    final path = (data['path'] ?? '/').toString();
    final statusCode =
        data['statusCode'] is num ? (data['statusCode'] as num).toInt() : 200;
    final durationMs =
        data['durationMs'] is num ? (data['durationMs'] as num).toInt() : 12;

    final userMap = data['user'] as Map<String, dynamic>?;
    final username = (userMap?['username'] ?? '').toString();
    final fullName = (userMap?['fullName'] ?? '').toString();
    final branchCode = (userMap?['branchCode'] ?? data['branchCode'] ?? '').toString();
    final hostName = (data['hostName'] ?? userMap?['hostName'] ?? '').toString();
    final deviceUid = (data['deviceUid'] ?? userMap?['deviceUid'] ?? '').toString();
    final customLabel = (data['actionLabel'] ?? '').toString();
    final platform = (data['platform'] ?? '').toString();
    final isMobile = platform.contains('mobile') || (data['platform']?.toString().contains('mobile') == true);

    // Match device from real fleet by deviceUid, hostName, username, branchCode or IP
    _FleetDeviceModel? matchedDev;
    for (final d in _allFleetDevices) {
      if (deviceUid.isNotEmpty && (d.id.contains(deviceUid) || (d.deviceUid.isNotEmpty && d.deviceUid == deviceUid))) {
        matchedDev = d;
        break;
      }
      if (hostName.isNotEmpty &&
          d.hostname.toLowerCase() == hostName.toLowerCase()) {
        matchedDev = d;
        break;
      }
      if (username.isNotEmpty &&
          username != '-' &&
          !username.startsWith('host:') &&
          d.username.toLowerCase() == username.toLowerCase()) {
        if (clientIp.isNotEmpty && clientIp != '-' && clientIp != '127.0.0.1' && d.ipAddress.isNotEmpty && d.ipAddress != '-' && d.ipAddress != clientIp) {
          continue;
        }
        matchedDev = d;
        break;
      }
      if (branchCode.isNotEmpty &&
          branchCode != 'MAIN' &&
          branchCode != '00' &&
          d.branchCode.toUpperCase() == branchCode.toUpperCase()) {
        matchedDev = d;
        break;
      }
      if (clientIp.isNotEmpty &&
          clientIp != '-' &&
          clientIp != '127.0.0.1' &&
          clientIp != 'localhost' &&
          d.ipAddress == clientIp) {
        matchedDev = d;
        break;
      }
    }

    final resolvedId = deviceUid.isNotEmpty
        ? 'dev_$deviceUid'
        : (hostName.isNotEmpty
            ? 'host_${hostName.toLowerCase()}'
            : (clientIp.isNotEmpty && clientIp != '-' && clientIp != '127.0.0.1' && clientIp != 'localhost'
                ? 'ip_${clientIp.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '_')}'
                : (username.isNotEmpty && username != '-' && !username.startsWith('host:')
                    ? 'user_${username.toLowerCase()}_${isMobile ? "m" : "d"}'
                    : 'act_${DateTime.now().millisecondsSinceEpoch}')));

    final displayName = hostName.isNotEmpty
        ? hostName
        : (clientIp.isNotEmpty && clientIp != '-' && clientIp != '127.0.0.1' && clientIp != 'localhost'
            ? 'جهاز ($clientIp)'
            : (fullName.isNotEmpty && fullName != 'جهاز بالشبكة'
                ? (isMobile ? '$fullName (موبايل)' : fullName)
                : (username.isNotEmpty && username != '-' && !username.startsWith('host:')
                    ? (isMobile ? '$username (موبايل)' : username)
                    : (branchCode.isNotEmpty && branchCode != 'MAIN' && branchCode != '00'
                        ? 'كاشير فرع $branchCode'
                        : 'محطة فرع'))));

    final displayBranch = branchCode.isNotEmpty && branchCode != 'MAIN' && branchCode != '00'
        ? 'فرع $branchCode'
        : 'المقر الرئيسي';

    matchedDev ??= _FleetDeviceModel(
      id: resolvedId,
      deviceUid: deviceUid,
      hostname: displayName,
      fullName: fullName.isNotEmpty ? fullName : displayName,
      username: username.isNotEmpty ? username : displayName,
      branchName: displayBranch,
      branchCode: branchCode.isNotEmpty ? branchCode : '00',
      ipAddress: clientIp,
      appVersion:
          widget.state.deploymentData?.summary.targetAppVersion ?? '1.1.22',
      isOutdated: false,
      isOnline: true,
      clientType: isMobile ? 'mobile' : 'desktop',
      os: isMobile ? 'Android' : 'Windows',
      lastSeenAt: DateTime.now(),
    );

    final engId = _mapEndpointToEngine(path);
    final visuals = _mapEndpointVisuals(method, path, customLabel: customLabel.isNotEmpty ? customLabel : null);

    _spawnRealActionOnCanvas(
      dev: matchedDev,
      actionLabel: visuals.label,
      engineId: engId,
      color: visuals.color,
      icon: visuals.icon,
      latencyMs: durationMs,
      statusCode: statusCode,
      method: method,
      endpoint: path,
    );
  }

  void _handleRealChatMessage(Map<String, dynamic> payload) {
    if (!mounted) return;
    final sender = payload['sender'] as Map<String, dynamic>? ?? {};
    final fullName =
        (sender['fullName'] ?? sender['username'] ?? 'مستخدم').toString();
    final username = (sender['username'] ?? '').toString();

    _FleetDeviceModel? matchedDev;
    for (final d in _allFleetDevices) {
      if (username.isNotEmpty &&
          d.username.toLowerCase() == username.toLowerCase()) {
        matchedDev = d;
        break;
      }
    }
    matchedDev ??= _FleetDeviceModel(
      id: username.isNotEmpty
          ? 'chat_${username.toLowerCase()}'
          : 'chat_${DateTime.now().microsecondsSinceEpoch}',
      hostname: fullName,
      fullName: fullName,
      username: username,
      branchName: 'المحادثات الفورية',
      branchCode: '00',
      ipAddress: '-',
      appVersion: '1.1.22',
      isOutdated: false,
      isOnline: true,
      clientType: 'desktop',
      os: 'Windows',
      lastSeenAt: DateTime.now(),
    );

    _spawnRealActionOnCanvas(
      dev: matchedDev,
      actionLabel: '💬 رسالة شات فورية',
      engineId: 'node_chat_engine',
      color: const Color(0xFF6366F1),
      icon: Icons.chat_bubble_outline_rounded,
      latencyMs: 6,
      statusCode: 200,
      method: 'SOCKET',
      endpoint: '/socket/receive_message',
    );
  }

  void _handleRealUpdateTelemetry(Map<String, dynamic> payload) {
    if (!mounted) return;
    final host =
        (payload['hostName'] ?? payload['deviceName'] ?? 'جهاز فرع').toString();
    final targetVer = (payload['targetVersion'] ?? '1.1.22').toString();
    final progress = payload['progress'] ?? 0;

    _FleetDeviceModel? matchedDev;
    for (final d in _allFleetDevices) {
      if (d.hostname.toLowerCase() == host.toLowerCase()) {
        matchedDev = d;
        break;
      }
    }
    matchedDev ??= _FleetDeviceModel(
      id: 'upd_${host.toLowerCase()}',
      hostname: host,
      fullName: host,
      username: host,
      branchName: 'تحديثات الفروع',
      branchCode: (payload['branchCode'] ?? '00').toString(),
      ipAddress: '-',
      appVersion: targetVer,
      isOutdated: false,
      isOnline: true,
      clientType: 'desktop',
      os: 'Windows',
      lastSeenAt: DateTime.now(),
    );

    _spawnRealActionOnCanvas(
      dev: matchedDev,
      actionLabel: '📦 سحب تحديث v$targetVer ($progress%)',
      engineId: 'node_release_engine',
      color: const Color(0xFFF59E0B),
      icon: Icons.system_update_alt_rounded,
      latencyMs: 14,
      statusCode: 200,
      method: 'STREAM',
      endpoint: '/api/updates/telemetry',
    );
  }

  /// Maps EVERY request to one of the 5 right-hand Service Engines so that
  /// requests always enter `node_gateway` (Server) and get distributed to a Service Engine!
  String _mapEndpointToEngine(String path) {
    final p = path.toLowerCase();
    if (p.contains('/chat') ||
        p.contains('/messages') ||
        p.contains('/conversations') ||
        p.contains('/reactions') ||
        p.contains('/polls')) {
      return 'node_chat_engine';
    }
    if (p.contains('/documents') ||
        p.contains('/orders') ||
        p.contains('/inventory') ||
        p.contains('/transfers') ||
        p.contains('/upload') ||
        p.contains('/files')) {
      return 'node_doc_engine';
    }
    if (p.contains('/print') ||
        p.contains('/printer') ||
        p.contains('/spool')) {
      return 'node_printer_engine';
    }
    if (p.contains('/release') ||
        p.contains('/update') ||
        p.contains('/deployment') ||
        p.contains('/version')) {
      return 'node_release_engine';
    }
    return 'node_database';
  }

  ({String label, Color color, IconData icon}) _mapEndpointVisuals(
      String method, String path, {String? customLabel}) {
    if (customLabel != null && customLabel.trim().isNotEmpty) {
      final p = path.toLowerCase();
      Color c = const Color(0xFF06B6D4);
      IconData ic = Icons.bolt_rounded;
      if (p.contains('chat') || p.contains('message')) {
        c = const Color(0xFF6366F1);
        ic = Icons.chat_bubble_outline_rounded;
      } else if (p.contains('print')) {
        c = const Color(0xFFEC4899);
        ic = Icons.print_rounded;
      } else if (p.contains('clip')) {
        c = const Color(0xFF8B5CF6);
        ic = Icons.content_paste_rounded;
      } else if (p.contains('presence') || p.contains('heartbeat')) {
        c = const Color(0xFF10B981);
        ic = Icons.sensors_rounded;
      }
      return (label: customLabel.trim(), color: c, icon: ic);
    }
    final p = path.toLowerCase();
    if (p.contains('/heartbeat')) {
      return (
        label: '💓 نبضة اتصال ومزامنة الفرع',
        color: const Color(0xFF10B981),
        icon: Icons.sensors_rounded,
      );
    }
    if (p.contains('/clipboard')) {
      return (
        label: '📋 مزامنة الحافظة الفورية',
        color: const Color(0xFF8B5CF6),
        icon: Icons.content_paste_rounded,
      );
    }
    if (p.contains('/presence')) {
      return (
        label: '🟢 نشاط وتواجد مباشر',
        color: const Color(0xFF10B981),
        icon: Icons.wifi_tethering_rounded,
      );
    }
    if (p.contains('/reactions')) {
      return (
        label: '❤️ تفاعل مع رسالة',
        color: const Color(0xFFEC4899),
        icon: Icons.favorite_rounded,
      );
    }
    if (p.contains('/typing')) {
      return (
        label: '✍️ مؤشر كتابة رسالة',
        color: const Color(0xFF3B82F6),
        icon: Icons.edit_note_rounded,
      );
    }
    if (p.contains('/seen')) {
      return (
        label: '✔️ تأكيد قراءة واستلام رسائل',
        color: const Color(0xFF10B981),
        icon: Icons.done_all_rounded,
      );
    }
    if (p.contains('/join')) {
      return (
        label: '💬 فتح واستعراض محادثة',
        color: const Color(0xFF6366F1),
        icon: Icons.chat_bubble_outline_rounded,
      );
    }
    if (p.contains('/connect')) {
      return (
        label: '🟢 اتصال جهاز بالشبكة',
        color: const Color(0xFF10B981),
        icon: Icons.wifi_tethering_rounded,
      );
    }
    if (p.contains('/chat') ||
        p.contains('/messages') ||
        p.contains('/conversations')) {
      return (
        label: method == 'POST' ? '💬 إرسال رسالة شات' : '💬 جلب رسائل الشات',
        color: const Color(0xFF6366F1),
        icon: Icons.chat_bubble_outline_rounded,
      );
    }
    if (p.contains('/documents') ||
        p.contains('/orders') ||
        p.contains('/upload') ||
        p.contains('/files')) {
      return (
        label:
            method == 'POST' ? '📄 رفع ملف / مستند' : '📄 استعلام المستندات',
        color: const Color(0xFF8B5CF6),
        icon: Icons.inventory_2_outlined,
      );
    }
    if (p.contains('/print') || p.contains('/printer')) {
      return (
        label: '🖨️ أمر طباعة مستند',
        color: const Color(0xFFEC4899),
        icon: Icons.print_rounded,
      );
    }
    if (p.contains('/release') ||
        p.contains('/update') ||
        p.contains('/deployment')) {
      return (
        label: '📦 فحص / سحب التحديثات',
        color: const Color(0xFFF59E0B),
        icon: Icons.system_update_alt_rounded,
      );
    }
    if (p.contains('/auth/login')) {
      return (
        label: '🔑 مصادقة وتسجيل دخول',
        color: const Color(0xFF10B981),
        icon: Icons.vpn_key_rounded,
      );
    }
    if (p.contains('/telemetry') ||
        p.contains('/stats') ||
        p.contains('/system')) {
      return (
        label: '📊 فحص تشخيص المنظومة',
        color: const Color(0xFF10B981),
        icon: Icons.storage_rounded,
      );
    }
    final shortPath = path.length > 22 ? '${path.substring(0, 22)}…' : path;
    return (
      label: '⚡ $method $shortPath',
      color: const Color(0xFF06B6D4),
      icon: Icons.bolt_rounded,
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // DYNAMIC DEVICE ACTION TRIGGER (DEDUPLICATED + UNLIMITED NON-OVERLAPPING SLOTS)
  // ══════════════════════════════════════════════════════════════════════════════
  int _allocateFreeSlotIndex() {
    final usedSlots = _activeDevices.map((d) => d.slotIndex).toSet();
    int candidate = 0;
    while (usedSlots.contains(candidate)) {
      candidate++;
    }
    return candidate;
  }

  void _spawnRealActionOnCanvas({
    required _FleetDeviceModel dev,
    required String actionLabel,
    required String engineId,
    required Color color,
    required IconData icon,
    required int latencyMs,
    required int statusCode,
    required String method,
    required String endpoint,
  }) {
    // Ensure targetEngineId is always one of the 5 right-side Service Engines
    final resolvedEngineId =
        (engineId == 'node_gateway' || !_coreNodesMap.containsKey(engineId))
            ? 'node_database'
            : engineId;
    final engName = _coreNodesMap[resolvedEngineId]?.name ?? 'قاعدة البيانات';

    final gw = _coreNodesMap['node_gateway'];
    if (gw != null) gw.executionCount++;
    final eng = _coreNodesMap[resolvedEngineId];
    if (eng != null) eng.executionCount++;

    // Check if this physical device is ALREADY active on the canvas
    _ActiveCanvasDevice? existing;
    for (final d in _activeDevices) {
      // 1. Exact match on unique deviceId or deviceUid
      if (dev.id.isNotEmpty && d.deviceId == dev.id) {
        existing = d;
        break;
      }
      if (dev.deviceUid.isNotEmpty && d.deviceUid.isNotEmpty && d.deviceUid == dev.deviceUid) {
        existing = d;
        break;
      }
      // 2. Physical hostname match (only if non-empty and non-generic)
      final dHost = d.hostname.trim().toLowerCase();
      final devHost = dev.hostname.trim().toLowerCase();
      final isGenericHost = devHost.isEmpty ||
          devHost == 'محطة فرع' ||
          devHost == 'جهاز بالشبكة' ||
          devHost.startsWith('جهاز -') ||
          devHost.startsWith('pos-');
      if (!isGenericHost && dHost == devHost) {
        existing = d;
        break;
      }
      // 3. Same IP address (only if non-local and real IP)
      final dIp = d.ipAddress.trim();
      final devIp = dev.ipAddress.trim();
      final isRealIp = devIp.isNotEmpty &&
          devIp != '-' &&
          devIp != '127.0.0.1' &&
          devIp != 'localhost' &&
          devIp != '::1';
      if (isRealIp && dIp == devIp) {
        existing = d;
        break;
      }
      // 4. Same username ONLY IF both devices have matching clientType, matching branch, AND no conflicting IP/host
      final dUser = d.username.trim().toLowerCase();
      final devUser = dev.username.trim().toLowerCase();
      if (devUser.isNotEmpty && devUser != '-' && !devUser.startsWith('host:') && dUser == devUser) {
        // If one is mobile and other is desktop, they are NOT the same device!
        if (d.clientType.isNotEmpty && dev.clientType.isNotEmpty && d.clientType != dev.clientType) {
          continue;
        }
        // If both have different real IPs, they are NOT the same device!
        if (isRealIp && dIp.isNotEmpty && dIp != '-' && dIp != devIp) {
          continue;
        }
        // If both have different non-generic hostnames, they are NOT the same device!
        if (!isGenericHost && dHost.isNotEmpty && dHost != devHost) {
          continue;
        }
        existing = d;
        break;
      }
    }

    if (existing != null) {
      setState(() {
        existing!.hostname = dev.hostname;
        existing.cashierName = dev.fullName;
        existing.branchName = dev.branchName;
        existing.branchCode = dev.branchCode;
        existing.ipAddress = dev.ipAddress;
        if (dev.deviceUid.isNotEmpty) existing.deviceUid = dev.deviceUid;
        if (dev.clientType.isNotEmpty) existing.clientType = dev.clientType;
        existing.actionLabel = actionLabel;
        existing.targetEngineId = resolvedEngineId;
        existing.targetEngineName = engName;
        existing.color = color;
        existing.icon = icon;
        existing.method = method;
        existing.endpoint = endpoint;
        existing.latencyMs = latencyMs;
        existing.statusCode = statusCode;
        existing.requestCount++;
        existing.requestStartedAt = DateTime.now();
        existing.isCompleted = false;
        existing.remainingSeconds = 25;

        _liveLogs.insert(0, {
          'time': _formatTime(DateTime.now()),
          'level': statusCode >= 400 ? 'WARN' : 'SUCCESS',
          'source': existing.hostname,
          'message':
              '$actionLabel من ${existing.hostname} (${existing.branchName}) ➔ السيرفر المركزي ➔ $engName ➔ رد [$statusCode • ${latencyMs}ms]',
        });
        if (_liveLogs.length > 80) _liveLogs.removeLast();
      });
      return;
    }

    // Allocate a dedicated non-overlapping slot (no 5-card limit!)
    final freeSlot = _allocateFreeSlotIndex();
    final slotPos =
        _computeDeviceSlotPosition(freeSlot, _lastCanvasWidth, _lastCanvasHeight);

    final activeDev = _ActiveCanvasDevice(
      id: 'act_${DateTime.now().microsecondsSinceEpoch}',
      deviceId: dev.id,
      deviceUid: dev.deviceUid,
      clientType: dev.clientType,
      username: dev.username,
      hostname: dev.hostname,
      cashierName: dev.fullName,
      branchName: dev.branchName,
      branchCode: dev.branchCode,
      ipAddress: dev.ipAddress,
      actionLabel: actionLabel,
      targetEngineId: resolvedEngineId,
      targetEngineName: engName,
      slotIndex: freeSlot,
      position: slotPos,
      color: color,
      icon: icon,
      requestStartedAt: DateTime.now(),
      method: method,
      endpoint: endpoint,
      latencyMs: latencyMs,
      statusCode: statusCode,
    );

    HapticFeedback.lightImpact();

    setState(() {
      _activeDevices.add(activeDev);
      _liveLogs.insert(0, {
        'time': _formatTime(DateTime.now()),
        'level': statusCode >= 400 ? 'WARN' : 'SUCCESS',
        'source': activeDev.hostname,
        'message':
            '$actionLabel من ${activeDev.hostname} (${activeDev.branchName}) ➔ السيرفر المركزي ➔ $engName ➔ رد [$statusCode • ${latencyMs}ms]',
      });
      if (_liveLogs.length > 80) _liveLogs.removeLast();
    });
  }

  void _triggerDeviceActionOnCanvas(_FleetDeviceModel dev,
      {String? customAction, String? customEngine}) {
    // Show the actual device's real status on the canvas instead of a fabricated action
    final isOutdated = dev.isOutdated;
    final isOnline = dev.isOnline;

    final String label;
    final String engineId;
    final Color color;
    final IconData icon;
    final String path;

    if (customAction != null && customEngine != null) {
      label = customAction;
      engineId = customEngine;
      color = const Color(0xFF06B6D4);
      icon = Icons.bolt_rounded;
      path = '/api/devices/${dev.branchCode}/telemetry';
    } else if (isOutdated) {
      label = '⚠️ فحص حزمة التحديث (v${dev.appVersion})';
      engineId = 'node_release_engine';
      color = const Color(0xFFF59E0B);
      icon = Icons.system_update_alt_rounded;
      path = '/api/updates/check';
    } else if (isOnline) {
      label = '🟢 اتصال نشط ومستقر (v${dev.appVersion})';
      engineId = 'node_database';
      color = const Color(0xFF10B981);
      icon = Icons.sensors_rounded;
      path = '/api/branches/${dev.branchCode}/status';
    } else {
      label = '⚪ استعلام حالة وتواجد المحطة';
      engineId = 'node_database';
      color = const Color(0xFF6B7280);
      icon = Icons.access_time_rounded;
      path = '/api/branches/${dev.branchCode}/last_seen';
    }

    _spawnRealActionOnCanvas(
      dev: dev,
      actionLabel: label,
      engineId: engineId,
      color: color,
      icon: icon,
      latencyMs: 11,
      statusCode: 200,
      method: 'GET',
      endpoint: path,
    );
  }

  Future<void> _triggerDiagnosticTestPulse() async {
    final sw = Stopwatch()..start();
    // Real refresh of stats and telemetry to measure ACTUAL backend roundtrip latency!
    await widget.notifier.refreshAll();
    sw.stop();
    final realLatency = sw.elapsedMilliseconds.clamp(4, 999);

    final authUser = ref.read(authControllerProvider).user;
    final adminDev = _FleetDeviceModel(
      id: 'admin_session_${authUser?.id ?? "main"}',
      hostname: authUser?.fullName.isNotEmpty == true
          ? 'محطة الإدارة (${authUser!.fullName})'
          : 'محطة إدارة المنظومة',
      fullName: authUser?.fullName ?? 'مدير النظام',
      username: authUser?.username ?? 'admin',
      branchName: 'المقر الرئيسي (HQ)',
      branchCode: authUser?.branchCode ?? '00',
      ipAddress: '127.0.0.1',
      appVersion: widget.state.deploymentData?.summary.targetAppVersion ?? '1.1.22',
      isOutdated: false,
      isOnline: true,
      clientType: 'desktop',
      os: 'Windows Desktop',
      lastSeenAt: DateTime.now(),
    );

    _spawnRealActionOnCanvas(
      dev: adminDev,
      actionLabel: '⚡ فحص حي لاستجابة السيرفر',
      engineId: 'node_database',
      color: const Color(0xFF06B6D4),
      icon: Icons.bolt_rounded,
      latencyMs: realLatency,
      statusCode: 200,
      method: 'GET',
      endpoint: '/api/admin/system-monitor/stats',
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // NON-OVERLAPPING MULTI-COLUMN GEOMETRY CALCULATION
  // ══════════════════════════════════════════════════════════════════════════════
  int _getActiveDeviceColumnCount() {
    if (_activeDevices.isEmpty) return 1;
    int maxSlot = 0;
    for (final d in _activeDevices) {
      if (d.slotIndex > maxSlot) maxSlot = d.slotIndex;
    }
    return (maxSlot ~/ _rowsPerDeviceColumn) + 1;
  }

  double _computeGatewayX(double canvasWidth, int deviceCols) {
    final totalDevColsWidth = (deviceCols * _deviceCardSize.width) +
        ((deviceCols - 1) * _deviceColGap);
    final minGwX = 36.0 + totalDevColsWidth + _wireCorridorGap;
    final centeredGwX = (canvasWidth - _gatewayCardSize.width) / 2.0;
    return math.max(minGwX, centeredGwX);
  }

  Offset _computeDeviceSlotPosition(
      int slotIndex, double canvasWidth, double canvasHeight) {
    final deviceCols = _getActiveDeviceColumnCount();
    final gwX = _computeGatewayX(canvasWidth, deviceCols);

    final col = slotIndex ~/ _rowsPerDeviceColumn;
    final row = slotIndex % _rowsPerDeviceColumn;

    // Column 0 is closest to Gateway; Column 1, 2... extend to the left with zero overlap
    final devX = gwX -
        _wireCorridorGap -
        _deviceCardSize.width -
        (col * (_deviceCardSize.width + _deviceColGap));

    const totalColHeight = (_rowsPerDeviceColumn * 114.0) +
        ((_rowsPerDeviceColumn - 1) * _deviceRowGap); // 642.0
    final startY = math.max(36.0, (canvasHeight - totalColHeight) / 2.0);
    // Slight vertical stagger on odd columns so wires from outer columns pass cleanly between inner column cards
    final staggerY = col.isOdd ? 16.0 : 0.0;
    final devY =
        startY + staggerY + (row * (_deviceCardSize.height + _deviceRowGap));

    return Offset(devX, devY);
  }

  void _updateNodePositions(double canvasWidth, double canvasHeight) {
    _lastCanvasWidth = canvasWidth;
    _lastCanvasHeight = canvasHeight;

    final deviceCols = _getActiveDeviceColumnCount();

    // 1. Gateway Center Position
    final gwX = _computeGatewayX(canvasWidth, deviceCols);
    final gwY = (canvasHeight - _gatewayCardSize.height) / 2.0;
    final gwNode = _coreNodesMap['node_gateway'];
    if (gwNode != null) {
      gwNode.position = Offset(gwX, gwY);
    }

    // 2. 5 Core Engines in Right Column
    final engX = gwX + _gatewayCardSize.width + _wireCorridorGap;
    const engGap = 16.0;
    final totalEngHeight =
        (5 * _engineCardSize.height) + (4 * engGap); // 540 + 64 = 604
    final engStartY = math.max(36.0, (canvasHeight - totalEngHeight) / 2.0);

    final engineIds = [
      'node_chat_engine',
      'node_doc_engine',
      'node_printer_engine',
      'node_release_engine',
      'node_database',
    ];
    for (int i = 0; i < engineIds.length; i++) {
      final engNode = _coreNodesMap[engineIds[i]];
      if (engNode != null) {
        engNode.position =
            Offset(engX, engStartY + (i * (_engineCardSize.height + engGap)));
      }
    }

    // 3. Active Devices in Non-Overlapping Multi-Column Grid on Left
    for (final dev in _activeDevices) {
      dev.position =
          _computeDeviceSlotPosition(dev.slotIndex, canvasWidth, canvasHeight);
    }
  }

  void _tickDeviceCountdowns() {
    bool changed = false;
    final toRemove = <_ActiveCanvasDevice>[];

    for (final dev in _activeDevices) {
      if (!dev.isCompleted && dev.routingStage >= 4) {
        dev.isCompleted = true;
        dev.remainingSeconds = 25;
        changed = true;
      } else if (dev.isCompleted) {
        if (dev.remainingSeconds > 1) {
          dev.remainingSeconds--;
          changed = true;
        } else {
          // 25 full seconds after completion elapsed — disappear!
          toRemove.add(dev);
        }
      }
    }

    if (toRemove.isNotEmpty) {
      for (final r in toRemove) {
        _activeDevices.remove(r);
      }
      changed = true;
    }

    if (changed) {
      setState(() {});
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // MAIN BUILD
  // ══════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0F1118) : const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Column(
            children: [
              // 1. TOP HEADER & NAVIGATION BAR
              _buildTopBar(isDark),

              // 2. MAIN WORKSPACE VIEW
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: switch (_activeTab) {
                        1 => _buildFleetDirectoryTab(isDark),
                        2 => _buildEventLogTab(isDark),
                        _ => _buildN8nCanvasTab(isDark),
                      },
                    ),

                    // Side Inspector Panel (if node selected)
                    if (_selectedNodeId != null)
                      SizedBox(
                        width: 350,
                        child: _buildInspectorPanel(isDark),
                      ),
                  ],
                ),
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
  Widget _buildTopBar(bool isDark) {
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
              IconButton(
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                tooltip: 'العودة للمراقبة',
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6D5A).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.hub_rounded,
                    size: 20, color: Color(0xFFFF6D5A)),
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
                        'شبكة n8n التفاعلية الحية',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '● LIVE FLOW (${_activeDevices.length} جهاز نشط الآن)',
                          style: const TextStyle(
                            fontSize: 9.5,
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
                    'مسار الطلب الكامل: الجهاز ⬅ السيرفر المركزي ⬅ التوزيع للخدمة المختصة ⬅ الرد للجهاز ثم الاختفاء بعد 5 ثوانٍ',
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

          // Tabs Switcher & Quick Actions
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
                      label: '⚡ خريطة n8n الحية',
                      icon: Icons.donut_large_rounded,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                    _tabPill(
                      index: 1,
                      label:
                          '🏢 كافة أجهزة الفروع (${_allFleetDevices.length})',
                      icon: Icons.devices_rounded,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                    _tabPill(
                      index: 2,
                      label: '📜 سجل الحركات (${_liveLogs.length})',
                      icon: Icons.history_rounded,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              FilledButton.icon(
                onPressed: _triggerDiagnosticTestPulse,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.bolt_rounded, size: 16),
                label: const Text(
                  '⚡ نبضة فحص للمنظومة',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
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
                  ? const Color(0xFFFF6D5A)
                  : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
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
  // TAB 0: AUTHENTIC n8n CANVAS VIEW (DEVICE ➔ SERVER ➔ SERVICE ➔ DEVICE)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildN8nCanvasTab(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableW = constraints.maxWidth;
        final availableH = constraints.maxHeight;

        final deviceCols = _getActiveDeviceColumnCount();
        final requiredWidth = 36.0 +
            (deviceCols * _deviceCardSize.width) +
            ((deviceCols - 1) * _deviceColGap) +
            _wireCorridorGap +
            _gatewayCardSize.width +
            _wireCorridorGap +
            _engineCardSize.width +
            44.0;

        final canvasWidth = math.max(availableW, math.max(1180.0, requiredWidth));
        final canvasHeight = math.max(availableH, 720.0);

        _updateNodePositions(canvasWidth, canvasHeight);
        final gwNode = _coreNodesMap['node_gateway'];
        final gwPos = gwNode?.position ??
            Offset((canvasWidth - _gatewayCardSize.width) / 2.0,
                (canvasHeight - _gatewayCardSize.height) / 2.0);
        final gwSize = gwNode?.size ?? _gatewayCardSize;

        return Stack(
          children: [
            InteractiveViewer(
              transformationController: _interactiveController,
              minScale: 0.45,
              maxScale: 1.8,
              boundaryMargin: const EdgeInsets.all(300),
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
                        painter: _N8nCanvasGridPainter(isDark: isDark),
                      ),
                    ),

                    // Layer 2: Multi-Stage Animated Wires (Device ➔ Gateway ➔ Target Service Engine ➔ Response)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _wireFlowController,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: _N8nFullTopologyWiresPainter(
                              coreNodes: _coreNodes,
                              coreNodesMap: _coreNodesMap,
                              activeDevices: _activeDevices,
                              gatewayPosition: gwPos,
                              gatewaySize: gwSize,
                              selectedNodeId: _selectedNodeId,
                              pulseValue: _wireFlowController.value,
                              isDark: isDark,
                            ),
                          );
                        },
                      ),
                    ),

                    // Layer 3: Empty State Watermark if no devices calling right now
                    if (_activeDevices.isEmpty)
                      Positioned(
                        left: math.max(
                            36.0, gwPos.dx - _deviceCardSize.width - _wireCorridorGap),
                        top: gwPos.dy - 12,
                        child: _buildIdleLiveMonitorBanner(isDark),
                      ),

                    // Layer 4: Fixed Core Service Cards (Center Server + 5 Service Engines)
                    for (final node in _coreNodes)
                      Positioned(
                        left: node.position.dx,
                        top: node.position.dy,
                        child: AnimatedBuilder(
                          animation: _wireFlowController,
                          builder: (context, _) =>
                              _buildCoreNodeCard(node, isDark),
                        ),
                      ),

                    // Layer 5: Dynamic Calling Devices (Appear, route 3 stages, count down 5s, fade out)
                    for (final activeDev in _activeDevices)
                      Positioned(
                        left: activeDev.position.dx,
                        top: activeDev.position.dy,
                        child: AnimatedBuilder(
                          animation: _wireFlowController,
                          builder: (context, _) =>
                              _buildCallingDeviceCard(activeDev, isDark),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Single Floating Controls HUD (Bottom Left)
            Positioned(
              left: 20,
              bottom: 20,
              child: _buildCanvasFloatingHUD(isDark),
            ),
          ],
        );
      },
    );
  }

  Widget _buildIdleLiveMonitorBanner(bool isDark) {
    return Container(
      width: _deviceCardSize.width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF141722).withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.sensors_rounded,
                size: 24, color: Color(0xFF10B981)),
          ),
          const SizedBox(height: 10),
          const Text(
            'شبكة n8n في وضع الاستماع اللحظي 🟢',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 5),
          Text(
            'تظهر أجهزة الفروع هنا تلقائياً فور إرسال أي طلب، ويمر الطلب للسيرفر ثم للخدمة المختصة ويعود بالرد قبل الاختفاء بعد 5 ثوانٍ.',
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // CARD WIDGETS: ALL TEXT & BADGES STRICTLY INSIDE CARDS (ZERO OVERFLOW)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildCoreNodeCard(_CoreServiceNode node, bool isDark) {
    final isSelected = _selectedNodeId == node.id;
    final isGateway = node.id == 'node_gateway';

    // Check if any active device is currently routing through or targeting this node
    final activeTargetingThis = _activeDevices.where((d) {
      final st = d.routingStage;
      if (isGateway) return st == 1 || st == 2 || st == 3;
      return d.targetEngineId == node.id && (st == 2 || st == 3);
    }).toList();
    final isActivelyProcessing = activeTargetingThis.isNotEmpty;

    final borderColor = isActivelyProcessing || isSelected
        ? node.color
        : (isGateway
            ? const Color(0xFF06B6D4)
            : node.color.withValues(alpha: 0.55));

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedNodeId = node.id;
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main Clipped Card Body (Nothing can overflow outside!)
          Container(
            width: node.size.width,
            height: node.size.height,
            clipBehavior: Clip.hardEdge,
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: isGateway ? 10 : 8,
            ),
            decoration: BoxDecoration(
              color: isGateway
                  ? (isDark ? const Color(0xFF0F232D) : const Color(0xFFECFEFF))
                  : (isDark ? const Color(0xFF141722) : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderColor,
                width: isActivelyProcessing || isSelected || isGateway
                    ? 2.2
                    : 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: node.color.withValues(
                      alpha: isActivelyProcessing
                          ? 0.38
                          : (isGateway ? 0.22 : 0.08)),
                  blurRadius:
                      isActivelyProcessing || isGateway || isSelected ? 18 : 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Row 1: Top Badge & Execution Counter (Strictly INSIDE card)
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: isActivelyProcessing
                              ? node.color
                              : node.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          isActivelyProcessing
                              ? (isGateway
                                  ? '⚡ يوزع ${activeTargetingThis.length} طلب للخدمات'
                                  : '⚡ يعالج طلب ${activeTargetingThis.first.hostname}')
                              : node.category,
                          style: TextStyle(
                            fontSize: 8.8,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                            color: isActivelyProcessing
                                ? Colors.white
                                : node.color,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '✓ ${node.executionCount}',
                        style: const TextStyle(
                          fontSize: 8.8,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),

                // Row 2: Icon + Node Name + Subtitle
                Row(
                  children: [
                    Container(
                      width: isGateway ? 36 : 32,
                      height: isGateway ? 36 : 32,
                      decoration: BoxDecoration(
                        color: node.color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                            color: node.color.withValues(alpha: 0.4)),
                      ),
                      child: Icon(node.icon,
                          color: node.color, size: isGateway ? 19 : 17),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            node.name,
                            style: TextStyle(
                              fontSize: isGateway ? 12.0 : 11.2,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            node.subtitle,
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

                // Row 3: Live Status Footer
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isActivelyProcessing
                            ? (isGateway
                                ? '🔄 توجيه الطلب واستلام الرد...'
                                : '📤 إرسال الرد عبر البوابة المركزية...')
                            : (isGateway
                                ? 'بوابة التوجيه المركزية نشطة'
                                : 'الخدمة متصلة وجاهزة'),
                        style: TextStyle(
                          fontSize: 9.0,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          color: isActivelyProcessing
                              ? node.color
                              : (isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B)),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'ONLINE 🟢',
                      style: TextStyle(
                        fontSize: 8.8,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Left Port Connector Dot (pure circle on border)
          Positioned(
            left: -5,
            top: (node.size.height / 2) - 5,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F1118) : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: node.color, width: 2.2),
              ),
            ),
          ),

          // Right Port Connector Dot (for Gateway)
          if (isGateway)
            Positioned(
              right: -5,
              top: (node.size.height / 2) - 5,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F1118) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: node.color, width: 2.2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// DYNAMIC CALLING DEVICE CARD:
  /// All badges and text live strictly INSIDE the card (Clip.hardEdge) with zero overflow!
  Widget _buildCallingDeviceCard(_ActiveCanvasDevice dev, bool isDark) {
    final stage = dev.routingStage;
    final isDone = dev.isCompleted || stage >= 4;
    final statusColor = isDone ? const Color(0xFF10B981) : dev.color;

    String stageText;
    IconData stageIcon;
    if (isDone) {
      stageText = 'تم الرد ✓ (نشط لمدة ${dev.remainingSeconds}ث)';
      stageIcon = Icons.check_circle_rounded;
    } else if (stage == 1) {
      stageText = '1/3 📤 إرسال الطلب للسيرفر...';
      stageIcon = Icons.upload_rounded;
    } else if (stage == 2) {
      stageText = '2/3 ⚙️ يُعالج في ${dev.targetEngineName}';
      stageIcon = Icons.settings_suggest_rounded;
    } else {
      stageText = '3/3 📥 استلام رد الخدمة (${dev.statusCode})';
      stageIcon = Icons.download_done_rounded;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: _deviceCardSize.width,
          height: _deviceCardSize.height,
          clipBehavior: Clip.hardEdge,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141722) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: statusColor,
              width: isDone ? 2.2 : 1.9,
            ),
            boxShadow: [
              BoxShadow(
                color: statusColor.withValues(alpha: isDone ? 0.32 : 0.22),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Row 1: Top Stage Status Pill + Request Counter Badge (Strictly INSIDE card!)
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(stageIcon, color: Colors.white, size: 11),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              stageText,
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
                  if (dev.requestCount > 1) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        'x${dev.requestCount}',
                        style: TextStyle(
                          fontSize: 8.8,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // Row 2: Device Icon + Hostname + Cashier/Branch
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Icon(dev.icon, color: statusColor, size: 17),
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
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
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

              // Row 3: Action Label + Target Engine & Latency
              Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        dev.actionLabel,
                        style: TextStyle(
                          fontSize: 8.6,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          color: statusColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isDone
                        ? '${dev.latencyMs}ms • ${dev.statusCode}'
                        : '⬅ ${dev.targetEngineName}',
                    style: TextStyle(
                      fontSize: 8.8,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: isDone
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),

        // Right Output Port Dot (facing Central Gateway)
        Positioned(
          right: -5,
          top: (_deviceCardSize.height / 2) - 5,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F1118) : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: statusColor, width: 2.2),
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // FLOATING HUD: ZOOM & STATUS
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildCanvasFloatingHUD(bool isDark) {
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
                ? Icons.sensors_rounded
                : Icons.sensors_off_rounded,
            size: 16,
            color:
                _isSocketConnected ? const Color(0xFF10B981) : Colors.amber,
          ),
          const SizedBox(width: 6),
          Text(
            _isSocketConnected
                ? 'البث اللحظي: نشط 🟢 (${_activeDevices.length} جهاز باللوحة)'
                : 'جاري الاتصال بالسيرفر...',
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 1: ALL FLEET DEVICES DIRECTORY (TEST ANY DEVICE LIVE ON CANVAS)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildFleetDirectoryTab(bool isDark) {
    final filtered = _allFleetDevices.where((d) {
      if (_deviceFilter == 'online' && !d.isOnline) return false;
      if (_deviceFilter == 'outdated' && !d.isOutdated) return false;
      if (_deviceFilter == 'offline' && d.isOnline) return false;
      if (_selectedBranchCode != 'all' && d.branchCode != _selectedBranchCode) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchHost = d.hostname.toLowerCase().contains(q);
        final matchName = d.fullName.toLowerCase().contains(q);
        final matchBranch = d.branchName.toLowerCase().contains(q);
        final matchIp = d.ipAddress.contains(q);
        if (!matchHost && !matchName && !matchBranch && !matchIp) return false;
      }
      return true;
    }).toList();

    final Map<String, List<_FleetDeviceModel>> branchGroups = {};
    for (final dev in filtered) {
      branchGroups.putIfAbsent(dev.branchCode, () => []).add(dev);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDirectoryFilterBar(isDark),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
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
              child: const Text('لا توجد أجهزة مطابقة للبحث حالياً',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            )
          else
            for (final entry in branchGroups.entries)
              _buildBranchDirectoryCard(entry.key, entry.value, isDark),
        ],
      ),
    );
  }

  Widget _buildDirectoryFilterBar(bool isDark) {
    final allCount = _allFleetDevices.length;
    final onlineCount = _allFleetDevices.where((d) => d.isOnline).length;
    final outdatedCount = _allFleetDevices.where((d) => d.isOutdated).length;

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
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterPill('all', 'كل الأجهزة ($allCount)',
                  const Color(0xFF6366F1), isDark),
              _filterPill('online', 'متصل الآن 🟢 ($onlineCount)',
                  const Color(0xFF10B981), isDark),
              _filterPill('outdated', 'نسخة قديمة ⚠️ ($outdatedCount)',
                  const Color(0xFFF59E0B), isDark),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0D1117)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isDark
                          ? const Color(0xFF222938)
                          : const Color(0xFFCBD5E1)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: branchOptions.containsKey(_selectedBranchCode)
                        ? _selectedBranchCode
                        : 'all',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color:
                            isDark ? Colors.white : const Color(0xFF0F172A)),
                    dropdownColor:
                        isDark ? const Color(0xFF141722) : Colors.white,
                    items: branchOptions.entries
                        .map((e) =>
                            DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() => _selectedBranchCode = val);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 200,
                height: 36,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (val) =>
                      setState(() => _searchQuery = val.trim()),
                  style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'بحث بالجهاز أو الموظف أو IP...',
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterPill(String id, String label, Color color, bool isDark) {
    final isSelected = _deviceFilter == id;
    return InkWell(
      onTap: () => setState(() => _deviceFilter = id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.18)
              : (isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isSelected
                  ? color
                  : (isDark
                      ? const Color(0xFF222938)
                      : const Color(0xFFE2E8F0))),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected
                ? color
                : (isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  Widget _buildBranchDirectoryCard(
      String branchCode, List<_FleetDeviceModel> devs, bool isDark) {
    final bName = devs.first.branchName;
    final onlineCount = devs.where((d) => d.isOnline).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF191F2E) : const Color(0xFFF1F5F9),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront_rounded,
                    size: 18, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text(bName,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('كود $branchCode',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF10B981))),
                ),
                const Spacer(),
                Text('$onlineCount من ${devs.length} متصل الآن',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF10B981))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              children: devs
                  .map((dev) => _buildDirectoryDeviceCard(dev, isDark))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryDeviceCard(_FleetDeviceModel dev, bool isDark) {
    return Container(
      width: 295,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dev.isOnline
              ? const Color(0xFF10B981).withValues(alpha: 0.45)
              : (isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.desktop_windows_rounded,
                  color:
                      dev.isOnline ? const Color(0xFF10B981) : Colors.grey,
                  size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dev.hostname,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0F172A)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                dev.isOnline ? 'متصل 🟢' : 'غير متصل ⚪',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: dev.isOnline
                        ? const Color(0xFF10B981)
                        : Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${dev.fullName} • IP: ${dev.ipAddress}',
            style: TextStyle(
                fontSize: 10.5,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: dev.isOutdated
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                      : const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  dev.isOutdated
                      ? 'v${dev.appVersion} ⚠️'
                      : 'v${dev.appVersion} ✓',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: dev.isOutdated
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF10B981)),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  _triggerDeviceActionOnCanvas(dev);
                  setState(() => _activeTab = 0);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D5A),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 28),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.bolt_rounded, size: 12),
                label: const Text('إظهار في خريطة n8n ⚡',
                    style:
                        TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 2: LIVE EVENT LOG
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildEventLogTab(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _liveLogs.length,
      itemBuilder: (context, idx) {
        final log = _liveLogs[idx];
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
                '[${log['time']}]',
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
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  log['source'] as String? ?? 'Hub',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF10B981)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  log['message'] as String? ?? '',
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

  // ══════════════════════════════════════════════════════════════════════════════
  // SIDE INSPECTOR PANEL
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildInspectorPanel(bool isDark) {
    final node =
        _selectedNodeId != null ? _coreNodesMap[_selectedNodeId!] : null;
    if (node == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        border: Border(
            right: BorderSide(
                color: isDark
                    ? const Color(0xFF222938)
                    : const Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: node.color.withValues(alpha: 0.12),
              border: Border(
                  bottom:
                      BorderSide(color: node.color.withValues(alpha: 0.25))),
            ),
            child: Row(
              children: [
                Icon(node.icon, color: node.color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(node.name,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w900)),
                      Text(node.category,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: node.color)),
                    ],
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _selectedNodeId = null)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(node.description,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF334155))),
                const SizedBox(height: 16),
                const Text('القياسات التشغيلية الحية',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                ...node.metrics.entries.map((e) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0D1117)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: isDark
                                ? const Color(0xFF222938)
                                : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Text(e.key,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B))),
                          const Spacer(),
                          Text(e.value,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900)),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CANVAS PAINTERS FOR 3-STAGE n8n WORKFLOW WIRES & PACKETS
// ══════════════════════════════════════════════════════════════════════════════

class _N8nCanvasGridPainter extends CustomPainter {
  const _N8nCanvasGridPainter({required this.isDark});
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
  bool shouldRepaint(covariant _N8nCanvasGridPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Full 3-Stage n8n Topology Painter:
/// Stage 1: Device ➔ Central Server (Gateway)
/// Stage 2: Central Server (Gateway) ➔ Target Service Engine
/// Stage 3: Target Service Engine ➔ Central Server ➔ Device (Response)
class _N8nFullTopologyWiresPainter extends CustomPainter {
  const _N8nFullTopologyWiresPainter({
    required this.coreNodes,
    required this.coreNodesMap,
    required this.activeDevices,
    required this.gatewayPosition,
    required this.gatewaySize,
    required this.selectedNodeId,
    required this.pulseValue,
    required this.isDark,
  });

  final List<_CoreServiceNode> coreNodes;
  final Map<String, _CoreServiceNode> coreNodesMap;
  final List<_ActiveCanvasDevice> activeDevices;
  final Offset gatewayPosition;
  final Size gatewaySize;
  final String? selectedNodeId;
  final double pulseValue;
  final bool isDark;

  void _drawPacketWithChip({
    required Canvas canvas,
    required Path path,
    required double progress,
    required Color color,
    required String label,
  }) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final offsetDist = (metric.length * progress.clamp(0.0, 1.0));
    final tangent = metric.getTangentForOffset(offsetDist);
    if (tangent == null) return;

    // Outer Glow Halo
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(tangent.position, 9.0, glowPaint);

    // Inner Bright Core
    final corePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(tangent.position, 4.0, corePaint);

    // Floating Action Chip above the packet
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.rtl,
      maxLines: 1,
    )..layout(maxWidth: 165);

    final chipRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(tangent.position.dx, tangent.position.dy - 15),
        width: tp.width + 12,
        height: tp.height + 5,
      ),
      const Radius.circular(5),
    );

    final bgPaint = Paint()..color = color.withValues(alpha: 0.94);
    canvas.drawRRect(chipRect, bgPaint);
    tp.paint(
      canvas,
      Offset(
        tangent.position.dx - (tp.width / 2),
        tangent.position.dy - 15 - (tp.height / 2),
      ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gwLeftPort =
        Offset(gatewayPosition.dx, gatewayPosition.dy + (gatewaySize.height / 2.0));
    final gwRightPort = Offset(gatewayPosition.dx + gatewaySize.width,
        gatewayPosition.dy + (gatewaySize.height / 2.0));

    final wirePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // 1. Draw Core Wires (Gateway ➔ 5 Service Engines)
    final Map<String, Path> enginePaths = {};
    for (final node in coreNodes) {
      if (node.id == 'node_gateway') continue;

      final nodeLeftPort =
          Offset(node.position.dx, node.position.dy + (node.size.height / 2.0));
      final midX = (gwRightPort.dx + nodeLeftPort.dx) / 2.0;
      final path = Path()
        ..moveTo(gwRightPort.dx, gwRightPort.dy)
        ..cubicTo(midX, gwRightPort.dy, midX, nodeLeftPort.dy, nodeLeftPort.dx,
            nodeLeftPort.dy);
      enginePaths[node.id] = path;

      // Check if any active device is currently routing on this engine wire
      final hasActiveRouting = activeDevices.any((d) =>
          d.targetEngineId == node.id &&
          (d.routingStage == 2 || d.routingStage == 3));
      final isHighlighted = hasActiveRouting ||
          selectedNodeId == node.id ||
          selectedNodeId == 'node_gateway';

      wirePaint.color = isHighlighted
          ? node.color.withValues(alpha: hasActiveRouting ? 0.95 : 0.75)
          : (isDark ? const Color(0xFF283144) : const Color(0xFFCBD5E1));
      wirePaint.strokeWidth = hasActiveRouting ? 2.8 : (isHighlighted ? 2.2 : 1.6);

      canvas.drawPath(path, wirePaint);
    }

    // 2. Draw Active Device Wires & 3-Stage Animated Packets
    for (final dev in activeDevices) {
      final devRightPort = Offset(
        dev.position.dx + 275.0,
        dev.position.dy + (114.0 / 2.0),
      );

      final stage = dev.routingStage;
      final sProg = dev.stageProgress;
      final isDone = dev.isCompleted || stage >= 4;
      final lineColor = isDone ? const Color(0xFF10B981) : dev.color;

      final midX = (devRightPort.dx + gwLeftPort.dx) / 2.0;
      final devToGwPath = Path()
        ..moveTo(devRightPort.dx, devRightPort.dy)
        ..cubicTo(midX, devRightPort.dy, midX, gwLeftPort.dy, gwLeftPort.dx,
            gwLeftPort.dy);

      wirePaint.color = lineColor.withValues(alpha: isDone ? 0.50 : 0.88);
      wirePaint.strokeWidth = isDone ? 2.0 : 2.5;
      canvas.drawPath(devToGwPath, wirePaint);

      final engPath = enginePaths[dev.targetEngineId];
      final engNode = coreNodesMap[dev.targetEngineId];
      final engColor = engNode?.color ?? dev.color;

      if (stage == 1) {
        // Stage 1: Packet travels from Device ➔ Central Server (Gateway)
        _drawPacketWithChip(
          canvas: canvas,
          path: devToGwPath,
          progress: sProg,
          color: dev.color,
          label: '📤 ${dev.actionLabel}',
        );
      } else if (stage == 2) {
        // Stage 2: Central Server distributes packet ➔ Target Service Engine
        if (engPath != null) {
          _drawPacketWithChip(
            canvas: canvas,
            path: engPath,
            progress: sProg,
            color: engColor,
            label: '⚙️ توزيع: ${dev.actionLabel}',
          );
        }
      } else if (stage == 3) {
        // Stage 3: Service Engine sends Response ➔ Server ➔ Device
        if (sProg < 0.5 && engPath != null) {
          // 3a: Engine ➔ Gateway (reverse along engPath: 1.0 ➔ 0.0)
          final revT = 1.0 - (sProg * 2.0);
          _drawPacketWithChip(
            canvas: canvas,
            path: engPath,
            progress: revT,
            color: const Color(0xFF10B981),
            label: '✅ رد الخدمة (${dev.statusCode})',
          );
        } else {
          // 3b: Gateway ➔ Device (reverse along devToGwPath: 1.0 ➔ 0.0)
          final revT = 1.0 - ((sProg - 0.5) * 2.0);
          _drawPacketWithChip(
            canvas: canvas,
            path: devToGwPath,
            progress: revT,
            color: const Color(0xFF10B981),
            label: '✅ رد السيرفر (${dev.latencyMs}ms)',
          );
        }
      } else {
        // Stage 4 (Completed): Gentle green confirmation pulse during 5s countdown
        _drawPacketWithChip(
          canvas: canvas,
          path: devToGwPath,
          progress: 1.0 - pulseValue,
          color: const Color(0xFF10B981),
          label: '✓ نشط (${dev.remainingSeconds}ث)',
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _N8nFullTopologyWiresPainter oldDelegate) =>
      true;
}
