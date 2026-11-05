import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/system_monitor_models.dart';
import '../system_monitor_controller.dart';
import 'n8n_workflow_diagram_widget.dart';
import '../live_operations_topology_screen.dart';

class BranchesDeploymentView extends StatefulWidget {
  const BranchesDeploymentView({
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
  State<BranchesDeploymentView> createState() => _BranchesDeploymentViewState();
}

class _BranchesDeploymentViewState extends State<BranchesDeploymentView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filterType = 'all'; // 'all', 'installed', 'not_installed'

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openLiveTopologyScreen(BuildContext context) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, anim, secAnim) => LiveOperationsTopologyScreen(
          state: widget.state,
          notifier: widget.notifier,
          isDark: widget.isDark,
          cs: widget.cs,
        ),
        transitionsBuilder: (context, anim, secAnim, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  String _formatTimeAgo(DateTime? dt) {
    if (dt == null) return 'غير متوفر';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 45) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'منذ ${diff.inDays} يوم';
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final notifier = widget.notifier;
    final isDark = widget.isDark;
    final cs = widget.cs;

    final deployment = state.deploymentData;
    final summary = deployment?.summary;
    final telemetry = state.requestTelemetry;
    final stats = state.stats;

    final allBranches = deployment?.branches ?? [];
    final query = _searchCtrl.text.trim().toLowerCase();

    final installedCount = allBranches.where((b) => b.isInstalled).length;
    final pendingCount = allBranches.where((b) => !b.isInstalled).length;

    final filteredBranches = allBranches.where((b) {
      if (_filterType == 'installed' && !b.isInstalled) return false;
      if (_filterType == 'not_installed' && b.isInstalled) return false;
      if (query.isNotEmpty) {
        final matchesName = b.branchName.toLowerCase().contains(query);
        final matchesCode = b.branchCode.toLowerCase().contains(query);
        return matchesName || matchesCode;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. n8n Animated Topology Canvas
        N8nWorkflowDiagramWidget(
          summary: summary,
          telemetry: telemetry,
          stats: stats,
          isDark: isDark,
          onOpenFullscreen: () => _openLiveTopologyScreen(context),
        ),
        const SizedBox(height: 18),

        // 2. Executive Bento KPI Cards
        _buildBentoKpiRow(summary, telemetry, isDark, cs),
        const SizedBox(height: 18),

        // 3. Action and Filter Bar
        _buildActionFilterBar(
          state: state,
          notifier: notifier,
          allCount: allBranches.length,
          installedCount: installedCount,
          pendingCount: pendingCount,
          isDark: isDark,
          cs: cs,
        ),
        const SizedBox(height: 14),

        // 4. Fleet Data Table / Cards
        if (state.isLoadingDeployment && allBranches.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (filteredBranches.isEmpty)
          _buildEmptyBranchesCard(isDark)
        else
          _buildFleetView(filteredBranches, isDark, cs),

        const SizedBox(height: 22),

        // 5. Live Server Requests Stream (Cloudflare-style Log Stream)
        _buildLiveRequestsStreamCard(telemetry, isDark, cs),
      ],
    );
  }

  Widget _buildBentoKpiRow(
    BranchDeploymentSummary? summary,
    RequestTelemetryData? telemetry,
    bool isDark,
    ColorScheme cs,
  ) {
    final adoptionPercent = summary?.adoptionPercentage ?? 0;
    final installedBranches = summary?.installedBranchesCount ?? 0;
    final totalBranches = summary?.totalBranches ?? 0;
    final notInstalled = summary?.notInstalledBranchesCount ?? 0;

    final totalDevs = summary?.totalInstalledDevices ?? 0;
    final onlineDevs = summary?.totalOnlineDevices ?? 0;

    final rps = telemetry?.rps ?? 0.0;
    final latency = telemetry?.avgLatencyMs ?? 14;
    final totalReqs = telemetry?.totalRequests ?? 0;

    final appVer = summary?.currentAppVersion ?? '1.1.21';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 840;
        final cardCount = isCompact ? 2 : 4;
        final spacing = 12.0;
        final cardWidth =
            (constraints.maxWidth - (spacing * (cardCount - 1))) / cardCount;

        final cards = [
          // Card 1: Branch Coverage
          _buildKpiCard(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.apartment_rounded,
            accentColor: const Color(0xFF10B981),
            title: 'تغطية أسطول الفروع',
            value: '$adoptionPercent%',
            subtitle: '$installedBranches مثبت  •  $notInstalled بانتظار النشر',
            extraWidget: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: totalBranches > 0
                      ? (installedBranches / totalBranches).clamp(0.0, 1.0)
                      : 0.0,
                  minHeight: 5,
                  backgroundColor: isDark
                      ? const Color(0xFF1F2937)
                      : const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF10B981),
                  ),
                ),
              ),
            ),
          ),
          // Card 2: Workstation Fleet
          _buildKpiCard(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.computer_rounded,
            accentColor: const Color(0xFF0284C7),
            title: 'محطات وأجهزة العمل',
            value: '$totalDevs محطة',
            subtitle: '$onlineDevs متصل الآن بالشبكة',
            badge: '$onlineDevs نشط',
            badgeColor: const Color(0xFF0284C7),
          ),
          // Card 3: Server Throughput
          _buildKpiCard(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.speed_rounded,
            accentColor: const Color(0xFF6366F1),
            title: 'أداء الخادم والـ API',
            value: '$rps req/s',
            subtitle: 'متوسط الاستجابة: $latency ms',
            badge: '$totalReqs طلب',
            badgeColor: const Color(0xFF6366F1),
          ),
          // Card 4: Enterprise Release
          _buildKpiCard(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.verified_rounded,
            accentColor: const Color(0xFF8B5CF6),
            title: 'إصدار المنظومة المعتمد',
            value: 'v$appVer',
            subtitle: 'الإصدار الإنتاجي المستقر',
            badge: 'معتمد',
            badgeColor: const Color(0xFF8B5CF6),
          ),
        ];

        if (isCompact) {
          return Column(
            children: [
              Row(children: [cards[0], SizedBox(width: spacing), cards[1]]),
              const SizedBox(height: 12),
              Row(children: [cards[2], SizedBox(width: spacing), cards[3]]),
            ],
          );
        }

        return Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              cards[i],
            ],
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required bool isDark,
    required double width,
    required IconData icon,
    required Color accentColor,
    required String title,
    required String value,
    required String subtitle,
    String? badge,
    Color? badgeColor,
    Widget? extraWidget,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? accentColor).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: badgeColor ?? accentColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF64748B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (extraWidget != null) extraWidget,
        ],
      ),
    );
  }

  Widget _buildActionFilterBar({
    required SystemMonitorState state,
    required SystemMonitorController notifier,
    required int allCount,
    required int installedCount,
    required int pendingCount,
    required bool isDark,
    required ColorScheme cs,
  }) {
    final isExporting = state.isExportingReport;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 820;

          final searchWidget = SizedBox(
            width: isCompact ? constraints.maxWidth : 280,
            height: 36,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'بحث باسم الفرع أو الكود...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? const Color(0xFF64748B)
                      : const Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 17),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
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

          final filterPills = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFilterChoice('all', 'جميع الفروع ($allCount)'),
              const SizedBox(width: 6),
              _buildFilterChoice('installed', 'المثبتة ($installedCount)'),
              const SizedBox(width: 6),
              _buildFilterChoice('not_installed', 'بانتظار التثبيت ($pendingCount)'),
            ],
          );

          final exportButtons = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Excel Export
              OutlinedButton.icon(
                onPressed: isExporting
                    ? null
                    : () => notifier.exportReport('xlsx'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: BorderSide(
                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: isExporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF10B981),
                        ),
                      )
                    : const Icon(Icons.table_chart_rounded, size: 15),
                label: const Text(
                  'تصدير إكسيل',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              // PDF Export
              OutlinedButton.icon(
                onPressed: isExporting
                    ? null
                    : () => notifier.exportReport('pdf'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: BorderSide(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: isExporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFEF4444),
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 15),
                label: const Text(
                  'تصدير PDF',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchWidget,
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: filterPills,
                ),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: exportButtons),
              ],
            );
          }

          return Row(
            children: [
              searchWidget,
              const SizedBox(width: 12),
              filterPills,
              const Spacer(),
              exportButtons,
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChoice(String key, String label) {
    final isSelected = _filterType == key;
    final isDark = widget.isDark;

    return InkWell(
      onTap: () => setState(() => _filterType = key),
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: isSelected
                ? (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1))
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? (isDark ? Colors.white : const Color(0xFF0F172A))
                : (isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }

  Widget _buildFleetView(
    List<BranchDeploymentItem> branches,
    bool isDark,
    ColorScheme cs,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 840;

        if (isWide) {
          return _buildEnterpriseFleetTable(branches, isDark, cs);
        }

        // Compact list for smaller screens
        return Column(
          children: branches
              .map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildBranchCard(b, isDark, cs),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildEnterpriseFleetTable(
    List<BranchDeploymentItem> branches,
    bool isDark,
    ColorScheme cs,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Table Header Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'الفرع والكود',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'موقف التثبيت',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'محطات العمل',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'المستخدمين',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'إصدار المنظومة',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'آخر نشاط',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text(
                      'الإجراءات',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Rows
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: branches.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF1F5F9),
              ),
              itemBuilder: (context, index) {
                final b = branches[index];
                final isInstalled = b.isInstalled;

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  child: Row(
                    children: [
                      // Branch name & code
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1F2937)
                                    : const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                b.branchCode.isNotEmpty ? b.branchCode : 'BR',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? const Color(0xFFCBD5E1)
                                      : const Color(0xFF334155),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                b.branchName,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Status pill
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isInstalled
                                  ? const Color(0xFF10B981)
                                      .withValues(alpha: 0.1)
                                  : (isDark
                                      ? const Color(0xFF1F2937)
                                      : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isInstalled
                                    ? const Color(0xFF10B981)
                                        .withValues(alpha: 0.25)
                                    : (isDark
                                        ? const Color(0xFF334155)
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
                                    shape: BoxShape.circle,
                                    color: isInstalled
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isInstalled
                                      ? 'تم التثبيت'
                                      : 'بانتظار التثبيت',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: isInstalled
                                        ? const Color(0xFF10B981)
                                        : (isDark
                                            ? const Color(0xFF94A3B8)
                                            : const Color(0xFF64748B)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Workstations
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Text(
                              '${b.devicesCount} جهاز',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? const Color(0xFFF1F5F9)
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            if (b.onlineDevicesCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${b.onlineDevicesCount} متصل',
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0284C7),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Users
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${b.installedUsersCount} مفعل / ${b.totalRegisteredUsers}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark
                                ? const Color(0xFFCBD5E1)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ),

                      // Version
                      Expanded(
                        flex: 2,
                        child: Text(
                          b.appVersions.isNotEmpty
                              ? 'v${b.appVersions.first}'
                              : (isInstalled ? 'v1.1.21' : '-'),
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? const Color(0xFFA5B4FC)
                                : const Color(0xFF4F46E5),
                          ),
                        ),
                      ),

                      // Last seen
                      Expanded(
                        flex: 2,
                        child: Text(
                          _formatTimeAgo(b.lastActivityAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ),

                      // Actions
                      SizedBox(
                        width: 120,
                        child: OutlinedButton(
                          onPressed: b.devices.isEmpty && b.installedUsers.isEmpty
                              ? null
                              : () => _showBranchDevicesModal(context, b, isDark),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: const Size(0, 30),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            side: BorderSide(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Text(
                            'تفاصيل الأجهزة (${b.devicesCount})',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchCard(
    BranchDeploymentItem branch,
    bool isDark,
    ColorScheme cs,
  ) {
    final isInstalled = branch.isInstalled;
    final statusColor =
        isInstalled ? const Color(0xFF10B981) : const Color(0xFF94A3B8);
    final statusText = isInstalled ? 'تم التثبيت' : 'بانتظار التثبيت';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Code, Name, Status
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1F2937)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  branch.branchCode.isNotEmpty ? branch.branchCode : 'BR',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF334155),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  branch.branchName,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF1F5F9),
          ),
          const SizedBox(height: 10),
          // Micro row
          Row(
            children: [
              Expanded(
                child: _buildBranchStatItem(
                  isDark: isDark,
                  label: 'الأجهزة المثبتة',
                  value: '${branch.devicesCount} جهاز',
                  sub: '${branch.onlineDevicesCount} متصل الآن',
                  color: const Color(0xFF0284C7),
                ),
              ),
              Expanded(
                child: _buildBranchStatItem(
                  isDark: isDark,
                  label: 'المستخدمين',
                  value: '${branch.installedUsersCount} مفعل',
                  sub: '${branch.totalRegisteredUsers} مسجل',
                  color: const Color(0xFF10B981),
                ),
              ),
              Expanded(
                child: _buildBranchStatItem(
                  isDark: isDark,
                  label: 'إصدار البرنامج',
                  value: branch.appVersions.isNotEmpty
                      ? 'v${branch.appVersions.first}'
                      : (isInstalled ? 'v1.1.21' : '-'),
                  sub: _formatTimeAgo(branch.lastActivityAt),
                  color: const Color(0xFF8B5CF6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: branch.devices.isEmpty && branch.installedUsers.isEmpty
                ? null
                : () => _showBranchDevicesModal(context, branch, isDark),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 6),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
              side: BorderSide(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFCBD5E1),
              ),
            ),
            child: Text(
              'عرض الأجهزة والمستخدمين (${branch.devicesCount})',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchStatItem({
    required bool isDark,
    required String label,
    required String value,
    required String sub,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 1),
        Text(
          sub,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildEmptyBranchesCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.domain_disabled_rounded,
            size: 36,
            color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
          ),
          const SizedBox(height: 8),
          Text(
            'لا توجد فروع تطابق معايير البحث الحالية',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveRequestsStreamCard(
    RequestTelemetryData? telemetry,
    bool isDark,
    ColorScheme cs,
  ) {
    final recent = telemetry?.recentRequests ?? [];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF090D16) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(
                      Icons.sync_alt_rounded,
                      color: Color(0xFF38BDF8),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سجل حركة الطلبات والـ API المباشرة (Live Request Stream)',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? const Color(0xFFF1F5F9)
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'رصد لحظي فوري لحركة الـ API وزمن الاستجابة مع كل طلب وارد',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${recent.length} طلبات مسجلة',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'جاري استقبال طلبات الـ API من الخادم...',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recent.take(10).length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF1F5F9),
                ),
                itemBuilder: (context, index) {
                  return _buildLiveRequestRow(recent[index], isDark);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveRequestRow(LiveRequestItem req, bool isDark) {
    Color methodColor;
    switch (req.method.toUpperCase()) {
      case 'GET':
        methodColor = const Color(0xFF0284C7);
        break;
      case 'POST':
        methodColor = const Color(0xFF10B981);
        break;
      case 'PATCH':
      case 'PUT':
        methodColor = const Color(0xFFF59E0B);
        break;
      case 'DELETE':
        methodColor = const Color(0xFFEF4444);
        break;
      default:
        methodColor = const Color(0xFF8B5CF6);
    }

    final isOk = req.statusCode >= 200 && req.statusCode < 300;
    final isWarn = req.statusCode >= 400 && req.statusCode < 500;
    final statusColor = isOk
        ? const Color(0xFF10B981)
        : (isWarn ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    final timeStr =
        '${req.timestamp.hour.toString().padLeft(2, '0')}:${req.timestamp.minute.toString().padLeft(2, '0')}:${req.timestamp.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          // Time
          Text(
            timeStr,
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(width: 8),

          // Method tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: methodColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              req.method,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
                color: methodColor,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Path
          Expanded(
            child: Text(
              req.path,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),

          // Status code
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${req.statusCode}',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Duration
          Text(
            '${req.durationMs}ms',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 10),

          // User / IP
          Text(
            req.fullName ?? req.username ?? req.clientIp,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  void _showBranchDevicesModal(
    BuildContext context,
    BranchDeploymentItem branch,
    bool isDark,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111827) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Title Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'أجهزة ومستخدمي فرع: ${branch.branchName}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                'كود الفرع: ${branch.branchCode}  •  الأجهزة: ${branch.devicesCount}  •  المستخدمين: ${branch.installedUsersCount}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Content list
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (branch.devices.isNotEmpty) ...[
                          Text(
                            'المحطات والأجهزة المسجلة (${branch.devices.length})',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? const Color(0xFF38BDF8)
                                  : const Color(0xFF0284C7),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...branch.devices.map(
                            (d) => _buildDeviceItemRow(d, isDark),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (branch.installedUsers.isNotEmpty) ...[
                          Text(
                            'المستخدمين الذين قاموا بتشغيل المنظومة (${branch.installedUsers.length})',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF059669),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...branch.installedUsers.map(
                            (u) => _buildUserItemRow(u, isDark),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDeviceItemRow(BranchDeviceItem d, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: d.isOnline
                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                  : (isDark
                      ? const Color(0xFF1F2937)
                      : const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.laptop_chromebook_rounded,
              color: d.isOnline
                  ? const Color(0xFF10B981)
                  : const Color(0xFF94A3B8),
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      d.hostname,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'v${d.appVersion}',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'المستخدم: ${d.fullName.isNotEmpty ? d.fullName : d.username}  •  IP: ${d.ipAddress}  •  ${d.os}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: d.isOnline
                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                  : (isDark
                      ? const Color(0xFF1F2937)
                      : const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              d.isOnline ? 'متصل الآن' : 'غير متصل',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: d.isOnline
                    ? const Color(0xFF10B981)
                    : const Color(0xFF94A3B8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserItemRow(InstalledUserItem u, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor:
                const Color(0xFF6366F1).withValues(alpha: 0.15),
            child: Text(
              u.fullName.isNotEmpty ? u.fullName.characters.first : 'U',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6366F1),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.fullName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'الحساب: ${u.username}  •  المسمى: ${u.jobTitle}  •  الدور: ${u.role}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatTimeAgo(u.lastActiveAt),
            style: TextStyle(
              fontSize: 10,
              color: isDark
                  ? const Color(0xFF64748B)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
