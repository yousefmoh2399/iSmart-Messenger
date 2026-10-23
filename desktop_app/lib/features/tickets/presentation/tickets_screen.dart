import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/button_loading_indicator.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../chat/models/chat_models.dart';
import '../models/ticket_models.dart';
import '../../reports/presentation/custom_report_export_dialog.dart';
import '../../reports/presentation/report_templates_screen.dart';
import 'tickets_ui_kit.dart';

class _TicketsUi {
  const _TicketsUi._();

  // static const double pagePadding = 16;
  // static const double sectionGap = 16;
  static const double cardRadius = 20;
  static const double chipRadius = 999;
  static const double panelRadius = 24;
  static const double dialogWidth = 620;

  static const Duration fast = Duration(milliseconds: 180);

  static const Color brand = Color(0xFF2563EB);
  static const Color brandSoft = Color(0xFFEAF2FF);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC2626);
  static const Color purple = Color(0xFF7C3AED);
}

enum TicketFilter { all, open, resolved, closed, critical, mine }

extension TicketFilterLabel on TicketFilter {
  String get label => switch (this) {
    TicketFilter.all => 'الكل',
    TicketFilter.open => 'المفتوحة',
    TicketFilter.resolved => 'تم حلها',
    TicketFilter.closed => 'المغلقة',
    TicketFilter.critical => 'الحرجة',
    TicketFilter.mine => 'المسندة',
  };
}

enum TicketTypeTab { ticket, complaint, suggestion }

extension TicketTypeTabLabel on TicketTypeTab {
  String get label => switch (this) {
    TicketTypeTab.ticket => 'تذاكر الدعم',
    TicketTypeTab.complaint => 'الشكاوى',
    TicketTypeTab.suggestion => 'المقترحات',
  };
}

extension TicketTypeTabIcon on TicketTypeTab {
  IconData get icon => switch (this) {
    TicketTypeTab.ticket => Icons.support_agent_outlined,
    TicketTypeTab.complaint => Icons.report_problem_outlined,
    TicketTypeTab.suggestion => Icons.lightbulb_outline_rounded,
  };

  String get shortLabel => switch (this) {
    TicketTypeTab.ticket => 'تذاكر',
    TicketTypeTab.complaint => 'شكاوى',
    TicketTypeTab.suggestion => 'مقترحات',
  };
}

class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({
    super.key,
    this.embedded = false,
    this.isWrapped = false,
    this.initialTab = TicketTypeTab.ticket,
    this.closedOnly = false,
    this.onTabChanged,
  });

  final bool embedded;
  final bool isWrapped;
  final TicketTypeTab initialTab;
  final bool closedOnly;
  final ValueChanged<TicketTypeTab>? onTabChanged;

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  final TextEditingController _searchController = TextEditingController();
  TicketFilter _activeFilter = TicketFilter.all;
  late TicketTypeTab _activeTab;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    if (widget.closedOnly) {
      _activeFilter = TicketFilter.closed;
    }
  }

  @override
  void didUpdateWidget(covariant TicketsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() {
        _activeTab = widget.initialTab;
      });
    }
    if (oldWidget.closedOnly != widget.closedOnly) {
      setState(() {
        _activeFilter = widget.closedOnly
            ? TicketFilter.closed
            : TicketFilter.all;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showCreateTicketDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CreateTicketDialog(ticketType: _activeTab),
    );
  }

  Future<void> _showSupportTeamDialog() async {
    final authUser = ref.read(authControllerProvider).valueOrNull;
    if (authUser?.role != 'admin') return;

    try {
      final data = await ref
          .read(ticketsControllerProvider.notifier)
          .fetchSupportUsers();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _SupportTeamDialog(data: data),
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString(), isError: true);
    }
  }

  String _departmentHandlerTypeForTab() => switch (_activeTab) {
    TicketTypeTab.complaint => 'complaint',
    TicketTypeTab.suggestion => 'suggestion',
    TicketTypeTab.ticket => 'ticket',
  };

  Future<void> _showDepartmentHandlersDialog() async {
    final authUser = ref.read(authControllerProvider).valueOrNull;
    if (authUser?.role != 'admin') return;

    try {
      await showDialog<void>(
        context: context,
        builder: (_) => _DepartmentHandlersDialog(
          handlerType: _departmentHandlerTypeForTab(),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _exportTicketsReport({String format = 'xlsx', String? templateId}) async {
    try {
      final status = widget.closedOnly
          ? 'closed'
          : switch (_activeFilter) {
              TicketFilter.resolved => 'resolved',
              TicketFilter.closed => 'closed',
              _ => null,
            };
      final ticketType = switch (_activeTab) {
        TicketTypeTab.ticket => 'ticket',
        TicketTypeTab.complaint => 'complaint',
        TicketTypeTab.suggestion => 'suggestion',
      };
      final priority = _activeFilter == TicketFilter.critical
          ? 'critical'
          : null;
      await ref
          .read(ticketsControllerProvider.notifier)
          .exportTicketsReport(
            ticketType: ticketType,
            status: status,
            priority: priority,
            q: _searchController.text.trim(),
            format: format,
            templateId: templateId,
          );
      if (!mounted) return;
      _showMessage('تم تصدير تقرير التذاكر.');
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _showCustomExportDialog() async {
    final result = await CustomReportExportDialog.show(
      context: context,
      reportType: 'tickets',
      title: 'تصدير تقرير ${_activeTab.label}',
    );
    if (result != null) {
      await _exportTicketsReport(
        format: result.format,
        templateId: result.templateId,
      );
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? _TicketsUi.danger : null,
          content: Text(message),
        ),
      );
  }

  bool _ticketHasAssignee(TicketItem ticket) {
    final assigneeId = ticket.assignedTo?.id.trim() ?? '';
    if (assigneeId.isNotEmpty) {
      return true;
    }
    return ticket.status == 'assigned';
  }

  List<TicketItem> _filteredTickets(
    List<TicketItem> tickets,
    AppUser? authUser,
  ) {
    final query = _searchController.text.trim().toLowerCase();

    return tickets.where((ticket) {
      final matchesType = switch (_activeTab) {
        TicketTypeTab.ticket => ticket.ticketType == 'ticket',
        TicketTypeTab.complaint => ticket.ticketType == 'complaint',
        TicketTypeTab.suggestion => ticket.ticketType == 'suggestion',
      };

      if (!matchesType) {
        return false;
      }
      final matchesQuery =
          query.isEmpty ||
          ticket.ticketNumber.toLowerCase().contains(query) ||
          ticket.title.toLowerCase().contains(query) ||
          ticket.description.toLowerCase().contains(query) ||
          (ticket.assignedTo?.displayName.toLowerCase().contains(query) ??
              false);

      final matchesFilter = switch (_activeFilter) {
        TicketFilter.all => true,
        TicketFilter.open =>
          ticket.status == 'open' ||
              ticket.status == 'assigned' ||
              ticket.status == 'in_progress' ||
              ticket.status == 'waiting_branch',
        TicketFilter.resolved => ticket.status == 'resolved',
        TicketFilter.closed => ticket.status == 'closed',
        TicketFilter.critical => ticket.priority == 'critical',
        TicketFilter.mine => _ticketHasAssignee(ticket),
      };

      return matchesQuery && matchesFilter;
    }).toList();
  }

  Color _tabAccent() => switch (_activeTab) {
    TicketTypeTab.ticket => TicketsPalette.brand,
    TicketTypeTab.complaint => TicketsPalette.complaint,
    TicketTypeTab.suggestion => TicketsPalette.suggestion,
  };

  Widget _buildToolbar(AppUser? authUser, data) {
    final theme = Theme.of(context);
    final tabTickets = data.tickets.where((ticket) {
      return switch (_activeTab) {
        TicketTypeTab.ticket => ticket.ticketType == 'ticket',
        TicketTypeTab.complaint => ticket.ticketType == 'complaint',
        TicketTypeTab.suggestion => ticket.ticketType == 'suggestion',
      };
    }).toList();
    final total = tabTickets.length;
    final open = tabTickets
        .where(
          (t) =>
              t.status == 'open' ||
              t.status == 'assigned' ||
              t.status == 'in_progress' ||
              t.status == 'waiting_branch',
        )
        .length;
    final critical = tabTickets.where((t) => t.priority == 'critical').length;
    final assigned = tabTickets.where(_ticketHasAssignee).length;
    final accent = _tabAccent();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TicketsHeroHeader(
            title: _activeTab.label,
            subtitle: 'إدارة الطلبات والمتابعة حسب القسم والحالة',
            icon: _activeTab.icon,
            accent: accent,
            createLabel: switch (_activeTab) {
              TicketTypeTab.ticket => 'تذكرة جديدة',
              TicketTypeTab.complaint => 'شكوى جديدة',
              TicketTypeTab.suggestion => 'مقترح جديد',
            },
            onCreate: _showCreateTicketDialog,
            onSecondary: authUser?.role == 'admin'
                ? (_activeTab == TicketTypeTab.ticket
                      ? _showSupportTeamDialog
                      : _showDepartmentHandlersDialog)
                : null,
            secondaryLabel: switch (_activeTab) {
              TicketTypeTab.ticket => 'فريق الدعم',
              TicketTypeTab.complaint => 'مسؤولو الشكاوى',
              TicketTypeTab.suggestion => 'مسؤولو المقترحات',
            },
            secondaryIcon: _activeTab == TicketTypeTab.ticket
                ? Icons.admin_panel_settings_outlined
                : Icons.corporate_fare_rounded,
            onTertiary:
                authUser?.role == 'admin' && _activeTab == TicketTypeTab.ticket
                ? _showDepartmentHandlersDialog
                : null,
            tertiaryLabel: 'مسؤولو التذاكر',
            tertiaryIcon: Icons.corporate_fare_rounded,
          ),
          const SizedBox(height: 8),
          TicketsTypeSegmentBar(
            labels: TicketTypeTab.values.map((tab) => tab.shortLabel).toList(),
            icons: TicketTypeTab.values.map((tab) => tab.icon).toList(),
            selectedIndex: _activeTab.index,
            onChanged: (index) {
              setState(() {
                _activeTab = TicketTypeTab.values[index];
                widget.onTabChanged?.call(_activeTab);
              });
            },
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF1C1C1E)
                  : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: 'ابحث برقم التذكرة أو العنوان أو الوصف',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                  size: 20,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: Icon(
                          Icons.cancel_rounded,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                          size: 18,
                        ),
                      ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in widget.closedOnly
                  ? const [TicketFilter.closed]
                  : TicketFilter.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(filter.label),
                      selected: _activeFilter == filter,
                      onSelected: (_) => setState(() => _activeFilter = filter),
                      showCheckmark: false,
                      backgroundColor: Colors.transparent,
                      selectedColor: accent.withValues(alpha: 0.12),
                      side: BorderSide(
                        color: _activeFilter == filter
                            ? accent.withValues(alpha: 0.5)
                            : theme.colorScheme.outlineVariant.withValues(
                                alpha: 0.3,
                              ),
                      ),
                      labelStyle: theme.textTheme.labelMedium?.copyWith(
                        color: _activeFilter == filter
                            ? accent
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: _activeFilter == filter
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TicketsStatGroup(
            stats: [
              TicketStatItem(
                label: 'الإجمالي',
                value: '$total',
                icon: Icons.layers_rounded,
                color: accent,
              ),
              TicketStatItem(
                label: 'مفتوحة',
                value: '$open',
                icon: Icons.mark_email_unread_outlined,
                color: TicketsPalette.warning,
              ),
              TicketStatItem(
                label: 'حرجة',
                value: '$critical',
                icon: Icons.priority_high_rounded,
                color: TicketsPalette.danger,
              ),
              TicketStatItem(
                label: 'مسندة',
                value: '$assigned',
                icon: Icons.person_pin_circle_outlined,
                color: TicketsPalette.success,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: () =>
                    ref.read(ticketsControllerProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('تحديث'),
              ),
              if (data.settings.canExportTicketReport ||
                  data.settings.canExportComplaintReport ||
                  data.settings.canExportSuggestionReport)
                FilledButton.tonalIcon(
                  onPressed: _showCustomExportDialog,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('تصدير التقرير'),
                ),
              if (authUser?.role == 'admin')
                IconButton(
                  tooltip: 'تخصيص قوالب التقارير',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ReportTemplatesScreen(
                        initialReportType: 'tickets',
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.tune_rounded),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final ticketState = widget.closedOnly
        ? ref.watch(closedTicketsControllerProvider)
        : ref.watch(ticketsControllerProvider);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.surface,
            Theme.of(context).colorScheme.surfaceContainerLowest,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: ticketState.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Row(
              children: [
                Expanded(child: ShimmerSkeleton(height: 220, borderRadius: 24)),
                SizedBox(width: 12),
                ShimmerSkeleton(width: 180, height: 220, borderRadius: 24),
              ],
            ),
            SizedBox(height: 12),
            ShimmerSkeleton(height: 124, borderRadius: 20),
            SizedBox(height: 12),
            ShimmerSkeleton(height: 124, borderRadius: 20),
            SizedBox(height: 12),
            ShimmerSkeleton(height: 124, borderRadius: 20),
          ],
        ),
        error: (error, _) => _TicketsStateView(
          icon: Icons.error_outline_rounded,
          title: 'تعذر تحميل التذاكر',
          message: error.toString(),
        ),
        data: (data) {
          final tickets = _filteredTickets(data.tickets, authUser);

          return RefreshIndicator(
            onRefresh: () => widget.closedOnly
                ? ref.read(closedTicketsControllerProvider.notifier).refresh()
                : ref.read(ticketsControllerProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _buildToolbar(authUser, data),
                if (tickets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TicketsEmptyIllustration(
                      title: 'لا توجد عناصر مطابقة',
                      subtitle:
                          'جرّب تعديل البحث أو الفلاتر، أو أنشئ طلباً جديداً من الأعلى.',
                      icon: _activeTab.icon,
                      accent: _tabAccent(),
                    ),
                  )
                else
                  ...tickets.map(
                    (ticket) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: ModernTicketCard(
                        ticket: ticket,
                        dateFormat: formatEgyptDateTime,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TicketDetailsScreen(
                              ticketId: ticket.id,
                              initialTicket: ticket,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded || widget.isWrapped) return _buildContent();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text('مركز التذاكر'),
      ),
      body: _buildContent(),
    );
  }
}

class TicketDetailsScreen extends ConsumerStatefulWidget {
  const TicketDetailsScreen({
    super.key,
    required this.ticketId,
    this.initialTicket,
  });

  final String ticketId;
  final TicketItem? initialTicket;

  @override
  ConsumerState<TicketDetailsScreen> createState() =>
      _TicketDetailsScreenState();
}

class _TicketDetailsScreenState extends ConsumerState<TicketDetailsScreen> {
  final TextEditingController _messageController = TextEditingController();
  bool _internalNote = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _changeStatus(TicketDetailsData details) async {
    const statuses = [
      'open',
      'assigned',
      'in_progress',
      'waiting_branch',
      'resolved',
      'closed',
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: statuses
              .map(
                (status) => ListTile(
                  leading: _StatusDot(color: _statusColor(status)),
                  title: Text(_statusLabel(status)),
                  trailing: details.ticket.status == status
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, status),
                ),
              )
              .toList(),
        ),
      ),
    );

    if (selected == null || selected == details.ticket.status || !mounted) return;

    try {
      final detailsCtrl = ref.read(
        ticketDetailsControllerProvider(widget.ticketId).notifier,
      );
      final ticketsCtrl = ref.read(ticketsControllerProvider.notifier);
      await detailsCtrl.updateStatus(selected);
      await ticketsCtrl.refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: _TicketsUi.danger,
            content: Text('خطأ: $e'),
          ),
        );
      }
    }
  }

  Future<void> _assignTicket(TicketDetailsData details) async {
    var allUsers = <dynamic>[];
    try {
      allUsers = await ref.read(chatRepositoryProvider).fetchUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: _TicketsUi.danger,
            content: Text('خطأ في جلب المستخدمين: $e'),
          ),
        );
      }
      return;
    }

    final departmentId = details.ticket.targetDepartmentId;
    final branchId = details.ticket.branchDepartmentId;
    final departmentName = details.ticket.targetDepartmentName;
    List<TicketActor> departmentHandlers = [];
    if (departmentId != null && departmentId.isNotEmpty) {
      try {
        final handlerType = switch (details.ticket.ticketType) {
          'complaint' => 'complaint',
          'suggestion' => 'suggestion',
          _ => 'ticket',
        };
        departmentHandlers = await ref
            .read(ticketsControllerProvider.notifier)
            .fetchDepartmentHandlers(departmentId, handlerType: handlerType);
      } catch (_) {
        departmentHandlers = [];
      }
    }

    if (!mounted) return;

    final currentAssignedId = details.ticket.assignedTo?.id;
    String searchQuery = '';
    final List<dynamic> candidateUsers = [];
    final seenIds = <String>{};

    void addCandidate(dynamic user) {
      final id = (user as dynamic).id as String;
      if (seenIds.add(id)) {
        candidateUsers.add(user);
      }
    }

    if (departmentId != null && departmentId.isNotEmpty) {
      // Strictly use ONLY department handlers for department tickets/complaints/suggestions
      for (final handler in departmentHandlers) {
        addCandidate(handler);
      }
    } else {
      // Fallback for general tickets with no specific target department
      final usersInBranch = allUsers
          .where((user) => branchId != null && user.branchId == branchId)
          .toList();
      for (final user in usersInBranch) {
        addCandidate(user);
      }
      if (candidateUsers.isEmpty) {
        candidateUsers.addAll(allUsers);
      }
    }

    final selected = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final borderColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE2E8F0);
          final surfaceColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
          final fieldFillColor = isDark ? const Color(0xFF242428) : const Color(0xFFF8FAFC);
          final brandColor = const Color(0xFF2563EB);

          final useHandlers = departmentHandlers.isNotEmpty;
          final filteredCandidates = candidateUsers.where((candidate) {
            if (searchQuery.trim().isEmpty) return true;
            final query = searchQuery.trim().toLowerCase();
            final name = candidate is TicketActor
                ? candidate.displayName.toLowerCase()
                : (candidate as dynamic).displayName.toString().toLowerCase();
            final username = candidate is TicketActor
                ? candidate.username.toLowerCase()
                : (candidate as dynamic).username.toString().toLowerCase();
            return name.contains(query) || username.contains(query);
          }).toList();

          return Dialog(
            backgroundColor: surfaceColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: borderColor, width: 1),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 480,
                maxHeight: 580,
              ),
              child: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: brandColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(Icons.person_pin_circle_rounded, color: brandColor, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'تعيين مسؤول للتذكرة',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  departmentName != null && departmentName.isNotEmpty
                                      ? 'قسم التذكرة: $departmentName'
                                      : 'حدد الموظف الذي سيتولى معالجة هذه التذكرة',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => Navigator.pop(context, currentAssignedId),
                            style: IconButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Divider(height: 1, thickness: 1, color: borderColor),

                    // Search field
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'بحث باسم المستخدم أو الاسم...',
                          prefixIcon: Icon(Icons.search_rounded, size: 20, color: brandColor),
                          filled: true,
                          fillColor: fieldFillColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: brandColor, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        onChanged: (value) => setModalState(() {
                          searchQuery = value;
                        }),
                      ),
                    ),

                    // Candidates list
                    Expanded(
                      child: Scrollbar(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          children: [
                            // "بدون إسناد" tile
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: currentAssignedId == null
                                    ? brandColor.withValues(alpha: 0.08)
                                    : (isDark ? const Color(0xFF222226) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: currentAssignedId == null
                                      ? brandColor.withValues(alpha: 0.3)
                                      : borderColor,
                                ),
                              ),
                              child: ListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                leading: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF2E2E32) : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.person_off_outlined,
                                    size: 18,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                                title: const Text('بدون إسناد (إلغاء التعيين)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                                trailing: currentAssignedId == null
                                    ? Icon(Icons.check_circle_rounded, color: brandColor, size: 20)
                                    : null,
                                onTap: () => Navigator.pop(context, null),
                              ),
                            ),

                            if (departmentId != null && departmentId.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                child: Text(
                                  useHandlers ? 'مسؤولو هذا القسم المعينون:' : 'لا يوجد مسؤولو دعم مخصصين لهذا القسم',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ),

                            if (filteredCandidates.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Text(
                                    'لا توجد نتائج مطابقة لبحثك.',
                                    style: TextStyle(
                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )
                            else
                              ...filteredCandidates.map((candidate) {
                                final candidateData = candidate as dynamic;
                                final id = candidateData.id as String;
                                final name = candidateData.displayName as String;
                                final username = candidateData.username as String;
                                final isSelected = currentAssignedId == id;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? brandColor.withValues(alpha: 0.08)
                                        : (isDark ? const Color(0xFF222226) : const Color(0xFFF8FAFC)),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected
                                          ? brandColor.withValues(alpha: 0.3)
                                          : borderColor,
                                    ),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    leading: CircleAvatar(
                                      radius: 17,
                                      backgroundColor: brandColor.withValues(alpha: 0.15),
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: brandColor,
                                        ),
                                      ),
                                    ),
                                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                                    subtitle: Text('@' + username, style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                                    trailing: isSelected
                                        ? Icon(Icons.check_circle_rounded, color: brandColor, size: 20)
                                        : null,
                                    onTap: () => Navigator.pop(context, id),
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ),

                    Divider(height: 1, thickness: 1, color: borderColor),

                    // Close action
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context, currentAssignedId),
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('إلغاء'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (selected == currentAssignedId || !mounted) return;

    try {
      final detailsCtrl = ref.read(
        ticketDetailsControllerProvider(widget.ticketId).notifier,
      );
      final ticketsCtrl = ref.read(ticketsControllerProvider.notifier);
      await detailsCtrl.assignTo(selected);
      await ticketsCtrl.refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: _TicketsUi.danger,
          content: Text('خطأ في الإسناد: $error'),
        ),
      );
    }
  }

  Future<void> _sendComment(TicketDetailsData details) async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    try {
      await ref
          .read(ticketDetailsControllerProvider(widget.ticketId).notifier)
          .addComment(
            message,
            internalNote: _internalNote && details.canManage,
          );

      _messageController.clear();
      setState(() => _internalNote = false);
      await ref.read(ticketsControllerProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: _TicketsUi.danger,
            content: Text('خطأ: $e'),
          ),
        );
      }
    }
  }

  Widget _buildBottomInputArea(
    BuildContext context,
    TicketItem ticket,
    TicketDetailsData details,
    bool ticketClosed,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ticketClosed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C241D)
                    : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: Color(0xFFD97706),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'هذا الطلب مغلق حالياً، لا يمكن إرسال تحديثات أو ردود جديدة إلا بعد إعادة فتحه.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFFFDE68A)
                            : const Color(0xFFB45309),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            if (details.canManage)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => setState(() => _internalNote = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: !_internalNote
                              ? TicketsPalette.brand.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: !_internalNote
                                ? TicketsPalette.brand.withValues(alpha: 0.4)
                                : theme.colorScheme.outlineVariant.withValues(
                                    alpha: 0.3,
                                  ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 14,
                              color: !_internalNote
                                  ? TicketsPalette.brand
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'رد عام للعميل / الموظف',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: !_internalNote
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: !_internalNote
                                    ? TicketsPalette.brand
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => setState(() => _internalNote = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _internalNote
                              ? TicketsPalette.suggestion.withValues(alpha: 0.14)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _internalNote
                                ? TicketsPalette.suggestion
                                    .withValues(alpha: 0.45)
                                : theme.colorScheme.outlineVariant.withValues(
                                    alpha: 0.3,
                                  ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_rounded,
                              size: 14,
                              color: _internalNote
                                  ? TicketsPalette.suggestion
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'ملاحظة داخلية خاصة',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: _internalNote
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: _internalNote
                                    ? TicketsPalette.suggestion
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_internalNote)
                      Text(
                        '🔒 مرئية لفريق الدعم فقط',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: TicketsPalette.suggestion,
                        ),
                      ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFFF4F4F6),
                      borderRadius: BorderRadius.circular(16),
                      border: _internalNote
                          ? Border.all(
                              color: TicketsPalette.suggestion
                                  .withValues(alpha: 0.4),
                            )
                          : null,
                    ),
                    child: TextField(
                      controller: _messageController,
                      enabled: !ticketClosed,
                      minLines: 1,
                      maxLines: 5,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: _internalNote
                            ? 'اكتب ملاحظة داخلية خاصة بفريق العمل...'
                            : 'اكتب رداً أو تعليقاً على الطلب...',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        prefixIcon: Icon(
                          _internalNote
                              ? Icons.lock_outline_rounded
                              : Icons.edit_note_rounded,
                          color: _internalNote
                              ? TicketsPalette.suggestion
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _internalNote
                        ? TicketsPalette.suggestion
                        : TicketsPalette.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: ticketClosed ? null : () => _sendComment(details),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text(
                    'إرسال',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailsState = ref.watch(
      ticketDetailsControllerProvider(widget.ticketId),
    );
    final dateFormat = formatEgyptDateTime;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.initialTicket != null &&
                  widget.initialTicket!.ticketNumber.isNotEmpty
              ? 'طلب #${widget.initialTicket!.ticketNumber}'
              : 'تفاصيل الطلب',
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: () => ref
                .read(ticketDetailsControllerProvider(widget.ticketId).notifier)
                .refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: detailsState.when(
        loading: () {
          if (widget.initialTicket != null) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                TicketDetailsHeaderCard(
                  ticket: widget.initialTicket!,
                  dateFormat: dateFormat,
                  canManage: false,
                ),
                const SizedBox(height: 32),
                const Center(child: CircularProgressIndicator()),
              ],
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
        error: (error, _) => _TicketsStateView(
          icon: Icons.error_outline_rounded,
          title: 'تعذر تحميل التفاصيل',
          message: error.toString(),
        ),
        data: (details) {
          final displayTicket = widget.initialTicket != null
              ? widget.initialTicket!.mergeWith(details.ticket)
              : details.ticket;
          final viewData = TicketDetailsData(
            ticket: displayTicket,
            updates: details.updates,
            settings: details.settings,
            canManage: details.canManage,
          );
          final ticketClosed = displayTicket.status == 'closed';
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final accent = TicketsPalette.typeColor(displayTicket.ticketType);

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    TicketDetailsHeaderCard(
                      ticket: displayTicket,
                      dateFormat: dateFormat,
                      canManage: viewData.canManage,
                      onChangeStatus: viewData.canManage
                          ? () => _changeStatus(viewData)
                          : null,
                      onAssign: viewData.canManage
                          ? () => _assignTicket(viewData)
                          : null,
                    ),
                    const SizedBox(height: 24),
                    // Timeline Section Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.history_rounded,
                            size: 18,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'سجل التحديثات والنشاط',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF2C2C2E)
                                : const Color(0xFFE5E5EA),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${details.updates.length}',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'مرتب من الأقدم إلى الأحدث',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (details.updates.isEmpty)
                      const _TimelineEmptyView()
                    else
                      for (int i = 0; i < details.updates.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TicketTimelineTile(
                            label: _kindLabel(details.updates[i].kind),
                            message: _ticketUpdateDisplayMessage(
                              details.updates[i],
                            ),
                            actor: details.updates[i].createdBy.displayName,
                            visibilityLabel: _visibilityLabel(
                              details.updates[i].visibility,
                            ),
                            timestamp: dateFormat(
                              details.updates[i].createdAt,
                            ),
                            accent: _timelineAccent(details.updates[i]),
                            isInternal:
                                details.updates[i].visibility == 'internal',
                            isFirst: i == 0,
                            isLast: i == details.updates.length - 1,
                          ),
                        ),
                  ],
                ),
              ),
              _buildBottomInputArea(
                context,
                displayTicket,
                details,
                ticketClosed,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CreateTicketDialog extends ConsumerStatefulWidget {
  const _CreateTicketDialog({required this.ticketType});

  final TicketTypeTab ticketType;

  @override
  ConsumerState<_CreateTicketDialog> createState() =>
      _CreateTicketDialogState();
}

class _CreateTicketDialogState extends ConsumerState<_CreateTicketDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _priority = 'normal';
  bool _isSaving = false;
  bool _isLoadingDepartments = false;
  String? _selectedDepartmentId;
  List<Map<String, String>> _departments = [];
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    setState(() {
      _isLoadingDepartments = true;
      _errorText = null;
    });

    try {
      final departments = await ref
          .read(chatRepositoryProvider)
          .fetchDepartments();
      if (!mounted) return;
      setState(() {
        _departments = departments
            .map((dept) => {'id': dept.id, 'name': dept.name})
            .toList();
        _selectedDepartmentId = _departments.isNotEmpty
            ? _departments.first['id']
            : null;
        _isLoadingDepartments = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingDepartments = false;
        _errorText = error.toString();
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();

    if (title.length < 4 || description.length < 4) {
      setState(() {
        _errorText = 'العنوان والوصف مطلوبان، 4 أحرف على الأقل.';
      });
      return;
    }

    if (_selectedDepartmentId == null) {
      setState(() {
        _errorText = 'يجب اختيار القسم الموجه إليه الطلب.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      await ref
          .read(ticketsControllerProvider.notifier)
          .createTicket(
            title: title,
            description: description,
            priority: _priority,
            ticketType: widget.ticketType == TicketTypeTab.ticket
                ? 'ticket'
                : widget.ticketType == TicketTypeTab.complaint
                ? 'complaint'
                : 'suggestion',
            targetDepartmentId: _selectedDepartmentId,
          );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      setState(() {
        _isSaving = false;
        _errorText = error.toString();
      });
    }
  }

  Color get _themeColor => switch (widget.ticketType) {
    TicketTypeTab.ticket => const Color(0xFF2563EB),
    TicketTypeTab.complaint => const Color(0xFFEA580C),
    TicketTypeTab.suggestion => const Color(0xFF7C3AED),
  };

  IconData get _typeIcon => switch (widget.ticketType) {
    TicketTypeTab.ticket => Icons.support_agent_rounded,
    TicketTypeTab.complaint => Icons.report_problem_rounded,
    TicketTypeTab.suggestion => Icons.lightbulb_rounded,
  };

  String get _titleLabel => switch (widget.ticketType) {
    TicketTypeTab.ticket => 'إنشاء تذكرة دعم جديدة',
    TicketTypeTab.complaint => 'تقديم شكوى جديدة',
    TicketTypeTab.suggestion => 'تقديم مقترح جديد',
  };

  String get _subtitleLabel => switch (widget.ticketType) {
    TicketTypeTab.ticket => 'تواصل مع فريق الدعم الفني لحل مشكلة أو استفسار بنظام العمل',
    TicketTypeTab.complaint => 'أرسل شكواك إلى القسم المعني لمتابعتها وحلها بأسرع وقت',
    TicketTypeTab.suggestion => 'شاركنا أفكارك ومقترحاتك لتطوير بيئة العمل وتحسين الخدمات',
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogWidth = (MediaQuery.sizeOf(context).width - 48).clamp(320.0, 560.0);
    final dialogHeight = MediaQuery.sizeOf(context).height * 0.86;

    final borderColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE2E8F0);
    final surfaceColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final fieldFillColor = isDark ? const Color(0xFF242428) : const Color(0xFFF8FAFC);

    return Dialog(
      backgroundColor: surfaceColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
        ),
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _themeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(_typeIcon, color: _themeColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _titleLabel,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _subtitleLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'إغلاق',
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, thickness: 1, color: borderColor),

              // Form content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title
                      _buildFieldLabel('عنوان الطلب', isRequired: true),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _titleController,
                        enabled: !_isSaving,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: switch (widget.ticketType) {
                            TicketTypeTab.ticket => 'مثال: عطل في طابعة الفرع الرئيسي',
                            TicketTypeTab.complaint => 'مثال: تأخر في استلام البضائع الأسبوعية',
                            TicketTypeTab.suggestion => 'مثال: اقتراح نظام إلكتروني للأرشفة',
                          },
                          prefixIcon: Icon(Icons.title_rounded, color: _themeColor, size: 20),
                          filled: true,
                          fillColor: fieldFillColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: _themeColor, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Target Department
                      _buildFieldLabel('القسم الموجه إليه', isRequired: true),
                      const SizedBox(height: 6),
                      if (_isLoadingDepartments)
                        Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: fieldFillColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: const Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Text('جارٍ تحميل الأقسام...', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          value: _selectedDepartmentId,
                          isExpanded: true,
                          dropdownColor: surfaceColor,
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.apartment_rounded, color: _themeColor, size: 20),
                            filled: true,
                            fillColor: fieldFillColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: _themeColor, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          items: _departments
                              .map(
                                (dept) => DropdownMenuItem(
                                  value: dept['id'],
                                  child: Text(
                                    dept['name'] ?? '',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _isSaving
                              ? null
                              : (value) => setState(() {
                                  _selectedDepartmentId = value;
                                }),
                        ),

                      const SizedBox(height: 16),

                      // Priority
                      _buildFieldLabel('مستوى الأولوية'),
                      const SizedBox(height: 8),
                      _buildPrioritySelector(isDark),

                      const SizedBox(height: 16),

                      // Description
                      _buildFieldLabel('التفاصيل والوصف', isRequired: true),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _descriptionController,
                        enabled: !_isSaving,
                        minLines: 4,
                        maxLines: 7,
                        decoration: InputDecoration(
                          hintText: 'يرجى كتابة التفاصيل بوضوح لمساعدة الفريق المختص في المتابعة والإنجاز...',
                          alignLabelWithHint: true,
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(bottom: 50),
                            child: Icon(Icons.description_outlined, color: _themeColor, size: 20),
                          ),
                          filled: true,
                          fillColor: fieldFillColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: _themeColor, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                      ),

                      if (_errorText != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorText!,
                                  style: const TextStyle(
                                    color: Color(0xFFDC2626),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              Divider(height: 1, thickness: 1, color: borderColor),

              // Footer
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                      child: const Text('إلغاء', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _themeColor,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      icon: _isSaving
                          ? const ButtonLoadingIndicator(radius: 8)
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _isSaving ? 'جارٍ الإنشاء...' : 'إرسال الآن',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label, {bool isRequired = false}) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        if (isRequired) ...[
          const SizedBox(width: 4),
          const Text('*', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w800)),
        ],
      ],
    );
  }

  Widget _buildPrioritySelector(bool isDark) {
    final priorities = [
      {'key': 'low', 'label': 'منخفضة', 'color': const Color(0xFF0D9488), 'icon': Icons.arrow_downward_rounded},
      {'key': 'normal', 'label': 'عادية', 'color': const Color(0xFF2563EB), 'icon': Icons.remove_rounded},
      {'key': 'high', 'label': 'عالية', 'color': const Color(0xFFEA580C), 'icon': Icons.arrow_upward_rounded},
      {'key': 'critical', 'label': 'حرجة', 'color': const Color(0xFFDC2626), 'icon': Icons.warning_amber_rounded},
    ];

    return Row(
      children: priorities.map((prio) {
        final key = prio['key'] as String;
        final label = prio['label'] as String;
        final color = prio['color'] as Color;
        final icon = prio['icon'] as IconData;
        final isSelected = _priority == key;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              onTap: _isSaving ? null : () => setState(() => _priority = key),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.12)
                      : (isDark ? const Color(0xFF242428) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? color : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 15,
                      color: isSelected
                          ? color
                          : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected
                            ? color
                            : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SupportTeamDialog extends ConsumerStatefulWidget {
  const _SupportTeamDialog({required this.data});

  final dynamic data;

  @override
  ConsumerState<_SupportTeamDialog> createState() => _SupportTeamDialogState();
}

class _SupportTeamDialogState extends ConsumerState<_SupportTeamDialog> {
  late final Set<String> _selectedIds;
  late final Map<String, Set<String>> _exportPermissionsByUserId;
  bool _isSaving = false;
  bool _isLoadingDepartments = false;
  bool _isLoadingUsers = false;
  String? _selectedDepartmentId;
  List<DepartmentSummary> _departments = [];
  List<dynamic> _allUsers = [];
  String _searchText = '';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _searchText = '';
    _selectedIds = <String>{...widget.data.supportAgentIds};
    _exportPermissionsByUserId = {
      for (final user in widget.data.users as List<TicketSupportUser>)
        user.id: <String>{...user.exportTicketTypes},
    };
    _loadSupportTeamData();
  }

  Future<void> _loadSupportTeamData() async {
    setState(() {
      _isLoadingDepartments = true;
      _isLoadingUsers = true;
      _errorText = null;
    });

    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final departments = await chatRepo.fetchDepartments();
      final users = await chatRepo.fetchUsers();
      if (!mounted) return;
      setState(() {
        _departments = departments;
        _allUsers = users;
        _selectedDepartmentId = null; // Default to all departments
        _isLoadingDepartments = false;
        _isLoadingUsers = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingDepartments = false;
        _isLoadingUsers = false;
        _errorText = error.toString();
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      await ref
          .read(ticketsControllerProvider.notifier)
          .updateSupportAgents(
            _selectedIds.toList(),
            exportPermissionsByUserId: {
              for (final item in _exportPermissionsByUserId.entries)
                item.key: item.value.toList(),
            },
          );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      setState(() {
        _isSaving = false;
        _errorText = error.toString();
      });
    }
  }

  String _departmentName(String? id) {
    if (id == null || id.isEmpty) return 'بدون قسم';
    final dept = _departments.firstWhere(
      (department) => department.id == id,
      orElse: () => DepartmentSummary(
        id: id,
        name: id,
        code: '',
        description: '',
        managers: const [],
        membersCount: 0,
        defaultConversationId: null,
      ),
    );
    return dept.name.isNotEmpty ? dept.name : (dept.code.isNotEmpty ? dept.code : id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogWidth = (MediaQuery.sizeOf(context).width - 48).clamp(320.0, 640.0);
    final dialogHeight = MediaQuery.sizeOf(context).height * 0.88;

    final borderColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE2E8F0);
    final surfaceColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final fieldFillColor = isDark ? const Color(0xFF242428) : const Color(0xFFF8FAFC);
    final brandColor = const Color(0xFF2563EB);

    final users = _allUsers.isNotEmpty
        ? _allUsers
        : (widget.data.users as List<dynamic>);
    final query = _searchText.trim().toLowerCase();
    final filteredUsers = users.where((user) {
      final dynamic userData = user;
      if (_selectedDepartmentId != null && _selectedDepartmentId!.isNotEmpty) {
        if (userData.departmentId != _selectedDepartmentId) {
          return false;
        }
      }
      if (query.isEmpty) return true;
      final displayName = userData.displayName?.toString().toLowerCase() ?? '';
      final username = userData.username?.toString().toLowerCase() ?? '';
      return displayName.contains(query) || username.contains(query);
    }).toList();

    return Dialog(
      backgroundColor: surfaceColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
        ),
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: brandColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.admin_panel_settings_rounded, color: brandColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'إعداد فريق الدعم والصلاحيات',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'عيّن موظفي الدعم الفني وحدّد صلاحيات تصدير تذاكر وشكاوى ومقترحات النظام',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'إغلاق',
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, thickness: 1, color: borderColor),

              // Search & Filter Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Search bar
                        Expanded(
                          flex: 3,
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'بحث باسم المستخدم أو الاسم...',
                              prefixIcon: Icon(Icons.search_rounded, size: 20, color: brandColor),
                              suffixIcon: _searchText.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 18),
                                      onPressed: () => setState(() => _searchText = ''),
                                    )
                                  : null,
                              filled: true,
                              fillColor: fieldFillColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: brandColor, width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                            onChanged: (value) => setState(() => _searchText = value),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Department Filter Dropdown
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String?>(
                            value: _selectedDepartmentId,
                            isExpanded: true,
                            dropdownColor: surfaceColor,
                            decoration: InputDecoration(
                              prefixIcon: Icon(Icons.apartment_rounded, size: 20, color: brandColor),
                              filled: true,
                              fillColor: fieldFillColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: brandColor, width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('جميع الأقسام', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                              ..._departments.map(
                                (dept) => DropdownMenuItem<String?>(
                                  value: dept.id,
                                  child: Text(
                                    dept.name.isNotEmpty ? dept.name : dept.code,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: _isSaving
                                ? null
                                : (value) => setState(() {
                                    _selectedDepartmentId = value;
                                  }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Summary status capsule
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: brandColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, size: 14, color: brandColor),
                              const SizedBox(width: 5),
                              Text(
                                'تم تحديد ${_selectedIds.length} كأعضاء دعم فني',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: brandColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${filteredUsers.length} مستخدم',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Divider(height: 1, thickness: 1, color: borderColor),

              // Users List (Apple Inset Style)
              Expanded(
                child: _isLoadingDepartments || _isLoadingUsers
                    ? const Center(child: CircularProgressIndicator())
                    : filteredUsers.isEmpty
                    ? Center(
                        child: Text(
                          users.isEmpty ? 'لا يوجد مستخدمون بالنظام.' : 'لا توجد نتائج مطابقة لبحثك.',
                          style: TextStyle(
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            fontSize: 14,
                          ),
                        ),
                      )
                    : Scrollbar(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          itemCount: filteredUsers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final user = filteredUsers[index];
                            final isSelected = _selectedIds.contains(user.id);
                            final exportTypes = _exportPermissionsByUserId[user.id] ?? <String>{};

                            return Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? brandColor.withValues(alpha: 0.05)
                                    : (isDark ? const Color(0xFF222226) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? brandColor.withValues(alpha: 0.35)
                                      : borderColor,
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: _isSaving
                                        ? null
                                        : () {
                                            setState(() {
                                              if (isSelected) {
                                                _selectedIds.remove(user.id);
                                              } else {
                                                _selectedIds.add(user.id);
                                              }
                                            });
                                          },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      child: Row(
                                        children: [
                                          // Checkbox / toggle
                                          Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              color: isSelected ? brandColor : Colors.transparent,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isSelected ? brandColor : (isDark ? const Color(0xFF64748B) : const Color(0xFFCBD5E1)),
                                                width: 1.5,
                                              ),
                                            ),
                                            child: isSelected
                                                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                                                : null,
                                          ),
                                          const SizedBox(width: 12),
                                          // Avatar
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: brandColor.withValues(alpha: 0.15),
                                            child: Text(
                                              (user.displayName as String).isNotEmpty
                                                  ? (user.displayName as String)[0].toUpperCase()
                                                  : '?',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: brandColor,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Info
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      user.displayName,
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: isDark ? const Color(0xFF333338) : const Color(0xFFE2E8F0),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        _roleLabel(user.role),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w600,
                                                          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  '@${user.username} • ${_departmentName(user.departmentId)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Export permissions section
                                  if (isSelected) ...[
                                    Container(
                                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                                      decoration: BoxDecoration(
                                        color: brandColor.withValues(alpha: 0.04),
                                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.file_download_outlined, size: 16, color: brandColor),
                                          const SizedBox(width: 6),
                                          Text(
                                            'صلاحيات التصدير:',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: brandColor,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Wrap(
                                            spacing: 6,
                                            children: [
                                              _buildExportChip(
                                                label: 'تذاكر',
                                                type: 'ticket',
                                                types: exportTypes,
                                                userId: user.id,
                                                color: const Color(0xFF2563EB),
                                              ),
                                              _buildExportChip(
                                                label: 'شكاوى',
                                                type: 'complaint',
                                                types: exportTypes,
                                                userId: user.id,
                                                color: const Color(0xFFEA580C),
                                              ),
                                              _buildExportChip(
                                                label: 'مقترحات',
                                                type: 'suggestion',
                                                types: exportTypes,
                                                userId: user.id,
                                                color: const Color(0xFF7C3AED),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),

              if (_errorText != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    _errorText!,
                    style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],

              Divider(height: 1, thickness: 1, color: borderColor),

              // Actions Footer
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                      child: const Text('إلغاء', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: brandColor,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      icon: _isSaving
                          ? const ButtonLoadingIndicator(radius: 8)
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        _isSaving ? 'جارٍ الحفظ...' : 'حفظ التغييرات',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExportChip({
    required String label,
    required String type,
    required Set<String> types,
    required String userId,
    required Color color,
  }) {
    final isSelected = types.contains(type);

    return InkWell(
      onTap: _isSaving
          ? null
          : () {
              setState(() {
                if (isSelected) {
                  types.remove(type);
                } else {
                  types.add(type);
                }
                _exportPermissionsByUserId[userId] = types;
              });
            },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(Icons.check_rounded, size: 12, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : color.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentHandlersDialog extends ConsumerStatefulWidget {
  const _DepartmentHandlersDialog({required this.handlerType});

  final String handlerType;

  bool get isSuggestion => handlerType == 'suggestion';
  bool get isTicket => handlerType == 'ticket';

  String get dialogTitle => switch (handlerType) {
    'suggestion' => 'مسؤولو الرد على المقترحات',
    'ticket' => 'مسؤولو الرد على تذاكر الدعم',
    _ => 'مسؤولو الرد على الشكاوى',
  };

  String get dialogSubtitle => switch (handlerType) {
    'suggestion' => 'اختر القسم ثم حدّد الموظفين المسؤولين عن استلام والرد على مقترحات هذا القسم.',
    'ticket' => 'اختر القسم ثم حدّد الموظفين المسؤولين عن استلام والرد على تذاكر هذا القسم.',
    _ => 'اختر القسم ثم حدّد الموظفين المسؤولين عن استلام والرد على الشكاوى الموجهة لهذا القسم.',
  };

  Color get typeColor => switch (handlerType) {
    'suggestion' => const Color(0xFF7C3AED),
    'ticket' => const Color(0xFF2563EB),
    _ => const Color(0xFFEA580C),
  };

  IconData get typeIcon => switch (handlerType) {
    'suggestion' => Icons.lightbulb_rounded,
    'ticket' => Icons.support_agent_rounded,
    _ => Icons.report_problem_rounded,
  };

  @override
  ConsumerState<_DepartmentHandlersDialog> createState() =>
      _DepartmentHandlersDialogState();
}

class _DepartmentHandlersDialogState
    extends ConsumerState<_DepartmentHandlersDialog> {
  bool _isLoadingDepartments = false;
  bool _isLoadingHandlers = false;
  bool _isLoadingUsers = false;
  bool _isSaving = false;
  String? _selectedDepartmentId;
  String _searchText = '';
  List<dynamic> _departments = [];
  List<TicketSupportUser> _supportUsers = [];
  Map<String, List<Map<String, String>>> _handlerAssignmentsByUserId = {};
  Set<String> _selectedHandlerIds = {};
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _searchText = '';
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoadingDepartments = true;
      _isLoadingUsers = true;
      _errorText = null;
    });

    try {
      final departments = await ref
          .read(chatRepositoryProvider)
          .fetchDepartments();
      final supportData = await ref
          .read(ticketsControllerProvider.notifier)
          .fetchSupportUsers();
      final assignments = await ref
          .read(ticketsControllerProvider.notifier)
          .fetchDepartmentHandlerAssignments(handlerType: widget.handlerType);

      if (!mounted) return;
      setState(() {
        _departments = departments;
        _supportUsers = supportData.users;
        _handlerAssignmentsByUserId = assignments;
        _selectedDepartmentId = departments.isNotEmpty
            ? departments.first.id
            : null;
        _isLoadingDepartments = false;
        _isLoadingUsers = false;
      });

      if (_selectedDepartmentId != null) {
        await _loadHandlers(_selectedDepartmentId!);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingDepartments = false;
        _isLoadingUsers = false;
        _errorText = error.toString();
      });
    }
  }

  Future<void> _loadHandlers(String departmentId) async {
    setState(() {
      _isLoadingHandlers = true;
      _errorText = null;
      _selectedHandlerIds = {};
    });

    try {
      final handlers = await ref
          .read(ticketsControllerProvider.notifier)
          .fetchDepartmentHandlers(
            departmentId,
            handlerType: widget.handlerType,
          );
      if (!mounted) return;
      setState(() {
        _selectedHandlerIds = handlers.map((handler) => handler.id).toSet();
        _isLoadingHandlers = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingHandlers = false;
        _errorText = error.toString();
      });
    }
  }

  String _departmentName(String? id) {
    if (id == null || id.isEmpty) return 'بدون قسم';
    final dept = _departments.firstWhere(
      (department) => department.id == id,
      orElse: () => DepartmentSummary(
        id: id,
        name: id,
        code: '',
        description: '',
        managers: const [],
        membersCount: 0,
        defaultConversationId: null,
      ),
    );
    return dept.name.isNotEmpty ? dept.name : (dept.code.isNotEmpty ? dept.code : id);
  }

  Future<void> _saveHandlers() async {
    if (_selectedDepartmentId == null) {
      setState(() {
        _errorText = 'يجب اختيار القسم أولاً.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      await ref
          .read(ticketsControllerProvider.notifier)
          .updateDepartmentHandlers(
            _selectedDepartmentId!,
            _selectedHandlerIds.toList(),
            handlerType: widget.handlerType,
          );
      final assignments = await ref
          .read(ticketsControllerProvider.notifier)
          .fetchDepartmentHandlerAssignments(handlerType: widget.handlerType);
      if (!mounted) return;
      setState(() {
        _handlerAssignmentsByUserId = assignments;
      });
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogWidth = (MediaQuery.sizeOf(context).width - 48).clamp(320.0, 640.0);
    final dialogHeight = MediaQuery.sizeOf(context).height * 0.88;

    final borderColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE2E8F0);
    final surfaceColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final fieldFillColor = isDark ? const Color(0xFF242428) : const Color(0xFFF8FAFC);

    final query = _searchText.trim().toLowerCase();
    final filteredUsers = _supportUsers.where((user) {
      if (query.isEmpty) return true;
      return user.displayName.toLowerCase().contains(query) ||
          user.username.toLowerCase().contains(query);
    }).toList();
    final hasContent = !_isLoadingDepartments && !_isLoadingUsers;

    return Dialog(
      backgroundColor: surfaceColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
        ),
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.typeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(widget.typeIcon, color: widget.typeColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.dialogTitle,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.dialogSubtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'إغلاق',
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, thickness: 1, color: borderColor),

              // Department Selector Inset Card
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: fieldFillColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.apartment_rounded, size: 16, color: widget.typeColor),
                              const SizedBox(width: 6),
                              const Text(
                                'القسم المراد تعيين مسؤولي الرد له:',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: widget.typeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'تم تعيين ${_selectedHandlerIds.length} مسؤول',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: widget.typeColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _selectedDepartmentId,
                            isExpanded: true,
                            dropdownColor: surfaceColor,
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: surfaceColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: widget.typeColor, width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            items: _departments
                                .map(
                                  (dept) => DropdownMenuItem<String>(
                                    value: dept.id?.toString(),
                                    child: Text(
                                      dept.name?.toString() ?? '',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _isSaving
                                ? null
                                : (value) async {
                                    if (value == null) return;
                                    setState(() {
                                      _selectedDepartmentId = value;
                                    });
                                    await _loadHandlers(value);
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Search bar
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'بحث في قائمة الموظفين...',
                        prefixIcon: Icon(Icons.search_rounded, size: 20, color: widget.typeColor),
                        suffixIcon: _searchText.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () => setState(() => _searchText = ''),
                              )
                            : null,
                        filled: true,
                        fillColor: fieldFillColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: widget.typeColor, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onChanged: (value) => setState(() => _searchText = value),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, thickness: 1, color: borderColor),

              // Handlers List (Apple Inset Style)
              Expanded(
                child: !hasContent || _isLoadingHandlers
                    ? const Center(child: CircularProgressIndicator())
                    : filteredUsers.isEmpty
                    ? Center(
                        child: Text(
                          _supportUsers.isEmpty ? 'لا يوجد مستخدمون متاحون.' : 'لا توجد نتائج مطابقة لبحثك.',
                          style: TextStyle(
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            fontSize: 14,
                          ),
                        ),
                      )
                    : Scrollbar(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          itemCount: filteredUsers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final user = filteredUsers[index];
                            final isAssigned = _selectedHandlerIds.contains(user.id);

                            final otherDepartments =
                                (_handlerAssignmentsByUserId[user.id] ?? const [])
                                    .where(
                                      (entry) =>
                                          entry['departmentId'] != _selectedDepartmentId,
                                    )
                                    .map(
                                      (entry) => entry['departmentName'] ?? '',
                                    )
                                    .where((name) => name.isNotEmpty)
                                    .toList();

                            return Container(
                              decoration: BoxDecoration(
                                color: isAssigned
                                    ? widget.typeColor.withValues(alpha: 0.05)
                                    : (isDark ? const Color(0xFF222226) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isAssigned
                                      ? widget.typeColor.withValues(alpha: 0.35)
                                      : borderColor,
                                  width: 1,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: _isSaving
                                    ? null
                                    : () {
                                        setState(() {
                                          if (isAssigned) {
                                            _selectedHandlerIds.remove(user.id);
                                          } else {
                                            _selectedHandlerIds.add(user.id);
                                          }
                                        });
                                      },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          // Checkbox indicator
                                          Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              color: isAssigned ? widget.typeColor : Colors.transparent,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isAssigned
                                                    ? widget.typeColor
                                                    : (isDark ? const Color(0xFF64748B) : const Color(0xFFCBD5E1)),
                                                width: 1.5,
                                              ),
                                            ),
                                            child: isAssigned
                                                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                                                : null,
                                          ),
                                          const SizedBox(width: 12),
                                          // Avatar
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: widget.typeColor.withValues(alpha: 0.15),
                                            child: Text(
                                              user.displayName.isNotEmpty
                                                  ? user.displayName[0].toUpperCase()
                                                  : '?',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: widget.typeColor,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Info
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      user.displayName,
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: isDark ? const Color(0xFF333338) : const Color(0xFFE2E8F0),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        _roleLabel(user.role),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w600,
                                                          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  '@${user.username} • ${_departmentName(user.departmentId)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),

                                      // Other department assignments warning/info badge
                                      if (otherDepartments.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          margin: const EdgeInsetsDirectional.only(start: 34),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0xFF28282C) : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isDark ? const Color(0xFF38383E) : const Color(0xFFE2E8F0),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.push_pin_outlined,
                                                size: 13,
                                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                'مسؤول أيضاً في: ${otherDepartments.join('، ')}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),

              if (_errorText != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    _errorText!,
                    style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],

              Divider(height: 1, thickness: 1, color: borderColor),

              // Actions Footer
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                      child: const Text('إلغاء', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveHandlers,
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.typeColor,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      icon: _isSaving
                          ? const ButtonLoadingIndicator(radius: 8)
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        _isSaving ? 'جارٍ الحفظ...' : 'حفظ التعيينات',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketTag extends StatelessWidget {
  const _TicketTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(_TicketsUi.chipRadius),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.label,
    required this.message,
    required this.actor,
    required this.visibilityLabel,
    required this.timestamp,
    required this.accent,
    required this.isInternal,
  });

  final String label;
  final String message;
  final String actor;
  final String visibilityLabel;
  final String timestamp;
  final Color accent;
  final bool isInternal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TicketTag(label: label, color: accent),
                    _TicketTag(
                      label: visibilityLabel,
                      color: isInternal ? _TicketsUi.purple : _TicketsUi.brand,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(timestamp, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            actor,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.7),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _TicketsStateView extends StatelessWidget {
  const _TicketsStateView({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineEmptyView extends StatelessWidget {
  const _TimelineEmptyView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E20) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: TicketsPalette.brand.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 28,
                color: TicketsPalette.brand,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'لا توجد تحديثات حتى الآن',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'لم يتم تسجيل أي ردود أو تغييرات في حالة هذا الطلب بعد.\nيمكنك كتابة أول تعليق أو ملاحظة باستخدام النموذج بالأسفل.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
  'open' => 'مفتوحة',
  'assigned' => 'مسندة',
  'in_progress' => 'قيد التنفيذ',
  'waiting_branch' => 'بانتظار الفرع',
  'resolved' => 'تم الحل',
  'closed' => 'مغلقة',
  _ => status,
};

String _priorityLabel(String priority) => switch (priority) {
  'low' => 'منخفضة',
  'normal' => 'عادية',
  'high' => 'عالية',
  'critical' => 'حرجة',
  _ => priority,
};

String _kindLabel(String kind) => switch (kind) {
  'comment' => 'تعليق',
  'status_changed' => 'تم تغيير الحالة',
  'assignment_changed' => 'تم تغيير المسؤول',
  'status' => 'تحديث حالة',
  'assignment' => 'تغيير الإسناد',
  'note' => 'ملاحظة داخلية',
  'created' => 'تم إنشاء التذكرة',
  _ => kind,
};

Color _statusColor(String status) => switch (status) {
  'open' => const Color(0xFF2563EB),
  'assigned' => const Color(0xFF7C3AED),
  'in_progress' => const Color(0xFF0F766E),
  'waiting_branch' => const Color(0xFFD97706),
  'resolved' => _TicketsUi.success,
  'closed' => const Color(0xFF64748B),
  _ => const Color(0xFF475569),
};

Color _priorityColor(String priority) => switch (priority) {
  'low' => const Color(0xFF0EA5E9),
  'normal' => const Color(0xFF2563EB),
  'high' => _TicketsUi.warning,
  'critical' => _TicketsUi.danger,
  _ => const Color(0xFF334155),
};

String _visibilityLabel(String visibility) => switch (visibility) {
  'internal' => 'ملاحظة داخلية',
  _ => 'رسالة عامة',
};

String _roleLabel(String role) => switch (role) {
  'admin' => 'مدير النظام',
  'manager' => 'مدير',
  'support' => 'دعم فني',
  'user' => 'موظف',
  _ => role,
};

Color _timelineAccent(TicketUpdateItem update) => switch (update.kind) {
  'created' => _TicketsUi.brand,
  'comment' => const Color(0xFF0EA5E9),
  'note' => _TicketsUi.purple,
  'status' => _statusColor(update.toStatus ?? update.fromStatus ?? 'open'),
  'status_changed' => _statusColor(update.toStatus ?? 'open'),
  'assignment' => _TicketsUi.purple,
  'assignment_changed' => _TicketsUi.purple,
  _ => update.visibility == 'internal' ? _TicketsUi.purple : _TicketsUi.brand,
};

String _ticketUpdateDisplayMessage(TicketUpdateItem update) {
  final rawMessage = update.message.trim();

  switch (update.kind) {
    case 'created':
      return rawMessage.isEmpty
          ? 'تم إنشاء التذكرة وفتحها للمراجعة.'
          : rawMessage;

    case 'comment':
      return rawMessage.isEmpty
          ? 'تمت إضافة تعليق جديد على التذكرة.'
          : rawMessage;

    case 'note':
      return rawMessage.isEmpty ? 'تمت إضافة ملاحظة داخلية.' : rawMessage;

    case 'status':
    case 'status_changed':
      final fromLabel = update.fromStatus == null
          ? null
          : _statusLabel(update.fromStatus!);
      final toLabel = update.toStatus == null
          ? null
          : _statusLabel(update.toStatus!);

      if (fromLabel != null && toLabel != null) {
        return 'تم تغيير حالة التذكرة من "$fromLabel" إلى "$toLabel".';
      }

      if (toLabel != null) {
        return 'تم تحديث حالة التذكرة إلى "$toLabel".';
      }

      return rawMessage.isEmpty ? 'تم تحديث حالة التذكرة.' : rawMessage;

    case 'assignment':
    case 'assignment_changed':
      if (update.toAssigneeName != null &&
          update.toAssigneeName!.trim().isNotEmpty) {
        return 'تم إسناد التذكرة إلى ${update.toAssigneeName!}.';
      }
      return 'تم إلغاء إسناد التذكرة.';

    default:
      return rawMessage.isEmpty ? _kindLabel(update.kind) : rawMessage;
  }
}
