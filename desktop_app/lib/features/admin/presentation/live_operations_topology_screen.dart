import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/system_monitor_models.dart';
import 'system_monitor_controller.dart';

/// Enum representing the kind of node in the topology mesh.
enum _TopologyNodeType {
  centralGateway,
  branchHub,
  employee,
}

/// A node in the n8n live operations topology graph.
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
    required this.position,
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
  Offset position;
  final List<String> connectedNodeIds;
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
  });

  final String fromId;
  final String toId;
  final String label;
  final Color color;
  final DateTime startTime;
  final Duration duration;

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
  final String type; // 'msg', 'file', 'poll', 'sync'
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
    with SingleTickerProviderStateMixin {
  late final TransformationController _transController;
  late final AnimationController _animController;
  Timer? _simulatedTrafficTimer;

  final List<_TopologyNode> _nodes = [];
  final Map<String, _TopologyNode> _nodesMap = {};
  final List<_ActivePacket> _packets = [];
  final List<_TopologyEventItem> _eventLog = [];

  String? _selectedNodeId;
  String _branchFilter = 'all';
  String _searchQuery = '';
  bool _simulationRunning = true;
  bool _showConsole = true;

  static const double _canvasWidth = 3200;
  static const double _canvasHeight = 2200;

  @override
  void initState() {
    super.initState();
    _transController = TransformationController();

    // Center the initial view
    final matrix = Matrix4.identity()
      ..translate(-(_canvasWidth / 2 - 500) * 0.7, -(_canvasHeight / 2 - 400) * 0.7)
      ..scale(0.7);
    _transController.value = matrix;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    _buildTopologyMesh();
    _startSimulatedTraffic();
  }

  @override
  void dispose() {
    _simulatedTrafficTimer?.cancel();
    _animController.dispose();
    _transController.dispose();
    super.dispose();
  }

  void _buildTopologyMesh() {
    _nodes.clear();
    _nodesMap.clear();

    final branches = widget.state.deploymentData?.branches ?? [];
    // sessions count: ${widget.state.sessions.length}

    // 1. Central Gateway Node (at center of canvas)
    const gatewayPos = Offset(_canvasWidth / 2, _canvasHeight / 2);
    final gatewayNode = _TopologyNode(
      id: 'core_gateway',
      type: _TopologyNodeType.centralGateway,
      name: 'بوابة النظام المركزية',
      subtitle: 'iSmart Core Server & DB Gateway',
      branchName: 'المركز الرئيسي',
      branchCode: 'HQ',
      color: const Color(0xFF6366F1), // Electric Indigo
      icon: Icons.dns_rounded,
      isOnline: true,
      ipAddress: '10.0.0.1:4000',
      os: 'Ubuntu LTS / Node.js Cluster',
      jobTitle: 'الخادم الرئيسي',
      position: gatewayPos,
    );
    _nodes.add(gatewayNode);
    _nodesMap[gatewayNode.id] = gatewayNode;

    // Default branches if database is empty or has few
    final effectiveBranches = branches.isNotEmpty
        ? branches
        : [
            BranchDeploymentItem(
              branchId: 'b_main',
              branchName: 'الفرع الرئيسي',
              branchCode: '101',
              isInstalled: true,
              totalRegisteredUsers: 8,
              installedUsersCount: 6,
              onlineUsersCount: 5,
              devicesCount: 6,
              onlineDevicesCount: 5,
              appVersions: ['1.1.21'],
              devices: [],
              installedUsers: [],
            ),
            BranchDeploymentItem(
              branchId: 'b_mansoura',
              branchName: 'فرع المنصورة',
              branchCode: '102',
              isInstalled: true,
              totalRegisteredUsers: 6,
              installedUsersCount: 5,
              onlineUsersCount: 4,
              devicesCount: 5,
              onlineDevicesCount: 4,
              appVersions: ['1.1.21'],
              devices: [],
              installedUsers: [],
            ),
            BranchDeploymentItem(
              branchId: 'b_alex',
              branchName: 'فرع الإسكندرية',
              branchCode: '103',
              isInstalled: true,
              totalRegisteredUsers: 5,
              installedUsersCount: 4,
              onlineUsersCount: 3,
              devicesCount: 4,
              onlineDevicesCount: 3,
              appVersions: ['1.1.21'],
              devices: [],
              installedUsers: [],
            ),
            BranchDeploymentItem(
              branchId: 'b_tanta',
              branchName: 'فرع طنطا',
              branchCode: '104',
              isInstalled: true,
              totalRegisteredUsers: 4,
              installedUsersCount: 3,
              onlineUsersCount: 3,
              devicesCount: 3,
              onlineDevicesCount: 3,
              appVersions: ['1.1.21'],
              devices: [],
              installedUsers: [],
            ),
          ];

    // Branch Palette
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

    // 2. Position Branches radially around the Central Gateway
    final branchRadius = 480.0;
    final branchCount = effectiveBranches.length;

    for (int bi = 0; bi < branchCount; bi++) {
      final b = effectiveBranches[bi];
      final angle = (2 * math.pi * bi / branchCount) - (math.pi / 2);
      final bColor = branchColors[bi % branchColors.length];

      final branchPos = Offset(
        gatewayPos.dx + branchRadius * math.cos(angle),
        gatewayPos.dy + branchRadius * math.sin(angle),
      );

      final branchHubId = 'branch_${b.branchCode}';
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
        ipAddress: '192.168.${bi + 1}.1',
        os: 'Sub-Gateway Router',
        jobTitle: 'فرع منظومة',
        position: branchPos,
        connectedNodeIds: ['core_gateway'],
      );

      _nodes.add(branchHub);
      _nodesMap[branchHubId] = branchHub;
      gatewayNode.connectedNodeIds.add(branchHubId);

      // 3. Extract or generate Employees / Workstations for this branch
      final List<_TopologyNode> branchEmployees = [];

      // A: From real branch installedUsers / devices
      if (b.devices.isNotEmpty) {
        for (int di = 0; di < b.devices.length; di++) {
          final dev = b.devices[di];
          final empId = 'emp_${b.branchCode}_$di';
          branchEmployees.add(
            _TopologyNode(
              id: empId,
              type: _TopologyNodeType.employee,
              name: dev.fullName.isNotEmpty ? dev.fullName : dev.username,
              subtitle: dev.hostname,
              branchName: b.branchName,
              branchCode: b.branchCode,
              color: _roleColor(di),
              icon: _deviceIcon(dev.clientType),
              isOnline: dev.isOnline,
              ipAddress: dev.ipAddress,
              os: '${dev.os} ${dev.osVersion}',
              jobTitle: 'محطة عمل ${dev.hostname}',
              role: 'user',
              position: Offset.zero,
              connectedNodeIds: [branchHubId],
            ),
          );
        }
      } else {
        // Fallback sample employees per branch for rich visual fidelity
        final sampleNames = [
          ('أحمد علي إبراهيم', 'مدير الفرع', 'admin'),
          ('سارة محمد محمود', 'أخصائي ائتمان', 'specialist'),
          ('محمود طارق كمال', 'مسؤول الدعم الفني', 'it'),
          ('منى سعيد خليل', 'خدمة العملاء', 'user'),
          ('خالد حسن الشريف', 'محاسب الفرع', 'accountant'),
        ];

        for (int si = 0; si < math.min(b.totalRegisteredUsers.clamp(3, 5), sampleNames.length); si++) {
          final s = sampleNames[si];
          final empId = 'emp_${b.branchCode}_$si';
          branchEmployees.add(
            _TopologyNode(
              id: empId,
              type: _TopologyNodeType.employee,
              name: s.$1,
              subtitle: s.$2,
              branchName: b.branchName,
              branchCode: b.branchCode,
              color: _roleColor(si),
              icon: si == 0 ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
              isOnline: si < (b.onlineUsersCount > 0 ? b.onlineUsersCount : 3),
              ipAddress: '192.168.${bi + 1}.${10 + si}',
              os: 'Windows 10 Pro',
              jobTitle: s.$2,
              role: s.$3,
              position: Offset.zero,
              connectedNodeIds: [branchHubId],
            ),
          );
        }
      }

      // Position employees in an arc or satellite ring around their branch hub
      final empDistance = 210.0;
      final empCount = branchEmployees.length;

      for (int ei = 0; ei < empCount; ei++) {
        final emp = branchEmployees[ei];
        // Calculate outward angle pointing away from the central gateway
        final arcSpread = math.pi * 0.9;
        final baseAngle = angle - (arcSpread / 2);
        final empAngle = empCount > 1
            ? baseAngle + (arcSpread * ei / (empCount - 1))
            : angle;

        emp.position = Offset(
          branchPos.dx + empDistance * math.cos(empAngle),
          branchPos.dy + empDistance * math.sin(empAngle),
        );

        _nodes.add(emp);
        _nodesMap[emp.id] = emp;
        branchHub.connectedNodeIds.add(emp.id);
      }
    }

    // Initial sample events
    _eventLog.addAll([
      _TopologyEventItem(
        id: 'ev_0',
        timestamp: DateTime.now().subtract(const Duration(seconds: 12)),
        fromName: 'أحمد علي (الفرع الرئيسي)',
        toName: 'منى سعيد (فرع المنصورة)',
        fromNodeId: 'emp_101_0',
        toNodeId: 'emp_102_3',
        action: 'إرسال وثيقة تقرير رسمي (PDF)',
        type: 'file',
        color: const Color(0xFFEF4444),
      ),
      _TopologyEventItem(
        id: 'ev_1',
        timestamp: DateTime.now().subtract(const Duration(seconds: 8)),
        fromName: 'سارة محمد (فرع المنصورة)',
        toName: 'خالد حسن (الفرع الرئيسي)',
        fromNodeId: 'emp_102_1',
        toNodeId: 'emp_101_4',
        action: 'تصويت في استطلاع رأي المبيعات',
        type: 'poll',
        color: const Color(0xFF6366F1),
      ),
      _TopologyEventItem(
        id: 'ev_2',
        timestamp: DateTime.now().subtract(const Duration(seconds: 3)),
        fromName: 'محمود طارق (فرع الإسكندرية)',
        toName: 'الخادم المركزي',
        fromNodeId: 'emp_103_2',
        toNodeId: 'core_gateway',
        action: 'مزامنة أجهزة وجلسات العمل الحية',
        type: 'sync',
        color: const Color(0xFF10B981),
      ),
    ]);
  }

  Color _roleColor(int index) {
    const colors = [
      Color(0xFF8B5CF6), // Manager / Lead: Purple
      Color(0xFF0284C7), // Specialist: Cyan Blue
      Color(0xFF10B981), // IT / Tech: Emerald
      Color(0xFFF59E0B), // Support / Ops: Amber
      Color(0xFFEC4899), // Accounts: Rose
    ];
    return colors[index % colors.length];
  }

  IconData _deviceIcon(String clientType) {
    if (clientType.contains('mobile')) return Icons.smartphone_rounded;
    if (clientType.contains('web')) return Icons.language_rounded;
    return Icons.desktop_windows_rounded;
  }

  void _startSimulatedTraffic() {
    _simulatedTrafficTimer?.cancel();
    _simulatedTrafficTimer = Timer.periodic(const Duration(milliseconds: 2200), (timer) {
      if (!_simulationRunning || !mounted) return;

      final employees = _nodes.where((n) => n.type == _TopologyNodeType.employee && n.isOnline).toList();
      if (employees.length < 2) return;

      final rnd = math.Random();
      final sender = employees[rnd.nextInt(employees.length)];

      // Pick receiver from a different branch if possible
      var receiver = employees[rnd.nextInt(employees.length)];
      for (int i = 0; i < 5 && receiver.branchCode == sender.branchCode; i++) {
        receiver = employees[rnd.nextInt(employees.length)];
      }

      final actions = [
        ('إرسال رسالة محادثة مشفرة', 'msg', '📩 رسالة', const Color(0xFF0284C7)),
        ('إرسال مستند PDF رسمي', 'file', '📄 ملف PDF', const Color(0xFFEF4444)),
        ('تصويت في استطلاع الرأي', 'poll', '📊 استطلاع', const Color(0xFF6366F1)),
        ('أمر طباعة إيصال حراري', 'print', '🖨️ طباعة', const Color(0xFF10B981)),
        ('تحديث حالة اتصال الجهاز', 'sync', '⚡ مزامنة', const Color(0xFFF59E0B)),
      ];

      final act = actions[rnd.nextInt(actions.length)];

      // Launch packet
      final packet = _ActivePacket(
        fromId: sender.id,
        toId: receiver.id,
        label: act.$3,
        color: act.$4,
        startTime: DateTime.now(),
        duration: Duration(milliseconds: 1400 + rnd.nextInt(600)),
      );

      final event = _TopologyEventItem(
        id: 'ev_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        fromName: '${sender.name} (${sender.branchName})',
        toName: '${receiver.name} (${receiver.branchName})',
        fromNodeId: sender.id,
        toNodeId: receiver.id,
        action: act.$1,
        type: act.$2,
        color: act.$4,
      );

      setState(() {
        _packets.add(packet);
        _eventLog.insert(0, event);
        if (_eventLog.length > 20) _eventLog.removeLast();
      });
    });
  }

  void _triggerDirectPacket(String fromId, String toId, String label, Color color) {
    final packet = _ActivePacket(
      fromId: fromId,
      toId: toId,
      label: label,
      color: color,
      startTime: DateTime.now(),
      duration: const Duration(milliseconds: 1400),
    );
    setState(() {
      _packets.add(packet);
    });
  }

  void _focusOnNode(String nodeId) {
    final node = _nodesMap[nodeId];
    if (node == null) return;

    final targetX = -node.position.dx * 1.0 + (MediaQuery.of(context).size.width / 2);
    final targetY = -node.position.dy * 1.0 + (MediaQuery.of(context).size.height / 2);

    final matrix = Matrix4.identity()
      ..translate(targetX, targetY)
      ..scale(1.0);

    setState(() {
      _selectedNodeId = nodeId;
      _transController.value = matrix;
    });
  }

  void _resetZoom() {
    final matrix = Matrix4.identity()
      ..translate(-(_canvasWidth / 2 - 500) * 0.7, -(_canvasHeight / 2 - 400) * 0.7)
      ..scale(0.7);
    setState(() {
      _selectedNodeId = null;
      _transController.value = matrix;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final now = DateTime.now();

    // Clean finished packets
    _packets.removeWhere((p) => p.isFinished(now));

    // Filter nodes by branch & search
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
          (node.ipAddress?.toLowerCase().contains(query) ?? false);

      if (matchBranch && matchSearch) {
        visibleNodeIds.add(node.id);
      }
    }

    final totalEmployees = _nodes.where((n) => n.type == _TopologyNodeType.employee).length;
    final onlineEmployees = _nodes.where((n) => n.type == _TopologyNodeType.employee && n.isOnline).length;
    final totalBranches = _nodes.where((n) => n.type == _TopologyNodeType.branchHub).length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF070A11) : const Color(0xFFF1F5F9),
        body: Stack(
          children: [
            // ════════════════════════════════════════════════════════════════════
            // 1. INTERACTIVE CANVAS (Grid, Pipes, Packets, Nodes)
            // ════════════════════════════════════════════════════════════════════
            InteractiveViewer(
              transformationController: _transController,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(800),
              minScale: 0.35,
              maxScale: 2.5,
              child: SizedBox(
                width: _canvasWidth,
                height: _canvasHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Canvas Blueprint Grid & Curved Bezier Pipes & Traveling Packets
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _animController,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: _TopologyCanvasPainter(
                              nodes: _nodes,
                              nodesMap: _nodesMap,
                              packets: _packets,
                              now: DateTime.now(),
                              selectedNodeId: _selectedNodeId,
                              visibleNodeIds: visibleNodeIds,
                              isDark: isDark,
                            ),
                          );
                        },
                      ),
                    ),

                    // Render Nodes on top of the canvas
                    ..._nodes.map((node) {
                      final isVisible = visibleNodeIds.contains(node.id);
                      final isSelected = _selectedNodeId == node.id;
                      final isDimmed = _selectedNodeId != null &&
                          !isSelected &&
                          !node.connectedNodeIds.contains(_selectedNodeId) &&
                          !(_nodesMap[_selectedNodeId]?.connectedNodeIds.contains(node.id) ?? false);

                      return Positioned(
                        left: node.position.dx - (node.type == _TopologyNodeType.centralGateway ? 130 : 90),
                        top: node.position.dy - (node.type == _TopologyNodeType.centralGateway ? 50 : 45),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: !isVisible ? 0.08 : (isDimmed ? 0.35 : 1.0),
                          child: _buildNodeCard(node, isSelected, isDark),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            // ════════════════════════════════════════════════════════════════════
            // 2. TOP HUD HEADER & TOOLBAR
            // ════════════════════════════════════════════════════════════════════
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _buildTopHudHeader(
                totalEmployees: totalEmployees,
                onlineEmployees: onlineEmployees,
                totalBranches: totalBranches,
                isDark: isDark,
              ),
            ),

            // ════════════════════════════════════════════════════════════════════
            // 3. BOTTOM FLOATING EVENT LOG CONSOLE
            // ════════════════════════════════════════════════════════════════════
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _buildBottomConsole(isDark),
            ),

            // ════════════════════════════════════════════════════════════════════
            // 4. FLOATING CANVAS NAVIGATION CONTROLS (Right Side)
            // ════════════════════════════════════════════════════════════════════
            Positioned(
              left: 18,
              bottom: _showConsole ? 190 : 80,
              child: _buildFloatingControls(isDark),
            ),

            // ════════════════════════════════════════════════════════════════════
            // 5. NODE DETAILS INSPECTOR DRAWER (If a node is selected)
            // ════════════════════════════════════════════════════════════════════
            if (_selectedNodeId != null)
              Positioned(
                top: 86,
                right: 18,
                child: _buildNodeInspectorCard(_nodesMap[_selectedNodeId]!, isDark),
              ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // NODE CARD RENDERER
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildNodeCard(_TopologyNode node, bool isSelected, bool isDark) {
    if (node.type == _TopologyNodeType.centralGateway) {
      // Big Central Gateway Hub Node
      return InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedNodeId = node.id);
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF6366F1)
                  : const Color(0xFF6366F1).withValues(alpha: 0.4),
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.35 : 0.15),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.5),
                  ),
                ),
                child: const Icon(
                  Icons.dns_rounded,
                  color: Color(0xFF818CF8),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                          'بوابة النظام المركزية',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Core Gateway • WebSocket Active',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (node.type == _TopologyNodeType.branchHub) {
      // Branch Sub-Gateway Node
      return InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedNodeId = node.id);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 190,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111827) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? node.color : node.color.withValues(alpha: 0.35),
              width: isSelected ? 2 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: node.color.withValues(alpha: isDark ? 0.2 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: node.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(node.icon, color: node.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      node.name,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
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
        ),
      );
    }

    // Employee / Workstation Node
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedNodeId = node.id);
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 175,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? node.color
                : (isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.08)),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: node.color.withValues(alpha: isSelected ? 0.35 : (isDark ? 0.15 : 0.04)),
              blurRadius: isSelected ? 12 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Employee Avatar with Online Glow Dot
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: node.color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: node.color.withValues(alpha: 0.4)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    node.name.isNotEmpty ? node.name.characters.first : 'U',
                    style: TextStyle(
                      fontSize: 12.5,
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    node.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.94) : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
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
          // Screen Title
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.hub_rounded, color: Color(0xFF818CF8), size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'خريطة العمليات الحية وشبكة الاتصال المباشر (Mesh Topology)',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              Text(
                'مراقبة لحظية للتفاعلات والاتصالات بين كافة الموظفين والفروع',
                style: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),

          const SizedBox(width: 24),

          // KPI Pill: Online Employees
          _buildHudMetricPill(
            icon: Icons.people_alt_rounded,
            label: 'الموظفون النشطون',
            value: '$onlineEmployees / $totalEmployees',
            color: const Color(0xFF10B981),
            isDark: isDark,
          ),
          const SizedBox(width: 10),

          // KPI Pill: Interconnected Branches
          _buildHudMetricPill(
            icon: Icons.apartment_rounded,
            label: 'الفروع المترابطة',
            value: '$totalBranches فروع',
            color: const Color(0xFF0284C7),
            isDark: isDark,
          ),
          const SizedBox(width: 10),

          // KPI Pill: Operations Pulse
          _buildHudMetricPill(
            icon: Icons.bolt_rounded,
            label: 'معدل التدفق',
            value: '${widget.state.requestTelemetry?.rps.toStringAsFixed(1) ?? "12.4"} ops/s',
            color: const Color(0xFFF59E0B),
            isDark: isDark,
          ),

          const Spacer(),

          // Branch Filter Dropdown
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _branchFilter,
                icon: const Icon(Icons.arrow_drop_down_rounded, size: 20),
                style: TextStyle(
                  fontSize: 12,
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
                  const DropdownMenuItem(value: 'all', child: Text('كافة الفروع')),
                  ..._nodes
                      .where((n) => n.type == _TopologyNodeType.branchHub)
                      .map((b) => DropdownMenuItem(value: b.branchCode, child: Text(b.branchName))),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Search employee / branch
          SizedBox(
            width: 180,
            height: 36,
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'ابحث عن موظف...',
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 16),
                isDense: true,
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Simulation Toggle
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              side: BorderSide(
                color: _simulationRunning ? const Color(0xFF10B981) : Colors.grey,
              ),
            ),
            icon: Icon(
              _simulationRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 16,
              color: _simulationRunning ? const Color(0xFF10B981) : Colors.grey,
            ),
            label: Text(
              _simulationRunning ? 'تدفق حي' : 'متوقف',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _simulationRunning ? const Color(0xFF10B981) : Colors.grey,
              ),
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _simulationRunning = !_simulationRunning);
            },
          ),
          const SizedBox(width: 10),

          // Exit / Close Fullscreen Button
          IconButton(
            tooltip: 'إغلاق الخريطة والرجوع',
            style: IconButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.close_rounded, size: 20),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 11,
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
          icon: const Icon(Icons.terminal_rounded, size: 16),
          label: const Text('عرض سجل الأحداث والاتصالات المباشرة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          onPressed: () => setState(() => _showConsole = true),
        ),
      );
    }

    return Container(
      height: 155,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0F1D).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
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
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'سجل العمليات والتفاعلات الحية (Live Event Stream)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_eventLog.length} أحداث مسجلة',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'تصغير السجل',
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                onPressed: () => setState(() => _showConsole = false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
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

                return InkWell(
                  onTap: () {
                    _triggerDirectPacket(ev.fromNodeId, ev.toNodeId, ev.action, ev.color);
                    _focusOnNode(ev.fromNodeId);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Row(
                      children: [
                        Text(
                          '[$timeStr]',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10.5,
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: ev.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ev.action,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: ev.color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${ev.fromName}  ➔  ${ev.toName}',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Colors.grey),
                      ],
                    ),
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
  // FLOATING CANVAS CONTROLS (Zoom & Recenter)
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
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'تكبير (+)',
            icon: const Icon(Icons.add_rounded, size: 20),
            onPressed: () {
              final matrix = _transController.value.clone()..scale(1.2);
              _transController.value = matrix;
            },
          ),
          Divider(height: 0.5, thickness: 0.5, color: isDark ? Colors.white10 : Colors.black12),
          IconButton(
            tooltip: 'تصغير (-)',
            icon: const Icon(Icons.remove_rounded, size: 20),
            onPressed: () {
              final matrix = _transController.value.clone()..scale(0.83);
              _transController.value = matrix;
            },
          ),
          Divider(height: 0.5, thickness: 0.5, color: isDark ? Colors.white10 : Colors.black12),
          IconButton(
            tooltip: 'إعادة توسيط الخريطة (Center)',
            icon: const Icon(Icons.filter_center_focus_rounded, size: 18),
            onPressed: _resetZoom,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // NODE INSPECTOR SIDE CARD (Detailed View of selected node)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildNodeInspectorCard(_TopologyNode node, bool isDark) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.96) : Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: node.color.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
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
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      node.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() => _selectedNodeId = null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const Divider(height: 20),
          _inspectorRow('الفرع:', node.branchName),
          _inspectorRow('عنوان IP:', node.ipAddress ?? '-'),
          _inspectorRow('نظام التشغيل:', node.os ?? '-'),
          _inspectorRow('حالة الاتصال:', node.isOnline ? '🟢 متصل بالشبكة' : '🔴 غير متصل'),
          _inspectorRow('روابط الربط النشطة:', '${node.connectedNodeIds.length} روابط'),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: node.color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.send_rounded, size: 14),
              label: const Text('إرسال حزمة فحص تفاعلية', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
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
        ],
      ),
    );
  }

  Widget _inspectorRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            key,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER: CURVED BEZIER PIPELINES & TRAVELING PARTICLES
// ══════════════════════════════════════════════════════════════════════════════
class _TopologyCanvasPainter extends CustomPainter {
  _TopologyCanvasPainter({
    required this.nodes,
    required this.nodesMap,
    required this.packets,
    required this.now,
    required this.selectedNodeId,
    required this.visibleNodeIds,
    required this.isDark,
  });

  final List<_TopologyNode> nodes;
  final Map<String, _TopologyNode> nodesMap;
  final List<_ActivePacket> packets;
  final DateTime now;
  final String? selectedNodeId;
  final Set<String> visibleNodeIds;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Blueprint fine dot grid
    final gridPaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B).withValues(alpha: 0.35) : const Color(0xFFCBD5E1).withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    const spacing = 36.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, gridPaint);
      }
    }

    // 2. Draw curved connection pipelines
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

        _drawCurvedPipe(canvas, node, target, isHighlighted, isNodeVisible);
      }
    }

    // 3. Draw active traveling packets along bezier curves
    for (final packet in packets) {
      final sender = nodesMap[packet.fromId];
      final receiver = nodesMap[packet.toId];
      if (sender == null || receiver == null) continue;

      _drawTravelingPacket(canvas, sender, receiver, packet);
    }
  }

  void _drawCurvedPipe(Canvas canvas, _TopologyNode from, _TopologyNode to, bool isHighlighted, bool isVisible) {
    final p1 = from.position;
    final p2 = to.position;

    final path = Path()..moveTo(p1.dx, p1.dy);
    final midX = (p1.dx + p2.dx) / 2;
    final midY = (p1.dy + p2.dy) / 2;
    // Gentle perpendicular curvature
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final ctrl = Offset(midX - dy * 0.08, midY + dx * 0.08);

    path.quadraticBezierTo(ctrl.dx, ctrl.dy, p2.dx, p2.dy);

    final pipePaint = Paint()
      ..color = isHighlighted
          ? from.color
          : (isVisible
              ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))
              : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)))
      ..strokeWidth = isHighlighted ? 2.5 : 1.2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, pipePaint);
  }

  void _drawTravelingPacket(Canvas canvas, _TopologyNode from, _TopologyNode to, _ActivePacket packet) {
    final p1 = from.position;
    final p2 = to.position;
    final progress = packet.getProgress(now);

    final midX = (p1.dx + p2.dx) / 2;
    final midY = (p1.dy + p2.dy) / 2;
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final ctrl = Offset(midX - dy * 0.08, midY + dx * 0.08);

    // Quadratic bezier point at progress
    final t = progress;
    final x = (1 - t) * (1 - t) * p1.dx + 2 * (1 - t) * t * ctrl.dx + t * t * p2.dx;
    final y = (1 - t) * (1 - t) * p1.dy + 2 * (1 - t) * t * ctrl.dy + t * t * p2.dy;
    final pos = Offset(x, y);

    // Draw glowing laser pulse
    final glowPaint = Paint()
      ..color = packet.color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(pos, 10, glowPaint);

    final corePaint = Paint()
      ..color = packet.color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 4.5, corePaint);

    // Destination ripple upon arrival
    if (progress > 0.92) {
      final rippleFactor = ((progress - 0.92) / 0.08);
      final ripplePaint = Paint()
        ..color = packet.color.withValues(alpha: (1.0 - rippleFactor) * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(p2, 14 + (rippleFactor * 26), ripplePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TopologyCanvasPainter oldDelegate) => true;
}
