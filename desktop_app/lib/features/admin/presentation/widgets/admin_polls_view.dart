import 'package:flutter/material.dart';

import '../../models/system_monitor_models.dart';
import '../system_monitor_controller.dart';

class AdminPollsView extends StatefulWidget {
  const AdminPollsView({
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
  State<AdminPollsView> createState() => _AdminPollsViewState();
}

class _AdminPollsViewState extends State<AdminPollsView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _statusFilter = 'all'; // 'all', 'active', 'closed'

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatTimeAgo(DateTime dt) {
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

    final pollsData = state.pollsData;
    final allPolls = pollsData?.items ?? [];
    final query = _searchCtrl.text.trim().toLowerCase();

    final activeCount = allPolls.where((p) => !p.isClosed).length;
    final closedCount = allPolls.where((p) => p.isClosed).length;

    final filteredPolls = allPolls.where((p) {
      if (_statusFilter == 'active' && p.isClosed) return false;
      if (_statusFilter == 'closed' && !p.isClosed) return false;
      if (query.isNotEmpty) {
        final matchQ = p.question.toLowerCase().contains(query);
        final matchCreator = p.creator.fullName.toLowerCase().contains(query) ||
            p.creator.username.toLowerCase().contains(query) ||
            p.creator.branchName.toLowerCase().contains(query);
        return matchQ || matchCreator;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. KPI / Overview Summary Cards
        _buildPollsOverviewCards(
          totalCount: allPolls.length,
          activeCount: activeCount,
          closedCount: closedCount,
          totalVotesSum: allPolls.fold(0, (acc, p) => acc + p.totalVotes),
          isDark: isDark,
          cs: cs,
        ),
        const SizedBox(height: 16),

        // 2. Toolbar: Search & Filter
        _buildToolbar(
          totalCount: allPolls.length,
          activeCount: activeCount,
          closedCount: closedCount,
          isDark: isDark,
        ),
        const SizedBox(height: 16),

        // 3. Polls List
        if (state.isLoadingPolls && allPolls.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (filteredPolls.isEmpty)
          _buildEmptyPollsCard(isDark)
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredPolls.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _buildPollCard(filteredPolls[index], state, notifier, isDark, cs);
            },
          ),
      ],
    );
  }

  Widget _buildPollsOverviewCards({
    required int totalCount,
    required int activeCount,
    required int closedCount,
    required int totalVotesSum,
    required bool isDark,
    required ColorScheme cs,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 800;
        final cardCount = isCompact ? 2 : 4;
        final spacing = 12.0;
        final cardWidth =
            (constraints.maxWidth - (spacing * (cardCount - 1))) / cardCount;

        final cards = [
          _buildMiniKpi(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.poll_rounded,
            accentColor: const Color(0xFF6366F1),
            title: 'إجمالي الاستطلاعات',
            value: '$totalCount استطلاع',
            subtitle: 'كافة الاستطلاعات المنشأة بالمنظومة',
          ),
          _buildMiniKpi(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.how_to_vote_rounded,
            accentColor: const Color(0xFF10B981),
            title: 'الاستطلاعات النشطة',
            value: '$activeCount استطلاع',
            subtitle: 'مفتوحة للتصويت ومتاحة للمستخدمين',
          ),
          _buildMiniKpi(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.task_alt_rounded,
            accentColor: const Color(0xFF0284C7),
            title: 'المغلقة والمكتملة',
            value: '$closedCount استطلاع',
            subtitle: 'انتهت فترة التصويت عليها',
          ),
          _buildMiniKpi(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.people_alt_rounded,
            accentColor: const Color(0xFFF59E0B),
            title: 'إجمالي الأصوات المسجلة',
            value: '$totalVotesSum صوت',
            subtitle: 'تفاعل الموظفين بالمحادثات والمجموعات',
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

  Widget _buildMiniKpi({
    required bool isDark,
    required double width,
    required IconData icon,
    required Color accentColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
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
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: isDark
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF64748B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar({
    required int totalCount,
    required int activeCount,
    required int closedCount,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 800;

          final searchWidget = SizedBox(
            width: isCompact ? constraints.maxWidth : 300,
            height: 36,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'بحث بعنوان الاستطلاع أو اسم المنشئ...',
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
              _buildFilterChoice('all', 'الكل ($totalCount)'),
              const SizedBox(width: 6),
              _buildFilterChoice('active', 'النشطة ($activeCount)'),
              const SizedBox(width: 6),
              _buildFilterChoice('closed', 'المغلقة ($closedCount)'),
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
              ],
            );
          }

          return Row(
            children: [
              searchWidget,
              const SizedBox(width: 12),
              filterPills,
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChoice(String key, String label) {
    final isSelected = _statusFilter == key;
    final isDark = widget.isDark;

    return InkWell(
      onTap: () => setState(() => _statusFilter = key),
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

  Widget _buildPollCard(
    AdminPollItem poll,
    SystemMonitorState state,
    SystemMonitorController notifier,
    bool isDark,
    ColorScheme cs,
  ) {
    final isClosed = poll.isClosed;
    final isExporting = state.exportingPollId == poll.id;
    final statusColor =
        isClosed ? const Color(0xFF94A3B8) : const Color(0xFF10B981);
    final statusText = isClosed ? 'مغلق ومكتمل' : 'مفتوح للتصويت';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Creator info, status badge, date
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor:
                    const Color(0xFF6366F1).withValues(alpha: 0.15),
                child: Text(
                  poll.creator.fullName.isNotEmpty
                      ? poll.creator.fullName.characters.first
                      : 'U',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF818CF8),
                  ),
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
                          poll.creator.fullName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1F2937)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            poll.creator.branchName,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'المسمى: ${poll.creator.jobTitle}  •  المحادثة: ${poll.conversation.title}  •  ${_formatTimeAgo(poll.createdAt)}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.25),
                  ),
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
                        fontSize: 10.5,
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

          // Question Title
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.help_outline_rounded,
                  size: 20,
                  color: Color(0xFF6366F1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    poll.question,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${poll.totalVotes} صوت مسجل',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF818CF8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Options Progress Bars
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: poll.options.map((opt) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            opt.text,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFFE2E8F0)
                                  : const Color(0xFF334155),
                            ),
                          ),
                        ),
                        Text(
                          '${opt.votesCount} صوت  (${opt.percentage}%)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? const Color(0xFFA5B4FC)
                                : const Color(0xFF4F46E5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (opt.percentage / 100).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: isDark
                            ? const Color(0xFF1F2937)
                            : const Color(0xFFE2E8F0),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          opt.percentage > 40
                              ? const Color(0xFF10B981)
                              : const Color(0xFF6366F1),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),

          // Action Buttons: Excel Export, PDF Export
          Row(
            children: [
              // Export Excel Button
              OutlinedButton.icon(
                onPressed: isExporting
                    ? null
                    : () => notifier.exportPoll(
                          poll.id,
                          format: 'xlsx',
                          title: poll.question,
                        ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: BorderSide(
                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                  'تصدير إكسيل (.xlsx)',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),

              // Export PDF Button
              OutlinedButton.icon(
                onPressed: isExporting
                    ? null
                    : () => notifier.exportPoll(
                          poll.id,
                          format: 'pdf',
                          title: poll.question,
                        ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: BorderSide(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                  'تصدير PDF (.pdf)',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPollsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
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
            Icons.poll_outlined,
            size: 38,
            color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
          ),
          const SizedBox(height: 8),
          Text(
            'لا توجد استطلاعات رأي تطابق البحث',
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
}
