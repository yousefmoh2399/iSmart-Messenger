import 'package:flutter/material.dart';

import '../../models/system_monitor_models.dart';
import '../system_monitor_controller.dart';
import 'n8n_workflow_diagram_widget.dart';

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

  String _formatTimeAgo(DateTime? dt) {
    if (dt == null) return 'غير متوفر';
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
        // 1. n8n Animated Workflow Canvas
        N8nWorkflowDiagramWidget(
          summary: summary,
          telemetry: telemetry,
          stats: stats,
          isDark: isDark,
        ),
        const SizedBox(height: 20),

        // 2. Bento Deployment KPI Cards
        _buildBentoKpiRow(summary, telemetry, isDark, cs),
        const SizedBox(height: 20),

        // 3. Action and Filter Bar
        _buildActionFilterBar(state, notifier, isDark, cs),
        const SizedBox(height: 16),

        // 4. Branches List / Grid
        if (state.isLoadingDeployment)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (filteredBranches.isEmpty)
          _buildEmptyBranchesCard(isDark)
        else
          _buildBranchesGrid(filteredBranches, isDark, cs),

        const SizedBox(height: 24),

        // 5. Live Server Requests Stream (n8n Traffic Monitor)
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
          // Card 1: Adoption Rate
          _buildKpiCard(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.pie_chart_rounded,
            accentColor: const Color(0xFF10B981),
            title: 'نسبة انتشار المنظومة',
            value: '$adoptionPercent%',
            subtitle: '$installedBranches فرع مثبت من أصل $totalBranches',
            extraWidget: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: totalBranches > 0
                        ? (installedBranches / totalBranches).clamp(0.0, 1.0)
                        : 0.0,
                    minHeight: 6,
                    backgroundColor: isDark
                        ? const Color(0xFF21262D)
                        : const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF10B981),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Card 2: Devices & Users
          _buildKpiCard(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.computer_rounded,
            accentColor: const Color(0xFF3B82F6),
            title: 'محطات وأجهزة العمل',
            value: '$totalDevs جهاز',
            subtitle: '$onlineDevs جهاز متصل بالشبكة الآن',
            badge: '$onlineDevs نشط',
            badgeColor: const Color(0xFF3B82F6),
          ),
          // Card 3: Traffic & RPS
          _buildKpiCard(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.speed_rounded,
            accentColor: const Color(0xFF8B5CF6),
            title: 'معدل الطلبات اللحظي',
            value: '$rps req/s',
            subtitle: 'متوسط الاستجابة: $latency ms',
            badge: '$totalReqs إجمالي',
            badgeColor: const Color(0xFF8B5CF6),
          ),
          // Card 4: App Version
          _buildKpiCard(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.verified_rounded,
            accentColor: const Color(0xFFEC4899),
            title: 'إصدار المنظومة النشط',
            value: 'v$appVer',
            subtitle: 'الإصدار المعتمد والنشط رسمياً',
            badge: 'مستقر',
            badgeColor: const Color(0xFFEC4899),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF8B949E)
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
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: badgeColor ?? accentColor,
                    ),
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
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? const Color(0xFF8B949E)
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

  Widget _buildActionFilterBar(
    SystemMonitorState state,
    SystemMonitorController notifier,
    bool isDark,
    ColorScheme cs,
  ) {
    final isExporting = state.isExportingReport;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 800;

          final searchWidget = SizedBox(
            width: isCompact ? constraints.maxWidth : 280,
            height: 38,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'بحث باسم الفرع أو كود الفرع...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? const Color(0xFF8B949E)
                      : const Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF0D1117)
                    : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          );

          final filterPills = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFilterChoice('all', 'الكل'),
              const SizedBox(width: 6),
              _buildFilterChoice('installed', 'المثبتة فقط'),
              const SizedBox(width: 6),
              _buildFilterChoice('not_installed', 'غير المثبتة'),
            ],
          );

          final exportButtons = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Excel Export
              FilledButton.tonalIcon(
                onPressed: isExporting
                    ? null
                    : () => notifier.exportReport('xlsx'),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      const Color(0xFF10B981).withValues(alpha: 0.15),
                  foregroundColor: const Color(0xFF10B981),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: isExporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.table_chart_rounded, size: 16),
                label: const Text(
                  'تصدير إكسيل',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              // PDF Export
              FilledButton.tonalIcon(
                onPressed: isExporting
                    ? null
                    : () => notifier.exportReport('pdf'),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      const Color(0xFFEF4444).withValues(alpha: 0.15),
                  foregroundColor: const Color(0xFFEF4444),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: isExporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: const Text(
                  'تصدير PDF',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchWidget,
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: filterPills,
                ),
                const SizedBox(height: 10),
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
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF3B82F6)
              : (isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark
                    ? const Color(0xFF8B949E)
                    : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  Widget _buildBranchesGrid(
    List<BranchDeploymentItem> branches,
    bool isDark,
    ColorScheme cs,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final cardCount = isWide ? 2 : 1;
        final spacing = 12.0;
        final cardWidth =
            (constraints.maxWidth - (spacing * (cardCount - 1))) / cardCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: branches.map((b) {
            return SizedBox(
              width: cardWidth,
              child: _buildBranchCard(b, isDark, cs),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildBranchCard(
    BranchDeploymentItem branch,
    bool isDark,
    ColorScheme cs,
  ) {
    final isInstalled = branch.isInstalled;
    final statusColor =
        isInstalled ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    final statusText = isInstalled ? 'تم التثبيت' : 'لم يتم التثبيت بعد';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isInstalled
              ? statusColor.withValues(alpha: isDark ? 0.3 : 0.25)
              : (isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Name, Code & Status
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isInstalled
                      ? Icons.check_circle_rounded
                      : Icons.hourglass_top_rounded,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      branch.branchName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'كود الفرع: ${branch.branchCode}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? const Color(0xFF8B949E)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0),
          ),
          const SizedBox(height: 12),
          // Info stats grid
          Row(
            children: [
              Expanded(
                child: _buildBranchStatItem(
                  isDark: isDark,
                  label: 'الأجهزة المثبتة',
                  value: '${branch.devicesCount} جهاز',
                  sub: '${branch.onlineDevicesCount} متصل الآن',
                  color: const Color(0xFF3B82F6),
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
                      ? branch.appVersions.first
                      : (isInstalled ? '1.1.21' : '-'),
                  sub: _formatTimeAgo(branch.lastActivityAt),
                  color: const Color(0xFF8B5CF6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: branch.devices.isEmpty && branch.installedUsers.isEmpty
                      ? null
                      : () => _showBranchDevicesModal(context, branch, isDark),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: BorderSide(
                      color: isDark
                          ? const Color(0xFF30363D)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  icon: const Icon(Icons.devices_other_rounded, size: 16),
                  label: Text(
                    'عرض الأجهزة والمستخدمين (${branch.devicesCount})',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
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
            fontSize: 10.5,
            color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          sub,
          style: TextStyle(
            fontSize: 10,
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
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.domain_disabled_rounded,
            size: 40,
            color: isDark ? const Color(0xFF484F58) : const Color(0xFF94A3B8),
          ),
          const SizedBox(height: 10),
          Text(
            'لا توجد فروع تطابق شروط البحث',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFC9D1D9) : const Color(0xFF334155),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.sync_alt_rounded,
                  color: Color(0xFF3B82F6),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سجل طلبات الخادم المباشرة (Server Traffic Stream)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'مراقبة لحظية لحركة الـ API والاستجابة مع كل طلب وارد',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? const Color(0xFF8B949E)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${recent.length} طلبات حديثة',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0),
          ),
          const SizedBox(height: 10),

          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'جاري استقبال الطلبات من الخادم...',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF8B949E)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            )
          else
            ...recent.take(12).map((r) => _buildLiveRequestRow(r, isDark)),
        ],
      ),
    );
  }

  Widget _buildLiveRequestRow(LiveRequestItem req, bool isDark) {
    Color methodColor;
    switch (req.method.toUpperCase()) {
      case 'GET':
        methodColor = const Color(0xFF3B82F6);
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
    final statusBadgeColor = isOk
        ? const Color(0xFF10B981)
        : (isWarn ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            // Method badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: methodColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                req.method,
                style: TextStyle(
                  fontSize: 10.5,
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
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // Status code
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusBadgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${req.statusCode}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: statusBadgeColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Duration
            Text(
              '${req.durationMs}ms',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? const Color(0xFF8B949E)
                    : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 10),
            // IP / User
            Text(
              req.fullName ?? req.username ?? req.clientIp,
              style: TextStyle(
                fontSize: 10,
                color: isDark
                    ? const Color(0xFF6E7681)
                    : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
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
                color: isDark ? const Color(0xFF161B22) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF30363D)
                          : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Title Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'أجهزة ومستخدمي فرع: ${branch.branchName}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                'إجمالي الأجهزة: ${branch.devicesCount}  |  المستخدمين المفعلين: ${branch.installedUsersCount}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? const Color(0xFF8B949E)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // List
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        if (branch.devices.isNotEmpty) ...[
                          Text(
                            'قائمة الأجهزة المثبتة (${branch.devices.length})',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? const Color(0xFF58A6FF)
                                  : const Color(0xFF2563EB),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...branch.devices.map(
                            (d) => _buildDeviceItemRow(d, isDark),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (branch.installedUsers.isNotEmpty) ...[
                          Text(
                            'المستخدمين الذين قاموا بتثبيت وتشغيل المنظومة (${branch.installedUsers.length})',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? const Color(0xFF3FB950)
                                  : const Color(0xFF16A34A),
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: d.isOnline
                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                  : const Color(0xFF64748B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.laptop_chromebook_rounded,
              color: d.isOnline
                  ? const Color(0xFF10B981)
                  : const Color(0xFF64748B),
              size: 18,
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
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'v${d.appVersion}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'المستخدم: ${d.fullName.isNotEmpty ? d.fullName : d.username}  |  IP: ${d.ipAddress}  |  ${d.os}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark
                        ? const Color(0xFF8B949E)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: d.isOnline
                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                  : const Color(0xFF64748B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              d.isOnline ? 'متصل الآن' : 'غير متصل',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: d.isOnline
                    ? const Color(0xFF10B981)
                    : const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserItemRow(InstalledUserItem u, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor:
                const Color(0xFF8B5CF6).withValues(alpha: 0.15),
            child: Text(
              u.fullName.isNotEmpty ? u.fullName.characters.first : 'U',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8B5CF6),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.fullName,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'اسم الدخول: ${u.username}  |  المسمى: ${u.jobTitle}  |  الدور: ${u.role}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark
                        ? const Color(0xFF8B949E)
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
                  ? const Color(0xFF6E7681)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
