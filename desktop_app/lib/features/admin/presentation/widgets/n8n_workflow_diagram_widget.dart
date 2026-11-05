import 'package:flutter/material.dart';

import '../../models/system_monitor_models.dart';

class N8nWorkflowDiagramWidget extends StatefulWidget {
  const N8nWorkflowDiagramWidget({
    super.key,
    required this.summary,
    required this.telemetry,
    required this.stats,
    required this.isDark,
  });

  final BranchDeploymentSummary? summary;
  final RequestTelemetryData? telemetry;
  final SystemTelemetryStats? stats;
  final bool isDark;

  @override
  State<N8nWorkflowDiagramWidget> createState() =>
      _N8nWorkflowDiagramWidgetState();
}

class _N8nWorkflowDiagramWidgetState extends State<N8nWorkflowDiagramWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final summary = widget.summary;
    final telemetry = widget.telemetry;
    final stats = widget.stats;

    final installedBranches = summary?.installedBranchesCount ?? 0;
    final totalBranches = summary?.totalBranches ?? 0;
    final totalDevices = summary?.totalInstalledDevices ?? 0;
    final onlineDevices = summary?.totalOnlineDevices ?? 0;

    final rps = telemetry?.rps ?? 0.0;
    final latency = telemetry?.avgLatencyMs ?? (stats != null ? 14 : 0);
    final activeReqs = telemetry?.activeRequests ?? 0;

    final dbStatus = stats?.databaseStatus ?? 'connected';
    final dbHost = stats?.databaseHost ?? 'cluster0.ismart';
    final dbName = stats?.databaseName ?? 'ismart-prod';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            // Background n8n grid pattern
            Positioned.fill(
              child: CustomPaint(
                painter: _N8nCanvasGridPainter(isDark: isDark),
              ),
            ),
            // Header bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFEC4899).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFEC4899),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'iSmart Live Workflow Canvas',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFEC4899),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Active traffic pulse
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PulsingDot(color: const Color(0xFF10B981)),
                        const SizedBox(width: 6),
                        Text(
                          '$rps req/s | نشط ومستقر',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Canvas content: Nodes & Flow
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 52, 16, 20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 760;

                  if (!isWide) {
                    // Mobile/Compact vertical stack
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildNodeCard(
                          isDark: isDark,
                          title: 'فروع ومحطات العمل',
                          subtitle: 'Client Nodes',
                          icon: Icons.store_rounded,
                          accentColor: const Color(0xFF3B82F6),
                          badge: '$installedBranches / $totalBranches فرع',
                          badgeColor: const Color(0xFF3B82F6),
                          metrics: [
                            'الأجهزة: $totalDevices جهاز',
                            'متصل الآن: $onlineDevices',
                          ],
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Icon(
                            Icons.arrow_downward_rounded,
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.7),
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildNodeCard(
                          isDark: isDark,
                          title: 'خادم المنظومة الأساسي',
                          subtitle: 'iSmart Core Server',
                          icon: Icons.dns_rounded,
                          accentColor: const Color(0xFF8B5CF6),
                          badge: 'v1.1.21',
                          badgeColor: const Color(0xFF8B5CF6),
                          metrics: [
                            'المعدل: $rps طلب/ثانية',
                            'زمن الاستجابة: $latency ms',
                            'النشط: $activeReqs طلب',
                          ],
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Icon(
                            Icons.arrow_downward_rounded,
                            color: const Color(0xFF10B981).withValues(alpha: 0.7),
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildNodeCard(
                          isDark: isDark,
                          title: 'قاعدة بيانات MongoDB',
                          subtitle: 'Cluster Database',
                          icon: Icons.storage_rounded,
                          accentColor: const Color(0xFF10B981),
                          badge: dbStatus == 'connected' ? 'متصل' : dbStatus,
                          badgeColor: const Color(0xFF10B981),
                          metrics: [
                            'القاعدة: $dbName',
                            'المضيف: $dbHost',
                          ],
                        ),
                      ],
                    );
                  }

                  // Wide desktop view with animated bezier pipes
                  return SizedBox(
                    height: 154,
                    child: Stack(
                      children: [
                        // Animated Particle Flow Lines
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _animController,
                            builder: (context, _) {
                              return CustomPaint(
                                painter: _N8nFlowLinesPainter(
                                  progress: _animController.value,
                                  isDark: isDark,
                                ),
                              );
                            },
                          ),
                        ),
                        // 3 Nodes row
                        Row(
                          children: [
                            // Node 1: Branches
                            Expanded(
                              child: _buildNodeCard(
                                isDark: isDark,
                                title: 'فروع ومحطات العمل',
                                subtitle: 'Workstations & Branches',
                                icon: Icons.store_rounded,
                                accentColor: const Color(0xFF3B82F6),
                                badge: '$installedBranches / $totalBranches فرع',
                                badgeColor: const Color(0xFF3B82F6),
                                metrics: [
                                  'الأجهزة: $totalDevices جهاز',
                                  'متصل الآن: $onlineDevices',
                                ],
                              ),
                            ),
                            const SizedBox(width: 48), // gap for flow wire
                            // Node 2: Core Server
                            Expanded(
                              child: _buildNodeCard(
                                isDark: isDark,
                                title: 'خادم المنظومة المركزي',
                                subtitle: 'iSmart Core Server',
                                icon: Icons.dns_rounded,
                                accentColor: const Color(0xFF8B5CF6),
                                badge: 'v1.1.21',
                                badgeColor: const Color(0xFF8B5CF6),
                                metrics: [
                                  'المعدل: $rps req/s',
                                  'الاستجابة: $latency ms',
                                  'الطلبات النشطة: $activeReqs',
                                ],
                              ),
                            ),
                            const SizedBox(width: 48), // gap for flow wire
                            // Node 3: Database
                            Expanded(
                              child: _buildNodeCard(
                                isDark: isDark,
                                title: 'قاعدة بيانات MongoDB',
                                subtitle: 'Cluster Database',
                                icon: Icons.storage_rounded,
                                accentColor: const Color(0xFF10B981),
                                badge: dbStatus == 'connected' ? 'متصل ومستقر' : dbStatus,
                                badgeColor: const Color(0xFF10B981),
                                metrics: [
                                  'القاعدة: $dbName',
                                  'المضيف: $dbHost',
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeCard({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required String badge,
    required Color badgeColor,
    required List<String> metrics,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accentColor.withValues(alpha: isDark ? 0.35 : 0.25),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top node header
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: isDark
                            ? const Color(0xFF8B949E)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(
            height: 1,
            color: isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0),
          ),
          const SizedBox(height: 8),
          // Metric rows
          ...metrics.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      m,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? const Color(0xFFC9D1D9)
                            : const Color(0xFF334155),
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
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final scale = 0.8 + (_ctrl.value * 0.4);
        final opacity = 0.5 + (_ctrl.value * 0.5);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: opacity),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: opacity * 0.6),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _N8nCanvasGridPainter extends CustomPainter {
  const _N8nCanvasGridPainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.05 : 0.04)
      ..style = PaintingStyle.fill;

    const double spacing = 18;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _N8nCanvasGridPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

class _N8nFlowLinesPainter extends CustomPainter {
  const _N8nFlowLinesPainter({
    required this.progress,
    required this.isDark,
  });

  final double progress;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    // 3 cards divided equally with 2 gaps of 48px
    final double cardWidth = (size.width - 96) / 3;
    final double midY = size.height / 2;

    // Line 1: from Node 1 (right edge) to Node 2 (left edge)
    final double p1StartX = cardWidth;
    final double p1EndX = cardWidth + 48;

    // Line 2: from Node 2 (right edge) to Node 3 (left edge)
    final double p2StartX = (cardWidth * 2) + 48;
    final double p2EndX = (cardWidth * 2) + 96;

    _drawFlowWire(
      canvas: canvas,
      startX: p1StartX,
      endX: p1EndX,
      y: midY,
      wireColor: const Color(0xFF3B82F6),
      particleColor: const Color(0xFF60A5FA),
      progress: progress,
    );

    _drawFlowWire(
      canvas: canvas,
      startX: p2StartX,
      endX: p2EndX,
      y: midY,
      wireColor: const Color(0xFF8B5CF6),
      particleColor: const Color(0xFFA78BFA),
      progress: (progress + 0.5) % 1.0,
    );
  }

  void _drawFlowWire({
    required Canvas canvas,
    required double startX,
    required double endX,
    required double y,
    required Color wireColor,
    required Color particleColor,
    required double progress,
  }) {
    // Base dashed wire
    final basePaint = Paint()
      ..color = wireColor.withValues(alpha: isDark ? 0.3 : 0.25)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(startX, y)
      ..cubicTo(
        startX + ((endX - startX) * 0.4),
        y - 12,
        startX + ((endX - startX) * 0.6),
        y + 12,
        endX,
        y,
      );

    canvas.drawPath(path, basePaint);

    // Glowing connection ports at the card edges
    final portPaint = Paint()
      ..color = wireColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(startX, y), 3.5, portPaint);
    canvas.drawCircle(Offset(endX, y), 3.5, portPaint);

    // Flowing animated particle orb along path
    final pathMetrics = path.computeMetrics().toList();
    if (pathMetrics.isNotEmpty) {
      final metric = pathMetrics.first;
      final tangent = metric.getTangentForOffset(metric.length * progress);
      if (tangent != null) {
        // Outer halo
        final haloPaint = Paint()
          ..color = particleColor.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawCircle(tangent.position, 6, haloPaint);

        // Core bright orb
        final orbPaint = Paint()
          ..color = particleColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(tangent.position, 3.2, orbPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _N8nFlowLinesPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isDark != isDark;
}
