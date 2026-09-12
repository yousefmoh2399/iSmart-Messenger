import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/button_loading_indicator.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../models/ticket_models.dart';
import 'tickets_ui_kit.dart';

typedef _TicketDateFormatter = String Function(DateTime value);

class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

enum TicketTab { tickets, complaints, suggestions }

extension TicketTabLabel on TicketTab {
  String get label => switch (this) {
    TicketTab.tickets => 'تذاكر الدعم',
    TicketTab.complaints => 'الشكاوى',
    TicketTab.suggestions => 'المقترحات',
  };
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  final _searchController = TextEditingController();
  TicketTab _activeTab = TicketTab.tickets;

  double _dialogWidth(BuildContext context, double preferredWidth) {
    final availableWidth = MediaQuery.sizeOf(context).width - 32;
    return math.max(280, math.min(preferredWidth, availableWidth));
  }

  double _dialogMaxHeight(BuildContext context) {
    return MediaQuery.sizeOf(context).height * 0.78;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showCreateTicketDialog() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String priority = 'normal';
    String? selectedDepartmentId;
    List<dynamic> departments = [];
    var isSaving = false;
    String? errorText;

    try {
      final dio = ref.read(authenticatedApiClientProvider).dio;
      final res = await dio.get('/api/departments');
      departments =
          (res.data['departments'] as List<dynamic>?) ??
          ((res.data['data'] as Map<String, dynamic>?)?['departments']
              as List<dynamic>?) ??
          const <dynamic>[];
      if (departments.isNotEmpty) {
        selectedDepartmentId =
            departments.first['id']?.toString() ??
            departments.first['_id']?.toString();
      }
    } catch (e) {
      errorText = e.toString();
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          final dialogWidth = _dialogWidth(context, 440);
          final dialogHeight = _dialogMaxHeight(context);

          final titleLabel = switch (_activeTab) {
            TicketTab.tickets => 'إنشاء تذكرة جديدة',
            TicketTab.complaints => 'تقديم شكوى جديدة',
            TicketTab.suggestions => 'تقديم مقترح جديد',
          };

          return AlertDialog(
            title: Text(titleLabel),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: dialogWidth,
                maxHeight: dialogHeight,
              ),
              child: SizedBox(
                width: dialogWidth,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        enabled: !isSaving,
                        decoration: const InputDecoration(labelText: 'العنوان'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        enabled: !isSaving,
                        minLines: 4,
                        maxLines: 8,
                        decoration: InputDecoration(
                          labelText: _activeTab == TicketTab.tickets
                              ? 'وصف المشكلة'
                              : 'التفاصيل',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedDepartmentId,
                        isExpanded: true,
                        items: departments.map((dept) {
                          final id =
                              dept['id']?.toString() ??
                              dept['_id']?.toString() ??
                              '';
                          final name =
                              dept['name']?.toString() ?? 'قسم غير معروف';
                          return DropdownMenuItem(value: id, child: Text(name));
                        }).toList(),
                        onChanged: isSaving
                            ? null
                            : (value) => setLocalState(
                                () => selectedDepartmentId = value,
                              ),
                        decoration: const InputDecoration(
                          labelText: 'القسم الموجه إليه',
                          prefixIcon: Icon(Icons.account_tree_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_activeTab == TicketTab.tickets)
                        DropdownButtonFormField<String>(
                          initialValue: priority,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'low',
                              child: Text('منخفضة'),
                            ),
                            DropdownMenuItem(
                              value: 'normal',
                              child: Text('عادية'),
                            ),
                            DropdownMenuItem(
                              value: 'high',
                              child: Text('عالية'),
                            ),
                            DropdownMenuItem(
                              value: 'critical',
                              child: Text('حرجة'),
                            ),
                          ],
                          onChanged: isSaving
                              ? null
                              : (value) => setLocalState(
                                  () => priority = value ?? priority,
                                ),
                          decoration: const InputDecoration(
                            labelText: 'الأولوية',
                          ),
                        ),
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText!,
                          style: const TextStyle(color: Color(0xFFB91C1C)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final title = titleController.text.trim();
                        final description = descriptionController.text.trim();
                        if (title.length < 4 || description.length < 4) {
                          setLocalState(() {
                            errorText =
                                'العنوان والوصف مطلوبان (4 أحرف على الأقل).';
                          });
                          return;
                        }
                        if (selectedDepartmentId == null) {
                          setLocalState(() {
                            errorText = 'يجب اختيار القسم الموجه إليه الطلب.';
                          });
                          return;
                        }

                        setLocalState(() {
                          isSaving = true;
                          errorText = null;
                        });
                        try {
                          final ticketType = switch (_activeTab) {
                            TicketTab.tickets => 'ticket',
                            TicketTab.complaints => 'complaint',
                            TicketTab.suggestions => 'suggestion',
                          };

                          await ref
                              .read(ticketsControllerProvider.notifier)
                              .createTicket(
                                title: title,
                                description: description,
                                priority: priority,
                                ticketType: ticketType,
                                targetDepartmentId: selectedDepartmentId,
                              );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        } catch (error) {
                          setLocalState(() {
                            isSaving = false;
                            errorText = error.toString();
                          });
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: ButtonLoadingIndicator(),
                      )
                    : const Text('إنشاء'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showSupportTeamDialog() async {
    final authUser = ref.read(authControllerProvider).valueOrNull;
    if (authUser?.role != 'admin') {
      return;
    }

    try {
      final data = await ref
          .read(ticketsControllerProvider.notifier)
          .fetchSupportUsers();
      final selectedIds = <String>{...data.supportAgentIds};
      var isSaving = false;
      String? errorText;

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocalState) {
            final dialogWidth = _dialogWidth(context, 520);
            return AlertDialog(
              title: const Text('إعداد فريق IT'),
              content: SizedBox(
                width: dialogWidth,
                height: 500,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: data.users.length,
                        itemBuilder: (context, index) {
                          final user = data.users[index];
                          return CheckboxListTile(
                            value: selectedIds.contains(user.id),
                            title: Text(user.displayName),
                            subtitle: Text('${user.username} • ${user.role}'),
                            onChanged: isSaving
                                ? null
                                : (value) {
                                    setLocalState(() {
                                      if (value == true) {
                                        selectedIds.add(user.id);
                                      } else {
                                        selectedIds.remove(user.id);
                                      }
                                    });
                                  },
                          );
                        },
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: const TextStyle(color: Color(0xFFB91C1C)),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setLocalState(() {
                            isSaving = true;
                            errorText = null;
                          });
                          try {
                            await ref
                                .read(ticketsControllerProvider.notifier)
                                .updateSupportAgents(selectedIds.toList());
                            if (!context.mounted) return;
                            Navigator.pop(context);
                          } catch (error) {
                            setLocalState(() {
                              isSaving = false;
                              errorText = error.toString();
                            });
                          }
                        },
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _departmentHandlerTypeForTab() => switch (_activeTab) {
    TicketTab.complaints => 'complaint',
    TicketTab.suggestions => 'suggestion',
    TicketTab.tickets => 'ticket',
  };

  Future<void> _showDepartmentHandlersDialog() async {
    final authUser = ref.read(authControllerProvider).valueOrNull;
    if (authUser?.role != 'admin') return;

    await showDialog<void>(
      context: context,
      builder: (_) => _DepartmentHandlersDialog(
        handlerType: _departmentHandlerTypeForTab(),
      ),
    );
  }

  List<TicketItem> _filteredTickets(List<TicketItem> tickets) {
    final query = _searchController.text.trim().toLowerCase();

    final typeFiltered = tickets.where((t) {
      final type = t.ticketType;
      return switch (_activeTab) {
        TicketTab.tickets => type == 'ticket',
        TicketTab.complaints => type == 'complaint',
        TicketTab.suggestions => type == 'suggestion',
      };
    }).toList();

    if (query.isEmpty) {
      return typeFiltered;
    }
    return typeFiltered.where((ticket) {
      return ticket.ticketNumber.toLowerCase().contains(query) ||
          ticket.title.toLowerCase().contains(query) ||
          ticket.description.toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildContent() {
    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final ticketState = ref.watch(ticketsControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ticketState.when(
      loading: () => CustomScrollView(
        slivers: [
          if (!widget.embedded)
            SliverAppBar(
              pinned: true,
              title: const Text('جاري التحميل...'),
              backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
              surfaceTintColor: Colors.transparent,
            ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  ShimmerSkeleton(height: 136, borderRadius: 24),
                  SizedBox(height: 10),
                  ShimmerSkeleton(height: 56, borderRadius: 16),
                  SizedBox(height: 10),
                  ShimmerSkeleton(height: 132, borderRadius: 20),
                  SizedBox(height: 10),
                  ShimmerSkeleton(height: 132, borderRadius: 20),
                ],
              ),
            ),
          ),
        ],
      ),
      error: (error, _) => Center(child: Text(error.toString())),
      data: (data) {
        final tabTickets = data.tickets.where((ticket) {
          final type = ticket.ticketType;
          return switch (_activeTab) {
            TicketTab.tickets => type == 'ticket',
            TicketTab.complaints => type == 'complaint',
            TicketTab.suggestions => type == 'suggestion',
          };
        }).toList();

        final tickets = _filteredTickets(data.tickets);
        final dateFormat = formatEgyptDateTime;
        final openTickets = tabTickets
            .where((ticket) => ticket.status != 'closed')
            .length;
        final myAssignedTickets = authUser == null
            ? 0
            : tabTickets
                  .where((ticket) => ticket.assignedTo?.id == authUser.id)
                  .length;

        final searchHint = switch (_activeTab) {
          TicketTab.tickets => 'ابحث في التذاكر',
          TicketTab.complaints => 'ابحث في الشكاوى',
          TicketTab.suggestions => 'ابحث في المقترحات',
        };

        return RefreshIndicator(
          onRefresh: () =>
              ref.read(ticketsControllerProvider.notifier).refresh(),
          child: CustomScrollView(
            slivers: [
              if (!widget.embedded)
                SliverAppBar(
                  pinned: true,
                  title: Text(switch (_activeTab) {
                    TicketTab.tickets => 'تذاكر الدعم',
                    TicketTab.complaints => 'الشكاوى',
                    TicketTab.suggestions => 'المقترحات',
                  }),
                  backgroundColor: isDark
                      ? Colors.black
                      : const Color(0xFFF2F2F7),
                  surfaceTintColor: Colors.transparent,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _showCreateTicketDialog,
                    ),
                    if (authUser?.role == 'admin')
                      IconButton(
                        icon: const Icon(Icons.tune_rounded),
                        onPressed: _activeTab == TicketTab.tickets
                            ? _showSupportTeamDialog
                            : _showDepartmentHandlersDialog,
                      ),
                  ],
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    children: [
                      Container(
                        clipBehavior: Clip.antiAlias,
                        // padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.38,
                            ),
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: searchHint,
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'مسح',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (tickets.isEmpty)
                        TicketsEmptyIllustration(
                          title: switch (_activeTab) {
                            TicketTab.tickets => 'لا توجد تذاكر حاليًا',
                            TicketTab.complaints => 'لا توجد شكاوى حاليًا',
                            TicketTab.suggestions => 'لا توجد مقترحات حاليًا',
                          },
                          subtitle: _searchController.text.trim().isEmpty
                              ? 'أنشئ طلباً جديداً وسيظهر لمسؤولي القسم المختار فقط.'
                              : 'لا توجد نتائج مطابقة لعبارة "${_searchController.text.trim()}".',
                          icon: switch (_activeTab) {
                            TicketTab.tickets => Icons.support_agent_rounded,
                            TicketTab.complaints =>
                              Icons.report_problem_rounded,
                            TicketTab.suggestions => Icons.lightbulb_rounded,
                          },
                          accent: switch (_activeTab) {
                            TicketTab.tickets => TicketsPalette.brand,
                            TicketTab.complaints => TicketsPalette.complaint,
                            TicketTab.suggestions => TicketsPalette.suggestion,
                          },
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1C1C1E)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (int i = 0; i < tickets.length; i++) ...[
                                ModernTicketCard(
                                  ticket: tickets[i],
                                  dateFormat: dateFormat,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => TicketDetailsScreen(
                                        ticketId: tickets[i].id,
                                        initialTicket: tickets[i],
                                      ),
                                    ),
                                  ),
                                ),
                                if (i < tickets.length - 1)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      start: 16,
                                    ),
                                    child: Divider(
                                      height: 0.5,
                                      thickness: 0.5,
                                      color: colorScheme.outlineVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildContent();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      body: _buildContent(),
      bottomNavigationBar: BottomNavigationBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        selectedItemColor: TicketsPalette.brand,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        currentIndex: _activeTab.index,
        onTap: (index) {
          setState(() {
            _activeTab = TicketTab.values[index];
            _searchController.clear();
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.support_agent_outlined),
            activeIcon: Icon(Icons.support_agent_rounded),
            label: 'تذاكر',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.report_problem_outlined),
            activeIcon: Icon(Icons.report_problem_rounded),
            label: 'شكاوى',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.lightbulb_outline_rounded),
            activeIcon: Icon(Icons.lightbulb_rounded),
            label: 'مقترحات',
          ),
        ],
      ),
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
  final _messageController = TextEditingController();
  bool _internalNote = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _changeStatus(TicketDetailsData details) async {
    final statuses = const [
      'open',
      'assigned',
      'in_progress',
      'waiting_branch',
      'resolved',
      'closed',
    ];
    final selected = await showModalBottomSheet<String>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: statuses
              .map(
                (status) => ListTile(
                  title: Text(_statusLabel(status)),
                  trailing: details.ticket.status == status
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, status),
                ),
              )
              .toList(),
        ),
      ),
    );

    if (selected == null || selected == details.ticket.status) {
      return;
    }
    try {
      await ref
          .read(ticketDetailsControllerProvider(widget.ticketId).notifier)
          .updateStatus(selected);
      await ref.read(ticketsControllerProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _assignTicket(TicketDetailsData details) async {
    final departmentId = details.ticket.targetDepartmentId;
    List<TicketActor> departmentHandlers = [];
    List<TicketActor> allSupportUsers = [];

    try {
      if (departmentId != null && departmentId.isNotEmpty) {
        final handlerType = details.ticket.ticketType == 'complaint'
            ? 'complaint'
            : (details.ticket.ticketType == 'suggestion'
                  ? 'suggestion'
                  : 'ticket');
        departmentHandlers = await ref
            .read(ticketsControllerProvider.notifier)
            .fetchDepartmentHandlers(departmentId, handlerType: handlerType);
      }
      final supportData = await ref
          .read(ticketsControllerProvider.notifier)
          .fetchSupportUsers();
      allSupportUsers = supportData.users
          .map(
            (u) => TicketActor(
              id: u.id,
              username: u.username,
              fullName: u.fullName,
              role: u.role,
            ),
          )
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في جلب المستخدمين: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return; // Skip assignment modal on failure
    }

    if (!mounted) return;

    final List<TicketActor> candidates = [];
    final seen = <String>{};
    for (final handler in departmentHandlers) {
      if (seen.add(handler.id)) candidates.add(handler);
    }
    for (final user in allSupportUsers) {
      if (seen.add(user.id)) candidates.add(user);
    }

    final selected = await showModalBottomSheet<String?>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('بدون إسناد'),
              onTap: () => Navigator.pop(context, null),
            ),
            if (departmentHandlers.isNotEmpty)
              const ListTile(
                title: Text(
                  'مسؤولو القسم:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
              ),
            ...candidates.map((user) {
              final isHandler = departmentHandlers.any((h) => h.id == user.id);
              return ListTile(
                leading: Icon(
                  isHandler
                      ? Icons.admin_panel_settings_outlined
                      : Icons.person_outline,
                ),
                title: Text(user.displayName),
                subtitle: Text(user.username),
                trailing: details.ticket.assignedTo?.id == user.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, user.id),
              );
            }),
          ],
        ),
      ),
    );

    if (selected == null && selected == details.ticket.assignedTo?.id) {
      // No change
      return;
    }

    try {
      await ref
          .read(ticketDetailsControllerProvider(widget.ticketId).notifier)
          .assignTo(selected);
      await ref.read(ticketsControllerProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الإسناد: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendComment(TicketDetailsData details) async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      return;
    }
    try {
      await ref
          .read(ticketDetailsControllerProvider(widget.ticketId).notifier)
          .addComment(
            message,
            internalNote: _internalNote && details.canManage,
          );
      _messageController.clear();
      setState(() {
        _internalNote = false;
      });
      await ref.read(ticketsControllerProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? Colors.black : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('تفاصيل التذكرة'),
        backgroundColor: scaffoldBg,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: () => ref
                .read(ticketDetailsControllerProvider(widget.ticketId).notifier)
                .refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: detailsState.when(
        loading: () {
          if (widget.initialTicket != null) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                TicketDetailsHeaderCard(
                  ticket: widget.initialTicket!,
                  dateFormat: dateFormat,
                  canManage: false,
                ),
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
        error: (error, _) => Center(child: Text(error.toString())),
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
          final colorScheme = Theme.of(context).colorScheme;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                    const SizedBox(height: 12),
                    Text(
                      'سجل التذكرة',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (details.updates.isEmpty)
                      const _TicketsEmptyState(
                        query: '',
                        title: 'لا توجد تحديثات بعد',
                        subtitle:
                            'ستظهر هنا كل الرسائل والإجراءات الخاصة بالتذكرة.',
                      )
                    else
                      ...details.updates.map(
                        (update) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TicketTimelineTile(
                            label: _kindLabel(update.kind),
                            message: _ticketUpdateDisplayMessage(update),
                            actor: update.createdBy.displayName,
                            visibilityLabel: _visibilityLabel(
                              update.visibility,
                            ),
                            timestamp: update.createdAt != null
                                ? dateFormat(update.createdAt!)
                                : '—',
                            accent: _kindColor(update.kind),
                            isInternal: update.visibility == 'internal',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (details.canManage)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Text(
                                'ملاحظة داخلية (فريق الدعم فقط)',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              Switch.adaptive(
                                value: _internalNote,
                                onChanged: ticketClosed
                                    ? null
                                    : (v) => setState(() => _internalNote = v),
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
                                    : const Color(0xFFF2F2F7),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: TextField(
                                controller: _messageController,
                                enabled: !ticketClosed,
                                minLines: 1,
                                maxLines: 5,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: ticketClosed
                                      ? 'التذكرة مغلقة'
                                      : 'رسالة...',
                                  hintStyle: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed:
                                ticketClosed ||
                                    _messageController.text.trim().isEmpty
                                ? null
                                : () => _sendComment(details),
                            icon: const Icon(
                              Icons.arrow_circle_up_rounded,
                              size: 36,
                            ),
                            color: TicketsPalette.brand,
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TicketsEmptyState extends StatelessWidget {
  const _TicketsEmptyState({
    required this.query,
    this.title = 'لا توجد تذاكر حاليًا',
    this.subtitle = 'يمكنك إنشاء تذكرة جديدة أو تعديل البحث لعرض النتائج.',
  });

  final String query;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.12),
            child: const Icon(
              Icons.confirmation_number_outlined,
              color: Color(0xFF2563EB),
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            query.isEmpty ? subtitle : 'لا توجد نتائج مطابقة لعبارة "$query".',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketDetailsHeaderCard extends StatelessWidget {
  const _TicketDetailsHeaderCard({
    required this.ticket,
    required this.dateFormat,
    required this.canManage,
    required this.onChangeStatus,
    required this.onAssign,
  });

  final TicketItem ticket;
  final _TicketDateFormatter dateFormat;
  final bool canManage;
  final VoidCallback onChangeStatus;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ticket.title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            ticket.ticketNumber,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            ticket.description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TicketTag(
                label: _statusLabel(ticket.status),
                color: _statusColor(ticket.status),
              ),
              if (ticket.ticketType == 'ticket')
                _TicketTag(
                  label: _priorityLabel(ticket.priority),
                  color: _priorityColor(ticket.priority),
                ),
              if (ticket.ticketType != 'ticket' &&
                  ticket.targetDepartmentName != null)
                _TicketTag(
                  label: 'القسم: ${ticket.targetDepartmentName!}',
                  color: const Color(0xFF0F766E),
                ),
              if (ticket.assignedTo != null)
                _TicketTag(
                  label: 'المسؤول: ${ticket.assignedTo!.displayName}',
                  color: const Color(0xFF6366F1),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'آخر تحديث: ${ticket.lastUpdateAt != null ? dateFormat(ticket.lastUpdateAt!) : '-'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onChangeStatus,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('تغيير الحالة'),
                ),
                OutlinedButton.icon(
                  onPressed: onAssign,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('إسناد التذكرة'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TicketUpdateCard extends StatelessWidget {
  const _TicketUpdateCard({required this.update, required this.dateFormat});

  final TicketUpdateItem update;
  final _TicketDateFormatter dateFormat;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final kindLabel = _kindLabel(update.kind);
    final visibilityLabel = _visibilityLabel(update.visibility);
    final displayMessage = _ticketUpdateDisplayMessage(update);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TicketTag(
                      label: kindLabel,
                      color: _kindColor(update.kind),
                    ),
                    _TicketTag(
                      label: visibilityLabel,
                      color: update.visibility == 'internal'
                          ? const Color(0xFF7C3AED)
                          : const Color(0xFF2563EB),
                    ),
                  ],
                ),
              ),
              Text(
                update.createdAt != null ? dateFormat(update.createdAt!) : '',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            update.createdBy.displayName,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            displayMessage,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _statusLabel(String status) {
  return switch (status) {
    'open' => 'مفتوحة',
    'assigned' => 'مسندة',
    'in_progress' => 'قيد التنفيذ',
    'waiting_branch' => 'بانتظار الفرع',
    'resolved' => 'تم الحل',
    'closed' => 'مغلقة',
    _ => status,
  };
}

Color _statusColor(String status) {
  return switch (status) {
    'open' => const Color(0xFF2563EB),
    'assigned' => const Color(0xFF7C3AED),
    'in_progress' => const Color(0xFF0EA5E9),
    'waiting_branch' => const Color(0xFFF59E0B),
    'resolved' => const Color(0xFF16A34A),
    'closed' => const Color(0xFF6B7280),
    _ => const Color(0xFF334155),
  };
}

String _priorityLabel(String priority) {
  return switch (priority) {
    'low' => 'منخفضة',
    'normal' => 'عادية',
    'high' => 'عالية',
    'critical' => 'حرجة',
    _ => priority,
  };
}

Color _priorityColor(String priority) {
  return switch (priority) {
    'low' => const Color(0xFF64748B),
    'normal' => const Color(0xFF2563EB),
    'high' => const Color(0xFFF97316),
    'critical' => const Color(0xFFDC2626),
    _ => const Color(0xFF334155),
  };
}

String _kindLabel(String kind) {
  return switch (kind) {
    'created' => 'تم إنشاء التذكرة',
    'comment' => 'تعليق',
    'status' => 'تحديث حالة',
    'assignment' => 'تغيير الإسناد',
    'note' => 'ملاحظة داخلية',
    _ => kind,
  };
}

String _visibilityLabel(String visibility) {
  return visibility == 'internal' ? 'ملاحظة داخلية' : 'رسالة عامة';
}

Color _kindColor(String kind) {
  return switch (kind) {
    'created' => const Color(0xFF2563EB),
    'comment' => const Color(0xFF0EA5E9),
    'status' => const Color(0xFFF59E0B),
    'assignment' => const Color(0xFF6366F1),
    'note' => const Color(0xFF7C3AED),
    _ => const Color(0xFF475569),
  };
}

String _ticketUpdateDisplayMessage(TicketUpdateItem update) {
  if (update.kind == 'status') {
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
  }

  if (update.kind == 'assignment') {
    if (update.toAssigneeName != null &&
        update.toAssigneeName!.trim().isNotEmpty) {
      return 'تم إسناد التذكرة إلى ${update.toAssigneeName!}.';
    }
    return 'تم إلغاء إسناد التذكرة.';
  }

  if (update.kind == 'created') {
    return update.message.trim().isEmpty
        ? 'تم إنشاء التذكرة وفتحها للمراجعة.'
        : update.message;
  }

  if (update.kind == 'note') {
    return update.message.trim().isEmpty
        ? 'تمت إضافة ملاحظة داخلية.'
        : update.message;
  }

  if (update.kind == 'comment') {
    return update.message.trim().isEmpty
        ? 'تمت إضافة رد جديد على التذكرة.'
        : update.message;
  }

  return update.message.trim().isEmpty
      ? _kindLabel(update.kind)
      : update.message;
}

class _DepartmentHandlersDialog extends ConsumerStatefulWidget {
  const _DepartmentHandlersDialog({required this.handlerType});

  final String handlerType;

  bool get isSuggestion => handlerType == 'suggestion';

  String get dialogTitle => switch (handlerType) {
    'suggestion' => 'مسؤولو المقترحات حسب القسم',
    'ticket' => 'مسؤولو التذاكر حسب القسم',
    _ => 'مسؤولو الشكاوى حسب القسم',
  };

  @override
  ConsumerState<_DepartmentHandlersDialog> createState() =>
      _DepartmentHandlersDialogState();
}

class _DepartmentHandlersDialogState
    extends ConsumerState<_DepartmentHandlersDialog> {
  List<dynamic> _departments = [];
  String? _selectedDeptId;
  List<TicketSupportUser> _supportUsers = [];
  Set<String> _selectedHandlerIds = {};
  bool _isLoadingDepts = true;
  bool _isLoadingHandlers = false;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final dio = ref.read(authenticatedApiClientProvider).dio;
      final res = await dio.get('/api/departments');
      final depts =
          (res.data['departments'] as List<dynamic>?) ??
          ((res.data['data'] as Map<String, dynamic>?)?['departments']
              as List<dynamic>?) ??
          const <dynamic>[];
      final supportData = await ref
          .read(ticketsControllerProvider.notifier)
          .fetchSupportUsers();

      if (!mounted) return;
      setState(() {
        _departments = depts;
        _supportUsers = supportData.users;
        _isLoadingDepts = false;
        if (depts.isNotEmpty) {
          final firstId =
              depts.first['id']?.toString() ?? depts.first['_id']?.toString();
          _selectedDeptId = firstId;
          if (firstId != null) {
            _loadHandlers(firstId);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingDepts = false;
        _errorText = e.toString();
      });
    }
  }

  Future<void> _loadHandlers(String deptId) async {
    setState(() {
      _isLoadingHandlers = true;
      _errorText = null;
    });
    try {
      final handlers = await ref
          .read(ticketsControllerProvider.notifier)
          .fetchDepartmentHandlers(deptId, handlerType: widget.handlerType);
      if (!mounted) return;
      setState(() {
        _selectedHandlerIds = handlers.map((h) => h.id).toSet();
        _isLoadingHandlers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingHandlers = false;
        _errorText = e.toString();
      });
    }
  }

  Future<void> _saveHandlers() async {
    if (_selectedDeptId == null) return;
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      await ref
          .read(ticketsControllerProvider.notifier)
          .updateDepartmentHandlers(
            _selectedDeptId!,
            _selectedHandlerIds.toList(),
            handlerType: widget.handlerType,
          );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDepts) {
      return const AlertDialog(
        content: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final availableWidth = MediaQuery.sizeOf(context).width - 32;
    final dialogWidth = math.max(280.0, math.min(520.0, availableWidth));
    final dialogHeight = MediaQuery.sizeOf(context).height * 0.78;

    return AlertDialog(
      title: Text(widget.dialogTitle),
      content: ConstrainedBox(
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
              DropdownButtonFormField<String>(
                value: _selectedDeptId,
                isExpanded: true,
                items: _departments.map((dept) {
                  final id =
                      dept['id']?.toString() ?? dept['_id']?.toString() ?? '';
                  final name = dept['name']?.toString() ?? 'قسم غير معروف';
                  return DropdownMenuItem(value: id, child: Text(name));
                }).toList(),
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _selectedDeptId = value;
                          });
                          _loadHandlers(value);
                        }
                      },
                decoration: const InputDecoration(
                  labelText: 'اختر القسم لتحديد المسؤولين عنه',
                ),
              ),
              const SizedBox(height: 16),
              if (_isLoadingHandlers)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _supportUsers.map((user) {
                        return CheckboxListTile(
                          value: _selectedHandlerIds.contains(user.id),
                          title: Text(user.displayName),
                          subtitle: Text('${user.username} • ${user.role}'),
                          onChanged: _isSaving
                              ? null
                              : (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _selectedHandlerIds.add(user.id);
                                    } else {
                                      _selectedHandlerIds.remove(user.id);
                                    }
                                  });
                                },
                        );
                      }).toList(),
                    ),
                  ),
                ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: const TextStyle(color: Color(0xFFB91C1C)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _isSaving || _selectedDeptId == null
              ? null
              : _saveHandlers,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('حفظ'),
        ),
      ],
    );
  }
}
