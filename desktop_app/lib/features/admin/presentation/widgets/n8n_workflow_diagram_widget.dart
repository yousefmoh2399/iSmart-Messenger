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
      duration: const Duration(milliseconds: 2600),
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
    final adoptionPercent = summary?.adoptionPercentage ?? 0;

    final rps = telemetry?.rps ?? 0.0;
    final latency = telemetry?.avgLatencyMs ?? (stats != null ? 14 : 0);
    final activeReqs = telemetry?.activeRequests ?? 0;

    final dbStatus = stats?.databaseStatus ?? 'connected';
    final dbHost = stats?.databaseHost ?? 'cluster0.ismart';
    final dbName = stats?.databaseName ?? 'ismart-prod';
    final cpuCores = stats?.cpuCores ?? 8;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Background subtle grid
            Positioned.fill(
              child: CustomPaint(
                painter: _N8nCanvasGridPainter(isDark: isDark),
              ),
            ),
            // Header bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.hub_rounded,
                          size: 14,
                          color: Color(0xFF818CF8),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'بنية الربط والتشغيل المباشر (Live Telemetry Architecture)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? const Color(0xFFA5B4FC)
                                : const Color(0xFF4F46E5),
                            letterSpacing: -0.2,
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
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PulsingDot(color: const Color(0xFF10B981)),
                        const SizedBox(width: 6),
                        Text(
                          '$rps req/s  •  $latency ms استجابة  •  نشط ومستقر',
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
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
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
                          title: 'محطات وفروع المنظومة',
                          subtitle: 'Client Fleet & Workstations',
                          icon: Icons.corporate_fare_rounded,
                          accentColor: const Color(0xFF0284C7),
                          badge: '$installedBranches / $totalBranches فرع',
                          badgeColor: const Color(0xFF0284C7),
                          metrics: [
                            'المحطات: $totalDevices جهاز ($onlineDevices متصل)',
                            'نسبة التغطية: $adoptionPercent%',
                          ],
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: Icon(
                            Icons.arrow_downward_rounded,
                            color: const Color(0xFF6366F1).withValues(alpha: 0.6),
                            size: 18,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildNodeCard(
                          isDark: isDark,
                          title: 'خادم المنظومة المركزي',
                          subtitle: 'iSmart Core Gateway & Cluster',
                          icon: Icons.dns_rounded,
                          accentColor: const Color(0xFF6366F1),
                          badge: 'v1.1.21 معتمد',
                          badgeColor: const Color(0xFF6366F1),
                          metrics: [
                            'المعدل: $rps req/s ($latency ms)',
                            'العمليات الجارية: $activeReqs نشط',
                          ],
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: Icon(
                            Icons.arrow_downward_rounded,
                            color: const Color(0xFF10B981).withValues(alpha: 0.6),
                            size: 18,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildNodeCard(
                          isDark: isDark,
                          title: 'قاعدة بيانات MongoDB',
                          subtitle: 'Primary Database Cluster',
                          icon: Icons.storage_rounded,
                          accentColor: const Color(0xFF10B981),
                          badge: dbStatus == 'connected' ? 'متصل ومستقر' : dbStatus,
                          badgeColor: const Color(0xFF10B981),
                          metrics: [
                            'القاعدة: $dbName',
                            'المضيف: $dbHost ($cpuCores Cores)',
                          ],
                        ),
                      ],
                    );
                  }

                  // Wide desktop view with animated bezier pipes
                  return SizedBox(
                    height: 148,
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
                                title: 'محطات وفروع المنظومة',
                                subtitle: 'Client Fleet & Workstations',
                                icon: Icons.corporate_fare_rounded,
                                accentColor: const Color(0xFF0284C7),
                                badge: '$installedBranches / $totalBranches فرع',
                                badgeColor: const Color(0xFF0284C7),
                                metrics: [
                                  'المحطات: $totalDevices جهاز ($onlineDevices متصل)',
                                  'نسبة التغطية: $adoptionPercent% من الفروع',
                                ],
                              ),
                            ),
                            const SizedBox(width: 44),
                            // Node 2: Core Server
                            Expanded(
                              child: _buildNodeCard(
                                isDark: isDark,
                                title: 'خادم المنظومة المركزي',
                                subtitle: 'iSmart Core Gateway & Cluster',
                                icon: Icons.dns_rounded,
                                accentColor: const Color(0xFF6366F1),
                                badge: 'v1.1.21 معتمد',
                                badgeColor: const Color(0xFF6366F1),
                                metrics: [
                                  'المعدل: $rps req/s ($latency ms)',
                                  'العمليات الجارية: $activeReqs نشط',
                                ],
                              ),
                            ),
                            const SizedBox(width: 44),
                            // Node 3: Database
                            Expanded(
                              child: _buildNodeCard(
                                isDark: isDark,
                                title: 'قاعدة بيانات MongoDB',
                                subtitle: 'Primary Database Cluster',
                                icon: Icons.storage_rounded,
                                accentColor: const Color(0xFF10B981),
                                badge: dbStatus == 'connected' ? 'متصل ومستقر' : dbStatus,
                                badgeColor: const Color(0xFF10B981),
                                metrics: [
                                  'القاعدة: $dbName',
                                  'المضيف: $dbHost ($cpuCores Cores)',
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
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? accentColor.withValues(alpha: 0.3)
              : accentColor.withValues(alpha: 0.2),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
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
                        color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 9,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
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
            color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF1F5F9),
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
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? const Color(0xFFCBD5E1)
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
      duration: const Duration(milliseconds: 1100),
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
        final scale = 0.85 + (_ctrl.value * 0.35);
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
                  color: widget.color.withValues(alpha: opacity * 0.5),
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
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.04 : 0.035)
      ..style = PaintingStyle.fill;

    const double spacing = 16;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 0.8, dotPaint);
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
    final double cardWidth = (size.width - 88) / 3;
    final double midY = size.height / 2;

    // Line 1: from Node 1 (right edge) to Node 2 (left edge)
    final double p1StartX = cardWidth;
    final double p1EndX = cardWidth + 44;

    // Line 2: from Node 2 (right edge) to Node 3 (left edge)
    final double p2StartX = (cardWidth * 2) + 44;
    final double p2EndX = (cardWidth * 2) + 88;

    _drawFlowWire(
      canvas: canvas,
      startX: p1StartX,
      endX: p1EndX,
      y: midY,
      wireColor: const Color(0xFF0284C7),
      particleColor: const Color(0xFF38BDF8),
      progress: progress,
    );

    _drawFlowWire(
      canvas: canvas,
      startX: p2StartX,
      endX: p2EndX,
      y: midY,
      wireColor: const Color(0xFF6366F1),
      particleColor: const Color(0xFF818CF8),
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
    // Base pipe
    final basePaint = Paint()
      ..color = wireColor.withValues(alpha: isDark ? 0.35 : 0.25)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(startX, y)
      ..cubicTo(
        startX + ((endX - startX) * 0.4),
        y - 10,
        startX + ((endX - startX) * 0.6),
        y + 10,
        endX,
        y,
      );

    canvas.drawPath(path, basePaint);

    // Glowing connection ports at the card edges
    final portPaint = Paint()
      ..color = wireColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(startX, y), 3.0, portPaint);
    canvas.drawCircle(Offset(endX, y), 3.0, portPaint);

    // Flowing animated particles
    final pathMetrics = path.computeMetrics().toList();
    if (pathMetrics.isNotEmpty) {
      final metric = pathMetrics.first;

      // Draw 2 particles spaced along the line
      for (int i = 0; i < 2; i++) {
        final pOffset = (progress + (i * 0.5)) % 1.0;
        final tangent = metric.getTangentForOffset(metric.length * pOffset);
        if (tangent != null) {
          // Halo
          final haloPaint = Paint()
            ..color = particleColor.withValues(alpha: 0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
          canvas.drawCircle(tangent.position, 5, haloPaint);

          // Core
          final orbPaint = Paint()
            ..color = particleColor
            ..style = PaintingStyle.fill;
          canvas.drawCircle(tangent.position, 2.8, orbPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _N8nFlowLinesPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isDark != isDark;
}
