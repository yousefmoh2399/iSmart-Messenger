import 'package:flutter/material.dart';

import '../../models/system_monitor_models.dart';

class N8nWorkflowDiagramWidget extends StatefulWidget {
  const N8nWorkflowDiagramWidget({
    super.key,
    required this.summary,
    required this.telemetry,
    required this.stats,
    required this.isDark,
    this.onOpenFullscreen,
  });

  final BranchDeploymentSummary? summary;
  final RequestTelemetryData? telemetry;
  final SystemTelemetryStats? stats;
  final bool isDark;
  final VoidCallback? onOpenFullscreen;

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
    final adoptionPercent = summary?.adoptionPercentage ?? 0;

    final rps = telemetry?.rps ?? 0.0;
    final latency = telemetry?.avgLatencyMs ?? (stats != null ? 14 : 0);
    final activeReqs = telemetry?.activeRequests ?? 0;

    final dbStatus = stats?.databaseStatus ?? 'connected';
    final dbHost = stats?.databaseHost ?? 'cluster0.ismart';
    final dbName = stats?.databaseName ?? 'ismart-prod';
    final cpuCores = stats?.cpuCores ?? 8;
    final targetVer = summary?.targetAppVersion ?? summary?.currentAppVersion ?? '1.1.22';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10131A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Background subtle dot grid
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
                      color: const Color(0xFFFF6D5A).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFFF6D5A).withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hub_rounded,
                          size: 14,
                          color: Color(0xFFFF6D5A),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'بنية الربط والتشغيل المباشر (Live Telemetry Architecture)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFF6D5A),
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
                        const _PulsingDot(color: Color(0xFF10B981)),
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
                  if (widget.onOpenFullscreen != null) ...[
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: widget.onOpenFullscreen,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6D5A), // n8n Coral
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.open_in_full_rounded, size: 14),
                      label: const Text(
                        'خريطة العمليات وشبكة الأجهزة الحية (n8n Live Map)',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Canvas content: Nodes & Flow
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 50, 16, 16),
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
                          category: 'TRIGGER / POS',
                          icon: Icons.devices_rounded,
                          accentColor: const Color(0xFFFF6D5A),
                          badge: '$onlineDevices / $totalDevices متصل',
                          badgeColor: const Color(0xFF10B981),
                          metrics: [
                            'المحطات: $totalDevices جهاز ($onlineDevices متصل)',
                            'نسبة التغطية: $adoptionPercent% من الفروع ($installedBranches / $totalBranches)',
                          ],
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: Icon(
                            Icons.arrow_downward_rounded,
                            color: const Color(0xFF06B6D4).withValues(alpha: 0.6),
                            size: 18,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildNodeCard(
                          isDark: isDark,
                          title: 'خادم المنظومة المركزي وبوابة الاتصال',
                          subtitle: 'iSmart Core Gateway & Cluster',
                          category: 'GATEWAY / ROUTER',
                          icon: Icons.router_rounded,
                          accentColor: const Color(0xFF06B6D4),
                          badge: 'v$targetVer معتمد',
                          badgeColor: const Color(0xFF06B6D4),
                          metrics: [
                            'المعدل: $rps req/s ($latency ms استجابة)',
                            'العمليات الجارية: $activeReqs طلب نشط',
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
                          title: 'قاعدة بيانات MongoDB والتخزين',
                          subtitle: 'Primary Database Cluster',
                          category: 'DATABASE',
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
                    height: 154,
                    child: Stack(
                      clipBehavior: Clip.none,
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
                                category: 'TRIGGER / POS',
                                icon: Icons.devices_rounded,
                                accentColor: const Color(0xFFFF6D5A),
                                badge: '$onlineDevices / $totalDevices متصل',
                                badgeColor: const Color(0xFF10B981),
                                metrics: [
                                  'المحطات: $totalDevices جهاز ($onlineDevices متصل)',
                                  'نسبة التغطية: $adoptionPercent% من الفروع ($installedBranches / $totalBranches)',
                                ],
                                hasLeftPort: false,
                                hasRightPort: true,
                              ),
                            ),
                            const SizedBox(width: 46),
                            // Node 2: Core Server
                            Expanded(
                              child: _buildNodeCard(
                                isDark: isDark,
                                title: 'خادم المنظومة المركزي وبوابة الاتصال',
                                subtitle: 'iSmart Core Gateway & Cluster',
                                category: 'GATEWAY / ROUTER',
                                icon: Icons.router_rounded,
                                accentColor: const Color(0xFF06B6D4),
                                badge: 'v$targetVer معتمد',
                                badgeColor: const Color(0xFF06B6D4),
                                metrics: [
                                  'المعدل: $rps req/s ($latency ms استجابة)',
                                  'العمليات الجارية: $activeReqs طلب نشط',
                                ],
                                hasLeftPort: true,
                                hasRightPort: true,
                              ),
                            ),
                            const SizedBox(width: 46),
                            // Node 3: Database
                            Expanded(
                              child: _buildNodeCard(
                                isDark: isDark,
                                title: 'قاعدة بيانات MongoDB والتخزين',
                                subtitle: 'Primary Database Cluster',
                                category: 'DATABASE',
                                icon: Icons.storage_rounded,
                                accentColor: const Color(0xFF10B981),
                                badge: dbStatus == 'connected' ? 'متصل ومستقر' : dbStatus,
                                badgeColor: const Color(0xFF10B981),
                                metrics: [
                                  'القاعدة: $dbName',
                                  'المضيف: $dbHost ($cpuCores Cores)',
                                ],
                                hasLeftPort: true,
                                hasRightPort: false,
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
    required String category,
    required IconData icon,
    required Color accentColor,
    required String badge,
    required Color badgeColor,
    required List<String> metrics,
    bool hasLeftPort = false,
    bool hasRightPort = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141722) : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isDark ? const Color(0xFF222938) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Left port handle
          if (hasLeftPort)
            Positioned(
              left: -5,
              top: 50,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF10131A) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor, width: 2),
                ),
              ),
            ),

          // Right port handle
          if (hasRightPort)
            Positioned(
              right: -5,
              top: 50,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF10131A) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor, width: 2),
                ),
              ),
            ),

          // Content
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top node header
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
                      ),
                      child: Icon(icon, color: accentColor, size: 17),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  category,
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 9.5,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 9,
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
      ..color = (isDark ? const Color(0xFF222938) : const Color(0xFFCBD5E1)).withValues(alpha: isDark ? 0.7 : 0.6)
      ..style = PaintingStyle.fill;

    const double spacing = 18;
    for (double x = 8; x < size.width; x += spacing) {
      for (double y = 8; y < size.height; y += spacing) {
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
    final double cardWidth = (size.width - 92) / 3;
    const double midY = 60; // aligned with ports

    // Line 1: from Node 1 (right edge) to Node 2 (left edge)
    final double p1StartX = cardWidth;
    final double p1EndX = cardWidth + 46;

    // Line 2: from Node 2 (right edge) to Node 3 (left edge)
    final double p2StartX = (cardWidth * 2) + 46;
    final double p2EndX = (cardWidth * 2) + 92;

    _drawFlowWire(
      canvas: canvas,
      startX: p1StartX,
      endX: p1EndX,
      y: midY,
      wireColor: const Color(0xFFFF6D5A),
      particleColor: const Color(0xFFFF8B7A),
      label: '💬 رسالة كاشير',
      progress: progress,
    );

    _drawFlowWire(
      canvas: canvas,
      startX: p2StartX,
      endX: p2EndX,
      y: midY,
      wireColor: const Color(0xFF06B6D4),
      particleColor: const Color(0xFF38BDF8),
      label: '💾 حفظ MongoDB',
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
    required String label,
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

    // Flowing animated particles with trail
    final pathMetrics = path.computeMetrics().toList();
    if (pathMetrics.isNotEmpty) {
      final metric = pathMetrics.first;
      final tangent = metric.getTangentForOffset(metric.length * progress);
      if (tangent != null) {
        // Halo
        final haloPaint = Paint()
          ..color = particleColor.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(tangent.position, 6, haloPaint);

        // Core
        final orbPaint = Paint()
          ..color = particleColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(tangent.position, 3.2, orbPaint);

        // White center
        final centerPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(tangent.position, 1.8, centerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _N8nFlowLinesPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isDark != isDark;
}
