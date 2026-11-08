import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'system_monitor_controller.dart';

/// Supported view modes for the live operations screen.
enum _TopologyViewMode {
  canvasWorkflow,     // Concentric Circular Building Tower (Authentic n8n Radial Canvas)
  responsivePipeline, // Clean, 100% responsive 5-stage pipeline board
  branchFleet,        // Grid of enterprise branches and cashier workstations
}

/// Concentric floor / tier in the circular building architecture.
class _TopologyFloor {
  const _TopologyFloor({
    required this.floorNumber,
    required this.radius,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.icon,
  });

  final int floorNumber;
  final double radius;
  final String title;
  final String subtitle;
  final Color accentColor;
  final IconData icon;
}

/// Device representation model extracted from real database branches and sessions.
class _DeviceModel {
  _DeviceModel({
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
    this.lastSeenAt,
  });

  final String id;
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

/// Node model representing an authentic n8n block in the circular system mesh.
class _TopologyNode {
  _TopologyNode({
    required this.id,
    required this.stageIndex,
    required this.name,
    required this.subtitle,
    required this.category,
    required this.description,
    required this.color,
    required this.icon,
    required this.isOnline,
    required this.statusTag,
    required this.executionMs,
    required this.metrics,
    required this.details,
    required this.inputPayload,
    required this.outputPayload,
    required this.position,
    required this.size,
    required this.connectedNodeIds,
    this.hostname,
    this.ipAddress,
    this.appVersion,
    this.isOutdated = false,
    this.cashierName,
    this.branchName,
    this.branchCode,
    this.clientType,
    this.executionCount = 0,
    this.targetPortOffset = 0.5,
    this.floorNumber = 0,
    this.radialAngle = 0.0,
  });

  final String id;
  final int stageIndex; // 0: Devices, 1: Gateway, 2: Logic Engines, 3: Storage
  final String name;
  final String subtitle;
  final String category;
  final String description;
  final Color color;
  final IconData icon;
  final bool isOnline;
  final String statusTag;
  final int executionMs;
  final Map<String, String> metrics;
  final Map<String, dynamic> details;
  final Map<String, dynamic> inputPayload;
  final Map<String, dynamic> outputPayload;
  Offset position;
  final Size size;
  final List<String> connectedNodeIds;
  final String? hostname;
  final String? ipAddress;
  final String? appVersion;
  final bool isOutdated;
  final String? cashierName;
  final String? branchName;
  final String? branchCode;
  final String? clientType;
  int executionCount;
  final double targetPortOffset;
  final int floorNumber; // 0: Center, 1: Core Services Ring, 2: Primary Fleet Ring, 3: Extension Ring, 4: Mobile Ring
  final double radialAngle; // Angle in radians from center
}

/// Animated data packet traveling between nodes along radial curves.
class _DataPacket {
  _DataPacket({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.label,
    required this.color,
    required this.startedAt,
    required this.duration,
    this.targetPortOffset = 0.5,
  });

  final String id;
  final String sourceId;
  final String targetId;
  final String label;
  final Color color;
  final DateTime startedAt;
  final Duration duration;
  final double targetPortOffset;

  double progress(DateTime now) {
    final elapsed = now.difference(startedAt).inMilliseconds;
    return (elapsed / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  bool isFinished(DateTime now) => progress(now) >= 1.0;
}

/// The modernized, authentic n8n Live Operations and Fleet Network Screen.
/// Structured as a high-performance Concentric Circular Building Tower (عمارة الشبكة الدائرية).
class LiveOperationsTopologyScreen extends StatefulWidget {
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
  State<LiveOperationsTopologyScreen> createState() =>
      _LiveOperationsTopologyScreenState();
}

class _LiveOperationsTopologyScreenState
    extends State<LiveOperationsTopologyScreen>
    with TickerProviderStateMixin {
  _TopologyViewMode _viewMode = _TopologyViewMode.canvasWorkflow;

  late final TransformationController _transController;
  late final AnimationController _pulseController;
  late final AnimationController _flyAnimController;
  Animation<Matrix4>? _flyMatrixAnimation;

  Timer? _telemetryPulseTimer;
  Timer? _packetCleanerTimer;
  Timer? _simulationTimer;

  final List<_TopologyNode> _nodes = [];
  final Map<String, _TopologyNode> _nodesMap = {};
  final List<_DataPacket> _packets = [];
  final List<Map<String, dynamic>> _liveLogs = [];
  final List<_TopologyFloor> _floors = const [];

  // Simulation State
  bool _isSimulating = false;
  int _simulationActiveStage = -1;
  String _simulationMessage = '';
  int _simulationTotalMs = 0;

  // Selection & Inspector
  String? _selectedNodeId;
  int _inspectorTabIndex = 0; // 0: Details, 1: Parameters, 2: Event Log
  int _selectedFloorFilter = 0; // 0 = All floors, 1..4 = specific floor

  // Filters
  String _deviceFilter = 'all'; // 'all', 'online', 'outdated'
  final String _selectedBranchCode = 'all';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  bool _simulationRunning = true;
  bool _showConsole = false;

  double _canvasWidth = 2600;
  double _canvasHeight = 2600;

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

    // Refresh cached data gently if empty (avoid heavy simultaneous burst)
    if (widget.state.deploymentData == null) {
      widget.notifier.refreshDeployment();
    }
    if (widget.state.stats == null) {
      widget.notifier.refreshStats();
    }

    _buildTopologyMesh();
    _buildRealEventLog();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fitCanvasToScreen(animated: false);
      }
    });

    _startLiveTelemetryPulse();

    // Isolated packet cleaner timer (never mutate state in build()!)
    _packetCleanerTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (_packets.isNotEmpty) {
        final now = DateTime.now();
        _packets.removeWhere((p) => p.isFinished(now));
      }
    });
  }

  @override
  void didUpdateWidget(covariant LiveOperationsTopologyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.deploymentData != widget.state.deploymentData ||
        oldWidget.state.sessions != widget.state.sessions ||
        oldWidget.state.stats != widget.state.stats ||
        oldWidget.state.errors != widget.state.errors ||
        oldWidget.state.pollsData != widget.state.pollsData) {
      _buildTopologyMesh();
    }
  }

  @override
  void dispose() {
    _telemetryPulseTimer?.cancel();
    _packetCleanerTimer?.cancel();
    _simulationTimer?.cancel();
    _pulseController.dispose();
    _flyAnimController.dispose();
    _transController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // MESH BUILDER: CONCENTRIC CIRCULAR BUILDING TOWER (عمارة الشبكة الدائرية)
  // ══════════════════════════════════════════════════════════════════════════════
  void _buildTopologyMesh() {
    _nodes.clear();
    _nodesMap.clear();

    final stats = widget.state.stats;
    final telemetry = widget.state.requestTelemetry;
    final summary = widget.state.deploymentData?.summary;
    final targetVer = summary?.targetAppVersion ?? summary?.currentAppVersion ?? '1.1.22';

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
    final uptimeHours = stats != null ? (stats.uptimeSeconds / 3600).toStringAsFixed(1) : '24.0';

    final allBranches = widget.state.deploymentData?.branches ?? [];
    final allSessions = widget.state.sessions;

    // 1. Gather all actual physical and cashier devices across branches
    final rawDevices = <_DeviceModel>[];
    for (final branch in allBranches) {
      if (branch.devices.isNotEmpty) {
        for (final d in branch.devices) {
          rawDevices.add(_DeviceModel(
            id: 'dev_${branch.branchCode}_${d.hostname.replaceAll(RegExp(r"[^a-zA-Z0-9_]"), "_")}',
            hostname: d.hostname.trim().isNotEmpty ? d.hostname.trim() : 'كاشير-${branch.branchCode}',
            fullName: d.fullName.trim().isNotEmpty ? d.fullName.trim() : (d.username.trim().isNotEmpty ? d.username.trim() : 'كاشير الفرع'),
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
      } else {
        if (branch.installedUsers.isNotEmpty) {
          for (final u in branch.installedUsers) {
            rawDevices.add(_DeviceModel(
              id: 'dev_user_${branch.branchCode}_${u.username}',
              hostname: 'محطة ${u.fullName}',
              fullName: u.fullName,
              username: u.username,
              branchName: branch.branchName,
              branchCode: branch.branchCode,
              ipAddress: '192.168.${branch.branchCode}.15',
              appVersion: targetVer,
              isOutdated: false,
              isOnline: u.isOnline,
              clientType: 'desktop',
              os: 'Windows 11 Pro',
              lastSeenAt: u.lastActiveAt,
            ));
          }
        } else {
          rawDevices.add(_DeviceModel(
            id: 'branch_${branch.branchCode}',
            hostname: 'فرع ${branch.branchName}',
            fullName: 'نقطة ربط الفرع (كود ${branch.branchCode})',
            username: 'branch-${branch.branchCode}',
            branchName: branch.branchName,
            branchCode: branch.branchCode,
            ipAddress: '192.168.${branch.branchCode}.10',
            appVersion: targetVer,
            isOutdated: !branch.isInstalled,
            isOnline: branch.isInstalled,
            clientType: 'desktop',
            os: 'Windows POS Terminal',
            lastSeenAt: null,
          ));
        }
      }
    }

    // Include active online sessions not in branches list
    for (final s in allSessions) {
      final exists = rawDevices.any((d) => d.username == s.username);
      if (!exists && s.username.isNotEmpty) {
        rawDevices.add(_DeviceModel(
          id: 'session_${s.id}',
          hostname: s.fullName.trim().isNotEmpty ? s.fullName.trim() : s.username,
          fullName: s.fullName,
          username: s.username,
          branchName: s.jobTitleBranch ?? s.department ?? 'المقر العام',
          branchCode: '00',
          ipAddress: s.ipAddress ?? '127.0.0.1',
          appVersion: targetVer,
          isOutdated: false,
          isOnline: s.isOnline,
          clientType: s.clientType,
          os: s.clientType == 'mobile' ? 'Android / iOS' : 'Windows Desktop',
          lastSeenAt: s.lastSeenAt,
        ));
      }
    }

    // Demo safety fallback if database has zero branches
    if (rawDevices.isEmpty) {
      rawDevices.addAll([
        _DeviceModel(
          id: 'dev_demo_110_1',
          hostname: 'POS-HRM-01',
          fullName: 'كاشير 1 (الهرم)',
          username: 'cas-110-1',
          branchName: 'فرع الهرم',
          branchCode: '110',
          ipAddress: '192.168.110.15',
          appVersion: targetVer,
          isOutdated: false,
          isOnline: true,
          clientType: 'desktop',
          os: 'Windows 11 POS',
          lastSeenAt: DateTime.now(),
        ),
        _DeviceModel(
          id: 'dev_demo_110_2',
          hostname: 'POS-HRM-02',
          fullName: 'كاشير 2 (الهرم)',
          username: 'cas-110-2',
          branchName: 'فرع الهرم',
          branchCode: '110',
          ipAddress: '192.168.110.16',
          appVersion: targetVer,
          isOutdated: false,
          isOnline: true,
          clientType: 'desktop',
          os: 'Windows 11 POS',
          lastSeenAt: DateTime.now(),
        ),
        _DeviceModel(
          id: 'dev_demo_111',
          hostname: 'POS-DOKKI-01',
          fullName: 'كاشير 1 (الدقي)',
          username: 'cas-111-1',
          branchName: 'فرع الدقي',
          branchCode: '111',
          ipAddress: '192.168.111.18',
          appVersion: targetVer,
          isOutdated: false,
          isOnline: true,
          clientType: 'desktop',
          os: 'Windows 10 Pro',
          lastSeenAt: DateTime.now(),
        ),
        _DeviceModel(
          id: 'dev_demo_112',
          hostname: 'POS-NASR-01',
          fullName: 'كاشير مدينة نصر',
          username: 'cas-112-1',
          branchName: 'فرع مدينة نصر',
          branchCode: '112',
          ipAddress: '192.168.112.22',
          appVersion: '1.1.21',
          isOutdated: true,
          isOnline: true,
          clientType: 'desktop',
          os: 'Windows 10 POS',
          lastSeenAt: DateTime.now(),
        ),
        _DeviceModel(
          id: 'dev_demo_113',
          hostname: 'POS-ALEX-01',
          fullName: 'كاشير الإسكندرية',
          username: 'cas-113-1',
          branchName: 'فرع الإسكندرية',
          branchCode: '113',
          ipAddress: '192.168.113.12',
          appVersion: targetVer,
          isOutdated: false,
          isOnline: true,
          clientType: 'desktop',
          os: 'Windows 11 Pro',
          lastSeenAt: DateTime.now(),
        ),
        _DeviceModel(
          id: 'dev_demo_114',
          hostname: 'MOBILE-MGR',
          fullName: 'مدير العمليات (جوال)',
          username: 'mgr-ops',
          branchName: 'الإدارة العامة',
          branchCode: '00',
          ipAddress: '172.16.0.45',
          appVersion: targetVer,
          isOutdated: false,
          isOnline: true,
          clientType: 'mobile',
          os: 'Android 14',
          lastSeenAt: DateTime.now(),
        ),
      ]);
    }

    // 2. Filter devices according to user selection
    final filteredDevices = rawDevices.where((d) {
      if (_deviceFilter == 'online' && !d.isOnline) return false;
      if (_deviceFilter == 'outdated' && !d.isOutdated) return false;
      if (_selectedBranchCode != 'all' && d.branchCode != _selectedBranchCode) return false;
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

    // ── 3-TIER ENTERPRISE ARCHITECTURE: GATEWAY ➔ ENGINES ➔ BRANCH FLEETS ─────
    // 1. Group client devices cleanly by branch
    final Map<String, List<_DeviceModel>> branchGroups = {};
    for (final d in filteredDevices) {
      branchGroups.putIfAbsent(d.branchCode, () => []).add(d);
    }

    const engineCardW = 230.0;
    const engineCardH = 88.0;
    const engineGap = 20.0;
    const totalEnginesW = 6 * engineCardW + 5 * engineGap; // 1480.0

    const branchColW = 270.0;
    const branchColGap = 28.0;
    final branchCodes = branchGroups.keys.toList();
    final totalCols = math.max(branchCodes.length, 1);
    final totalBranchesW = totalCols * branchColW + (totalCols - 1) * branchColGap;

    _canvasWidth = math.max(math.max(totalEnginesW, totalBranchesW) + 160.0, 1600.0);

    int maxDevs = 1;
    for (final list in branchGroups.values) {
      if (list.length > maxDevs) maxDevs = list.length;
    }
    _canvasHeight = math.max(340.0 + (maxDevs * 104.0) + 120.0, 820.0);
    final centerX = _canvasWidth / 2.0;

    // ── STAGE 1: CENTRAL GATEWAY HUB (TOP CENTER) ──────────────────────────────
    const gatewayWidth = 360.0;
    const gatewayHeight = 110.0;
    final gatewayNode = _TopologyNode(
      id: 'node_gateway',
      stageIndex: 1,
      name: 'خادم المنظومة المركزي وبوابة الاتصال',
      subtitle: 'Express API & Socket.IO Cluster Hub',
      category: 'GATEWAY / ROUTER',
      description: 'استقبال وفحص طلبات الشبكة، التحقق من صلاحيات التوكن، وتوجيه حركة البيانات اللحظية للمحركات.',
      color: const Color(0xFF06B6D4), // Cyan
      icon: Icons.router_rounded,
      isOnline: true,
      statusTag: '$latency ms LATENCY',
      executionMs: latency > 0 ? latency : 5,
      metrics: {
        'معدل الطلبات': '$rps req/s',
        'زمن الاستجابة': '$latency ms',
        'العمليات الجارية': '$activeReqs طلب',
      },
      details: {
        'Gateway Host': stats?.hostname ?? 'iSmart-Production-Gateway',
        'Express Version': 'v4.x',
        'Socket.IO Cluster': 'Active',
        'Live Sockets': stats?.liveSocketsCount ?? filteredDevices.where((d) => d.isOnline).length,
      },
      inputPayload: {
        'headers': {'Authorization': 'Bearer eyJhbGciOi...'},
        'route': '/api/chat/messages',
        'method': 'POST',
      },
      outputPayload: {
        'authorized': true,
        'routedTo': 'chat_engine',
        'verificationTimeMs': 2,
      },
      position: Offset(centerX - gatewayWidth / 2.0, 36.0),
      size: const Size(gatewayWidth, gatewayHeight),
      connectedNodeIds: [
        'node_chat_engine',
        'node_doc_engine',
        'node_printer_engine',
        'node_release_engine',
      ],
      floorNumber: 1,
      radialAngle: 0.0,
    );
    _nodes.add(gatewayNode);

    // ── STAGE 2: CORE MICROSERVICES & STORAGE (HORIZONTAL BUS) ──────────────────
    final enginesStartX = centerX - (totalEnginesW / 2.0);
    const engineY = 190.0;

    final chatEngineNode = _TopologyNode(
      id: 'node_chat_engine',
      stageIndex: 2,
      name: 'محرك المحادثات والرسائل',
      subtitle: 'Real-time Messaging & Event Bus',
      category: 'CORE LOGIC',
      description: 'معالجة الرسائل، توزيع الإشعارات اللحظية، وتحديث مؤشرات القراءة.',
      color: const Color(0xFF6366F1), // Indigo
      icon: Icons.chat_bubble_outline_rounded,
      isOnline: true,
      statusTag: 'ONLINE',
      executionMs: 8,
      metrics: {
        'بيئة التشغيل': 'Node.js ${stats?.nodeVersion ?? "v22"}',
        'استهلاك الرام': '$memUsedGb / $memTotalGb GB',
        'التشغيل': '$uptimeHours ساعة',
      },
      details: {
        'Engine': 'iSmart Chat Orchestrator',
        'Node Version': stats?.nodeVersion ?? 'v22.x',
        'OS': '${stats?.osType ?? "Linux"} ${stats?.osRelease ?? ""}',
        'CPU Cores': '$cpuCores Cores',
      },
      inputPayload: {
        'conversationId': 'conv_9921',
        'sender': 'Cashier-POS',
        'text': 'طلب تحويل بضاعة للمستودع',
      },
      outputPayload: {
        'broadcastEvent': 'message:received',
        'dispatchStatus': 'delivered',
      },
      position: Offset(enginesStartX + 0 * (engineCardW + engineGap), engineY),
      size: const Size(engineCardW, engineCardH),
      connectedNodeIds: ['node_database'],
      floorNumber: 2,
      radialAngle: 0.0,
    );

    final docEngineNode = _TopologyNode(
      id: 'node_doc_engine',
      stageIndex: 2,
      name: 'محرك المستندات والطلبات',
      subtitle: 'Documents & Orders Pipeline',
      category: 'CORE LOGIC',
      description: 'معالجة تحويلات الفروع، فواتير الشراء، وأوامر الصرف مع تدقيق الصلاحيات.',
      color: const Color(0xFF8B5CF6), // Purple
      icon: Icons.inventory_2_outlined,
      isOnline: true,
      statusTag: 'HEALTHY',
      executionMs: 11,
      metrics: {
        'حالة النظام': 'مستقر 100%',
        'التزامن': 'فوري Realtime',
        'الأخطاء': '${stats?.unresolvedErrors ?? 0}',
      },
      details: {
        'Worker Type': 'Internal Event Bus',
        'Queue Latency': '< 1ms',
        'Batch Generator': 'Active',
      },
      inputPayload: {
        'operation': 'sync_branch_stock',
        'branchCode': '110',
        'itemsCount': 4,
      },
      outputPayload: {
        'persisted': true,
        'auditLogged': true,
      },
      position: Offset(enginesStartX + 1 * (engineCardW + engineGap), engineY),
      size: const Size(engineCardW, engineCardH),
      connectedNodeIds: ['node_database', 'node_storage'],
      floorNumber: 2,
      radialAngle: 0.0,
    );

    final printerEngineNode = _TopologyNode(
      id: 'node_printer_engine',
      stageIndex: 2,
      name: 'سيرفر الطباعة والفواتير',
      subtitle: 'Print Spooler & ESC/POS',
      category: 'CORE LOGIC',
      description: 'إدارة طابعات الباركود والإيصالات بالفروع وجدولة أوامر الطباعة.',
      color: const Color(0xFFEC4899), // Pink
      icon: Icons.print_rounded,
      isOnline: true,
      statusTag: 'READY',
      executionMs: 7,
      metrics: {
        'بروتوكول الطباعة': 'ESC/POS Network',
        'حالة الطابعات': 'جاهزة للطباعة',
        'زمن الإرسال': '4ms',
      },
      details: {
        'Driver Engine': 'Thermal Receipt & Barcode Spooler',
        'Spool Buffer': 'Active',
      },
      inputPayload: {'jobType': 'receipt', 'template': 'standard_80mm'},
      outputPayload: {'printed': true, 'latencyMs': 4},
      position: Offset(enginesStartX + 2 * (engineCardW + engineGap), engineY),
      size: const Size(engineCardW, engineCardH),
      connectedNodeIds: const [],
      floorNumber: 2,
      radialAngle: 0.0,
    );

    final releaseEngineNode = _TopologyNode(
      id: 'node_release_engine',
      stageIndex: 2,
      name: 'سيرفر التحديثات ونشر الحزم',
      subtitle: 'Auto-Update & Version Cache',
      category: 'CORE LOGIC',
      description: 'مقارنة إصدارات الأجهزة بالنسخة المعتمدة v$targetVer وتوفير التحديث التلقائي.',
      color: const Color(0xFFF59E0B), // Amber
      icon: Icons.system_update_alt_rounded,
      isOnline: true,
      statusTag: 'v$targetVer',
      executionMs: 6,
      metrics: {
        'الإصدار المعتمد': 'v$targetVer',
        'حزم التحديث': 'Windows / Android',
        'نظام النشر': 'Chunked Stream',
      },
      details: {
        'Target Release': 'v$targetVer',
        'Package Directory': '/data/ismart/releases',
      },
      inputPayload: {'checkVersion': 'v$targetVer'},
      outputPayload: {'hasUpdate': false},
      position: Offset(enginesStartX + 3 * (engineCardW + engineGap), engineY),
      size: const Size(engineCardW, engineCardH),
      connectedNodeIds: ['node_storage'],
      floorNumber: 2,
      radialAngle: 0.0,
    );

    final databaseNode = _TopologyNode(
      id: 'node_database',
      stageIndex: 3,
      name: 'عنقود قاعدة بيانات MongoDB',
      subtitle: 'Primary Cluster ReplicaSet',
      category: 'DATABASE',
      description: 'الحفظ الدائم لسجلات المحادثات، بيانات الفروع، الجلسات، والمستخدمين.',
      color: const Color(0xFF10B981), // Emerald
      icon: Icons.storage_rounded,
      isOnline: dbStatus == 'connected',
      statusTag: dbStatus == 'connected' ? 'CONNECTED' : dbStatus.toUpperCase(),
      executionMs: 14,
      metrics: {
        'الحالة': dbStatus == 'connected' ? 'متصل ومستقر' : dbStatus,
        'اسم القاعدة': dbName,
        'المضيف': dbHost,
      },
      details: {
        'Database Engine': 'MongoDB Enterprise Cluster',
        'Host': dbHost,
        'Total Users': stats?.totalUsers ?? 214,
        'Total Sessions': stats?.totalSessions ?? 86,
      },
      inputPayload: {
        'collection': 'messages',
        'action': 'insertOne',
      },
      outputPayload: {
        'acknowledged': true,
        'writeTimeMs': 3.2,
      },
      position: Offset(enginesStartX + 4 * (engineCardW + engineGap), engineY),
      size: const Size(engineCardW, engineCardH),
      connectedNodeIds: const [],
      floorNumber: 2,
      radialAngle: 0.0,
    );

    final storageNode = _TopologyNode(
      id: 'node_storage',
      stageIndex: 3,
      name: 'مستودع المرفقات والتخزين',
      subtitle: 'Local Storage & Release Cache',
      category: 'STORAGE',
      description: 'أرشفة المرفقات والصور، وحزم تحديثات البرنامج الجاهزة للنشر المباشر للفروع.',
      color: const Color(0xFF0284C7), // Blue
      icon: Icons.cloud_done_rounded,
      isOnline: true,
      statusTag: 'READY',
      executionMs: 6,
      metrics: {
        'الإصدار المعتمد': 'v$targetVer',
        'مجلد التحديثات': 'جاهز للمزامنة',
        'بروتوكول النقل': 'HTTP Chunked',
      },
      details: {
        'Storage Path': '/data/ismart/uploads',
        'Update Directory': '/data/ismart/releases',
        'Active Release': 'v$targetVer',
      },
      inputPayload: {'platform': 'windows', 'version': targetVer},
      outputPayload: {'status': 'ready'},
      position: Offset(enginesStartX + 5 * (engineCardW + engineGap), engineY),
      size: const Size(engineCardW, engineCardH),
      connectedNodeIds: const [],
      floorNumber: 2,
      radialAngle: 0.0,
    );

    _nodes.addAll([
      chatEngineNode,
      docEngineNode,
      printerEngineNode,
      releaseEngineNode,
      databaseNode,
      storageNode,
    ]);

    // ── STAGE 3: BRANCH WORKSTATIONS & POS FLEET (STRUCTURED COLUMNS) ───────────
    const cardWidth = 270.0;
    const cardHeight = 90.0;
    final branchesStartX = (centerX - (totalBranchesW / 2.0)).clamp(40.0, double.infinity);

    for (int col = 0; col < branchCodes.length; col++) {
      final bCode = branchCodes[col];
      final devList = branchGroups[bCode]!;
      final colX = branchesStartX + col * (branchColW + branchColGap);

      for (int row = 0; row < devList.length; row++) {
        final d = devList[row];
        final devY = 330.0 + (row * (cardHeight + 14.0));

        final devNode = _TopologyNode(
          id: d.id,
          stageIndex: 0,
          name: d.hostname,
          subtitle: '${d.fullName} • ${d.branchName}',
          category: d.clientType == 'mobile' ? 'تطبيق جوال' : 'محطة كاشير POS',
          description: 'محطة عمل بـ ${d.branchName} • عنوان IP: ${d.ipAddress} • نظام: ${d.os}',
          color: d.isOnline ? const Color(0xFFFF6D5A) : const Color(0xFF64748B), // Coral
          icon: d.clientType == 'mobile' ? Icons.smartphone_rounded : Icons.desktop_windows_rounded,
          isOnline: d.isOnline,
          statusTag: d.isOnline ? 'ONLINE' : 'OFFLINE',
          executionMs: d.isOnline ? (math.Random().nextInt(8) + 6) : 0,
          appVersion: d.appVersion,
          isOutdated: d.isOutdated,
          ipAddress: d.ipAddress,
          hostname: d.hostname,
          cashierName: d.fullName,
          branchName: d.branchName,
          branchCode: d.branchCode,
          clientType: d.clientType,
          floorNumber: 3,
          radialAngle: 0.0,
          metrics: {
            'الموظف': d.fullName,
            'الفرع': d.branchName,
            'عنوان IP': d.ipAddress,
            'الإصدار': 'v${d.appVersion}',
            'الحالة': d.isOnline ? 'متصل ومستقر' : 'غير متصل',
          },
          details: {
            'Device Hostname': d.hostname,
            'Cashier Name': d.fullName,
            'Username': d.username,
            'Branch': d.branchName,
            'IP Address': d.ipAddress,
            'App Version': 'v${d.appVersion}',
            'Target Version': 'v$targetVer',
            'OS Platform': d.os,
          },
          inputPayload: {
            'device': d.hostname,
            'branchCode': d.branchCode,
            'clientType': d.clientType,
            'ping': 'heartbeat',
          },
          outputPayload: {
            'connected': d.isOnline,
            'status': d.isOnline ? 'active' : 'idle',
          },
          position: Offset(colX, devY),
          size: const Size(cardWidth, cardHeight),
          connectedNodeIds: ['node_gateway'],
        );

        _nodes.add(devNode);
      }
    }

    for (final n in _nodes) {
      _nodesMap[n.id] = n;
    }
  }

  void _buildRealEventLog() {
    _liveLogs.clear();
    final now = DateTime.now();

    _liveLogs.add({
      'time': _formatTime(now.subtract(const Duration(seconds: 1))),
      'level': 'SUCCESS',
      'source': 'Gateway',
      'message': 'Express Router: Socket.IO heartbeat acknowledged across concentric branch floors.',
    });
    _liveLogs.add({
      'time': _formatTime(now.subtract(const Duration(seconds: 3))),
      'level': 'INFO',
      'source': 'ChatEngine',
      'message': 'Realtime message broadcast synchronized across active cashier sessions.',
    });
    _liveLogs.add({
      'time': _formatTime(now.subtract(const Duration(seconds: 7))),
      'level': 'SUCCESS',
      'source': 'MongoDB',
      'message': 'ReplicaSet health verified: 0 write errors, avg query 3.2ms.',
    });
    _liveLogs.add({
      'time': _formatTime(now.subtract(const Duration(seconds: 11))),
      'level': 'INFO',
      'source': 'ReleaseHub',
      'message': 'Target app version verified against branch workstation registry.',
    });
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  void _startLiveTelemetryPulse() {
    _telemetryPulseTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!_simulationRunning || !mounted) return;
      if (_viewMode == _TopologyViewMode.canvasWorkflow) {
        _triggerFlowPacket();
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // DYNAMIC PACKET GENERATION (Zero UI stutter, completely isolated)
  // ══════════════════════════════════════════════════════════════════════════════
  void _triggerFlowPacket({_TopologyNode? specificDev}) {
    final now = DateTime.now();
    final onlineDevs = _nodes.where((n) => n.stageIndex == 0 && n.isOnline).toList();
    if (onlineDevs.isEmpty && specificDev == null) return;

    final dev = specificDev ?? onlineDevs[math.Random().nextInt(onlineDevs.length)];

    final actions = [
      (label: '💬 رسالة كاشير', color: const Color(0xFFFF6D5A), targetEngine: 'node_chat_engine', toDb: true, desc: 'إرسال رسالة محادثة'),
      (label: '⚡ نبضة اتصال', color: const Color(0xFF06B6D4), targetEngine: null, toDb: false, desc: 'نبضة اتصال وتأكيد حالة (Socket Heartbeat)'),
      (label: '🖨️ أمر طباعة', color: const Color(0xFFEC4899), targetEngine: 'node_printer_engine', toDb: false, desc: 'أمر طباعة فاتورة'),
      (label: '🧾 مزامنة فاتورة', color: const Color(0xFF8B5CF6), targetEngine: 'node_doc_engine', toDb: true, desc: 'مزامنة مستندات وطلبات'),
      (label: '📦 فحص نسخة', color: const Color(0xFFF59E0B), targetEngine: 'node_release_engine', toDb: false, desc: 'فحص إصدار البرنامج'),
    ];

    final act = actions[math.Random().nextInt(actions.length)];

    // 1. Packet from Device to Central Gateway
    final pkt1Id = 'pkt_${DateTime.now().microsecondsSinceEpoch}';
    _packets.add(_DataPacket(
      id: pkt1Id,
      sourceId: dev.id,
      targetId: 'node_gateway',
      label: act.label,
      color: act.color,
      startedAt: now,
      duration: const Duration(milliseconds: 850),
    ));

    // 2. Secondary packet from Gateway to Engine
    if (act.targetEngine != null) {
      Timer(const Duration(milliseconds: 850), () {
        if (!mounted) return;
        final pkt2Id = 'pkt_eng_${DateTime.now().microsecondsSinceEpoch}';
        _packets.add(_DataPacket(
          id: pkt2Id,
          sourceId: 'node_gateway',
          targetId: act.targetEngine!,
          label: act.label,
          color: act.color,
          startedAt: DateTime.now(),
          duration: const Duration(milliseconds: 700),
        ));

        // 3. Third packet to Database if applicable
        if (act.toDb) {
          Timer(const Duration(milliseconds: 700), () {
            if (!mounted) return;
            _packets.add(_DataPacket(
              id: 'pkt_db_${DateTime.now().microsecondsSinceEpoch}',
              sourceId: act.targetEngine!,
              targetId: 'node_database',
              label: '💾 حفظ MongoDB',
              color: const Color(0xFF10B981),
              startedAt: DateTime.now(),
              duration: const Duration(milliseconds: 600),
            ));
          });
        }
      });
    }

    dev.executionCount++;
    final gateway = _nodesMap['node_gateway'];
    if (gateway != null) gateway.executionCount++;

    final timeStr = _formatTime(now);
    _liveLogs.insert(0, {
      'time': timeStr,
      'level': 'SUCCESS',
      'source': dev.name,
      'message': '${act.label} من ${dev.name} (الدور ${dev.floorNumber}) ➔ السيرفر المركزي ${act.targetEngine != null ? "➔ " + act.desc : ""} [200 OK - ${dev.executionMs}ms]',
    });
    if (_liveLogs.length > 60) {
      _liveLogs.removeLast();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // SIMULATED END-TO-END WORKFLOW EXECUTION
  // ══════════════════════════════════════════════════════════════════════════════
  void _executeWorkflowSimulation() {
    if (_isSimulating) return;

    HapticFeedback.heavyImpact();
    _simulationTimer?.cancel();

    final onlineDevs = _nodes.where((n) => n.stageIndex == 0 && n.isOnline).toList();
    final leadDev = onlineDevs.isNotEmpty ? onlineDevs.first : (_nodes.isNotEmpty ? _nodes.first : null);
    final devName = leadDev?.name ?? 'محطة الكاشير';

    setState(() {
      _isSimulating = true;
      _simulationActiveStage = 0;
      _simulationTotalMs = 0;
      _simulationMessage = 'المرحلة 1: انطلاق الطلب الميداني من جهاز $devName...';
    });

    final stageDescriptions = [
      'المرحلة 1: انطلاق طلب الإرسال من جهاز $devName (Client Ingress)',
      'المرحلة 2: استقبال وفحص الطلب وتوثيق التوكن في السيرفر المركزي (Express Gateway)',
      'المرحلة 3: معالجة منطق الرسالة وتجهيز البث اللحظي (Chat Engine Core)',
      'المرحلة 4: الحفظ الدائم للرسالة وتحديث العدادات في قاعدة بيانات (MongoDB Persistence)',
      'المرحلة 5: استلام وتأكيد وصول البيانات لجميع أجهزة ومحطات الفروع (Branch Fleet Delivery)',
    ];

    final stageLatencies = [4, 7, 9, 13, 8];

    int step = 0;
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      step++;
      if (step < 5) {
        setState(() {
          _simulationActiveStage = step;
          _simulationTotalMs += stageLatencies[step - 1];
          _simulationMessage = stageDescriptions[step];
        });

        if (step == 1 && leadDev != null) {
          _triggerDirectPacket(leadDev.id, 'node_gateway', '⚡ API Req', const Color(0xFFFF6D5A));
        } else if (step == 2) {
          _triggerDirectPacket('node_gateway', 'node_chat_engine', '💬 Logic Dispatch', const Color(0xFF06B6D4));
        } else if (step == 3) {
          _triggerDirectPacket('node_chat_engine', 'node_database', '💾 DB Write', const Color(0xFF10B981));
        } else if (step == 4 && leadDev != null) {
          _triggerDirectPacket('node_database', leadDev.id, '🏢 Push Confirm', const Color(0xFF38BDF8));
        }
      } else {
        timer.cancel();
        _simulationTotalMs += stageLatencies[4];
        setState(() {
          _isSimulating = false;
          _simulationActiveStage = -1;
          _simulationMessage = '✅ اكتمل مسار العمليات بنجاح خلال ${_simulationTotalMs}ms • كافة أجهزة وفروع المنظومة متصلة بنجاح!';
        });

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
                    'اكتمل مسار الحركة بنجاح (${_simulationTotalMs}ms) — تم فحص وتأكيد جاهزية شبكة الأجهزة بالكامل.',
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

  void _triggerDirectPacket(String fromId, String toId, String label, Color color) {
    _packets.add(_DataPacket(
      id: 'pkt_dir_${DateTime.now().microsecondsSinceEpoch}',
      sourceId: fromId,
      targetId: toId,
      label: label,
      color: color,
      startedAt: DateTime.now(),
      duration: const Duration(milliseconds: 600),
    ));
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // RESPONSIVE CANVAS AUTO-FIT & ZOOM (Fits Concentric Tower Perfectly)
  // ══════════════════════════════════════════════════════════════════════════════
  void _fitCanvasToScreen({bool animated = true}) {
    final mediaSize = MediaQuery.of(context).size;
    final availableWidth = mediaSize.width - (_selectedNodeId != null && mediaSize.width >= 1150 ? 380 : 0);
    final availableHeight = mediaSize.height - 130;

    final scaleW = availableWidth / _canvasWidth;
    final scaleH = availableHeight / _canvasHeight;
    final scale = (math.min(scaleW, scaleH) * 0.94).clamp(0.24, 1.15);

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
    final mediaSize = MediaQuery.of(context).size;
    final center = Offset(mediaSize.width / 2, mediaSize.height / 2);

    final newMatrix = curMatrix.clone()
      ..translate(center.dx, center.dy)
      ..scale(factor)
      ..translate(-center.dx, -center.dy);

    _transController.value = newMatrix;
  }

  void _resetZoom() {
    _fitCanvasToScreen(animated: true);
  }

  void _flyToNode(String nodeId) {
    final node = _nodesMap[nodeId];
    if (node == null) return;

    final mediaSize = MediaQuery.of(context).size;
    const targetScale = 0.95;
    final targetX = -(node.position.dx + node.size.width / 2) * targetScale + (mediaSize.width / 2);
    final targetY = -(node.position.dy + node.size.height / 2) * targetScale + (mediaSize.height / 2);

    final endMatrix = Matrix4.identity()
      ..translate(targetX, targetY)
      ..scale(targetScale);

    _flyMatrixAnimation = Matrix4Tween(
      begin: _transController.value,
      end: endMatrix,
    ).animate(CurvedAnimation(
      parent: _flyAnimController,
      curve: Curves.easeOutCubic,
    ));

    _flyAnimController.forward(from: 0.0);
    setState(() => _selectedNodeId = nodeId);
  }

  void _flyToFloor(int floorNum) {
    setState(() => _selectedFloorFilter = floorNum);
    if (floorNum == 0) {
      _fitCanvasToScreen(animated: true);
      return;
    }

    final floor = _floors.firstWhere((f) => f.floorNumber == floorNum, orElse: () => _floors.first);
    final mediaSize = MediaQuery.of(context).size;
    final centerX = _canvasWidth / 2.0;
    final centerY = _canvasHeight / 2.0;

    final targetScale = (math.min(mediaSize.width, mediaSize.height) / (floor.radius * 2.3)).clamp(0.35, 1.2);
    final targetX = -centerX * targetScale + (mediaSize.width / 2);
    final targetY = -centerY * targetScale + (mediaSize.height / 2);

    final endMatrix = Matrix4.identity()
      ..translate(targetX, targetY)
      ..scale(targetScale);

    _flyMatrixAnimation = Matrix4Tween(
      begin: _transController.value,
      end: endMatrix,
    ).animate(CurvedAnimation(
      parent: _flyAnimController,
      curve: Curves.easeOutCubic,
    ));

    _flyAnimController.forward(from: 0.0);
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // MAIN BUILD METHOD
  // ══════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F1118) : const Color(0xFFF8FAFC),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWideScreen = constraints.maxWidth >= 1150;

              return Column(
                children: [
                  // 1. TOP RESPONSIVE HEADER & TOOLBAR
                  _buildResponsiveTopHeader(constraints, isDark),

                  // 2. SIMULATION ACTIVE BANNER
                  if (_isSimulating || _simulationMessage.isNotEmpty)
                    _buildSimulationBanner(isDark),

                  // 3. MAIN WORKSPACE AREA
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Main Viewport
                        Expanded(
                          child: Stack(
                            children: [
                              if (_viewMode == _TopologyViewMode.canvasWorkflow)
                                _buildN8nCanvasView(isDark)
                              else if (_viewMode == _TopologyViewMode.responsivePipeline)
                                _buildResponsivePipelineView(constraints, isDark)
                              else
                                _buildBranchFleetGridView(constraints, isDark),

                              // Bottom Floating Navigation HUD (in Canvas View)
                              if (_viewMode == _TopologyViewMode.canvasWorkflow)
                                Positioned(
                                  left: 20,
                                  bottom: _showConsole ? 220 : 20,
                                  child: _buildFloatingControls(isDark),
                                ),

                              // Bottom Live Movement Ticker & Terminal Console
                              Positioned(
                                bottom: 16,
                                left: _viewMode == _TopologyViewMode.canvasWorkflow ? 320 : 16,
                                right: 16,
                                child: _buildBottomConsole(isDark),
                              ),
                            ],
                          ),
                        ),

                        // Inspector Panel (Docked on wide screens)
                        if (_selectedNodeId != null && isWideScreen)
                          SizedBox(
                            width: 380,
                            child: _buildInspectorPanel(isDark, isDocked: true),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // Modal drawer for smaller screens
        endDrawer: _selectedNodeId != null && MediaQuery.of(context).size.width < 1150
            ? Drawer(
                width: 380,
                child: _buildInspectorPanel(isDark, isDocked: false),
              )
            : null,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // 1. RESPONSIVE TOP HEADER & ACTION BAR
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildResponsiveTopHeader(BoxConstraints constraints, bool isDark) {
    final isCompact = constraints.maxWidth < 980;

    final allDevsCount = _nodes.where((n) => n.stageIndex == 0).length;
    final onlineDevsCount = _nodes.where((n) => n.stageIndex == 0 && n.isOnline).length;
    final outdatedDevsCount = _nodes.where((n) => n.stageIndex == 0 && n.isOutdated).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _buildBackBtn(isDark),
                    const SizedBox(width: 10),
                    Expanded(child: _buildTitleBlock(isDark)),
                    _buildExecuteWorkflowBtn(),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildModeSelector(isDark),
                      const SizedBox(width: 8),
                      _buildFilterChips(allDevsCount, onlineDevsCount, outdatedDevsCount, isDark),
                      const SizedBox(width: 8),
                      _buildSearchField(isDark, width: 170),
                    ],
                  ),
                ),
              ],
            )
          : Row(
              children: [
                _buildBackBtn(isDark),
                const SizedBox(width: 12),
                _buildTitleBlock(isDark),
                const Spacer(),
                _buildFilterChips(allDevsCount, onlineDevsCount, outdatedDevsCount, isDark),
                const SizedBox(width: 10),
                _buildModeSelector(isDark),
                const SizedBox(width: 10),
                _buildSearchField(isDark, width: 190),
                const SizedBox(width: 10),
                _buildExecuteWorkflowBtn(),
              ],
            ),
    );
  }

  Widget _buildBackBtn(bool isDark) {
    return IconButton(
      icon: const Icon(Icons.arrow_forward_rounded, size: 20),
      tooltip: 'العودة للمراقبة',
      onPressed: () => Navigator.of(context).pop(),
      style: IconButton.styleFrom(
        backgroundColor: isDark ? const Color(0xFF1E2536) : const Color(0xFFF1F5F9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildTitleBlock(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6D5A).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.hub_rounded, size: 16, color: Color(0xFFFF6D5A)),
            ),
            const SizedBox(width: 8),
            const Text(
              'خريطة العمارة والشبكة الدائرية للأجهزة',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '● n8n CIRCULAR TOWER',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                  color: Color(0xFF10B981),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'توزيع دائري معماري للأجهزة بنظام الأدوار: السيرفر بالمركز وحوله الفروع وقواعد البيانات',
          style: TextStyle(
            fontSize: 10.5,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips(int all, int online, int outdated, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _filterChip(
          id: 'all',
          label: 'كافة الأجهزة ($all)',
          color: const Color(0xFF6366F1),
          isDark: isDark,
        ),
        const SizedBox(width: 6),
        _filterChip(
          id: 'online',
          label: 'متصل ($online)',
          color: const Color(0xFF10B981),
          isDark: isDark,
        ),
        const SizedBox(width: 6),
        _filterChip(
          id: 'outdated',
          label: 'بحاجة لتحديث ($outdated)',
          color: const Color(0xFFEF4444),
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _filterChip({
    required String id,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    final isSelected = _deviceFilter == id;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _deviceFilter = id;
          _buildTopologyMesh();
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.16)
              : (isDark ? const Color(0xFF1E2536) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? color : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0E1118) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: isDark ? const Color(0xFF222938) : const Color(0xFFCBD5E1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modePill(
            mode: _TopologyViewMode.canvasWorkflow,
            label: '🏢 عمارة الشبكة الدائرية',
            icon: Icons.donut_large_rounded,
            isDark: isDark,
          ),
          const SizedBox(width: 3),
          _modePill(
            mode: _TopologyViewMode.responsivePipeline,
            label: '⚡ مسار العمليات',
            icon: Icons.view_timeline_rounded,
            isDark: isDark,
          ),
          const SizedBox(width: 3),
          _modePill(
            mode: _TopologyViewMode.branchFleet,
            label: '🏢 جدول الأجهزة',
            icon: Icons.storefront_rounded,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _modePill({
    required _TopologyViewMode mode,
    required String label,
    required IconData icon,
    required bool isDark,
  }) {
    final isSelected = _viewMode == mode;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _viewMode = mode);
        if (mode == _TopologyViewMode.canvasWorkflow) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitCanvasToScreen());
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF1E2536) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected
                  ? const Color(0xFFFF6D5A)
                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
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

  Widget _buildSearchField(bool isDark, {required double width}) {
    return SizedBox(
      width: width,
      height: 34,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (val) {
          setState(() {
            _searchQuery = val.trim();
            _buildTopologyMesh();
          });
        },
        style: TextStyle(
          fontSize: 11.5,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          hintText: 'بحث بالجهاز أو الفرع...',
          hintStyle: TextStyle(
            fontSize: 11,
            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 15),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 14),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {
                      _searchQuery = '';
                      _buildTopologyMesh();
                    });
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          filled: true,
          fillColor: isDark ? const Color(0xFF0E1118) : const Color(0xFFF1F5F9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExecuteWorkflowBtn() {
    return FilledButton.icon(
      onPressed: _isSimulating ? null : _executeWorkflowSimulation,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFFF6D5A), // n8n signature Coral
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: _isSimulating
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : const Icon(Icons.play_arrow_rounded, size: 17),
      label: Text(
        _isSimulating ? 'جارٍ محاكاة الحركة...' : '⚡ محاكاة حركة حية',
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // 2. SIMULATION ACTIVE BANNER
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildSimulationBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _isSimulating
            ? const Color(0xFFFF6D5A).withValues(alpha: 0.12)
            : const Color(0xFF10B981).withValues(alpha: 0.12),
        border: Border(
          bottom: BorderSide(
            color: _isSimulating
                ? const Color(0xFFFF6D5A).withValues(alpha: 0.3)
                : const Color(0xFF10B981).withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isSimulating ? Icons.bolt_rounded : Icons.check_circle_rounded,
            size: 16,
            color: _isSimulating ? const Color(0xFFFF6D5A) : const Color(0xFF10B981),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _simulationMessage,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _isSimulating
                    ? (isDark ? const Color(0xFFFF8B7A) : const Color(0xFFC2410C))
                    : const Color(0xFF10B981),
              ),
            ),
          ),
          if (_isSimulating)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6D5A),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'المرحلة ${_simulationActiveStage + 1} من 5',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // VIEW 1: CONCENTRIC CIRCULAR BUILDING TOWER CANVAS VIEW (الخريطة الدائرية)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildN8nCanvasView(bool isDark) {
    final center = Offset(_canvasWidth / 2.0, _canvasHeight / 2.0);

    return InteractiveViewer(
      transformationController: _transController,
      constrained: false,
      boundaryMargin: const EdgeInsets.all(900),
      minScale: 0.22,
      maxScale: 2.5,
      child: SizedBox(
        width: _canvasWidth,
        height: _canvasHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Layer A: Static Grid & Building Floor Orbit Rings (GPU Cached)
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size(_canvasWidth, _canvasHeight),
                  painter: _N8nStaticFloorGridPainter(
                    center: center,
                    floors: _floors,
                    isDark: isDark,
                  ),
                ),
              ),
            ),

            // Layer B: Radial Connection Wires (GPU Cached)
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size(_canvasWidth, _canvasHeight),
                  painter: _N8nRadialWiresPainter(
                    nodes: _nodes,
                    nodesMap: _nodesMap,
                    selectedNodeId: _selectedNodeId,
                    isDark: isDark,
                  ),
                ),
              ),
            ),

            // Layer C: Animated Flowing Packets (Only this lightweight layer animates!)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return CustomPaint(
                    size: Size(_canvasWidth, _canvasHeight),
                    painter: _N8nRadialPacketsPainter(
                      packets: _packets,
                      nodesMap: _nodesMap,
                      now: DateTime.now(),
                    ),
                  );
                },
              ),
            ),

            // Layer D: Building Hub Node Cards (Center Server, Engines, Concentric Floors)
            ..._nodes.map((node) {
              final isSelected = _selectedNodeId == node.id;
              final isSimActive = _isSimulating && _simulationActiveStage == node.stageIndex;

              return Positioned(
                left: node.position.dx,
                top: node.position.dy,
                child: _buildN8nCanvasNodeCard(node, isSelected, isSimActive, isDark),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildN8nCanvasNodeCard(
    _TopologyNode node,
    bool isSelected,
    bool isSimActive,
    bool isDark,
  ) {
    final isDevice = node.stageIndex == 0;
    final isCentralGateway = node.id == 'node_gateway';

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedNodeId = node.id;
          _inspectorTabIndex = 0;
        });
        if (MediaQuery.of(context).size.width < 1150) {
          Scaffold.of(context).openEndDrawer();
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: node.size.width,
        height: node.size.height,
        decoration: BoxDecoration(
          color: isCentralGateway
              ? (isDark ? const Color(0xFF0F1E2E) : const Color(0xFFF0FDF4))
              : (isDark ? const Color(0xFF161B26) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSimActive
                ? const Color(0xFFFF6D5A)
                : (isSelected
                    ? node.color
                    : (isCentralGateway
                        ? const Color(0xFF06B6D4)
                        : (isDark ? const Color(0xFF283144) : const Color(0xFFE2E8F0)))),
            width: isSelected || isSimActive ? 2.5 : (isCentralGateway ? 2.0 : 1.3),
          ),
          boxShadow: [
            BoxShadow(
              color: isSimActive
                  ? const Color(0xFFFF6D5A).withValues(alpha: 0.35)
                  : (isSelected
                      ? node.color.withValues(alpha: 0.35)
                      : (isCentralGateway
                          ? const Color(0xFF06B6D4).withValues(alpha: isDark ? 0.3 : 0.15)
                          : Colors.black.withValues(alpha: isDark ? 0.3 : 0.05))),
              blurRadius: isSelected || isSimActive || isCentralGateway ? 18 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Floor Level Badge (for branch devices)
            if (node.floorNumber > 0)
              Positioned(
                top: -8,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: node.color.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'الدور ${node.floorNumber}',
                    style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),

            // Execution Counter Badge (Top-Left)
            if (node.executionCount > 0)
              Positioned(
                top: -9,
                left: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.45),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_rounded, color: Colors.white, size: 10),
                      const SizedBox(width: 3),
                      Text(
                        'x${node.executionCount}',
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

            // Card Interior Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top Row: Squircle Icon + Category Pill
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: node.color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: node.color.withValues(alpha: 0.40)),
                        ),
                        child: Icon(node.icon, color: node.color, size: 19),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    node.name,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: node.color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    node.category,
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      color: node.color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              node.subtitle,
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

                  // Bottom Row: Status Dot + Version + IP / Execution Ms + Quick Trigger
                  Row(
                    children: [
                      // Status Dot & Label
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: node.isOnline
                              ? const Color(0xFF10B981).withValues(alpha: 0.12)
                              : Colors.grey.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: node.isOnline ? const Color(0xFF10B981) : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              node.statusTag,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: node.isOnline ? const Color(0xFF10B981) : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (node.appVersion != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: node.isOutdated
                                ? const Color(0xFFF59E0B).withValues(alpha: 0.14)
                                : const Color(0xFF10B981).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            node.isOutdated ? 'v${node.appVersion} ⚠️' : 'v${node.appVersion} ✓',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: node.isOutdated ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],

                      const Spacer(),

                      // Quick Action Test Button on Devices
                      if (isDevice && node.isOnline)
                        InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _triggerFlowPacket(specificDev: node);
                          },
                          borderRadius: BorderRadius.circular(5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6D5A).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFFFF6D5A).withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.send_rounded, size: 10, color: Color(0xFFFF6D5A)),
                                SizedBox(width: 3),
                                Text(
                                  'إرسال حركة',
                                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: Color(0xFFFF6D5A)),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (node.ipAddress != null && node.ipAddress != '-')
                        Text(
                          node.ipAddress!,
                          style: TextStyle(
                            fontSize: 9,
                            fontFamily: 'monospace',
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          ),
                        )
                      else if (node.executionMs > 0)
                        Text(
                          '${node.executionMs}ms',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: node.color,
                          ),
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
  // VIEW 2: RESPONSIVE 5-STAGE PIPELINE BOARD
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildResponsivePipelineView(BoxConstraints constraints, bool isDark) {
    final stages = [
      (
        index: 0,
        title: 'المرحلة 01: محطات العملاء والكاشيرات',
        sub: 'Workstations Fleet & Triggers',
        color: const Color(0xFFFF6D5A),
        icon: Icons.devices_rounded,
        nodes: _nodes.where((n) => n.stageIndex == 0).toList(),
      ),
      (
        index: 1,
        title: 'المرحلة 02: بوابة الاتصال اللحظي',
        sub: 'API Gateway & WebSockets',
        color: const Color(0xFF06B6D4),
        icon: Icons.router_rounded,
        nodes: _nodes.where((n) => n.stageIndex == 1).toList(),
      ),
      (
        index: 2,
        title: 'المرحلة 03: محركات المعالجة والمنطق',
        sub: 'Core Chat & Business Engines',
        color: const Color(0xFF6366F1),
        icon: Icons.memory_rounded,
        nodes: _nodes.where((n) => n.stageIndex == 2).toList(),
      ),
      (
        index: 3,
        title: 'المرحلة 04: قواعد البيانات والتخزين',
        sub: 'MongoDB & Cloud Volume',
        color: const Color(0xFF10B981),
        icon: Icons.storage_rounded,
        nodes: _nodes.where((n) => n.stageIndex == 3).toList(),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final stg in stages) ...[
            _buildPipelineStageSection(stg, isDark),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildPipelineStageSection(
    ({
      int index,
      String title,
      String sub,
      Color color,
      IconData icon,
      List<_TopologyNode> nodes,
    }) stage,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: stage.color.withValues(alpha: isDark ? 0.12 : 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(
                bottom: BorderSide(
                  color: stage.color.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(stage.icon, color: stage.color, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stage.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        stage.sub,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: stage.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${stage.nodes.length} عقدة',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: stage.color),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: stage.nodes.map((node) {
                final isSelected = _selectedNodeId == node.id;
                return SizedBox(
                  width: 280,
                  height: 96,
                  child: _buildN8nCanvasNodeCard(node, isSelected, false, isDark),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // VIEW 3: BRANCH FLEET GRID VIEW
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildBranchFleetGridView(BoxConstraints constraints, bool isDark) {
    final devNodes = _nodes.where((n) => n.stageIndex == 0).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: devNodes.map((node) {
              final isSelected = _selectedNodeId == node.id;
              return SizedBox(
                width: 280,
                height: 96,
                child: _buildN8nCanvasNodeCard(node, isSelected, false, isDark),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // FLOATING CANVAS CONTROLS (Zoom, Fit, Floor Switcher)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildFloatingControls(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Floor Quick Switcher Pills
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _floorQuickPill(0, '🌐 كامل المنظومة', isDark),
              const SizedBox(width: 4),
              for (final fl in _floors) ...[
                _floorQuickPill(fl.floorNumber, fl.floorNumber == 1 ? 'بوابة الاتصال' : (fl.floorNumber == 2 ? 'المحركات' : 'الفروع'), isDark),
                const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // Zoom & Fit Buttons
          Row(
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
                tooltip: 'ملاءمة البرج الدائري',
                onPressed: () => _fitCanvasToScreen(),
              ),
              IconButton(
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                tooltip: 'إعادة الضبط',
                onPressed: () => _resetZoom(),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  _simulationRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 18,
                  color: _simulationRunning ? const Color(0xFF10B981) : Colors.grey,
                ),
                tooltip: _simulationRunning ? 'إيقاف النبض التلقائي' : 'تشغيل النبض التلقائي',
                onPressed: () {
                  setState(() => _simulationRunning = !_simulationRunning);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _floorQuickPill(int floorNum, String label, bool isDark) {
    final isSelected = _selectedFloorFilter == floorNum;
    return InkWell(
      onTap: () => _flyToFloor(floorNum),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF6D5A).withValues(alpha: 0.20)
              : (isDark ? const Color(0xFF1E2536) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF6D5A) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? const Color(0xFFFF6D5A) : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // BOTTOM TELEMETRY CONSOLE & ACTIVITY TICKER
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildBottomConsole(bool isDark) {
    final latestLog = _liveLogs.isNotEmpty ? _liveLogs.first : null;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ticker Header
          InkWell(
            onTap: () => setState(() => _showConsole = !_showConsole),
            borderRadius: BorderRadius.circular(11),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                    'سجل الحركة الحية والنبض اللحظي',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 12),
                  if (latestLog != null)
                    Expanded(
                      child: Text(
                        '[${latestLog['time']}] ${latestLog['message']}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Icon(
                    _showConsole ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                    size: 18,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ],
              ),
            ),
          ),

          // Expanded Terminal View
          if (_showConsole)
            Container(
              height: 180,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0C0E14) : const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
              ),
              child: ListView.builder(
                itemCount: _liveLogs.length,
                itemBuilder: (context, idx) {
                  final log = _liveLogs[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '[${log['time']}] ',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: log['level'] == 'SUCCESS'
                                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                : const Color(0xFF3B82F6).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            log['source'],
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              color: log['level'] == 'SUCCESS'
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF3B82F6),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            log['message'],
                            style: TextStyle(
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF1E293B),
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
  // INSPECTOR PANEL (Docked / Drawer)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildInspectorPanel(bool isDark, {required bool isDocked}) {
    final node = _selectedNodeId != null ? _nodesMap[_selectedNodeId!] : null;
    if (node == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
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
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: node.color.withValues(alpha: isDark ? 0.14 : 0.08),
              border: Border(
                bottom: BorderSide(
                  color: node.color.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: node.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(node.icon, color: node.color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        node.category,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: node.color,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => _selectedNodeId = null),
                ),
              ],
            ),
          ),

          // Tabs Switcher
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0C0E14) : const Color(0xFFF1F5F9),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                _tabPill(0, 'التفاصيل', isDark),
                const SizedBox(width: 4),
                _tabPill(1, 'المعاملات', isDark),
                const SizedBox(width: 4),
                _tabPill(2, 'سجل الحركات', isDark),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_inspectorTabIndex == 0) ...[
                  Text(
                    node.description,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'القياسات التشغيلية الحية',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...node.metrics.entries.map((e) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E2536) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? const Color(0xFF2B354A) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            e.key,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            e.value,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ] else if (_inspectorTabIndex == 1) ...[
                  Text(
                    'المعاملات والبيانات التقنية',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...node.details.entries.map((e) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1A1F2C) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            e.key,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${e.value}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ] else ...[
                  Text(
                    'الحركات المرتبطة بهذه العقدة',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._liveLogs.where((l) => l['source'] == node.name || l['message'].toString().contains(node.name)).take(15).map((l) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0E1118) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '[${l['time']}] ${l['message']}',
                            style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabPill(int index, String label, bool isDark) {
    final isSelected = _inspectorTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _inspectorTabIndex = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6366F1).withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            color: isSelected ? const Color(0xFF6366F1) : (isDark ? Colors.white70 : Colors.black54),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CANVAS PAINTERS: CONCENTRIC FLOORS, RADIAL WIRES, & COMET PACKETS
// ══════════════════════════════════════════════════════════════════════════════

/// Static painter for the background dot grid and concentric building floor orbits.
class _N8nStaticFloorGridPainter extends CustomPainter {
  const _N8nStaticFloorGridPainter({
    required this.center,
    required this.floors,
    required this.isDark,
  });

  final Offset center;
  final List<_TopologyFloor> floors;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Static Dot Grid
    final dotPaint = Paint()
      ..color = isDark ? const Color(0xFF1E2433) : const Color(0xFFE2E8F0)
      ..style = PaintingStyle.fill;

    const spacing = 28.0;
    for (double x = 14; x < size.width; x += spacing) {
      for (double y = 14; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }

    // 2. Structured Section Tier Dividers
    final tierDividers = [
      (y: 16.0, title: '⚡ بوابة الاتصال والراوتر المركزي (Tier 1: Gateway & Router)', color: const Color(0xFF06B6D4)),
      (y: 160.0, title: '⚙️ المحركات المركزية وقواعد البيانات (Tier 2: Core Engines & MongoDB)', color: const Color(0xFF6366F1)),
      (y: 300.0, title: '🏢 شبكة محطات وكاشيرات الفروع (Tier 3: Branch Fleets)', color: const Color(0xFFFF6D5A)),
    ];

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final tier in tierDividers) {
      linePaint.color = tier.color.withValues(alpha: isDark ? 0.20 : 0.15);
      canvas.drawLine(Offset(40, tier.y), Offset(size.width - 40, tier.y), linePaint);

      // Section Badge
      final tp = TextPainter(
        text: TextSpan(
          text: tier.title,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: tier.color,
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();

      final badgeRRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, tier.y),
          width: tp.width + 16,
          height: tp.height + 6,
        ),
        const Radius.circular(5),
      );

      final bgPaint = Paint()
        ..color = isDark ? const Color(0xFF0F1118) : Colors.white
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = tier.color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawRRect(badgeRRect, bgPaint);
      canvas.drawRRect(badgeRRect, borderPaint);
      tp.paint(canvas, Offset(center.dx - (tp.width / 2), tier.y - (tp.height / 2)));
    }
  }

  @override
  bool shouldRepaint(covariant _N8nStaticFloorGridPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}

class _N8nRadialWiresPainter extends CustomPainter {
  const _N8nRadialWiresPainter({
    required this.nodes,
    required this.nodesMap,
    required this.selectedNodeId,
    required this.isDark,
  });

  final List<_TopologyNode> nodes;
  final Map<String, _TopologyNode> nodesMap;
  final String? selectedNodeId;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final wirePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final glowWirePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    for (final source in nodes) {
      final sCenter = Offset(
        source.position.dx + source.size.width / 2.0,
        source.position.dy + source.size.height / 2.0,
      );

      for (final targetId in source.connectedNodeIds) {
        final target = nodesMap[targetId];
        if (target == null) continue;

        final tCenter = Offset(
          target.position.dx + target.size.width / 2.0,
          target.position.dy + target.size.height / 2.0,
        );

        final isHighlighted = selectedNodeId != null &&
            (source.id == selectedNodeId || target.id == selectedNodeId);

        final wireColor = isHighlighted
            ? source.color
            : (isDark ? const Color(0xFF283144) : const Color(0xFFCBD5E1));

        final angle = math.atan2(tCenter.dy - sCenter.dy, tCenter.dx - sCenter.dx);

        // Exit on border of source facing target
        final p1 = Offset(
          sCenter.dx + math.cos(angle) * (source.size.width / 2.1),
          sCenter.dy + math.sin(angle) * (source.size.height / 2.1),
        );

        // Entry on border of target facing source
        final p2 = Offset(
          tCenter.dx - math.cos(angle) * (target.size.width / 2.1),
          tCenter.dy - math.sin(angle) * (target.size.height / 2.1),
        );

        final dist = (p2 - p1).distance * 0.40;
        final c1 = Offset(p1.dx + math.cos(angle) * dist, p1.dy + math.sin(angle) * dist);
        final c2 = Offset(p2.dx - math.cos(angle) * dist, p2.dy - math.sin(angle) * dist);

        final path = Path()..moveTo(p1.dx, p1.dy);
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);

        if (isHighlighted) {
          glowWirePaint.color = source.color.withValues(alpha: 0.35);
          canvas.drawPath(path, glowWirePaint);
        }

        wirePaint.color = wireColor;
        wirePaint.strokeWidth = isHighlighted ? 2.6 : 1.6;
        canvas.drawPath(path, wirePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _N8nRadialWiresPainter oldDelegate) {
    return oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.isDark != isDark ||
        oldDelegate.nodes.length != nodes.length;
  }
}

/// Flowing animated data packets traveling along the exact radial curve with comet particle trails.
class _N8nRadialPacketsPainter extends CustomPainter {
  const _N8nRadialPacketsPainter({
    required this.packets,
    required this.nodesMap,
    required this.now,
  });

  final List<_DataPacket> packets;
  final Map<String, _TopologyNode> nodesMap;
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()..style = PaintingStyle.fill;

    for (final pkt in packets) {
      final src = nodesMap[pkt.sourceId];
      final dst = nodesMap[pkt.targetId];
      if (src == null || dst == null) continue;

      final sCenter = Offset(src.position.dx + src.size.width / 2.0, src.position.dy + src.size.height / 2.0);
      final tCenter = Offset(dst.position.dx + dst.size.width / 2.0, dst.position.dy + dst.size.height / 2.0);

      final angle = math.atan2(tCenter.dy - sCenter.dy, tCenter.dx - sCenter.dx);

      final p1 = Offset(sCenter.dx + math.cos(angle) * (src.size.width / 2.1), sCenter.dy + math.sin(angle) * (src.size.height / 2.1));
      final p2 = Offset(tCenter.dx - math.cos(angle) * (dst.size.width / 2.1), tCenter.dy - math.sin(angle) * (dst.size.height / 2.1));

      final dist = (p2 - p1).distance * 0.40;
      final c1 = Offset(p1.dx + math.cos(angle) * dist, p1.dy + math.sin(angle) * dist);
      final c2 = Offset(p2.dx - math.cos(angle) * dist, p2.dy - math.sin(angle) * dist);

      final t = pkt.progress(now);

      // Comet trail particles
      for (int i = 3; i >= 1; i--) {
        final trailT = (t - (i * 0.04)).clamp(0.0, 1.0);
        if (trailT > 0.0) {
          final trailPt = _evalCubicBezier(p1, c1, c2, p2, trailT);
          final trailPaint = Paint()
            ..color = pkt.color.withValues(alpha: 0.30 / i)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(trailPt, 3.2 - (i * 0.6), trailPaint);
        }
      }

      final pt = _evalCubicBezier(p1, c1, c2, p2, t);

      // Glowing Halo
      glowPaint.color = pkt.color.withValues(alpha: 0.40);
      canvas.drawCircle(pt, 9.0, glowPaint);

      // White Core
      dotPaint.color = Colors.white;
      canvas.drawCircle(pt, 3.8, dotPaint);

      // Colored Center
      final corePaint = Paint()
        ..color = pkt.color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, 2.3, corePaint);

      // Floating Action Chip Label Above the Packet
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
  bool shouldRepaint(covariant _N8nRadialPacketsPainter oldDelegate) => true;
}
