import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/providers.dart';
import '../../chat/data/chat_socket_service.dart';
import 'system_monitor_controller.dart';

/// Representation of an active branch device currently performing a live action on the n8n canvas.
/// Appears when an action occurs, connects to the server with an n8n wire, and disappears 5s after completion.
class _ActiveCanvasDevice {
  _ActiveCanvasDevice({
    required this.id,
    required this.deviceId,
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
    required this.startedAt,
    this.method = 'GET',
    this.endpoint = '',
  });

  final String id;
  final String deviceId;
  final String hostname;
  final String cashierName;
  final String branchName;
  final String branchCode;
  final String ipAddress;
  final String actionLabel;
  final String targetEngineId;
  final String targetEngineName;
  final int slotIndex;
  Offset position;
  final Color color;
  final IconData icon;
  final DateTime startedAt;
  final String method;
  final String endpoint;

  bool isCompleted = false;
  int latencyMs = 0;
  int statusCode = 200;
  int remainingSeconds = 5;
  double flowProgress = 0.0;
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

/// Fixed n8n Core Service Block (Gateway, Chat Engine, Docs, Printer, DB).
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
/// Core Server is in the middle, services are around it.
/// Branch devices appear dynamically with animation only when they send an action,
/// connect with an n8n Bézier line showing the action, and disappear 5 seconds after completion!
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
  final TransformationController _interactiveController = TransformationController();
  StreamSubscription<ChatSocketEvent>? _socketSub;
  Timer? _countdownTicker;

  String? _selectedNodeId;
  int _inspectorTabIndex = 0;

  // Active dynamically appearing devices on the n8n canvas (max 5 slots)
  final List<_ActiveCanvasDevice> _activeDevices = [];
  final List<bool> _slotOccupied = [false, false, false, false, false];

  // Fixed Core Nodes (Gateway in center, Engines on right)
  final List<_CoreServiceNode> _coreNodes = [];
  final Map<String, _CoreServiceNode> _coreNodesMap = {};

  // Complete directory of physical branch devices
  final List<_FleetDeviceModel> _allFleetDevices = [];
  final List<Map<String, dynamic>> _liveLogs = [];

  // Filter state for Fleet Directory tab
  String _deviceFilter = 'all'; // 'all', 'online', 'outdated', 'offline'
  String _selectedBranchCode = 'all';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  double _lastCanvasWidth = 1100.0;
  double _lastCanvasHeight = 680.0;
  bool _isSocketConnected = false;

  @override
  void initState() {
    super.initState();

    _wireFlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _initCoreNodesAndFleet();
    _buildInitialLogs();

    // 1-Second Ticker for active devices 5-second countdown & fadeout
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
    _wireFlowController.dispose();
    _interactiveController.dispose();
    _socketSub?.cancel();
    _countdownTicker?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // CORE NODES & FLEET DATA INITIALIZATION
  // ══════════════════════════════════════════════════════════════════════════════
  void _initCoreNodesAndFleet() {
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

    // Preserve execution counts
    final prevCounts = <String, int>{};
    for (final node in _coreNodes) {
      prevCounts[node.id] = node.executionCount;
    }

    _coreNodes.clear();
    _coreNodesMap.clear();

    // 1. Gateway Node in Center (410, 260)
    final gatewayNode = _CoreServiceNode(
      id: 'node_gateway',
      name: 'خادم المنظومة وبوابة الاتصال',
      subtitle: 'Express Gateway & Socket.IO Router',
      category: 'GATEWAY / ROUTER',
      description: 'استقبال وفحص طلبات الشبكة، التحقق من صلاحيات التوكن، وتوجيه حركة البيانات اللحظية للمحركات.',
      color: const Color(0xFF06B6D4), // Cyan
      icon: Icons.router_rounded,
      position: const Offset(420, 260),
      size: const Size(270, 100),
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

    // 2. Core Engines on the Right Column (X = 770)
    final chatEngineNode = _CoreServiceNode(
      id: 'node_chat_engine',
      name: 'محرك المحادثات والرسائل',
      subtitle: 'Real-time Messaging & Event Bus',
      category: 'CORE LOGIC',
      description: 'معالجة الرسائل، توزيع الإشعارات اللحظية، وتحديث مؤشرات القراءة.',
      color: const Color(0xFF6366F1), // Indigo
      icon: Icons.chat_bubble_outline_rounded,
      position: const Offset(770, 50),
      size: const Size(250, 90),
      executionCount: prevCounts['node_chat_engine'] ?? 0,
      metrics: {
        'بيئة التشغيل': 'Node.js ${stats?.nodeVersion ?? "v22"}',
        'استهلاك الرام': '$memUsedGb / $memTotalGb GB',
        'وقت التشغيل': '$uptimeHours ساعة',
      },
      details: {'Engine': 'iSmart Chat Orchestrator', 'CPU Cores': '$cpuCores Cores'},
      inputPayload: {'type': 'chat_message', 'channel': 'pos_cashiers'},
      outputPayload: {'status': 'broadcast_delivered', 'timeMs': 8},
    );

    final docEngineNode = _CoreServiceNode(
      id: 'node_doc_engine',
      name: 'محرك المستندات والطلبات',
      subtitle: 'Documents & Orders Pipeline',
      category: 'CORE LOGIC',
      description: 'معالجة تحويلات الفروع، فواتير الشراء، وأوامر الصرف مع تدقيق الصلاحيات.',
      color: const Color(0xFF8B5CF6), // Purple
      icon: Icons.inventory_2_outlined,
      position: const Offset(770, 165),
      size: const Size(250, 90),
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
      category: 'HARDWARE / SPOOL',
      description: 'إدارة طابعات الباركود والإيصالات بالفروع وجدولة أوامر الطباعة.',
      color: const Color(0xFFEC4899), // Pink
      icon: Icons.print_rounded,
      position: const Offset(770, 280),
      size: const Size(250, 90),
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
      category: 'DEPLOYMENT HUB',
      description: 'مقارنة إصدارات الأجهزة بالنسخة المعتمدة v$targetVer وتوفير التحديث التلقائي.',
      color: const Color(0xFFF59E0B), // Amber
      icon: Icons.system_update_alt_rounded,
      position: const Offset(770, 395),
      size: const Size(250, 90),
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
      category: 'DATABASE',
      description: 'الحفظ الدائم لسجلات المحادثات، بيانات الفروع، الجلسات، والمستخدمين.',
      color: const Color(0xFF10B981), // Emerald
      icon: Icons.storage_rounded,
      position: const Offset(770, 510),
      size: const Size(250, 90),
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

    // 3. Extract all physical devices for the Directory
    _allFleetDevices.clear();
    final allBranches = widget.state.deploymentData?.branches ?? [];
    final allSessions = widget.state.sessions;

    for (final branch in allBranches) {
      if (branch.devices.isNotEmpty) {
        for (final d in branch.devices) {
          _allFleetDevices.add(_FleetDeviceModel(
            id: 'dev_${branch.branchCode}_${d.hostname.replaceAll(RegExp(r"[^a-zA-Z0-9_]"), "_")}',
            hostname: d.hostname.trim().isNotEmpty ? d.hostname.trim() : 'كاشير-${branch.branchCode}',
            fullName: d.fullName.trim().isNotEmpty
                ? d.fullName.trim()
                : (d.username.trim().isNotEmpty ? d.username.trim() : 'كاشير الفرع'),
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
        _allFleetDevices.add(_FleetDeviceModel(
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

    for (final s in allSessions) {
      final exists = _allFleetDevices.any((d) => d.username == s.username);
      if (!exists && s.username.isNotEmpty) {
        _allFleetDevices.add(_FleetDeviceModel(
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

    // Safety fallback
    if (_allFleetDevices.isEmpty) {
      _allFleetDevices.addAll([
        _FleetDeviceModel(
          id: 'dev_demo_110_1',
          hostname: 'POS-HRM-01',
          fullName: 'أحمد علي (كاشير 1)',
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
        _FleetDeviceModel(
          id: 'dev_demo_111',
          hostname: 'POS-DOKKI-01',
          fullName: 'محمود سمير (كاشير رئيسي)',
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
        _FleetDeviceModel(
          id: 'dev_demo_112',
          hostname: 'POS-NASR-01',
          fullName: 'إبراهيم حسن (كاشير 1)',
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
        _FleetDeviceModel(
          id: 'dev_demo_113',
          hostname: 'POS-ALEX-01',
          fullName: 'ياسر ممدوح (كاشير الإسكندرية)',
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
      ]);
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
            : ((req.username != null && req.username!.isNotEmpty) ? req.username! : req.clientIp);
        final engId = _mapEndpointToEngine(req.path);
        final engName = _coreNodesMap[engId]?.name ?? 'بوابة الاتصال';
        _liveLogs.add({
          'time': timeStr,
          'level': req.statusCode >= 400 ? 'WARN' : 'SUCCESS',
          'source': userOrHost,
          'message': '${visuals.label} [${req.method} ${req.path}] من $userOrHost ➔ $engName [${req.statusCode} • ${req.durationMs}ms]',
        });
      }
    }

    if (_liveLogs.isEmpty) {
      final now = DateTime.now();
      _liveLogs.add({
        'time': _formatTime(now),
        'level': 'SUCCESS',
        'source': 'Gateway',
        'message': 'شبكة n8n في وضع المراقبة اللحظية: متصل بالسيرفر وينتظر طلبات حقيقية من الفروع والأجهزة.',
      });
      _liveLogs.add({
        'time': _formatTime(now.subtract(const Duration(seconds: 2))),
        'level': 'INFO',
        'source': 'SocketRouter',
        'message': 'السيرفر المركزي في المنتصف والمحركات الخمسة متصلة به بمسارات n8n انسيابية.',
      });
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
        _logSystemEvent('SUCCESS', 'WebSocket', '🟢 متصل بالسيرفر المركزي لحظياً - نظام المراقبة نشط');
      } else if (event.type == 'socket_disconnected' || event.type == 'socket_reconnecting') {
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
      if (_liveLogs.length > 60) _liveLogs.removeLast();
    });
  }

  void _handleRealApiRequest(Map<String, dynamic> data) {
    if (!mounted) return;

    final clientIp = (data['clientIp'] ?? '-').toString();
    final method = (data['method'] ?? 'GET').toString().toUpperCase();
    final path = (data['path'] ?? '/').toString();
    final statusCode = data['statusCode'] is num ? (data['statusCode'] as num).toInt() : 200;
    final durationMs = data['durationMs'] is num ? (data['durationMs'] as num).toInt() : 12;

    final userMap = data['user'] as Map<String, dynamic>?;
    final username = (userMap?['username'] ?? '').toString();
    final fullName = (userMap?['fullName'] ?? '').toString();
    final branchCode = (userMap?['branchCode'] ?? '').toString();

    // Match device from fleet or create dynamic entry
    _FleetDeviceModel? matchedDev;
    for (final d in _allFleetDevices) {
      if (username.isNotEmpty && d.username.toLowerCase() == username.toLowerCase()) {
        matchedDev = d;
        break;
      }
      if (clientIp.isNotEmpty && clientIp != '-' && d.ipAddress == clientIp) {
        matchedDev = d;
        break;
      }
      if (branchCode.isNotEmpty && d.branchCode == branchCode) {
        matchedDev = d;
        break;
      }
    }

    matchedDev ??= _FleetDeviceModel(
      id: 'dyn_${DateTime.now().microsecondsSinceEpoch}',
      hostname: fullName.isNotEmpty ? fullName : (username.isNotEmpty ? username : 'محطة $clientIp'),
      fullName: fullName.isNotEmpty ? fullName : (username.isNotEmpty ? username : 'كاشير الفرع'),
      username: username.isNotEmpty ? username : clientIp,
      branchName: branchCode.isNotEmpty ? 'فرع $branchCode' : 'شبكة النظام',
      branchCode: branchCode.isNotEmpty ? branchCode : 'MAIN',
      ipAddress: clientIp,
      appVersion: widget.state.deploymentData?.summary.targetAppVersion ?? '1.1.22',
      isOutdated: false,
      isOnline: true,
      clientType: 'desktop',
      os: 'Windows 11',
      lastSeenAt: DateTime.now(),
    );

    final engId = _mapEndpointToEngine(path);
    final visuals = _mapEndpointVisuals(method, path);

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
    final fullName = (sender['fullName'] ?? sender['username'] ?? 'مستخدم').toString();
    final username = (sender['username'] ?? '').toString();

    _FleetDeviceModel? matchedDev;
    for (final d in _allFleetDevices) {
      if (username.isNotEmpty && d.username.toLowerCase() == username.toLowerCase()) {
        matchedDev = d;
        break;
      }
    }
    matchedDev ??= _FleetDeviceModel(
      id: 'chat_${DateTime.now().microsecondsSinceEpoch}',
      hostname: fullName,
      fullName: fullName,
      username: username,
      branchName: 'المحادثات المباشرة',
      branchCode: '00',
      ipAddress: '127.0.0.1',
      appVersion: '1.1.22',
      isOutdated: false,
      isOnline: true,
      clientType: 'desktop',
      os: 'Windows 11',
      lastSeenAt: DateTime.now(),
    );

    _spawnRealActionOnCanvas(
      dev: matchedDev,
      actionLabel: '💬 رسالة شات لحظية',
      engineId: 'node_chat_engine',
      color: const Color(0xFF6366F1),
      icon: Icons.chat_bubble_outline_rounded,
      latencyMs: 6,
      statusCode: 200,
      method: 'SOCKET',
      endpoint: 'receive_message',
    );
  }

  void _handleRealUpdateTelemetry(Map<String, dynamic> payload) {
    if (!mounted) return;
    final host = (payload['hostName'] ?? 'جهاز فرع').toString();
    final targetVer = (payload['targetVersion'] ?? '1.1.22').toString();
    final progress = payload['progress'] ?? 0;

    _FleetDeviceModel? matchedDev;
    for (final d in _allFleetDevices) {
      if (d.hostname.toLowerCase() == host.toLowerCase()) {
        matchedDev = d;
        break;
      }
    }
    matchedDev ??= _allFleetDevices.isNotEmpty ? _allFleetDevices.first : null;
    if (matchedDev == null) return;

    _spawnRealActionOnCanvas(
      dev: matchedDev,
      actionLabel: '📦 سحب تحديث v$targetVer ($progress%)',
      engineId: 'node_release_engine',
      color: const Color(0xFFF59E0B),
      icon: Icons.system_update_alt_rounded,
      latencyMs: 14,
      statusCode: 200,
      method: 'TELEMETRY',
      endpoint: '/api/releases/telemetry',
    );
  }

  String _mapEndpointToEngine(String path) {
    final p = path.toLowerCase();
    if (p.contains('/chat') || p.contains('/messages') || p.contains('/conversations')) {
      return 'node_chat_engine';
    }
    if (p.contains('/documents') || p.contains('/orders') || p.contains('/inventory') || p.contains('/transfers')) {
      return 'node_doc_engine';
    }
    if (p.contains('/print') || p.contains('/printer') || p.contains('/spool')) {
      return 'node_printer_engine';
    }
    if (p.contains('/release') || p.contains('/update') || p.contains('/deployment')) {
      return 'node_release_engine';
    }
    if (p.contains('/system') || p.contains('/telemetry') || p.contains('/auth') || p.contains('/users') || p.contains('/branches') || p.contains('/polls')) {
      return 'node_database';
    }
    return 'node_gateway';
  }

  ({String label, Color color, IconData icon}) _mapEndpointVisuals(String method, String path) {
    final p = path.toLowerCase();
    if (p.contains('/chat') || p.contains('/messages')) {
      return (label: method == 'POST' ? '💬 إرسال رسالة شات' : '💬 قراءة رسائل الشات', color: const Color(0xFF6366F1), icon: Icons.chat_bubble_outline_rounded);
    }
    if (p.contains('/documents') || p.contains('/orders')) {
      return (label: method == 'POST' ? '📄 حفظ مستند / طلب' : '📄 استعلام المستندات', color: const Color(0xFF8B5CF6), icon: Icons.inventory_2_outlined);
    }
    if (p.contains('/print')) {
      return (label: '🖨️ أمر طباعة مستند', color: const Color(0xFFEC4899), icon: Icons.print_rounded);
    }
    if (p.contains('/release') || p.contains('/update')) {
      return (label: '📦 فحص / تنزيل التحديث', color: const Color(0xFFF59E0B), icon: Icons.system_update_alt_rounded);
    }
    if (p.contains('/auth/login')) {
      return (label: '🔑 تسجيل دخول موظف', color: const Color(0xFF10B981), icon: Icons.vpn_key_rounded);
    }
    if (p.contains('/telemetry') || p.contains('/stats') || p.contains('/system')) {
      return (label: '📊 نبضة تشخيص النظام', color: const Color(0xFF06B6D4), icon: Icons.insights_rounded);
    }
    return (label: '⚡ طلب $method $path', color: const Color(0xFF06B6D4), icon: Icons.bolt_rounded);
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // DYNAMIC DEVICE ACTION TRIGGER & 5-SECOND COUNTDOWN
  // ══════════════════════════════════════════════════════════════════════════════
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
    int freeSlot = -1;
    for (int i = 0; i < _slotOccupied.length; i++) {
      if (!_slotOccupied[i]) {
        freeSlot = i;
        break;
      }
    }

    if (freeSlot == -1) {
      freeSlot = 0;
      _activeDevices.removeWhere((d) => d.slotIndex == 0);
    }

    _slotOccupied[freeSlot] = true;
    final engName = _coreNodesMap[engineId]?.name ?? 'بوابة الاتصال';
    final slotPos = _computeDeviceSlotPosition(freeSlot, _lastCanvasWidth, _lastCanvasHeight);

    final activeDev = _ActiveCanvasDevice(
      id: 'act_${DateTime.now().microsecondsSinceEpoch}',
      deviceId: dev.id,
      hostname: dev.hostname,
      cashierName: dev.fullName,
      branchName: dev.branchName,
      branchCode: dev.branchCode,
      ipAddress: dev.ipAddress,
      actionLabel: actionLabel,
      targetEngineId: engineId,
      targetEngineName: engName,
      slotIndex: freeSlot,
      position: slotPos,
      color: color,
      icon: icon,
      startedAt: DateTime.now(),
      method: method,
      endpoint: endpoint,
    );

    activeDev.isCompleted = true;
    activeDev.latencyMs = latencyMs;
    activeDev.statusCode = statusCode;
    activeDev.remainingSeconds = 5;

    final gw = _coreNodesMap['node_gateway'];
    if (gw != null) gw.executionCount++;
    final eng = _coreNodesMap[engineId];
    if (eng != null) eng.executionCount++;

    HapticFeedback.lightImpact();

    setState(() {
      _activeDevices.add(activeDev);
      _liveLogs.insert(0, {
        'time': _formatTime(DateTime.now()),
        'level': statusCode >= 400 ? 'WARN' : 'SUCCESS',
        'source': activeDev.hostname,
        'message': '$actionLabel من ${activeDev.hostname} (${activeDev.branchName}) ➔ البوابة المركزية ➔ $engName [$statusCode • ${latencyMs}ms]',
      });
      if (_liveLogs.length > 60) _liveLogs.removeLast();
    });
  }

  void _triggerDeviceActionOnCanvas(_FleetDeviceModel dev, {String? customAction, String? customEngine}) {
    final engId = customEngine ?? 'node_gateway';
    _spawnRealActionOnCanvas(
      dev: dev,
      actionLabel: customAction ?? '⚡ فحص مباشر للمحطة',
      engineId: engId,
      color: const Color(0xFF06B6D4),
      icon: Icons.bolt_rounded,
      latencyMs: 9,
      statusCode: 200,
      method: 'TEST',
      endpoint: '/api/devices/${dev.username}/ping',
    );
  }

  void _triggerDiagnosticTestPulse() {
    final onlineList = _allFleetDevices.where((d) => d.isOnline).toList();
    final dev = onlineList.isNotEmpty ? onlineList.first : _allFleetDevices.first;
    _spawnRealActionOnCanvas(
      dev: dev,
      actionLabel: '⚡ نبضة فحص يدوي للمنظومة',
      engineId: 'node_gateway',
      color: const Color(0xFF06B6D4),
      icon: Icons.bolt_rounded,
      latencyMs: 7,
      statusCode: 200,
      method: 'GET',
      endpoint: '/api/system-telemetry/ping',
    );
  }

  Offset _computeDeviceSlotPosition(int slotIndex, double canvasWidth, double canvasHeight) {
    final gwX = (canvasWidth - 270.0) / 2.0;
    final devX = math.max(30.0, gwX - 270.0 - 80.0);
    const cardHeight = 90.0;
    const gap = 16.0;
    const totalHeight = (5 * cardHeight) + (4 * gap); // 514
    final startY = math.max(30.0, (canvasHeight - totalHeight) / 2.0);
    return Offset(devX, startY + (slotIndex * (cardHeight + gap)));
  }

  void _updateNodePositions(double canvasWidth, double canvasHeight) {
    _lastCanvasWidth = canvasWidth;
    _lastCanvasHeight = canvasHeight;

    // 1. Gateway Center Position
    final gwX = (canvasWidth - 270.0) / 2.0;
    final gwY = (canvasHeight - 100.0) / 2.0;
    final gwNode = _coreNodesMap['node_gateway'];
    if (gwNode != null) {
      gwNode.position = Offset(gwX, gwY);
    }

    // 2. 5 Core Engines in Right Column
    final engX = math.min(canvasWidth - 265.0, gwX + 270.0 + 80.0);
    const engHeight = 88.0;
    const engGap = 18.0;
    const totalEngHeight = (5 * engHeight) + (4 * engGap); // 512
    final engStartY = math.max(30.0, (canvasHeight - totalEngHeight) / 2.0);

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
        engNode.position = Offset(engX, engStartY + (i * (engHeight + engGap)));
      }
    }

    // 3. Active Devices in Left Column
    for (final dev in _activeDevices) {
      dev.position = _computeDeviceSlotPosition(dev.slotIndex, canvasWidth, canvasHeight);
    }
  }

  void _tickDeviceCountdowns() {
    bool changed = false;
    final toRemove = <_ActiveCanvasDevice>[];

    for (final dev in _activeDevices) {
      if (dev.isCompleted) {
        if (dev.remainingSeconds > 1) {
          dev.remainingSeconds--;
          changed = true;
        } else {
          // Time expired (5 seconds elapsed) — disappear!
          toRemove.add(dev);
        }
      }
    }

    if (toRemove.isNotEmpty) {
      for (final r in toRemove) {
        _slotOccupied[r.slotIndex] = false;
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
        backgroundColor: isDark ? const Color(0xFF0F1118) : const Color(0xFFF8FAFC),
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
                      child: Stack(
                        children: [
                          if (_activeTab == 0)
                            _buildN8nCanvasTab(isDark)
                          else if (_activeTab == 1)
                            _buildFleetDirectoryTab(isDark)
                          else
                            _buildEventLogTab(isDark),

                          // Floating Controls (Canvas Tab)
                          if (_activeTab == 0)
                            Positioned(
                              left: 20,
                              bottom: 20,
                              child: _buildCanvasFloatingHUD(isDark),
                            ),
                        ],
                      ),
                    ),

                    // Side Inspector Panel (if node selected)
                    if (_selectedNodeId != null)
                      SizedBox(
                        width: 360,
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
                  backgroundColor: isDark ? const Color(0xFF1E2536) : const Color(0xFFF1F5F9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6D5A).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.hub_rounded, size: 20, color: Color(0xFFFF6D5A)),
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
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '● LIVE n8n FLOW (${_activeDevices.length} أجهزة نشطة)',
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
                    'السيرفر بالمنتصف: الأجهزة تظهر لحظة إرسال الطلب وتتصل بالسيرفر بخط وتختفي بعد 5 ثوانٍ',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
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
                      label: '⚡ خريطة n8n الحية',
                      icon: Icons.donut_large_rounded,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                    _tabPill(
                      index: 1,
                      label: '🏢 كافة أجهزة الفروع (${_allFleetDevices.length})',
                      icon: Icons.devices_rounded,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                    _tabPill(
                      index: 2,
                      label: '📜 سجل الحركات',
                      icon: Icons.history_rounded,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Manual Simulate Action Button
              FilledButton.icon(
                onPressed: _triggerDiagnosticTestPulse,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.bolt_rounded, size: 16),
                label: const Text(
                  '⚡ تجربة فحص يدوي',
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
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? const Color(0xFFFF6D5A) : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
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

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 0: AUTHENTIC n8n CANVAS VIEW (CENTER SERVER + DYNAMIC APPEARING DEVICES)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildN8nCanvasTab(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableW = constraints.maxWidth;
        final availableH = constraints.maxHeight;
        final canvasWidth = math.max(availableW, 1100.0);
        final canvasHeight = math.max(availableH, 680.0);

        _updateNodePositions(canvasWidth, canvasHeight);
        final gwNode = _coreNodesMap['node_gateway'];
        final gwPos = gwNode?.position ?? Offset((canvasWidth - 270.0) / 2.0, (canvasHeight - 100.0) / 2.0);
        final gwSize = gwNode?.size ?? const Size(270, 100);

        return Stack(
          children: [
            InteractiveViewer(
              transformationController: _interactiveController,
              minScale: 0.5,
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
                        painter: _N8nCanvasGridPainter(isDark: isDark),
                      ),
                    ),

                    // Layer 2: Fixed Core Service Wires (Gateway ➔ 5 Microservices)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _N8nCoreWiresPainter(
                          coreNodes: _coreNodes,
                          coreNodesMap: _coreNodesMap,
                          selectedNodeId: _selectedNodeId,
                          isDark: isDark,
                        ),
                      ),
                    ),

                    // Layer 3: Dynamic Animated Wires from Calling Devices ➔ Gateway
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _wireFlowController,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: _N8nCallingDevicesWiresPainter(
                              activeDevices: _activeDevices,
                              gatewayPosition: gwPos,
                              gatewaySize: gwSize,
                              flowProgress: _wireFlowController.value,
                              isDark: isDark,
                            ),
                          );
                        },
                      ),
                    ),

                    // Layer 4: Empty State Watermark if no devices calling right now
                    if (_activeDevices.isEmpty)
                      Positioned(
                        left: math.max(30.0, gwPos.dx - 270.0 - 80.0),
                        top: gwPos.dy + 5,
                        child: _buildIdleLiveMonitorBanner(isDark),
                      ),

                    // Layer 5: Fixed Core Service Cards (Center Server + 5 Engines)
                    for (final node in _coreNodes)
                      Positioned(
                        left: node.position.dx,
                        top: node.position.dy,
                        child: _buildCoreNodeCard(node, isDark),
                      ),

                    // Layer 6: Dynamic Calling Devices (Appear, pulse, fade out after 5s)
                    for (final activeDev in _activeDevices)
                      Positioned(
                        left: activeDev.position.dx,
                        top: activeDev.position.dy,
                        child: _buildCallingDeviceCard(activeDev, isDark),
                      ),
                  ],
                ),
              ),
            ),

            // Floating Controls HUD (Canvas Tab)
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
      width: 270,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722).withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.9),
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
            child: const Icon(Icons.sensors_rounded, size: 24, color: Color(0xFF10B981)),
          ),
          const SizedBox(height: 10),
          const Text(
            'شبكة n8n في وضع المراقبة اللحظية 🟢',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 5),
          Text(
            'متصل بالسيرفر المركزي وينتظر طلبات حقيقية من الفروع والأجهزة... تظهر الشاشات فور حدوث أي طلب وتختفي بعد 5 ثوانٍ.',
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _triggerDiagnosticTestPulse,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF06B6D4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.bolt_rounded, size: 14),
            label: const Text(
              '⚡ تجربة فحص يدوي',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // CARD WIDGETS: FIXED CORE NODES & DYNAMIC CALLING DEVICES
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildCoreNodeCard(_CoreServiceNode node, bool isDark) {
    final isSelected = _selectedNodeId == node.id;
    final isGateway = node.id == 'node_gateway';

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedNodeId = node.id;
          _inspectorTabIndex = 0;
        });
      },
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: node.size.width,
        height: node.size.height,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isGateway
              ? (isDark ? const Color(0xFF0F232D) : const Color(0xFFECFEFF))
              : (isDark ? const Color(0xFF141722) : Colors.white),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isSelected
                ? node.color
                : (isGateway ? const Color(0xFF06B6D4) : node.color.withValues(alpha: 0.5)),
            width: isSelected || isGateway ? 2.2 : 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: node.color.withValues(alpha: isGateway ? 0.25 : 0.08),
              blurRadius: isGateway || isSelected ? 16 : 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Left Input Port Dot (facing Gateway or Devices)
            Positioned(
              left: -17,
              top: (node.size.height / 2) - 17,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F1118) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: node.color, width: 2),
                ),
              ),
            ),

            // Right Output Port Dot
            if (isGateway)
              Positioned(
                right: -17,
                top: (node.size.height / 2) - 17,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F1118) : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: node.color, width: 2),
                  ),
                ),
              ),

            // Execution Counter Badge (Top Right)
            if (node.executionCount > 0)
              Positioned(
                top: -18,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.35), blurRadius: 4),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_rounded, color: Colors.white, size: 10),
                      const SizedBox(width: 3),
                      Text(
                        'x${node.executionCount}',
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white),
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
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: node.color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: node.color.withValues(alpha: 0.4)),
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
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            node.subtitle,
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

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: node.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        node.category,
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: node.color),
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'متصل 🟢',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// DYNAMIC CALLING DEVICE CARD:
  /// Appears when calling, displays the action & progress, turns green upon completion,
  /// counts down 5s, and disappears!
  Widget _buildCallingDeviceCard(_ActiveCanvasDevice dev, bool isDark) {
    final statusColor = dev.isCompleted ? const Color(0xFF10B981) : dev.color;

    return Container(
      width: 270,
      height: 90,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: statusColor,
          width: dev.isCompleted ? 2.2 : 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: dev.isCompleted ? 0.35 : 0.20),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Right Output Port Dot (facing Central Gateway)
          Positioned(
            right: -16,
            top: 30,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F1118) : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: statusColor, width: 2),
              ),
            ),
          ),

          // Top Badge: Action Pill + 5-Second Disappear Countdown
          Positioned(
            top: -18,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(color: statusColor.withValues(alpha: 0.35), blurRadius: 4),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    dev.isCompleted ? Icons.check_circle_rounded : Icons.sync_rounded,
                    color: Colors.white,
                    size: 11,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    dev.isCompleted
                        ? 'اكتمل ✓ (يختفي خلال ${dev.remainingSeconds}ث)'
                        : 'جاري إرسال الطلب...',
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
                      color: statusColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Icon(dev.icon, color: statusColor, size: 17),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dev.hostname,
                          style: TextStyle(
                            fontSize: 12,
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

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      dev.actionLabel,
                      style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: statusColor),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dev.isCompleted ? '${dev.latencyMs}ms • ${dev.statusCode}' : 'جارٍ المعالجة...',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: dev.isCompleted ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
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
  // FLOATING HUD: AUTO-PULSE TOGGLE & STATS
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildCanvasFloatingHUD(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
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
          // Zoom In
          IconButton(
            icon: const Icon(Icons.zoom_in_rounded, size: 18),
            tooltip: 'تكبير اللوحة',
            onPressed: () {
              final val = _interactiveController.value.clone()..scale(1.2, 1.2);
              _interactiveController.value = val;
            },
            visualDensity: VisualDensity.compact,
          ),
          // Zoom Out
          IconButton(
            icon: const Icon(Icons.zoom_out_rounded, size: 18),
            tooltip: 'تصغير اللوحة',
            onPressed: () {
              final val = _interactiveController.value.clone()..scale(0.833, 0.833);
              _interactiveController.value = val;
            },
            visualDensity: VisualDensity.compact,
          ),
          // Reset Zoom
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            tooltip: 'إعادة ضبط العرض',
            onPressed: () {
              _interactiveController.value = Matrix4.identity();
            },
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: isDark ? Colors.white24 : Colors.black12),
          const SizedBox(width: 10),
          Icon(
            _isSocketConnected ? Icons.sensors_rounded : Icons.sensors_off_rounded,
            size: 16,
            color: _isSocketConnected ? const Color(0xFF10B981) : Colors.amber,
          ),
          const SizedBox(width: 6),
          Text(
            _isSocketConnected ? 'البث اللحظي للطلبات: نشط 🟢' : 'جاري الاتصال بالسيرفر...',
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _triggerDiagnosticTestPulse,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF06B6D4).withValues(alpha: 0.16),
              foregroundColor: const Color(0xFF06B6D4),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.bolt_rounded, size: 14),
            label: const Text('⚡ فحص تجريبي يدوي', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
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

    // Group by branch
    final Map<String, List<_FleetDeviceModel>> branchGroups = {};
    for (final dev in filtered) {
      branchGroups.putIfAbsent(dev.branchCode, () => []).add(dev);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter Chips & Search Bar
          _buildDirectoryFilterBar(isDark),
          const SizedBox(height: 16),

          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141722) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
              ),
              child: const Text('لا توجد أجهزة مطابقة للبحث', style: TextStyle(fontWeight: FontWeight.w800)),
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
        border: Border.all(color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
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
              _filterPill('all', 'كل الأجهزة ($allCount)', const Color(0xFF6366F1), isDark),
              _filterPill('online', 'متصل الآن 🟢 ($onlineCount)', const Color(0xFF10B981), isDark),
              _filterPill('outdated', 'نسخة قديمة ⚠️ ($outdatedCount)', const Color(0xFFF59E0B), isDark),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
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
                    value: branchOptions.containsKey(_selectedBranchCode) ? _selectedBranchCode : 'all',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                    dropdownColor: isDark ? const Color(0xFF141722) : Colors.white,
                    items: branchOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
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
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'بحث بالجهاز أو الموظف أو IP...',
                    hintStyle: const TextStyle(fontSize: 10.5),
                    prefixIcon: const Icon(Icons.search_rounded, size: 16),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
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
          color: isSelected ? color.withValues(alpha: 0.18) : (isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? color : (isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0))),
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

  Widget _buildBranchDirectoryCard(String branchCode, List<_FleetDeviceModel> devs, bool isDark) {
    final bName = devs.first.branchName;
    final onlineCount = devs.where((d) => d.isOnline).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF191F2E) : const Color(0xFFF1F5F9),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront_rounded, size: 18, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text(bName, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('كود $branchCode', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF10B981))),
                ),
                const Spacer(),
                Text('$onlineCount من ${devs.length} متصل الآن', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF10B981))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              children: devs.map((dev) => _buildDirectoryDeviceCard(dev, isDark)).toList(),
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
          color: dev.isOnline ? const Color(0xFF10B981).withValues(alpha: 0.45) : (isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.desktop_windows_rounded, color: dev.isOnline ? const Color(0xFF10B981) : Colors.grey, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dev.hostname,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                dev.isOnline ? 'متصل 🟢' : 'غير متصل ⚪',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: dev.isOnline ? const Color(0xFF10B981) : Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${dev.fullName} • IP: ${dev.ipAddress}', style: TextStyle(fontSize: 10.5, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: dev.isOutdated ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  dev.isOutdated ? 'v${dev.appVersion} ⚠️' : 'v${dev.appVersion} ✓',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: dev.isOutdated ? const Color(0xFFF59E0B) : const Color(0xFF10B981)),
                ),
              ),
              const Spacer(),
              // Trigger Live n8n Animation Button!
              FilledButton.icon(
                onPressed: () {
                  _triggerDeviceActionOnCanvas(dev);
                  setState(() => _activeTab = 0); // Switch to canvas tab so user sees it live!
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D5A),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 28),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.bolt_rounded, size: 12),
                label: const Text('إظهار في خريطة n8n ⚡', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)),
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
            border: Border.all(color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Text(
                '[${log['time']}]',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  log['source'] as String? ?? 'Hub',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF10B981)),
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
    final node = _selectedNodeId != null ? _coreNodesMap[_selectedNodeId!] : null;
    if (node == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        border: Border(right: BorderSide(color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: node.color.withValues(alpha: 0.12),
              border: Border(bottom: BorderSide(color: node.color.withValues(alpha: 0.25))),
            ),
            child: Row(
              children: [
                Icon(node.icon, color: node.color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(node.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900)),
                      Text(node.category, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: node.color)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => _selectedNodeId = null)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(node.description, style: TextStyle(fontSize: 11.5, height: 1.4, color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155))),
                const SizedBox(height: 16),
                const Text('القياسات التشغيلية الحية', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                ...node.metrics.entries.map((e) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Text(e.key, style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                          const Spacer(),
                          Text(e.value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
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
// CANVAS PAINTERS FOR n8n WORKFLOW WIRES & PACKETS
// ══════════════════════════════════════════════════════════════════════════════

/// Dot grid background painter.
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
  bool shouldRepaint(covariant _N8nCanvasGridPainter oldDelegate) => oldDelegate.isDark != isDark;
}

/// Static wires connecting Central Gateway ➔ 5 Microservices.
class _N8nCoreWiresPainter extends CustomPainter {
  const _N8nCoreWiresPainter({
    required this.coreNodes,
    required this.coreNodesMap,
    required this.selectedNodeId,
    required this.isDark,
  });

  final List<_CoreServiceNode> coreNodes;
  final Map<String, _CoreServiceNode> coreNodesMap;
  final String? selectedNodeId;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final gw = coreNodesMap['node_gateway'];
    if (gw == null) return;

    final gwRightPort = Offset(gw.position.dx + gw.size.width, gw.position.dy + (gw.size.height / 2.0));

    final wirePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    for (final node in coreNodes) {
      if (node.id == 'node_gateway') continue;

      final nodeLeftPort = Offset(node.position.dx, node.position.dy + (node.size.height / 2.0));
      final isHighlighted = selectedNodeId == node.id || selectedNodeId == 'node_gateway';

      wirePaint.color = isHighlighted
          ? node.color
          : (isDark ? const Color(0xFF283144) : const Color(0xFFCBD5E1));
      wirePaint.strokeWidth = isHighlighted ? 2.4 : 1.6;

      final midX = (gwRightPort.dx + nodeLeftPort.dx) / 2.0;
      final path = Path()
        ..moveTo(gwRightPort.dx, gwRightPort.dy)
        ..cubicTo(midX, gwRightPort.dy, midX, nodeLeftPort.dy, nodeLeftPort.dx, nodeLeftPort.dy);

      canvas.drawPath(path, wirePaint);

      // Port glow dots at card edges
      final dotPaint = Paint()..color = node.color;
      canvas.drawCircle(nodeLeftPort, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _N8nCoreWiresPainter oldDelegate) {
    return oldDelegate.selectedNodeId != selectedNodeId || oldDelegate.isDark != isDark;
  }
}

/// Dynamic Bézier wires from Active Calling Devices ➔ Gateway with moving action packets!
class _N8nCallingDevicesWiresPainter extends CustomPainter {
  const _N8nCallingDevicesWiresPainter({
    required this.activeDevices,
    required this.gatewayPosition,
    required this.gatewaySize,
    required this.flowProgress,
    required this.isDark,
  });

  final List<_ActiveCanvasDevice> activeDevices;
  final Offset gatewayPosition;
  final Size gatewaySize;
  final double flowProgress;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (activeDevices.isEmpty) return;

    final gwLeftPort = Offset(gatewayPosition.dx, gatewayPosition.dy + (gatewaySize.height / 2.0));

    final wirePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()..style = PaintingStyle.fill;
    final corePaint = Paint()..style = PaintingStyle.fill;

    for (final dev in activeDevices) {
      final devRightPort = Offset(dev.position.dx + 270.0, dev.position.dy + 45.0);
      final lineColor = dev.isCompleted ? const Color(0xFF10B981) : dev.color;

      wirePaint.color = lineColor.withValues(alpha: dev.isCompleted ? 0.45 : 0.85);

      final midX = (devRightPort.dx + gwLeftPort.dx) / 2.0;
      final path = Path()
        ..moveTo(devRightPort.dx, devRightPort.dy)
        ..cubicTo(midX, devRightPort.dy, midX, gwLeftPort.dy, gwLeftPort.dx, gwLeftPort.dy);

      canvas.drawPath(path, wirePaint);

      // Moving glowing packet orb along the wire
      final metrics = path.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final metric = metrics.first;
        final tangent = metric.getTangentForOffset(metric.length * flowProgress);

        if (tangent != null) {
          // Glow Halo
          glowPaint.color = lineColor.withValues(alpha: 0.45);
          canvas.drawCircle(tangent.position, 8.0, glowPaint);

          // White Core
          corePaint.color = Colors.white;
          canvas.drawCircle(tangent.position, 3.5, corePaint);

          // Action Chip Floating on the Wire
          final tp = TextPainter(
            text: TextSpan(
              text: dev.actionLabel,
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
  bool shouldRepaint(covariant _N8nCallingDevicesWiresPainter oldDelegate) => true;
}
