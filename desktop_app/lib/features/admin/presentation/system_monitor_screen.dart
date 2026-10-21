import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/system_monitor_models.dart';
import 'system_monitor_controller.dart';

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
  int _currentTab = 0; // 0 = Sessions, 1 = Errors
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
          isDark ? const Color(0xFF0F1117) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header
            _buildHeader(context, state, notifier, isDark, cs),
            // 2. Scrollable Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Telemetry Bento KPI Cards
                    _buildTelemetryRow(state, isDark, cs),
                    const SizedBox(height: 20),
                    // Segmented Tabs Header
                    _buildTabsHeader(state, isDark, cs),
                    const SizedBox(height: 16),
                    // Active Tab Content
                    if (_currentTab == 0)
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

  Widget _buildHeader(
    BuildContext context,
    SystemMonitorState state,
    SystemMonitorController notifier,
    bool isDark,
    ColorScheme cs,
  ) {
    final isLoading =
        state.isLoadingStats || state.isLoadingSessions || state.isLoadingErrors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.analytics_rounded,
              color: Color(0xFF3B82F6),
              size: 24,
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
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'لوحة القيادة المركزية لمتابعة الاتصالات الحية، استهلاك الذاكرة، وصحة الخادم',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: isLoading ? null : () => notifier.refreshAll(),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(isLoading ? 'جاري الفحص...' : 'تحديث البيانات'),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryRow(
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. RAM / Memory
        Expanded(
          child: _buildBentoCard(
            isDark: isDark,
            icon: Icons.memory_rounded,
            iconColor: const Color(0xFF8B5CF6),
            title: 'استهلاك الذاكرة',
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
                  'Node Heap: $heapStr',
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
        ),
        const SizedBox(width: 14),
        // 2. Live WebSockets & Users
        Expanded(
          child: _buildBentoCard(
            isDark: isDark,
            icon: Icons.cell_tower_rounded,
            iconColor: const Color(0xFF10B981),
            title: 'الاتصالات الحية',
            value: '$liveSockets اتصال',
            subtitle: '$liveUsers موظف متصل الآن بالشبكة',
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
          ),
        ),
        const SizedBox(width: 14),
        // 3. Server & DB Uptime
        Expanded(
          child: _buildBentoCard(
            isDark: isDark,
            icon: Icons.dns_rounded,
            iconColor: const Color(0xFF3B82F6),
            title: 'الخادم وقاعدة البيانات',
            value: dbOnline ? 'متصل وجاهز' : 'غير متصل',
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
                  const SizedBox(width: 5),
                  Text(
                    'MongoDB ($nodeVer)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        // 4. Errors & Diagnostics
        Expanded(
          child: _buildBentoCard(
            isDark: isDark,
            icon: Icons.bug_report_rounded,
            iconColor: unresolved > 0
                ? const Color(0xFFEF4444)
                : const Color(0xFF10B981),
            title: 'سجلات المشاكل والأخطاء',
            value: unresolved > 0 ? '$unresolved بحاجة للحل' : 'لا توجد أخطاء',
            subtitle: 'إجمالي المسجل: $totalErrors بلاغ',
            extraWidget: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                unresolved > 0
                    ? 'يُنصح بمراجعة سجل الأخطاء أدناه'
                    : 'النظام يعمل باستقرار تام',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: unresolved > 0
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF10B981),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBentoCard({
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
        color: isDark ? const Color(0xFF1E2128) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
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
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
        ),
      ),
    );
  }

  Widget _buildTabsHeader(
    SystemMonitorState state,
    bool isDark,
    ColorScheme cs,
  ) {
    final liveCount = state.stats?.liveSocketsCount ?? 0;
    final errorsCount = state.errorsTotal;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFE2E8F0).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              title: 'الأجهزة والجلسات الحية ($liveCount متصل)',
              icon: Icons.devices_rounded,
              index: 0,
              isDark: isDark,
              cs: cs,
            ),
          ),
          Expanded(
            child: _buildTabButton(
              title: 'سجل المشاكل والأخطاء ($errorsCount)',
              icon: Icons.bug_report_rounded,
              index: 1,
              isDark: isDark,
              cs: cs,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required int index,
    required bool isDark,
    required ColorScheme cs,
  }) {
    final isSelected = _currentTab == index;
    return InkWell(
      onTap: () => setState(() => _currentTab = index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF1E2128) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
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
              size: 17,
              color: isSelected
                  ? cs.primary
                  : (isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Colors.white : const Color(0xFF0F172A))
                    : (isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
            subtitle: 'جرّب البحث بكلمات أخرى أو تغيير نوع الفلتر',
            icon: Icons.person_off_rounded,
            isDark: isDark,
            cs: cs,
          )
        else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final session = state.sessions[index];
              return _buildSessionCard(session, isDark, cs);
            },
          ),
          if (state.sessionsHasMore) ...[
            const SizedBox(height: 14),
            Center(
              child: FilledButton.tonal(
                onPressed: state.isLoadingSessions
                    ? null
                    : () => notifier.loadMoreSessions(),
                child: state.isLoadingSessions
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('تحميل المزيد من الجلسات'),
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
        color: isDark ? const Color(0xFF1E2128) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          // Status Chips
          _buildChip(
            label: 'الكل',
            selected: state.statusFilter == 'all',
            onTap: () => notifier.setFilters(status: 'all'),
            isDark: isDark,
            cs: cs,
          ),
          const SizedBox(width: 6),
          _buildChip(
            label: '🟢 متصل الآن',
            selected: state.statusFilter == 'online',
            onTap: () => notifier.setFilters(status: 'online'),
            isDark: isDark,
            cs: cs,
          ),
          const SizedBox(width: 6),
          _buildChip(
            label: '⚪ غير متصل',
            selected: state.statusFilter == 'offline',
            onTap: () => notifier.setFilters(status: 'offline'),
            isDark: isDark,
            cs: cs,
          ),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 20,
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.1),
          ),
          const SizedBox(width: 12),
          // Client Type Chips
          _buildChip(
            label: '💻 كمبيوتر',
            selected: state.clientTypeFilter == 'desktop',
            onTap: () => notifier.setFilters(
              clientType:
                  state.clientTypeFilter == 'desktop' ? 'all' : 'desktop',
            ),
            isDark: isDark,
            cs: cs,
          ),
          const SizedBox(width: 6),
          _buildChip(
            label: '📱 موبايل',
            selected: state.clientTypeFilter == 'mobile',
            onTap: () => notifier.setFilters(
              clientType: state.clientTypeFilter == 'mobile' ? 'all' : 'mobile',
            ),
            isDark: isDark,
            cs: cs,
          ),
          const Spacer(),
          // Search Box
          SizedBox(
            width: 240,
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
                  fontSize: 11,
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
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
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
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
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

    final osName =
        session.deviceInfo['os']?.toString() ??
        session.deviceInfo['platform']?.toString() ??
        'غير محدد';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2128) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          // Avatar with Status Indicator
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
                          ? const Color(0xFF1E2128)
                          : Colors.white,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          // User Info
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      session.fullName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '@${session.username}',
                      style: TextStyle(
                        fontSize: 11,
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
                  ),
                ],
              ],
            ),
          ),
          // Device & OS
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(
                  clientIcon,
                  size: 16,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      osName,
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // IP Address Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              session.ipAddress ?? 'IP محلي',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Consolas',
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Status & Last Seen
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isOnline ? 'متصل الآن' : 'غير متصل',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isOnline
                      ? const Color(0xFF10B981)
                      : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isOnline
                    ? 'نشط بالخدمة'
                    : 'آخر ظهور: ${_formatTimeAgo(session.lastSeenAt)}',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark
                      ? const Color(0xFF64748B)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorsTab(
    SystemMonitorState state,
    SystemMonitorController notifier,
    bool isDark,
    ColorScheme cs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Toolbar
        Row(
          children: [
            Text(
              'سجل البلاغات والأخطاء المسجلة (${state.errors.length})',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const Spacer(),
            if (state.errors.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('تأكيد مسح الأخطاء'),
                      content: const Text(
                        'هل أنت متأكد من مسح جميع الأخطاء المسجلة من قاعدة البيانات؟',
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
                          child: const Text('مسح الكل'),
                        ),
                      ],
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('مسح الكل', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (state.isLoadingErrors && state.errors.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.errors.isEmpty)
          _buildEmptyState(
            title: 'لا توجد أخطاء مسجلة',
            subtitle: 'جميع الأنظمة والتطبيقات تعمل بكفاءة ودون مشاكل برمجية',
            icon: Icons.check_circle_outline_rounded,
            isDark: isDark,
            cs: cs,
          )
        else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.errors.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final error = state.errors[index];
              return _buildErrorCard(error, notifier, isDark, cs);
            },
          ),
          if (state.errorsHasMore) ...[
            const SizedBox(height: 14),
            Center(
              child: FilledButton.tonal(
                onPressed: state.isLoadingErrors
                    ? null
                    : () => notifier.loadMoreErrors(),
                child: state.isLoadingErrors
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('تحميل المزيد من الأخطاء'),
              ),
            ),
          ],
        ],
      ],
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
        color: isDark ? const Color(0xFF1E2128) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isResolved
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : const Color(0xFFEF4444).withValues(alpha: 0.3),
        ),
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
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'تم الحل',
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
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('تحديد كمحلول', style: TextStyle(fontSize: 11)),
              ),
        children: [
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 12),
          // Error Context
          if (error.errorContext.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'بيانات وسياق الخطأ (Context):',
                style: TextStyle(
                  fontSize: 12,
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
                    ? Colors.black.withValues(alpha: 0.25)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                error.errorContext.toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Consolas',
                  color: isDark
                      ? const Color(0xFFCBD5E1)
                      : const Color(0xFF334155),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Stack Trace
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'تتبع الخطأ (StackTrace):',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: error.stackTrace ?? 'No stack trace'),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ نص الخطأ إلى الحافظة')),
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
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                error.stackTrace?.trim().isNotEmpty == true
                    ? error.stackTrace!
                    : 'لا يوجد تتبع برمجي مسجل لهذا الخطأ.',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'Consolas',
                  color: Color(0xFFE2E8F0),
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
