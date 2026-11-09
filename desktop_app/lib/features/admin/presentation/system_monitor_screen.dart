import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/system_monitor_models.dart';
import 'system_monitor_controller.dart';
import 'widgets/branches_deployment_view.dart';
import 'widgets/admin_polls_view.dart';
import 'live_operations_topology_screen.dart';

class SystemMonitorScreen extends ConsumerStatefulWidget {
  const SystemMonitorScreen({
    super.key,
    this.isWrapped = false,
  });

  final bool isWrapped;

  @override
  ConsumerState<SystemMonitorScreen> createState() =>
      _SystemMonitorScreenState();
}

class _SystemMonitorScreenState extends ConsumerState<SystemMonitorScreen> {
  int _currentTab = 0; // 0 = Deployment & Ops, 1 = Polls, 2 = Sessions, 3 = Errors
  final TextEditingController _searchController = TextEditingController();
  bool? _errorResolvedFilter; // null = all, false = unresolved, true = resolved

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openLiveTopologyScreen(
    BuildContext context,
    SystemMonitorState state,
    SystemMonitorController notifier,
    bool isDark,
    ColorScheme cs,
  ) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, anim, secAnim) => LiveOperationsTopologyScreen(
          state: state,
          notifier: notifier,
          isDark: isDark,
          cs: cs,
        ),
        transitionsBuilder: (context, anim, secAnim, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatUptime(int seconds) {
    if (seconds <= 0) return 'لحظات';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (days > 0) {
      return '$days يوم و $hours ساعة';
    }
    if (hours > 0) {
      return '$hours ساعة و $minutes دقيقة';
    }
    return '$minutes دقيقة';
  }

  String _formatTimeAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 45) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'منذ ${diff.inDays} يوم';
    return '${dt.year}/${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(systemMonitorControllerProvider);
    final notifier = ref.read(systemMonitorControllerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    final scaffold = Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0B0F19) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Executive Apple SaaS Header
            _buildExecutiveHeader(context, state, notifier, isDark, cs),

            // 2. Scrollable Body Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Bento Telemetry KPI Strip (Shown on Sessions & Errors tabs)
                    if (_currentTab >= 2) ...[
                      _buildResponsiveTelemetryRow(state, isDark, cs),
                      const SizedBox(height: 18),
                    ],

                    // Segmented Tabs Header
                    _buildSegmentedTabsHeader(state, isDark, cs),
                    const SizedBox(height: 16),

                    // Active Tab View
                    if (_currentTab == 0)
                      BranchesDeploymentView(
                        state: state,
                        notifier: notifier,
                        isDark: isDark,
                        cs: cs,
                      )
                    else if (_currentTab == 1)
                      AdminPollsView(
                        state: state,
                        notifier: notifier,
                        isDark: isDark,
                        cs: cs,
                      )
                    else if (_currentTab == 2)
                      _buildSessionsTab(state, notifier, isDark, cs)
                    else
                      _buildErrorsTab(state, notifier, isDark, cs),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return widget.isWrapped
        ? ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: scaffold,
          )
        : scaffold;
  }

  // ---------------------------------------------------------------------------
  // 1. EXECUTIVE APPLE SAAS HEADER
  // ---------------------------------------------------------------------------
  Widget _buildExecutiveHeader(
    BuildContext context,
    SystemMonitorState state,
    SystemMonitorController notifier,
    bool isDark,
    ColorScheme cs,
  ) {
    final isLoading =
        state.isLoadingStats || state.isLoadingSessions || state.isLoadingErrors;
    final dbOnline = state.stats?.databaseStatus == 'connected';
    final latency = state.requestTelemetry?.avgLatencyMs ?? 14;
    final uptimeStr = _formatUptime(state.stats?.uptimeSeconds ?? 0);

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131926) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 880;

          // Title & Status Badges
          final infoSection = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Live Telemetry Badges Strip
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Server status pill
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: dbOnline
                          ? const Color(0xFF10B981).withValues(alpha: 0.12)
                          : const Color(0xFFEF4444).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: dbOnline
                            ? const Color(0xFF10B981).withValues(alpha: 0.3)
                            : const Color(0xFFEF4444).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: dbOnline
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          dbOnline ? 'الخادم متصل وجاهز' : 'الخادم غير متصل',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: dbOnline
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Latency badge
                  _buildHeaderPill(
                    icon: Icons.bolt_rounded,
                    label: '$latency ms زمن الاستجابة',
                    color: const Color(0xFF0284C7),
                    isDark: isDark,
                  ),

                  // Uptime badge
                  _buildHeaderPill(
                    icon: Icons.timer_outlined,
                    label: 'مدة التشغيل: $uptimeStr',
                    color: const Color(0xFF8B5CF6),
                    isDark: isDark,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Title and Description
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF2563EB).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.analytics_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مراقبة وتشخيص النظام',
                          style: TextStyle(
                            fontSize: isCompact ? 22 : 26,
                            fontWeight: FontWeight.w800,
                            color:
                                isDark ? Colors.white : const Color(0xFF0F172A),
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'لوحة القيادة المركزية لمتابعة أسطول الفروع، استهلاك الموارد، الجلسات الحية، وسجلات الاستقرار',
                          style: TextStyle(
                            fontSize: isCompact ? 13 : 14,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );

          // Action Buttons
          final actionButtons = Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Refresh Button
              FilledButton.tonalIcon(
                onPressed: isLoading ? null : () => notifier.refreshAll(),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 20),
                label: Text(
                  isLoading ? 'جاري الفحص...' : 'تحديث البيانات',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              // Interactive n8n Topology Button
              FilledButton.icon(
                onPressed: () => _openLiveTopologyScreen(
                  context,
                  state,
                  notifier,
                  isDark,
                  cs,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D5A), // n8n Coral
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  shadowColor: const Color(0xFFFF6D5A).withValues(alpha: 0.35),
                ),
                icon: const Icon(Icons.hub_rounded, size: 20),
                label: const Text(
                  'خريطة العمارة والشبكة (n8n)',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                infoSection,
                const SizedBox(height: 14),
                actionButtons,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: infoSection),
              const SizedBox(width: 16),
              actionButtons,
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderPill({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. RESPONSIVE TELEMETRY BENTO ROW (SESSIONS & ERRORS TABS)
  // ---------------------------------------------------------------------------
  Widget _buildResponsiveTelemetryRow(
    SystemMonitorState state,
    bool isDark,
    ColorScheme cs,
  ) {
    final stats = state.stats;

    // Card 1: RAM & Memory
    final memPercent = stats?.memoryUsagePercent ?? 0;
    final totalMemStr = _formatBytes(stats?.totalMemoryBytes ?? 0);
    final usedMemStr = _formatBytes(stats?.usedMemoryBytes ?? 0);
    final heapStr = _formatBytes(stats?.processHeapUsedBytes ?? 0);

    // Card 2: Live Connections
    final liveSockets = stats?.liveSocketsCount ?? 0;
    final liveUsers = stats?.liveUsersCount ?? 0;
    final desktopCount = stats?.desktopClientsCount ?? 0;
    final mobileCount = stats?.mobileClientsCount ?? 0;

    // Card 3: Server & Database
    final dbOnline = stats?.databaseStatus == 'connected';
    final uptimeStr = _formatUptime(stats?.uptimeSeconds ?? 0);
    final nodeVer = stats?.nodeVersion ?? 'Node.js';

    // Card 4: Error Diagnostics
    final unresolved = stats?.unresolvedErrors ?? 0;
    final totalErrors = stats?.totalErrors ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isWide = width >= 960;
        final isMedium = width >= 600 && width < 960;

        final card1 = _buildTelemetryCard(
          isDark: isDark,
          icon: Icons.memory_rounded,
          iconColor: const Color(0xFF8B5CF6),
          title: 'استهلاك الذاكرة (RAM)',
          value: '$memPercent%',
          subtitle: 'مستخدم $usedMemStr من $totalMemStr',
          extraWidget: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (memPercent / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    memPercent > 85
                        ? const Color(0xFFEF4444)
                        : (memPercent > 65
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF8B5CF6)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Node.js Heap: $heapStr',
                style: TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        );

        final card2 = _buildTelemetryCard(
          isDark: isDark,
          icon: Icons.cell_tower_rounded,
          iconColor: const Color(0xFF10B981),
          title: 'الاتصالات الحية بالشبكة',
          value: '$liveSockets اتصال',
          subtitle: '$liveUsers موظف متصل الآن بالخدمة',
          extraWidget: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _buildMicroBadge('💻 $desktopCount كمبيوتر', isDark),
                _buildMicroBadge('📱 $mobileCount موبايل', isDark),
              ],
            ),
          ),
        );

        final card3 = _buildTelemetryCard(
          isDark: isDark,
          icon: Icons.dns_rounded,
          iconColor: const Color(0xFF0284C7),
          title: 'الخادم وقاعدة البيانات',
          value: dbOnline ? 'متصل ومستقر' : 'غير متصل',
          subtitle: 'وقت تشغيل الخادم: $uptimeStr',
          extraWidget: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: dbOnline
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'MongoDB • $nodeVer',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        );

        final card4 = _buildTelemetryCard(
          isDark: isDark,
          icon: Icons.shield_rounded,
          iconColor: unresolved > 0
              ? const Color(0xFFEF4444)
              : const Color(0xFF10B981),
          title: 'سجل المشاكل والاستقرار',
          value: unresolved > 0 ? '$unresolved بحاجة للحل' : 'مستقر 100%',
          subtitle: 'إجمالي المسجل: $totalErrors بلاغ',
          extraWidget: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: unresolved > 0
                    ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                    : const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                unresolved > 0
                    ? '⚠️ يُنصح بمراجعة سجل الأخطاء'
                    : '✅ النظام يعمل بأمان تام',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: unresolved > 0
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF10B981),
                ),
              ),
            ),
          ),
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: card1),
              const SizedBox(width: 14),
              Expanded(child: card2),
              const SizedBox(width: 14),
              Expanded(child: card3),
              const SizedBox(width: 14),
              Expanded(child: card4),
            ],
          );
        }

        if (isMedium) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: card1),
                  const SizedBox(width: 14),
                  Expanded(child: card2),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: card3),
                  const SizedBox(width: 14),
                  Expanded(child: card4),
                ],
              ),
            ],
          );
        }

        // Compact stacked
        return Column(
          children: [
            card1,
            const SizedBox(height: 12),
            card2,
            const SizedBox(height: 12),
            card3,
            const SizedBox(height: 12),
            card4,
          ],
        );
      },
    );
  }

  Widget _buildTelemetryCard({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
    Widget? extraWidget,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131926) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? const Color(0xFF64748B)
                  : const Color(0xFF94A3B8),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (extraWidget != null) extraWidget,
        ],
      ),
    );
  }

  Widget _buildMicroBadge(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. SEGMENTED TABS HEADER
  // ---------------------------------------------------------------------------
  Widget _buildSegmentedTabsHeader(
    SystemMonitorState state,
    bool isDark,
    ColorScheme cs,
  ) {
    final liveCount = state.stats?.liveSocketsCount ?? 0;
    final errorsCount = state.errorsTotal;
    final installedBranches =
        state.deploymentData?.summary.installedBranchesCount ?? 0;
    final totalBranches = state.deploymentData?.summary.totalBranches ?? 0;
    final pollsCount =
        state.pollsData?.total ?? (state.pollsData?.items.length ?? 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 920;

        return Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF131926)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildSegmentedTabItem(
                  title: isCompact ? 'الفروع والعمليات' : 'انتشار الفروع والعمليات',
                  badge: totalBranches > 0
                      ? '$installedBranches/$totalBranches'
                      : null,
                  icon: Icons.hub_rounded,
                  index: 0,
                  isDark: isDark,
                  cs: cs,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildSegmentedTabItem(
                  title: isCompact ? 'استطلاعات الرأي' : 'استطلاعات الرأي والتصويت',
                  badge: '$pollsCount',
                  icon: Icons.poll_rounded,
                  index: 1,
                  isDark: isDark,
                  cs: cs,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildSegmentedTabItem(
                  title: isCompact ? 'الجلسات الحية' : 'الأجهزة والجلسات الحية',
                  badge: '$liveCount',
                  icon: Icons.devices_rounded,
                  index: 2,
                  isDark: isDark,
                  cs: cs,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildSegmentedTabItem(
                  title: isCompact ? 'سجل الأخطاء' : 'سجل المشاكل والأخطاء',
                  badge: '$errorsCount',
                  badgeColor: errorsCount > 0 ? const Color(0xFFEF4444) : null,
                  icon: Icons.bug_report_rounded,
                  index: 3,
                  isDark: isDark,
                  cs: cs,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSegmentedTabItem({
    required String title,
    required IconData icon,
    required int index,
    required bool isDark,
    required ColorScheme cs,
    String? badge,
    Color? badgeColor,
  }) {
    final isSelected = _currentTab == index;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _currentTab = index);
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF1E2638) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? cs.primary
                  : (isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? (isDark ? Colors.white : const Color(0xFF0F172A))
                      : (isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
                ),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (badgeColor ?? cs.primary).withValues(alpha: 0.15)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: isSelected
                        ? (badgeColor ?? cs.primary)
                        : (isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF475569)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. SESSIONS TAB
  // ---------------------------------------------------------------------------
  Widget _buildSessionsTab(
    SystemMonitorState state,
    SystemMonitorController notifier,
    bool isDark,
    ColorScheme cs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filter & Search Controls
        _buildSessionsFilterBar(state, notifier, isDark, cs),
        const SizedBox(height: 14),

        // Sessions List
        if (state.isLoadingSessions && state.sessions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.sessions.isEmpty)
          _buildEmptyState(
            title: 'لا توجد جلسات مطابقة',
            subtitle: 'جرّب البحث باسم مستخدم آخر أو إعادة ضبط الفلاتر المحددة',
            icon: Icons.person_off_rounded,
            isDark: isDark,
            cs: cs,
          )
        else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final session = state.sessions[index];
              return _buildSessionCard(session, isDark, cs);
            },
          ),
          if (state.sessionsHasMore) ...[
            const SizedBox(height: 16),
            Center(
              child: FilledButton.tonal(
                onPressed: state.isLoadingSessions
                    ? null
                    : () => notifier.loadMoreSessions(),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: state.isLoadingSessions
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'تحميل المزيد من الجلسات',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildSessionsFilterBar(
    SystemMonitorState state,
    SystemMonitorController notifier,
    bool isDark,
    ColorScheme cs,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131926) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 840;

          final chipsSection = Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildFilterChip(
                label: 'الكل',
                selected: state.statusFilter == 'all',
                onTap: () => notifier.setFilters(status: 'all'),
                isDark: isDark,
                cs: cs,
              ),
              _buildFilterChip(
                label: '🟢 متصل الآن',
                selected: state.statusFilter == 'online',
                onTap: () => notifier.setFilters(status: 'online'),
                isDark: isDark,
                cs: cs,
              ),
              _buildFilterChip(
                label: '⚪ غير متصل',
                selected: state.statusFilter == 'offline',
                onTap: () => notifier.setFilters(status: 'offline'),
                isDark: isDark,
                cs: cs,
              ),
              Container(
                width: 1,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : const Color(0xFFCBD5E1),
              ),
              _buildFilterChip(
                label: '💻 كمبيوتر',
                selected: state.clientTypeFilter == 'desktop',
                onTap: () => notifier.setFilters(
                  clientType:
                      state.clientTypeFilter == 'desktop' ? 'all' : 'desktop',
                ),
                isDark: isDark,
                cs: cs,
              ),
              _buildFilterChip(
                label: '📱 موبايل',
                selected: state.clientTypeFilter == 'mobile',
                onTap: () => notifier.setFilters(
                  clientType:
                      state.clientTypeFilter == 'mobile' ? 'all' : 'mobile',
                ),
                isDark: isDark,
                cs: cs,
              ),
            ],
          );

          final searchBox = SizedBox(
            width: isCompact ? constraints.maxWidth : 260,
            height: 36,
            child: TextField(
              controller: _searchController,
              onChanged: (val) => notifier.setFilters(search: val),
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'بحث باسم المستخدم أو الموظف...',
                hintStyle: TextStyle(
                  fontSize: 11.5,
                  color: isDark
                      ? const Color(0xFF64748B)
                      : const Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 16),
                suffixIcon: state.searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 14),
                        onPressed: () {
                          _searchController.clear();
                          notifier.setFilters(search: '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF090D16)
                    : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF1F2937)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF1F2937)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
            ),
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                chipsSection,
                const SizedBox(height: 10),
                searchBox,
              ],
            );
          }

          return Row(
            children: [
              chipsSection,
              const Spacer(),
              searchBox,
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required bool isDark,
    required ColorScheme cs,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? cs.primary
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFCBD5E1)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? cs.onPrimary
                : (isDark
                    ? const Color(0xFFCBD5E1)
                    : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionCard(
    DeviceSession session,
    bool isDark,
    ColorScheme cs,
  ) {
    final isOnline = session.isOnline;
    final clientIcon = switch (session.clientType) {
      'desktop' => Icons.laptop_mac_rounded,
      'mobile' => Icons.phone_iphone_rounded,
      'web' => Icons.language_rounded,
      _ => Icons.devices_rounded,
    };
    final clientLabel = switch (session.clientType) {
      'desktop' => 'كمبيوتر',
      'mobile' => 'موبايل',
      'web' => 'ويب',
      _ => session.clientType,
    };

    final osName = session.deviceInfo['os']?.toString() ??
        session.deviceInfo['platform']?.toString() ??
        'غير محدد';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131926) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 700;

          final userDetails = Row(
            children: [
              // Avatar with Online Pulse Indicator
              Stack(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: cs.primary.withValues(alpha: 0.12),
                    child: Text(
                      session.fullName.isNotEmpty
                          ? session.fullName.substring(0, 1)
                          : 'U',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? const Color(0xFF10B981)
                            : const Color(0xFF94A3B8),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF131926)
                              : Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // Name, Handle & Job Title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            session.fullName,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '@${session.username}',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: isDark
                                ? const Color(0xFF64748B)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                    if (session.jobTitleBranch != null &&
                        session.jobTitleBranch!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '💼 ${session.jobTitleBranch!}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          final technicalDetails = Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Device & OS
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    clientIcon,
                    size: 15,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$clientLabel ($osName)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFF334155),
                    ),
                  ),
                ],
              ),

              // IP Address Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  session.ipAddress ?? 'IP محلي',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),

              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isOnline
                      ? const Color(0xFF10B981).withValues(alpha: 0.12)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isOnline
                        ? const Color(0xFF10B981).withValues(alpha: 0.3)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFCBD5E1)),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? const Color(0xFF10B981)
                            : const Color(0xFF94A3B8),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isOnline
                          ? 'متصل الآن'
                          : _formatTimeAgo(session.lastSeenAt),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: isOnline
                            ? const Color(0xFF10B981)
                            : (isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                userDetails,
                const SizedBox(height: 8),
                technicalDetails,
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 3, child: userDetails),
              const SizedBox(width: 14),
              technicalDetails,
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. ERRORS & DIAGNOSTICS TAB
  // ---------------------------------------------------------------------------
  Widget _buildErrorsTab(
    SystemMonitorState state,
    SystemMonitorController notifier,
    bool isDark,
    ColorScheme cs,
  ) {
    // Filter errors locally or via controller
    final filteredErrors = state.errors.where((e) {
      if (_errorResolvedFilter != null) {
        return e.resolved == _errorResolvedFilter;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131926) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 750;

              final titleAndFilters = Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'سجل المشاكل والأخطاء (${state.errors.length})',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Filter chips
                  _buildErrorFilterChip(
                    label: 'الكل',
                    selected: _errorResolvedFilter == null,
                    onTap: () => setState(() => _errorResolvedFilter = null),
                    isDark: isDark,
                    cs: cs,
                  ),
                  _buildErrorFilterChip(
                    label: '🔴 بانتظار الحل',
                    selected: _errorResolvedFilter == false,
                    onTap: () => setState(() => _errorResolvedFilter = false),
                    isDark: isDark,
                    cs: cs,
                  ),
                  _buildErrorFilterChip(
                    label: '🟢 تم الحل',
                    selected: _errorResolvedFilter == true,
                    onTap: () => setState(() => _errorResolvedFilter = true),
                    isDark: isDark,
                    cs: cs,
                  ),
                ],
              );

              final clearBtn = state.errors.isNotEmpty
                  ? OutlinedButton.icon(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('تأكيد مسح الأخطاء'),
                            content: const Text(
                              'هل أنت متأكد من مسح جميع سجلات الأخطاء من قاعدة البيانات؟',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('إلغاء'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4444),
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  notifier.deleteAllErrors();
                                },
                                child: const Text('مسح السجلات'),
                              ),
                            ],
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: BorderSide(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                      label: const Text('مسح السجلات',
                          style: TextStyle(fontSize: 11.5)),
                    )
                  : const SizedBox.shrink();

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    titleAndFilters,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: clearBtn),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: titleAndFilters),
                  clearBtn,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 14),

        // Errors List
        if (state.isLoadingErrors && state.errors.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (filteredErrors.isEmpty)
          _buildEmptyState(
            title: 'لا توجد أخطاء مسجلة',
            subtitle: 'كافة التطبيقات والأنظمة تعمل باستقرار تام ودون بلاغات برمجية',
            icon: Icons.check_circle_outline_rounded,
            isDark: isDark,
            cs: cs,
          )
        else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredErrors.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final error = filteredErrors[index];
              return _buildErrorCard(error, notifier, isDark, cs);
            },
          ),
          if (state.errorsHasMore) ...[
            const SizedBox(height: 16),
            Center(
              child: FilledButton.tonal(
                onPressed: state.isLoadingErrors
                    ? null
                    : () => notifier.loadMoreErrors(),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: state.isLoadingErrors
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'تحميل المزيد من الأخطاء',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildErrorFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required bool isDark,
    required ColorScheme cs,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? cs.primary
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFCBD5E1)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? cs.onPrimary
                : (isDark
                    ? const Color(0xFFCBD5E1)
                    : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(
    ClientErrorLog error,
    SystemMonitorController notifier,
    bool isDark,
    ColorScheme cs,
  ) {
    final isResolved = error.resolved;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131926) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isResolved
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : const Color(0xFFEF4444).withValues(alpha: 0.3),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isResolved
                ? const Color(0xFF10B981).withValues(alpha: 0.12)
                : const Color(0xFFEF4444).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isResolved
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            color: isResolved
                ? const Color(0xFF10B981)
                : const Color(0xFFEF4444),
            size: 20,
          ),
        ),
        title: Text(
          error.errorMessage,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            height: 1.35,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${error.fullName ?? error.username ?? 'مجهول'} • ${error.clientType} • ${_formatTimeAgo(error.createdAt)}',
            style: TextStyle(
              fontSize: 11,
              color: isDark
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF64748B),
            ),
          ),
        ),
        trailing: isResolved
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'تم الحل بنجاح',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF10B981),
                  ),
                ),
              )
            : FilledButton.tonal(
                onPressed: () => notifier.resolveError(error.id),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'تحديد كمحلول',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
        children: [
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE2E8F0),
          ),
          const SizedBox(height: 14),

          // Error Context
          if (error.errorContext.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'بيانات وسياق الخطأ (Context):',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF090D16)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: SelectableText(
                error.errorContext.toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: isDark
                      ? const Color(0xFFCBD5E1)
                      : const Color(0xFF334155),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Stack Trace Mac-style Terminal Box
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('🔴 🟡 🟢', style: TextStyle(fontSize: 10)),
                  const SizedBox(width: 8),
                  Text(
                    'تتبع الاستدعاء (Stack Trace):',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: error.stackTrace ?? 'No stack trace'),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم نسخ تفاصيل الخطأ إلى الحافظة بنجاح'),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('نسخ الخطأ', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF090D16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                error.stackTrace?.trim().isNotEmpty == true
                    ? error.stackTrace!
                    : 'لا يوجد تتبع برمجي مسجل لهذا الخطأ.',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Color(0xFFE2E8F0),
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 6. EMPTY STATE
  // ---------------------------------------------------------------------------
  Widget _buildEmptyState({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
    required ColorScheme cs,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131926) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: cs.primary),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
