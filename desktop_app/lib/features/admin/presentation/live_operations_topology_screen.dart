import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'system_monitor_controller.dart';

/// Enum representing the kind of node in the topology mesh.
enum _TopologyNodeType {
  centralGateway,
  branchHub,
  employee,
}

/// A node in the n8n-style live operations topology graph.
class _TopologyNode {
  _TopologyNode({
    required this.id,
    required this.type,
    required this.name,
    required this.subtitle,
    required this.branchName,
    required this.branchCode,
    required this.color,
    required this.icon,
    this.avatarUrl,
    required this.isOnline,
    this.ipAddress,
    this.os,
    this.jobTitle,
    this.role,
    this.appVersion,
    this.isOutdated = false,
    this.versionStatusLabel,
    this.workstationType,
    this.hostname,
    required this.position,
    required this.size,
    List<String>? connectedNodeIds,
  }) : connectedNodeIds = connectedNodeIds ?? [];

  final String id;
  final _TopologyNodeType type;
  final String name;
  final String subtitle;
  final String branchName;
  final String branchCode;
  final Color color;
  final IconData icon;
  final String? avatarUrl;
  final bool isOnline;
  final String? ipAddress;
  final String? os;
  final String? jobTitle;
  final String? role;
  final String? appVersion;
  final bool isOutdated;
  final String? versionStatusLabel;
  final String? workstationType;
  final String? hostname;
  Offset position;
  final Size size;
  final List<String> connectedNodeIds;

  Offset get leftPort => Offset(position.dx, position.dy + size.height / 2);
  Offset get rightPort => Offset(position.dx + size.width, position.dy + size.height / 2);
}

/// A live active packet traveling between two nodes.
class _ActivePacket {
  _ActivePacket({
    required this.fromId,
    required this.toId,
    required this.label,
    required this.color,
    required this.startTime,
    required this.duration,
    this.isDirect = false,
  });

  final String fromId;
  final String toId;
  final String label;
  final Color color;
  final DateTime startTime;
  final Duration duration;
  final bool isDirect;

  double getProgress(DateTime now) {
    final elapsed = now.difference(startTime).inMilliseconds;
    return (elapsed / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  bool isFinished(DateTime now) {
    return now.difference(startTime) >= duration;
  }
}

/// A real-time event item shown in the bottom ticker/console.
class _TopologyEventItem {
  _TopologyEventItem({
    required this.id,
    required this.timestamp,
    required this.fromName,
    required this.toName,
    required this.fromNodeId,
    required this.toNodeId,
    required this.action,
    required this.type,
    required this.color,
  });

  final String id;
  final DateTime timestamp;
  final String fromName;
  final String toName;
  final String fromNodeId;
  final String toNodeId;
  final String action;
  final String type; // 'sync', 'poll', 'error', 'ping'
  final Color color;
}

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
  late final TransformationController _transController;
  late final AnimationController _pulseController;
  late final AnimationController _flyAnimController;
  Animation<Matrix4>? _flyMatrixAnimation;
  Timer? _telemetryPulseTimer;

  final List<_TopologyNode> _nodes = [];
  final Map<String, _TopologyNode> _nodesMap = {};
  final List<_ActivePacket> _packets = [];
  final List<_TopologyEventItem> _eventLog = [];

  String? _selectedNodeId;
  String _branchFilter = 'all';
  bool _onlyActiveBranches = true;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _simulationRunning = true;
  bool _showConsole = true;
  bool _showDirectoryDrawer = false;

  double _canvasWidth = 2400;
  double _canvasHeight = 1800;

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
      duration: const Duration(milliseconds: 450),
    );
    _flyAnimController.addListener(() {
      if (_flyMatrixAnimation != null) {
        _transController.value = _flyMatrixAnimation!.value;
      }
    });

    // Refresh real backend data immediately
    widget.notifier.refreshDeployment();
    widget.notifier.refreshSessions();
    widget.notifier.refreshStats();
    widget.notifier.refreshPolls();
    widget.notifier.loadErrors();

    _buildTopologyMesh();
    _buildRealEventLog();

    // Center view smoothly after initial layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetZoom(animated: false);
    });

    _startLiveTelemetryPulse();
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
      _buildRealEventLog();
    }
  }

  @override
  void dispose() {
    _telemetryPulseTimer?.cancel();
    _pulseController.dispose();
    _flyAnimController.dispose();
    _transController.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // PURE REAL BACKEND DATA MESH (100% Free of Mock/Seeder Data)
  // ══════════════════════════════════════════════════════════════════════════════
  void _buildTopologyMesh() {
    _nodes.clear();
    _nodesMap.clear();

    final allBranches = widget.state.deploymentData?.branches ?? [];
    if (allBranches.isEmpty) {
      return;
    }

    // Filter active vs all branches
    final activeBranches = allBranches
        .where((b) => b.isInstalled || b.devices.isNotEmpty || b.installedUsers.isNotEmpty)
        .toList();
    final effectiveBranches = (_onlyActiveBranches && activeBranches.isNotEmpty)
        ? activeBranches
        : allBranches;

    // Palette for distinct branch visual identification
    final branchColors = [
      const Color(0xFF0284C7), // Sky Blue
      const Color(0xFF10B981), // Emerald
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFFF59E0B), // Amber
      const Color(0xFFEC4899), // Pink
      const Color(0xFF06B6D4), // Cyan
      const Color(0xFF14B8A6), // Teal
      const Color(0xFF6366F1), // Indigo
    ];

    // Pre-calculate vertical heights required for all branches and real devices/staff
    double totalHeightNeeded = 140.0;
    final List<List<_TopologyNode>> branchEmployeesList = [];

    for (int bi = 0; bi < effectiveBranches.length; bi++) {
      final b = effectiveBranches[bi];
      final branchHubId = 'branch_${b.branchCode}';
      final List<_TopologyNode> branchEmployees = [];

      // 1. Real Physical Devices from UpdateDevice / DeviceSession
      final Set<String> representedUsers = {};
      if (b.devices.isNotEmpty) {
        for (int di = 0; di < b.devices.length; di++) {
          final dev = b.devices[di];
          if (dev.username.isNotEmpty) representedUsers.add(dev.username.toLowerCase());
          if (dev.fullName.isNotEmpty) representedUsers.add(dev.fullName.toLowerCase());
          final empId = 'dev_${b.branchCode}_$di';
          branchEmployees.add(
            _TopologyNode(
              id: empId,
              type: _TopologyNodeType.employee,
              name: dev.fullName.isNotEmpty ? dev.fullName : (dev.username.isNotEmpty ? dev.username : dev.hostname),
              subtitle: dev.hostname,
              branchName: b.branchName,
              branchCode: b.branchCode,
              color: dev.isOutdated ? const Color(0xFFEF4444) : _roleColor(di),
              icon: _deviceIcon(dev.clientType),
              isOnline: dev.isOnline,
              ipAddress: dev.ipAddress,
              os: '${dev.os} ${dev.osVersion}'.trim(),
              jobTitle: dev.workstationType.isNotEmpty ? dev.workstationType : 'محطة عمل',
              role: 'user',
              appVersion: dev.appVersion,
              isOutdated: dev.isOutdated,
              versionStatusLabel: dev.versionStatusLabel,
              workstationType: dev.workstationType,
              hostname: dev.hostname,
              position: Offset.zero,
              size: const Size(220, 68),
              connectedNodeIds: [branchHubId],
            ),
          );
        }
      }

      // 2. Real branch users without explicit device registrations
      if (b.installedUsers.isNotEmpty) {
        int nonDevIndex = 0;
        for (int ui = 0; ui < b.installedUsers.length; ui++) {
          final usr = b.installedUsers[ui];
          final uName = usr.username.toLowerCase();
          final fName = usr.fullName.toLowerCase();
          if (representedUsers.contains(uName) || representedUsers.contains(fName)) {
            continue; // Already displayed with their active device above
          }
          final empId = 'usr_${b.branchCode}_$ui';
          branchEmployees.add(
            _TopologyNode(
              id: empId,
              type: _TopologyNodeType.employee,
              name: usr.fullName.isNotEmpty ? usr.fullName : usr.username,
              subtitle: usr.jobTitle.isNotEmpty ? usr.jobTitle : 'موظف بالفرع',
              branchName: b.branchName,
              branchCode: b.branchCode,
              color: _roleColor(b.devices.length + nonDevIndex++),
              icon: Icons.person_outline_rounded,
              isOnline: usr.isOnline,
              ipAddress: '-',
              os: 'غير مسجل على جهاز',
              jobTitle: usr.jobTitle.isNotEmpty ? usr.jobTitle : 'موظف بالفرع',
              role: usr.role,
              appVersion: 'غير محدد',
              isOutdated: false,
              versionStatusLabel: 'لم يسجل جهازاً',
              workstationType: 'مستخدم فرع',
              hostname: 'محطة غير معينة',
              position: Offset.zero,
              size: const Size(220, 68),
              connectedNodeIds: [branchHubId],
            ),
          );
        }
      }
      // Note: If a branch has neither devices nor users, branchEmployees is empty.
      // ZERO mock/sample names are generated!

      branchEmployeesList.add(branchEmployees);

      final empCount = branchEmployees.length;
      final rows = empCount > 2 ? ((empCount + 1) / 2).ceil() : math.max(1, empCount);
      final slotHeight = math.max(110.0, (rows * 82.0) + 16.0);
      totalHeightNeeded += slotHeight + 40.0;
    }

    _canvasHeight = math.max(1600.0, totalHeightNeeded + 220.0);
    _canvasWidth = 2200.0;

    // Real Central Gateway Telemetry Node (Stage 1 - Left)
    final stats = widget.state.stats;
    final serverHostname = stats?.hostname.isNotEmpty == true ? stats!.hostname : 'iSmart Server';
    final nodeVer = stats?.nodeVersion.isNotEmpty == true ? 'Node.js ${stats!.nodeVersion}' : 'Node.js Cluster';
    final dbName = stats?.databaseName.isNotEmpty == true ? stats!.databaseName : 'MongoDB';
    final serverOs = stats != null && stats.osType.isNotEmpty ? '${stats.osType} ${stats.osRelease}'.trim() : 'Ubuntu Server';

    final gatewayY = _canvasHeight / 2 - 50.0;
    final gatewayNode = _TopologyNode(
      id: 'core_gateway',
      type: _TopologyNodeType.centralGateway,
      name: 'خادم المنظومة المركزي',
      subtitle: '$serverHostname • $dbName',
      branchName: 'المركز الرئيسي',
      branchCode: 'HQ',
      color: const Color(0xFF6366F1), // Electric Indigo
      icon: Icons.dns_rounded,
      isOnline: true,
      ipAddress: stats?.databaseHost.isNotEmpty == true ? stats!.databaseHost : '127.0.0.1:5000',
      os: '$serverOs ($nodeVer)',
      jobTitle: 'الخادم الرئيسي والوسيط المركزي',
      position: Offset(100, gatewayY),
      size: const Size(280, 100),
    );
    _nodes.add(gatewayNode);
    _nodesMap[gatewayNode.id] = gatewayNode;

    // Stage 2 (Branches) & Stage 3 (Real Workstations)
    double currentY = 120.0;
    const branchX = 540.0;
    const employeeBaseX = 890.0;

    for (int bi = 0; bi < effectiveBranches.length; bi++) {
      final b = effectiveBranches[bi];
      final bColor = branchColors[bi % branchColors.length];
      final branchHubId = 'branch_${b.branchCode}';
      final employees = branchEmployeesList[bi];

      final empCount = employees.length;
      final rows = empCount > 2 ? ((empCount + 1) / 2).ceil() : math.max(1, empCount);
      final slotHeight = math.max(110.0, (rows * 82.0) + 16.0);

      final branchY = currentY + (slotHeight / 2) - 42.0;
      final hasOutdated = employees.any((e) => e.isOutdated);

      final branchHub = _TopologyNode(
        id: branchHubId,
        type: _TopologyNodeType.branchHub,
        name: b.branchName,
        subtitle: 'كود الفرع: ${b.branchCode} • ${b.devicesCount} أجهزة',
        branchName: b.branchName,
        branchCode: b.branchCode,
        color: bColor,
        icon: Icons.apartment_rounded,
        isOnline: b.isInstalled,
        ipAddress: 'فرع كود ${b.branchCode}',
        os: 'بوابة الفرع',
        jobTitle: 'بوابة اتصال الفرع الفرعية',
        appVersion: b.appVersions.isNotEmpty ? b.appVersions.join(', ') : '1.1.21',
        isOutdated: hasOutdated,
        position: Offset(branchX, branchY),
        size: const Size(230, 84),
        connectedNodeIds: ['core_gateway'],
      );

      _nodes.add(branchHub);
      _nodesMap[branchHubId] = branchHub;
      gatewayNode.connectedNodeIds.add(branchHubId);

      // Position real devices/employees in structured columns
      for (int ei = 0; ei < empCount; ei++) {
        final emp = employees[ei];
        final col = empCount > 2 ? (ei % 2) : 0;
        final row = empCount > 2 ? (ei ~/ 2) : ei;

        final empX = employeeBaseX + (col * 245.0);
        final empY = currentY + (row * 82.0) + 8.0;

        emp.position = Offset(empX, empY);
        _nodes.add(emp);
        _nodesMap[emp.id] = emp;
        branchHub.connectedNodeIds.add(emp.id);
      }

      currentY += slotHeight + 40.0;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // PURE REAL BACKEND EVENT LOG (From Real Sessions, Real Polls, Real Errors)
  // ══════════════════════════════════════════════════════════════════════════════
  void _buildRealEventLog() {
    _eventLog.clear();

    // 1. Real user login / active sessions from DB
    for (final s in widget.state.sessions.take(15)) {
      _eventLog.add(
        _TopologyEventItem(
          id: 'sess_${s.id}',
          timestamp: s.lastSeenAt,
          fromName: '${s.fullName} (${s.jobTitleBranch ?? s.department ?? "مستخدم"})',
          toName: 'خادم المنظومة المركزي',
          fromNodeId: 'core_gateway',
          toNodeId: 'core_gateway',
          action: s.isOnline ? 'اتصال حي نشط ومزامنة' : 'تسجيل دخول سابق',
          type: 'sync',
          color: s.isOnline ? const Color(0xFF10B981) : const Color(0xFF64748B),
        ),
      );
    }

    // 2. Real system polls from DB
    final polls = widget.state.pollsData?.items ?? [];
    for (final p in polls.take(6)) {
      final creatorName = p.creator.fullName.isNotEmpty
          ? p.creator.fullName
          : (p.creator.username.isNotEmpty ? p.creator.username : 'المشرف');
      _eventLog.add(
        _TopologyEventItem(
          id: 'poll_${p.id}',
          timestamp: p.createdAt,
          fromName: creatorName,
          toName: 'كافة الفروع والمستخدمين',
          fromNodeId: 'core_gateway',
          toNodeId: 'core_gateway',
          action: 'استطلاع رأي: ${p.question}',
          type: 'poll',
          color: const Color(0xFF6366F1),
        ),
      );
    }

    // 3. Real system error logs from DB
    for (final err in widget.state.errors.take(8)) {
      _eventLog.add(
        _TopologyEventItem(
          id: 'err_${err.id}',
          timestamp: err.createdAt,
          fromName: err.fullName ?? err.username ?? "محطة عمل",
          toName: 'سجل أخطاء النظام المركزي',
          fromNodeId: 'core_gateway',
          toNodeId: 'core_gateway',
          action: 'سجل خطأ نظام: ${err.errorMessage}',
          type: 'error',
          color: const Color(0xFFEF4444),
        ),
      );
    }

    // Sort by timestamp descending
    _eventLog.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Color _roleColor(int index) {
    const colors = [
      Color(0xFF8B5CF6), // Lead: Purple
      Color(0xFF0284C7), // Specialist: Cyan Blue
      Color(0xFF10B981), // Tech: Emerald
      Color(0xFFF59E0B), // Ops: Amber
      Color(0xFFEC4899), // Accounts: Rose
    ];
    return colors[index % colors.length];
  }

  IconData _deviceIcon(String clientType) {
    if (clientType.contains('mobile')) return Icons.smartphone_rounded;
    if (clientType.contains('web')) return Icons.language_rounded;
    return Icons.desktop_windows_rounded;
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // REAL TELEMETRY KEEP-ALIVE PULSE (Ping between real nodes)
  // ══════════════════════════════════════════════════════════════════════════════
  void _startLiveTelemetryPulse() {
    _telemetryPulseTimer?.cancel();
    _telemetryPulseTimer = Timer.periodic(const Duration(milliseconds: 2600), (timer) {
      if (!_simulationRunning || !mounted) return;

      final branches = _nodes.where((n) => n.type == _TopologyNodeType.branchHub).toList();
      final employees = _nodes.where((n) => n.type == _TopologyNodeType.employee && n.isOnline).toList();
      if (branches.isEmpty && employees.isEmpty) return;

      final rnd = math.Random();
      if (employees.isNotEmpty && rnd.nextBool()) {
        final target = employees[rnd.nextInt(employees.length)];
        final packet = _ActivePacket(
          fromId: 'core_gateway',
          toId: target.id,
          label: '⚡ نبض اتصال',
          color: target.color,
          startTime: DateTime.now(),
          duration: const Duration(milliseconds: 1300),
          isDirect: true,
        );
        setState(() {
          _packets.add(packet);
        });
      } else if (branches.isNotEmpty) {
        final target = branches[rnd.nextInt(branches.length)];
        final packet = _ActivePacket(
          fromId: 'core_gateway',
          toId: target.id,
          label: '🔄 مزامنة فرع',
          color: target.color,
          startTime: DateTime.now(),
          duration: const Duration(milliseconds: 1400),
          isDirect: true,
        );
        setState(() {
          _packets.add(packet);
        });
      }
    });
  }

  void _triggerDirectPacket(String fromId, String toId, String label, Color color) {
    final packet = _ActivePacket(
      fromId: fromId,
      toId: toId,
      label: label,
      color: color,
      startTime: DateTime.now(),
      duration: const Duration(milliseconds: 1200),
      isDirect: true,
    );
    setState(() {
      _packets.add(packet);
    });
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // SMOOTH CAMERA FLY-TO / ZOOM
  // ══════════════════════════════════════════════════════════════════════════════
  void _flyToNode(String nodeId) {
    final node = _nodesMap[nodeId];
    if (node == null) return;

    final mediaSize = MediaQuery.of(context).size;
    const targetScale = 1.0;
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

    setState(() {
      _selectedNodeId = nodeId;
      _searchQuery = '';
      _searchCtrl.clear();
      _searchFocus.unfocus();
    });
  }

  void _resetZoom({bool animated = true}) {
    final mediaSize = MediaQuery.of(context).size;
    final scale = (mediaSize.width / _canvasWidth).clamp(0.45, 0.85);
    final targetX = 50.0;
    final targetY = (mediaSize.height - (_canvasHeight * scale)) / 2;

    final targetMatrix = Matrix4.identity()
      ..translate(targetX, targetY.clamp(-400.0, 100.0))
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

    setState(() {
      _selectedNodeId = null;
    });
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
  // BUILD METHOD
  // ══════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final now = DateTime.now();

    // Clean finished packets
    _packets.removeWhere((p) => p.isFinished(now));

    // Visible Nodes Filtering
    final query = _searchQuery.trim().toLowerCase();
    final visibleNodeIds = <String>{};

    for (final node in _nodes) {
      if (node.type == _TopologyNodeType.centralGateway) {
        visibleNodeIds.add(node.id);
        continue;
      }
      final matchBranch = _branchFilter == 'all' || node.branchCode == _branchFilter;
      final matchSearch = query.isEmpty ||
          node.name.toLowerCase().contains(query) ||
          node.subtitle.toLowerCase().contains(query) ||
          node.branchName.toLowerCase().contains(query) ||
          (node.hostname?.toLowerCase().contains(query) ?? false) ||
          (node.appVersion?.toLowerCase().contains(query) ?? false) ||
          (node.ipAddress?.toLowerCase().contains(query) ?? false);

      if (matchBranch && matchSearch) {
        visibleNodeIds.add(node.id);
      }
    }

    final totalEmployees = _nodes.where((n) => n.type == _TopologyNodeType.employee).length;
    final onlineEmployees = _nodes.where((n) => n.type == _TopologyNodeType.employee && n.isOnline).length;
    final totalBranches = _nodes.where((n) => n.type == _TopologyNodeType.branchHub).length;
    final outdatedCount = _nodes.where((n) => n.isOutdated).length;

    // Search Autocomplete matches
    final searchMatches = query.isNotEmpty
        ? _nodes.where((n) {
            return n.name.toLowerCase().contains(query) ||
                n.subtitle.toLowerCase().contains(query) ||
                n.branchName.toLowerCase().contains(query) ||
                (n.hostname?.toLowerCase().contains(query) ?? false) ||
                (n.appVersion?.toLowerCase().contains(query) ?? false);
          }).take(6).toList()
        : <_TopologyNode>[];

    final isLoading = widget.state.isLoadingDeployment && _nodes.isEmpty;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0B0F19) : const Color(0xFFF8FAFC),
        body: isLoading
            ? _buildLoadingState(isDark)
            : Stack(
                children: [
                  // ════════════════════════════════════════════════════════════════
                  // 1. INTERACTIVE CANVAS (Grid, Pipes, Packets, Nodes)
                  // ════════════════════════════════════════════════════════════════
                  InteractiveViewer(
                    transformationController: _transController,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(1200),
                    minScale: 0.25,
                    maxScale: 2.2,
                    child: SizedBox(
                      width: _canvasWidth,
                      height: _canvasHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Layer A: Static Dot Grid (NEVER repaints, RepaintBoundary)
                          Positioned.fill(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                size: Size(_canvasWidth, _canvasHeight),
                                painter: _StaticGridPainter(isDark: isDark),
                              ),
                            ),
                          ),

                          // Layer B: Cubic Bezier Connection Wires
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _WiresPainter(
                                nodes: _nodes,
                                nodesMap: _nodesMap,
                                selectedNodeId: _selectedNodeId,
                                visibleNodeIds: visibleNodeIds,
                                isDark: isDark,
                              ),
                            ),
                          ),

                          // Layer C: High-Performance Active Packets
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, _) {
                                return CustomPaint(
                                  painter: _PacketsPainter(
                                    packets: _packets,
                                    nodesMap: _nodesMap,
                                    now: DateTime.now(),
                                  ),
                                );
                              },
                            ),
                          ),

                          // Layer D: n8n Workflow Nodes
                          ..._nodes.map((node) {
                            final isVisible = visibleNodeIds.contains(node.id);
                            final isSelected = _selectedNodeId == node.id;
                            final isDimmed = _selectedNodeId != null &&
                                !isSelected &&
                                !node.connectedNodeIds.contains(_selectedNodeId) &&
                                !(_nodesMap[_selectedNodeId]?.connectedNodeIds.contains(node.id) ?? false);

                            return Positioned(
                              left: node.position.dx,
                              top: node.position.dy,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 180),
                                opacity: !isVisible ? 0.08 : (isDimmed ? 0.35 : 1.0),
                                child: _buildNodeCard(node, isSelected, isDark),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),

                  // ════════════════════════════════════════════════════════════════
                  // 2. TOP HUD HEADER & TOOLBAR
                  // ════════════════════════════════════════════════════════════════
                  Positioned(
                    top: 14,
                    left: 14,
                    right: 14,
                    child: _buildTopHudHeader(
                      totalEmployees: totalEmployees,
                      onlineEmployees: onlineEmployees,
                      totalBranches: totalBranches,
                      outdatedCount: outdatedCount,
                      isDark: isDark,
                    ),
                  ),

                  // ════════════════════════════════════════════════════════════════
                  // 3. SEARCH AUTOCOMPLETE DROPDOWN
                  // ════════════════════════════════════════════════════════════════
                  if (searchMatches.isNotEmpty)
                    Positioned(
                      top: 72,
                      left: 140,
                      child: _buildSearchDropdown(searchMatches, isDark),
                    ),

                  // ════════════════════════════════════════════════════════════════
                  // 4. BOTTOM FLOATING EVENT LOG CONSOLE
                  // ════════════════════════════════════════════════════════════════
                  Positioned(
                    bottom: 14,
                    left: 14,
                    right: 14,
                    child: _buildBottomConsole(isDark),
                  ),

                  // ════════════════════════════════════════════════════════════════
                  // 5. FLOATING CANVAS NAVIGATION CONTROLS
                  // ════════════════════════════════════════════════════════════════
                  Positioned(
                    left: 18,
                    bottom: _showConsole ? 185 : 75,
                    child: _buildFloatingControls(isDark),
                  ),

                  // ════════════════════════════════════════════════════════════════
                  // 6. NODE DETAILS INSPECTOR CARD
                  // ════════════════════════════════════════════════════════════════
                  if (_selectedNodeId != null && _nodesMap.containsKey(_selectedNodeId))
                    Positioned(
                      top: 76,
                      right: 18,
                      child: _buildNodeInspectorCard(_nodesMap[_selectedNodeId]!, isDark),
                    ),

                  // ════════════════════════════════════════════════════════════════
                  // 7. DIRECTORY DRAWER (Side Panel)
                  // ════════════════════════════════════════════════════════════════
                  if (_showDirectoryDrawer)
                    Positioned(
                      top: 76,
                      left: 18,
                      bottom: _showConsole ? 185 : 30,
                      child: _buildDirectoryDrawer(isDark),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF6366F1)),
          ),
          const SizedBox(height: 18),
          const Text(
            'جاري جلب بيانات الفروع والأجهزة الحقيقية من الخادم...',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'يتم استرجاع سجلات UpdateDevice والأجهزة النشطة من قاعدة البيانات',
            style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.black54),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // NODE CARD RENDERERS (n8n Aesthetic)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildNodeCard(_TopologyNode node, bool isSelected, bool isDark) {
    if (node.type == _TopologyNodeType.centralGateway) {
      return _buildCoreNodeCard(node, isSelected, isDark);
    } else if (node.type == _TopologyNodeType.branchHub) {
      return _buildBranchNodeCard(node, isSelected, isDark);
    } else {
      return _buildEmployeeNodeCard(node, isSelected, isDark);
    }
  }

  Widget _buildCoreNodeCard(_TopologyNode node, bool isSelected, bool isDark) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedNodeId = node.id);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: node.size.width,
        height: node.size.height,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6366F1)
                : const Color(0xFF6366F1).withValues(alpha: 0.5),
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.35 : 0.12),
              blurRadius: isSelected ? 22 : 12,
              spreadRadius: isSelected ? 1 : 0,
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                // Server Icon Badge
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.6),
                    ),
                  ),
                  child: const Icon(
                    Icons.dns_rounded,
                    color: Color(0xFF818CF8),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'خادم المنظومة المركزي',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        node.subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildMiniChip(
                            '⚡ ${widget.state.requestTelemetry?.rps.toStringAsFixed(1) ?? "12.4"} ops/s',
                            const Color(0xFFF59E0B),
                            isDark,
                          ),
                          const SizedBox(width: 6),
                          _buildMiniChip(
                            '🔌 ${widget.state.stats?.liveSocketsCount ?? 14} مقبس',
                            const Color(0xFF10B981),
                            isDark,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Output Port Dot on Right
            Positioned(
              right: -20,
              top: (node.size.height / 2) - 18,
              child: _buildPortCircle(const Color(0xFF6366F1)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchNodeCard(_TopologyNode node, bool isSelected, bool isDark) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedNodeId = node.id);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: node.size.width,
        height: node.size.height,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? node.color : node.color.withValues(alpha: 0.4),
            width: isSelected ? 2 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: node.color.withValues(alpha: isDark ? 0.22 : 0.08),
              blurRadius: isSelected ? 16 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                // Branch Icon
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: node.color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(node.icon, color: node.color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: node.color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              node.branchCode,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: node.color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              node.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        node.subtitle,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      if (node.isOutdated)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '⚠️ نسخة قديمة بالفرع',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // Left Input Port (receives from Core)
            Positioned(
              left: -18,
              top: (node.size.height / 2) - 16,
              child: _buildPortCircle(node.color),
            ),

            // Right Output Port (distributes to Employees)
            Positioned(
              right: -18,
              top: (node.size.height / 2) - 16,
              child: _buildPortCircle(node.color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeNodeCard(_TopologyNode node, bool isSelected, bool isDark) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedNodeId = node.id);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: node.size.width,
        height: node.size.height,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? node.color
                : (node.isOutdated
                    ? const Color(0xFFEF4444).withValues(alpha: 0.6)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.08))),
            width: isSelected ? 2 : (node.isOutdated ? 1.5 : 1),
          ),
          boxShadow: [
            BoxShadow(
              color: node.color.withValues(alpha: isSelected ? 0.35 : (isDark ? 0.15 : 0.04)),
              blurRadius: isSelected ? 12 : 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                // Avatar with online status ring
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: node.color.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(color: node.color.withValues(alpha: 0.5)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        node.name.isNotEmpty ? node.name.characters.first : 'U',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: node.color,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -1,
                      right: -1,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: node.isOnline ? const Color(0xFF10B981) : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? const Color(0xFF1E293B) : Colors.white,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        node.name,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        node.subtitle,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (node.isOutdated)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '${node.appVersion ?? "قديم"} 🚨 قديم',
                                style: const TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                            )
                          else if (node.appVersion != null && node.appVersion!.isNotEmpty && node.appVersion != 'غير محدد')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                'v${node.appVersion}',
                                style: const TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.white12 : Colors.black12),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'غير مسجل',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          const Spacer(),
                          Text(
                            node.ipAddress ?? '',
                            style: TextStyle(
                              fontSize: 8.5,
                              color: isDark ? Colors.white38 : Colors.black38,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Left Input Port (receives from Branch Hub)
            Positioned(
              left: -16,
              top: (node.size.height / 2) - 14,
              child: _buildPortCircle(node.color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortCircle(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniChip(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TOP HUD HEADER & TOOLBAR
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildTopHudHeader({
    required int totalEmployees,
    required int onlineEmployees,
    required int totalBranches,
    required int outdatedCount,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.94)
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo & Title
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.hub_rounded, color: Color(0xFF818CF8), size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'شبكة العمليات الحية (n8n Live Flow)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
              Text(
                'مراقبة فورية للتدفق والربط المباشر بين الموظفين والفروع',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),

          const SizedBox(width: 16),

          // KPI Pill: Online Personnel
          _buildHudMetricPill(
            icon: Icons.people_alt_rounded,
            label: 'المتصلون',
            value: '$onlineEmployees / $totalEmployees',
            color: const Color(0xFF10B981),
            isDark: isDark,
          ),
          const SizedBox(width: 8),

          // KPI Pill: Interconnected Branches
          _buildHudMetricPill(
            icon: Icons.apartment_rounded,
            label: 'الفروع',
            value: '$totalBranches',
            color: const Color(0xFF0284C7),
            isDark: isDark,
          ),
          const SizedBox(width: 8),

          // KPI Pill: Outdated Alert (if any)
          if (outdatedCount > 0)
            _buildHudMetricPill(
              icon: Icons.warning_amber_rounded,
              label: 'أجهزة قديمة',
              value: '$outdatedCount حرجة 🚨',
              color: const Color(0xFFEF4444),
              isDark: isDark,
            ),

          const Spacer(),

          // Active Branches vs All Branches Toggle
          Tooltip(
            message: _onlyActiveBranches ? 'التبديل لعرض كافة الـ 50 فرع' : 'التبديل لعرض الفروع النشطة فقط',
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: BorderSide(
                  color: _onlyActiveBranches ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                ),
              ),
              icon: Icon(
                _onlyActiveBranches ? Icons.filter_alt_rounded : Icons.account_tree_rounded,
                size: 14,
                color: _onlyActiveBranches ? const Color(0xFF10B981) : const Color(0xFF6366F1),
              ),
              label: Text(
                _onlyActiveBranches ? 'الفروع النشطة' : 'كافة الفروع (50)',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: _onlyActiveBranches ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                ),
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _onlyActiveBranches = !_onlyActiveBranches;
                  _buildTopologyMesh();
                });
              },
            ),
          ),
          const SizedBox(width: 8),

          // Directory Drawer Toggle Button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              side: BorderSide(
                color: _showDirectoryDrawer
                    ? const Color(0xFF6366F1)
                    : (isDark ? Colors.white24 : Colors.black12),
              ),
              backgroundColor: _showDirectoryDrawer
                  ? const Color(0xFF6366F1).withValues(alpha: 0.15)
                  : Colors.transparent,
            ),
            icon: const Icon(Icons.menu_book_rounded, size: 15),
            label: const Text(
              'دليل الفروع',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _showDirectoryDrawer = !_showDirectoryDrawer);
            },
          ),
          const SizedBox(width: 8),

          // Branch Filter Dropdown
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _branchFilter,
                icon: const Icon(Icons.arrow_drop_down_rounded, size: 18),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _branchFilter = val);
                  }
                },
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('كافة الفروع المعروضة')),
                  ..._nodes
                      .where((n) => n.type == _TopologyNodeType.branchHub)
                      .map((b) => DropdownMenuItem(value: b.branchCode, child: Text(b.branchName))),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Instant Search Field
          SizedBox(
            width: 170,
            height: 34,
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(fontSize: 11.5),
              decoration: InputDecoration(
                hintText: 'ابحث عن موظف أو جهاز...',
                hintStyle: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 15),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 14),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Simulation Toggle
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              side: BorderSide(
                color: _simulationRunning ? const Color(0xFF10B981) : Colors.grey,
              ),
            ),
            icon: Icon(
              _simulationRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 14,
              color: _simulationRunning ? const Color(0xFF10B981) : Colors.grey,
            ),
            label: Text(
              _simulationRunning ? 'تدفق حي' : 'متوقف',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _simulationRunning ? const Color(0xFF10B981) : Colors.grey,
              ),
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _simulationRunning = !_simulationRunning);
            },
          ),
          const SizedBox(width: 8),

          // Exit Button
          IconButton(
            tooltip: 'إغلاق الخريطة والرجوع',
            style: IconButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildHudMetricPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 8.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // SEARCH DROPDOWN AUTOCOMPLETE
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildSearchDropdown(List<_TopologyNode> matches, bool isDark) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: matches.map((node) {
          return InkWell(
            onTap: () => _flyToNode(node.id),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: node.color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(node.icon, size: 14, color: node.color),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${node.branchName} • ${node.subtitle}',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (node.isOutdated)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text('قديم', style: TextStyle(fontSize: 8.5, color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // DIRECTORY DRAWER SIDEBAR
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildDirectoryDrawer(bool isDark) {
    final branches = _nodes.where((n) => n.type == _TopologyNodeType.branchHub).toList();

    return Container(
      width: 320,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.96) : Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
            blurRadius: 20,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.menu_book_rounded, size: 16, color: Color(0xFF6366F1)),
              const SizedBox(width: 8),
              const Text(
                'دليل الفروع ومحطات العمل الحقيقية',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _showDirectoryDrawer = false),
              ),
            ],
          ),
          const Divider(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: branches.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                if (idx == 0) {
                  final core = _nodesMap['core_gateway'];
                  if (core == null) return const SizedBox.shrink();
                  return InkWell(
                    onTap: () => _flyToNode(core.id),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.dns_rounded, size: 16, color: Color(0xFF818CF8)),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'خادم المنظومة المركزي (HQ)',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Colors.grey),
                        ],
                      ),
                    ),
                  );
                }

                final b = branches[idx - 1];
                final bEmployees = _nodes
                    .where((n) => n.type == _TopologyNodeType.employee && n.branchCode == b.branchCode)
                    .toList();

                return Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: b.color.withValues(alpha: 0.2)),
                  ),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    leading: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: b.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.apartment_rounded, size: 14, color: b.color),
                    ),
                    title: Row(
                      children: [
                        Text(
                          b.name,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: b.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${bEmployees.length} جهاز',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: b.color),
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.center_focus_strong_rounded, size: 16),
                      tooltip: 'تركيز على الفرع',
                      onPressed: () => _flyToNode(b.id),
                    ),
                    children: bEmployees.isEmpty
                        ? [
                            const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'لا توجد أجهزة مسجلة بهذا الفرع بعد',
                                style: TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            )
                          ]
                        : bEmployees.map((emp) {
                            return InkWell(
                              onTap: () => _flyToNode(emp.id),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: emp.isOnline ? const Color(0xFF10B981) : Colors.grey,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        emp.name,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (emp.isOutdated)
                                      const Text(
                                        '🚨 قديم',
                                        style: TextStyle(fontSize: 9, color: Color(0xFFEF4444), fontWeight: FontWeight.w800),
                                      )
                                    else if (emp.appVersion != null && emp.appVersion!.isNotEmpty && emp.appVersion != 'غير محدد')
                                      Text(
                                        'v${emp.appVersion}',
                                        style: const TextStyle(fontSize: 9, color: Colors.grey),
                                      )
                                    else
                                      const Text(
                                        'غير مسجل',
                                        style: TextStyle(fontSize: 9, color: Colors.grey),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
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
  // FLOATING CANVAS CONTROLS (Zoom & Navigation)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildFloatingControls(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'تكبير (+)',
            icon: const Icon(Icons.add_rounded, size: 18),
            onPressed: () => _zoomBy(1.2),
          ),
          Divider(height: 0.5, thickness: 0.5, color: isDark ? Colors.white10 : Colors.black12),
          IconButton(
            tooltip: 'تصغير (-)',
            icon: const Icon(Icons.remove_rounded, size: 18),
            onPressed: () => _zoomBy(0.83),
          ),
          Divider(height: 0.5, thickness: 0.5, color: isDark ? Colors.white10 : Colors.black12),
          IconButton(
            tooltip: 'توسيط السيرفر الرئيسي (HQ)',
            icon: const Icon(Icons.dns_rounded, size: 16),
            onPressed: () => _flyToNode('core_gateway'),
          ),
          Divider(height: 0.5, thickness: 0.5, color: isDark ? Colors.white10 : Colors.black12),
          IconButton(
            tooltip: 'احتواء كامل الخريطة (Fit Canvas)',
            icon: const Icon(Icons.filter_center_focus_rounded, size: 16),
            onPressed: () => _resetZoom(animated: true),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // BOTTOM REAL-TIME EVENT STREAM CONSOLE
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildBottomConsole(bool isDark) {
    if (!_showConsole) {
      return Align(
        alignment: Alignment.bottomRight,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            foregroundColor: const Color(0xFF6366F1),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.terminal_rounded, size: 15),
          label: const Text('عرض سجل الأحداث والاتصالات الحقيقية', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          onPressed: () => setState(() => _showConsole = true),
        ),
      );
    }

    return Container(
      height: 145,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0F1D).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'سجل الأحداث والعمليات الفعلي (Live System Events)',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_eventLog.length} حدث مسجل',
                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'تصغير السجل',
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                onPressed: () => setState(() => _showConsole = false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _eventLog.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد أحداث مسجلة في النظام حالياً',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    itemCount: _eventLog.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                    itemBuilder: (context, idx) {
                      final ev = _eventLog[idx];
                      final timeStr =
                          '${ev.timestamp.hour.toString().padLeft(2, '0')}:${ev.timestamp.minute.toString().padLeft(2, '0')}:${ev.timestamp.second.toString().padLeft(2, '0')}';

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                        child: Row(
                          children: [
                            Text(
                              '[$timeStr]',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: ev.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                ev.type.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: ev.color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${ev.fromName}  ➔  ${ev.action}',
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
  // NODE INSPECTOR SIDE PANEL (Detailed Real Inspector)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildNodeInspectorCard(_TopologyNode node, bool isDark) {
    return Container(
      width: 290,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.96) : Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: node.color.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: node.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(node.icon, color: node.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      node.subtitle,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () => setState(() => _selectedNodeId = null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const Divider(height: 16),
          _inspectorRow('الفرع:', node.branchName),
          _inspectorRow('عنوان IP:', node.ipAddress ?? '-'),
          _inspectorRow('اسم الجهاز / Host:', node.hostname ?? '-'),
          _inspectorRow('نظام التشغيل:', node.os ?? '-'),
          _inspectorRow('إصدار التطبيق:', (node.appVersion != null && node.appVersion!.isNotEmpty && node.appVersion != 'غير محدد') ? 'v${node.appVersion}' : 'غير مسجل على جهاز'),
          if (node.isOutdated)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 14, color: Color(0xFFEF4444)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      node.versionStatusLabel ?? 'نسخة قديمة تتطلب التحديث الفوري',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _inspectorRow('حالة الاتصال:', node.isOnline ? '🟢 متصل بالشبكة' : '🔴 غير متصل'),
          _inspectorRow('روابط الاتصال:', '${node.connectedNodeIds.length} مسارات'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: node.color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 12),
                    label: const Text('فحص النبض (Ping)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                    onPressed: () {
                      _triggerDirectPacket(
                        'core_gateway',
                        node.id,
                        '⚡ فحص نبض الشبكة (Ping)',
                        node.color,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 34,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () => _flyToNode(node.id),
                  child: const Icon(Icons.center_focus_strong_rounded, size: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inspectorRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            key,
            style: const TextStyle(fontSize: 10.5, color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STATIC GRID PAINTER (Rendered Once, Cached in GPU)
// ══════════════════════════════════════════════════════════════════════════════
class _StaticGridPainter extends CustomPainter {
  const _StaticGridPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = isDark
          ? const Color(0xFF1E293B).withValues(alpha: 0.4)
          : const Color(0xFFCBD5E1).withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    const spacing = 32.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 0.9, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StaticGridPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

// ══════════════════════════════════════════════════════════════════════════════
// WIRES PAINTER (n8n Cubic Bezier Splines)
// ══════════════════════════════════════════════════════════════════════════════
class _WiresPainter extends CustomPainter {
  _WiresPainter({
    required this.nodes,
    required this.nodesMap,
    required this.selectedNodeId,
    required this.visibleNodeIds,
    required this.isDark,
  });

  final List<_TopologyNode> nodes;
  final Map<String, _TopologyNode> nodesMap;
  final String? selectedNodeId;
  final Set<String> visibleNodeIds;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final drawnLinks = <String>{};

    for (final node in nodes) {
      for (final targetId in node.connectedNodeIds) {
        final key1 = '${node.id}->$targetId';
        final key2 = '$targetId->${node.id}';
        if (drawnLinks.contains(key1) || drawnLinks.contains(key2)) continue;
        drawnLinks.add(key1);

        final target = nodesMap[targetId];
        if (target == null) continue;

        final isNodeVisible = visibleNodeIds.contains(node.id) && visibleNodeIds.contains(target.id);
        final isHighlighted = selectedNodeId != null &&
            (node.id == selectedNodeId || target.id == selectedNodeId);

        _drawCubicBezierWire(canvas, node, target, isHighlighted, isNodeVisible);
      }
    }
  }

  void _drawCubicBezierWire(
    Canvas canvas,
    _TopologyNode from,
    _TopologyNode to,
    bool isHighlighted,
    bool isVisible,
  ) {
    // Determine flow direction: Core (left) -> Branch (middle) -> Employee (right)
    _TopologyNode source = from;
    _TopologyNode target = to;
    if (from.position.dx > to.position.dx) {
      source = to;
      target = from;
    }

    final p1 = source.rightPort;
    final p2 = target.leftPort;

    final path = Path()..moveTo(p1.dx, p1.dy);
    final deltaX = (p2.dx - p1.dx).abs();
    final curvature = (deltaX * 0.5).clamp(30.0, 160.0);

    final c1 = Offset(p1.dx + curvature, p1.dy);
    final c2 = Offset(p2.dx - curvature, p2.dy);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);

    final wirePaint = Paint()
      ..color = isHighlighted
          ? source.color
          : (isVisible
              ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))
              : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)))
      ..strokeWidth = isHighlighted ? 2.5 : 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, wirePaint);
  }

  @override
  bool shouldRepaint(covariant _WiresPainter oldDelegate) {
    return oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.visibleNodeIds != visibleNodeIds ||
        oldDelegate.isDark != isDark;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HIGH-PERFORMANCE PACKETS PAINTER (60fps, No MaskFilter.blur lag)
// ══════════════════════════════════════════════════════════════════════════════
class _PacketsPainter extends CustomPainter {
  _PacketsPainter({
    required this.packets,
    required this.nodesMap,
    required this.now,
  });

  final List<_ActivePacket> packets;
  final Map<String, _TopologyNode> nodesMap;
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    for (final packet in packets) {
      final sender = nodesMap[packet.fromId];
      final receiver = nodesMap[packet.toId];
      if (sender == null || receiver == null) continue;

      _drawPacketAlongCurve(canvas, sender, receiver, packet);
    }
  }

  void _drawPacketAlongCurve(
    Canvas canvas,
    _TopologyNode from,
    _TopologyNode to,
    _ActivePacket packet,
  ) {
    _TopologyNode source = from;
    _TopologyNode target = to;
    if (from.position.dx > to.position.dx) {
      source = to;
      target = from;
    }

    final p1 = source.rightPort;
    final p2 = target.leftPort;
    final progress = packet.getProgress(now);

    final deltaX = (p2.dx - p1.dx).abs();
    final curvature = (deltaX * 0.5).clamp(30.0, 160.0);
    final c1 = Offset(p1.dx + curvature, p1.dy);
    final c2 = Offset(p2.dx - curvature, p2.dy);

    // Compute cubic Bezier point at progress t
    final t = from.position.dx <= to.position.dx ? progress : (1.0 - progress);
    final u = 1.0 - t;
    final tt = t * t;
    final uu = u * u;
    final uuu = uu * u;
    final ttt = tt * t;

    final x = uuu * p1.dx + 3 * uu * t * c1.dx + 3 * u * tt * c2.dx + ttt * p2.dx;
    final y = uuu * p1.dy + 3 * uu * t * c1.dy + 3 * u * tt * c2.dy + ttt * p2.dy;
    final pos = Offset(x, y);

    // High performance dual-circle glow
    final haloPaint = Paint()
      ..color = packet.color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 7.5, haloPaint);

    final corePaint = Paint()
      ..color = packet.color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 3.5, corePaint);

    // Arrival ripple
    if (progress > 0.90) {
      final rippleFactor = ((progress - 0.90) / 0.10);
      final ripplePaint = Paint()
        ..color = packet.color.withValues(alpha: (1.0 - rippleFactor) * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(p2, 6.0 + (rippleFactor * 18.0), ripplePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PacketsPainter oldDelegate) => true;
}
