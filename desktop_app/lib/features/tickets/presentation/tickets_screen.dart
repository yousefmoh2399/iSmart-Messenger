import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/button_loading_indicator.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../chat/models/chat_models.dart';
import '../models/ticket_models.dart';
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
    this.onTabChanged,
  });

  final bool embedded;
  final bool isWrapped;
  final TicketTypeTab initialTab;
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
  }

  @override
  void didUpdateWidget(covariant TicketsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() {
        _activeTab = widget.initialTab;
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

  Future<void> _exportTicketsReport() async {
    try {
      final status = switch (_activeFilter) {
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
          );
      if (!mounted) return;
      _showMessage('تم تصدير تقرير التذاكر.');
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString(), isError: true);
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
                for (final filter in TicketFilter.values)
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
                TextButton.icon(
                  onPressed: _exportTicketsReport,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('تصدير'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final ticketState = ref.watch(ticketsControllerProvider);

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
            onRefresh: () =>
                ref.read(ticketsControllerProvider.notifier).refresh(),
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

    if (selected == null || selected == details.ticket.status) return;

    try {
      await ref
          .read(ticketDetailsControllerProvider(widget.ticketId).notifier)
          .updateStatus(selected);
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

    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
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

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (departmentId != null && departmentId.isNotEmpty) ...[
                        Text(
                          'قسم التذكرة: ${departmentName ?? 'غير محدد'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                      ],
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'بحث باسم المستخدم أو الاسم',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: (value) => setModalState(() {
                          searchQuery = value;
                        }),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_off_outlined),
                        title: const Text('بدون إسناد'),
                        trailing: currentAssignedId == null
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.pop(context, null),
                      ),
                      if (departmentId != null &&
                          departmentId.isNotEmpty &&
                          useHandlers)
                        const ListTile(title: Text('مسؤولو هذا القسم')),
                      if (departmentId != null &&
                          departmentId.isNotEmpty &&
                          !useHandlers)
                        const ListTile(
                          title: Text('لا يوجد مسؤولي دعم مخصصين لهذا القسم.'),
                        ),
                      if ((departmentId == null || departmentId.isEmpty) &&
                          branchId != null &&
                          branchId.isNotEmpty)
                        const ListTile(
                          title: Text('المستخدمون داخل الفرع المختار'),
                        ),
                      if (filteredCandidates.isEmpty)
                        const ListTile(title: Text('لا توجد نتائج.'))
                      else
                        ...filteredCandidates.map((candidate) {
                          final candidateData = candidate as dynamic;
                          final id = candidateData.id as String;
                          final name = candidateData.displayName as String;
                          final username = candidateData.username as String;
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_outline_rounded),
                            ),
                            title: Text(name),
                            subtitle: Text(username),
                            trailing: currentAssignedId == id
                                ? const Icon(Icons.check_rounded)
                                : null,
                            onTap: () => Navigator.pop(context, id),
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (selected == currentAssignedId) return;

    try {
      await ref
          .read(ticketDetailsControllerProvider(widget.ticketId).notifier)
          .assignTo(selected);
      await ref.read(ticketsControllerProvider.notifier).refresh();
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

  @override
  Widget build(BuildContext context) {
    final detailsState = ref.watch(
      ticketDetailsControllerProvider(widget.ticketId),
    );
    final dateFormat = formatEgyptDateTime;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل التذكرة'),
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
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: TicketDetailsHeaderCard(
                    ticket: widget.initialTicket!,
                    dateFormat: dateFormat,
                    canManage: false,
                  ),
                ),
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                ),
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

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: TicketDetailsHeaderCard(
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
              ),
              Expanded(
                child: details.updates.isEmpty
                    ? const _TimelineEmptyView()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        itemCount: details.updates.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final update = details.updates[index];
                          return TicketTimelineTile(
                            label: _kindLabel(update.kind),
                            message: _ticketUpdateDisplayMessage(update),
                            actor: update.createdBy.displayName,
                            visibilityLabel: _visibilityLabel(
                              update.visibility,
                            ),
                            timestamp: dateFormat(update.createdAt),
                            accent: _timelineAccent(update),
                            isInternal: update.visibility == 'internal',
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    if (ticketClosed)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          // color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: const Text(
                          'التذكرة مغلقة، لا يمكن إرسال تحديثات جديدة.',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    if (details.canManage)
                      Align(
                        alignment: Alignment.centerRight,
                        child: SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _internalNote,
                          onChanged: ticketClosed
                              ? null
                              : (value) =>
                                    setState(() => _internalNote = value),

                          title: const Text('إرسال ملاحظة داخلية'),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            enabled: !ticketClosed,
                            minLines: 1,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              hintText: 'اكتب تحديثًا واضحًا للتذكرة...',
                              prefixIcon: Icon(Icons.edit_note_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: ticketClosed
                              ? null
                              : () => _sendComment(details),
                          icon: const Icon(Icons.send_rounded),
                          label: const Text('إرسال'),
                        ),
                      ],
                    ),
                  ],
                ),
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

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.sizeOf(context).width - 48).clamp(
      320.0,
      _TicketsUi.dialogWidth,
    );
    final dialogHeight = MediaQuery.sizeOf(context).height * 0.8;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(switch (widget.ticketType) {
        TicketTypeTab.ticket => 'إنشاء تذكرة جديدة',
        TicketTypeTab.complaint => 'تقديم شكوى جديدة',
        TicketTypeTab.suggestion => 'تقديم مقترح جديد',
      }),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth.toDouble(),
          maxHeight: dialogHeight,
        ),
        child: SizedBox(
          width: dialogWidth.toDouble(),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _titleController,
                  enabled: !_isSaving,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'العنوان',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  enabled: !_isSaving,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'وصف المشكلة',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                _isLoadingDepartments
                    ? const Center(child: CircularProgressIndicator())
                    : DropdownButtonFormField<String>(
                        value: _selectedDepartmentId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'قسم الدعم',
                          prefixIcon: Icon(Icons.account_tree_outlined),
                        ),
                        items: _departments
                            .map(
                              (dept) => DropdownMenuItem(
                                value: dept['id'],
                                child: Text(dept['name'] ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: _isSaving
                            ? null
                            : (value) => setState(() {
                                _selectedDepartmentId = value;
                              }),
                      ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _priority,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'الأولوية',
                    prefixIcon: Icon(Icons.low_priority_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('منخفضة')),
                    DropdownMenuItem(value: 'normal', child: Text('عادية')),
                    DropdownMenuItem(value: 'high', child: Text('عالية')),
                    DropdownMenuItem(value: 'critical', child: Text('حرجة')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) =>
                            setState(() => _priority = value ?? _priority),
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _errorText!,
                      style: const TextStyle(color: _TicketsUi.danger),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _submit,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: ButtonLoadingIndicator(),
                )
              : const Icon(Icons.add_task_rounded),
          label: Text(_isSaving ? 'جارٍ الإنشاء...' : 'إنشاء'),
        ),
      ],
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
  String? _searchText;
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
      final departments = await ref
          .read(chatRepositoryProvider)
          .fetchDepartments();
      final users = await ref.read(chatRepositoryProvider).fetchUsers();
      if (!mounted) return;
      setState(() {
        _departments = departments;
        _allUsers = users;
        _selectedDepartmentId = departments.isNotEmpty
            ? departments.first.id
            : null;
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

  @override
  Widget build(BuildContext context) {
    final users = _allUsers.isNotEmpty
        ? _allUsers
        : (widget.data.users as List<dynamic>);
    final query = _searchText?.trim().toLowerCase() ?? '';
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

    String departmentName(String? id) {
      final dept = _departments.firstWhere(
        (department) => department.id == id,
        orElse: () => DepartmentSummary(
          id: id ?? '',
          name: id ?? 'بدون قسم',
          code: '',
          description: '',
          managers: const [],
          membersCount: 0,
          defaultConversationId: null,
        ),
      );
      return dept.name;
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: const Text('إعداد فريق الدعم'),
      content: SizedBox(
        width: _TicketsUi.dialogWidth,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isLoadingDepartments || _isLoadingUsers)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              DropdownButtonFormField<String?>(
                value: _selectedDepartmentId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'القسم',
                  prefixIcon: Icon(Icons.account_tree_outlined),
                ),
                items: _departments
                    .map(
                      (dept) => DropdownMenuItem<String?>(
                        value: dept.id,
                        child: Text(
                          dept.name.isNotEmpty ? dept.name : dept.code,
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
              TextField(
                decoration: const InputDecoration(
                  hintText: 'بحث في المستخدمين',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _searchText = value),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: filteredUsers.isEmpty
                    ? Center(
                        child: Text(
                          users.isEmpty
                              ? 'لا يوجد مستخدمين بعد.'
                              : 'لا توجد نتائج مطابقة.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      )
                    : Scrollbar(
                        child: ListView.separated(
                          itemCount: filteredUsers.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final user = filteredUsers[index];
                            final exportTypes =
                                _exportPermissionsByUserId[user.id] ??
                                <String>{};
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 4,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  CheckboxListTile(
                                    value: _selectedIds.contains(user.id),
                                    title: Text(user.displayName),
                                    subtitle: Text(
                                      '${user.username} • ${_roleLabel(user.role)} • ${departmentName(user.departmentId)}',
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    onChanged: _isSaving
                                        ? null
                                        : (value) {
                                            setState(() {
                                              if (value == true) {
                                                _selectedIds.add(user.id);
                                              } else {
                                                _selectedIds.remove(user.id);
                                              }
                                            });
                                          },
                                  ),
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      start: 16,
                                      end: 16,
                                      bottom: 8,
                                    ),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        FilterChip(
                                          label: const Text('تذاكر'),
                                          selected: exportTypes.contains(
                                            'ticket',
                                          ),
                                          onSelected: _isSaving
                                              ? null
                                              : (selected) {
                                                  setState(() {
                                                    if (selected) {
                                                      exportTypes.add('ticket');
                                                    } else {
                                                      exportTypes.remove(
                                                        'ticket',
                                                      );
                                                    }
                                                    _exportPermissionsByUserId[user
                                                            .id] =
                                                        exportTypes;
                                                  });
                                                },
                                        ),
                                        FilterChip(
                                          label: const Text('شكاوى'),
                                          selected: exportTypes.contains(
                                            'complaint',
                                          ),
                                          onSelected: _isSaving
                                              ? null
                                              : (selected) {
                                                  setState(() {
                                                    if (selected) {
                                                      exportTypes.add(
                                                        'complaint',
                                                      );
                                                    } else {
                                                      exportTypes.remove(
                                                        'complaint',
                                                      );
                                                    }
                                                    _exportPermissionsByUserId[user
                                                            .id] =
                                                        exportTypes;
                                                  });
                                                },
                                        ),
                                        FilterChip(
                                          label: const Text('مقترحات'),
                                          selected: exportTypes.contains(
                                            'suggestion',
                                          ),
                                          onSelected: _isSaving
                                              ? null
                                              : (selected) {
                                                  setState(() {
                                                    if (selected) {
                                                      exportTypes.add(
                                                        'suggestion',
                                                      );
                                                    } else {
                                                      exportTypes.remove(
                                                        'suggestion',
                                                      );
                                                    }
                                                    _exportPermissionsByUserId[user
                                                            .id] =
                                                        exportTypes;
                                                  });
                                                },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: const TextStyle(color: _TicketsUi.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? 'جارٍ الحفظ...' : 'حفظ'),
        ),
      ],
    );
  }
}

class _DepartmentHandlersDialog extends ConsumerStatefulWidget {
  const _DepartmentHandlersDialog({required this.handlerType});

  final String handlerType;

  bool get isSuggestion => handlerType == 'suggestion';
  bool get isTicket => handlerType == 'ticket';

  String get dialogTitle => switch (handlerType) {
    'suggestion' => 'مسؤولو المقترحات حسب القسم',
    'ticket' => 'مسؤولو التذاكر حسب القسم',
    _ => 'مسؤولو الشكاوى حسب القسم',
  };

  String get dialogSubtitle => switch (handlerType) {
    'suggestion' => 'اختر القسم ثم حدّد من يدير المقترحات المرسلة إليه.',
    'ticket' => 'اختر القسم ثم حدّد من يدير التذاكر المرسلة إليه (غير قسم IT).',
    _ => 'اختر القسم ثم حدّد من يدير الشكاوى المرسلة إليه.',
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
  String? _searchText;
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
    final dept = _departments.firstWhere(
      (department) => department.id == id,
      orElse: () => DepartmentSummary(
        id: id ?? '',
        name: id ?? 'بدون قسم',
        code: '',
        description: '',
        managers: const [],
        membersCount: 0,
        defaultConversationId: null,
      ),
    );
    return dept.name;
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
    final query = _searchText?.trim().toLowerCase() ?? '';
    final filteredUsers = _supportUsers.where((user) {
      if (query.isEmpty) return true;
      return user.displayName.toLowerCase().contains(query) ||
          user.username.toLowerCase().contains(query);
    }).toList();
    final hasContent = !_isLoadingDepartments && !_isLoadingUsers;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(widget.dialogTitle),
      content: SizedBox(
        width: _TicketsUi.dialogWidth,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hasContent)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              Text(
                widget.dialogSubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedDepartmentId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'القسم',
                  prefixIcon: Icon(Icons.account_tree_outlined),
                ),
                items: _departments
                    .map(
                      (department) => DropdownMenuItem<String>(
                        value: department.id?.toString(),
                        child: Text(department.name?.toString() ?? ''),
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
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'بحث في المستخدمين',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _searchText = value),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoadingHandlers
                    ? const Center(child: CircularProgressIndicator())
                    : filteredUsers.isEmpty
                    ? const Center(child: Text('لا يوجد مستخدمين بعد.'))
                    : Scrollbar(
                        child: ListView.separated(
                          itemCount: filteredUsers.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final user = filteredUsers[index];
                            final otherDepartments =
                                (_handlerAssignmentsByUserId[user.id] ??
                                        const [])
                                    .where(
                                      (entry) =>
                                          entry['departmentId'] !=
                                          _selectedDepartmentId,
                                    )
                                    .map(
                                      (entry) => entry['departmentName'] ?? '',
                                    )
                                    .where((name) => name.isNotEmpty)
                                    .toList();
                            final extraDepartmentsLabel =
                                otherDepartments.isEmpty
                                ? ''
                                : '\nمسؤول أيضاً في: ${otherDepartments.join('، ')}';
                            return CheckboxListTile(
                              value: _selectedHandlerIds.contains(user.id),
                              title: Text(user.displayName),
                              subtitle: Text(
                                '${user.username} • ${user.role} • ${_departmentName(user.departmentId)}$extraDepartmentsLabel',
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: _isSaving
                                  ? null
                                  : (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedHandlerIds.add(user.id);
                                        } else {
                                          _selectedHandlerIds.remove(user.id);
                                        }
                                      });
                                    },
                            );
                          },
                        ),
                      ),
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: const TextStyle(color: _TicketsUi.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _saveHandlers,
          child: Text(_isSaving ? 'جارٍ الحفظ...' : 'حفظ'),
        ),
      ],
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.timeline_rounded,
                size: 38,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'لا توجد تذاكر مطابقة',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'جرّب تعديل البحث أو الفلاتر، أو أنشئ تذكرة جديدة من الأعلى.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.6,
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
