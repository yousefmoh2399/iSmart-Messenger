import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../models/printer_models.dart';

class PrinterMonitoringScreen extends ConsumerStatefulWidget {
  const PrinterMonitoringScreen({super.key, this.isWrapped = false});

  final bool isWrapped;

  @override
  ConsumerState<PrinterMonitoringScreen> createState() =>
      _PrinterMonitoringScreenState();
}

class _PrinterMonitoringScreenState
    extends ConsumerState<PrinterMonitoringScreen> {
  String? _selectedBranchId;
  String? _selectedPrinterId;
  PrinterDashboardData? _selectedDashboard;
  bool _busy = false;
  bool _fullSyncRunning = false;
  String? _scanningBranchId;
  final TextEditingController _branchSearchController = TextEditingController();
  String _branchSearchQuery = '';
  bool? _manualSidebarCollapsed;
  bool _rightSidebarCollapsed = true;

  @override
  void initState() {
    super.initState();
    _branchSearchController.addListener(() {
      setState(() {
        _branchSearchQuery = _branchSearchController.text;
      });
    });
  }

  @override
  void dispose() {
    _branchSearchController.dispose();
    super.dispose();
  }

  bool _hasRunningFullSync(PrinterOverviewData? data) {
    if (data == null) {
      return false;
    }
    final latestFullLog = data.logs
        .where((item) => item['scope']?.toString() == 'full')
        .cast<Map<String, dynamic>?>()
        .firstOrNull;
    if (latestFullLog == null) {
      return false;
    }
    return latestFullLog['status']?.toString() == 'running';
  }

  Future<void> _runFullSync() async {
    if (_fullSyncRunning) {
      return;
    }
    setState(() {
      _busy = true;
      _fullSyncRunning = true;
    });
    try {
      await ref.read(printerRepositoryProvider).fullSync();
      await ref.read(printerControllerProvider.notifier).refresh();
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      await _showFullSyncProgressDialog();
      await ref.read(printerControllerProvider.notifier).refresh();
      await _refreshSelectedDashboard();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _fullSyncRunning = false);
      _message(error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _fullSyncRunning = false;
        });
      }
    }
  }

  Future<void> _stopFullSync() async {
    setState(() => _busy = true);
    try {
      await ref.read(printerControllerProvider.notifier).stopFullSync();
      await _refreshSelectedDashboard();
      if (!mounted) {
        return;
      }
      setState(() => _fullSyncRunning = false);
      _message('تم إيقاف مزامنة الطابعات.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _message(error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showFullSyncProgressDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: _FullSyncProgressDialog(
          fetchStatus: () => ref
              .read(printerControllerProvider.notifier)
              .fetchFullSyncStatus(),
          stopSync: () =>
              ref.read(printerControllerProvider.notifier).stopFullSync(),
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    final status = result['status']?.toString() ?? '';
    if (status == 'success') {
      _message('اكتملت مزامنة الطابعات بنجاح.');
    } else if (status == 'partial') {
      _message('انتهت المزامنة مع بعض التحذيرات.');
    }
  }

  Future<void> _selectBranch(String? branchId) async {
    setState(() {
      _selectedBranchId = branchId;
      _selectedPrinterId = null;
      _selectedDashboard = null;
      if (branchId != null) {
        _rightSidebarCollapsed = false;
      }
    });
    if (branchId == null) {
      return;
    }
    try {
      final dashboard = await ref
          .read(printerRepositoryProvider)
          .fetchDashboard(branchId: branchId);
      if (!mounted || _selectedBranchId != branchId) {
        return;
      }
      setState(() => _selectedDashboard = dashboard);
    } catch (_) {}
  }

  Future<void> _refreshSelectedDashboard() async {
    final branchId = _selectedBranchId;
    if (branchId == null) {
      return;
    }
    final dashboard = await ref
        .read(printerRepositoryProvider)
        .fetchDashboard(branchId: branchId);
    if (!mounted || _selectedBranchId != branchId) {
      return;
    }
    setState(() => _selectedDashboard = dashboard);
  }

  Future<void> _openPrinterDetails(PrinterItem printer) async {
    final navigator = Navigator.of(context);
    final parentContainer = ProviderScope.containerOf(context);
    PrinterItem resolvedPrinter = printer;
    try {
      final details = await ref
          .read(printerRepositoryProvider)
          .fetchPrinterDetails(printer.id);
      resolvedPrinter = details.printer;
    } catch (_) {}
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ProviderScope(
          parent: parentContainer,
          child: PrinterDetailsScreen(printer: resolvedPrinter),
        ),
      ),
    );
    if (mounted) {
      await ref.read(printerControllerProvider.notifier).refresh();
      await _refreshSelectedDashboard();
    }
  }

  Future<void> _runDiscover(String branchId) async {
    setState(() {
      _busy = true;
      _scanningBranchId = branchId;
    });
    try {
      await ref
          .read(printerControllerProvider.notifier)
          .discoverBranch(branchId);
      await _refreshSelectedDashboard();
      if (!mounted) return;
      _message('انتهى اكتشاف الطابعات.');
    } catch (error) {
      if (!mounted) return;
      _message(error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _scanningBranchId = null;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      await _refreshSelectedDashboard();
      if (!mounted) return;
      _message(done);
    } catch (error) {
      if (!mounted) return;
      _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? const Color(0xFFDC2626) : null,
          content: Text(_fixText(text)),
        ),
      );
  }

  Future<void> _showBranchDialog({PrinterBranchItem? branch}) async {
    final name = TextEditingController(text: branch?.name ?? '');
    final code = TextEditingController(text: branch?.code ?? '');
    final range = TextEditingController(text: branch?.networkRange ?? '');
    final location = TextEditingController(text: branch?.location ?? '');
    var status = branch?.status == 'inactive' ? 'inactive' : 'active';

    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: Text(branch == null ? 'إضافة فرع طابعات' : 'تعديل الفرع'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'اسم الفرع'),
                  ),
                  TextField(
                    controller: code,
                    decoration: const InputDecoration(labelText: 'كود الفرع'),
                  ),
                  TextField(
                    controller: range,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'نطاق الشبكة مثل 192.168.10.0/24',
                    ),
                  ),
                  TextField(
                    controller: location,
                    decoration: const InputDecoration(labelText: 'الموقع'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: status,
                    decoration: const InputDecoration(labelText: 'الحالة'),
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('نشط')),
                      DropdownMenuItem(
                        value: 'inactive',
                        child: Text('غير نشط'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setLocalState(() => status = value);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
    if (approved != true) return;
    if (branch == null) {
      await _run(
        () => ref
            .read(printerControllerProvider.notifier)
            .createBranch(
              name: name.text,
              code: code.text,
              networkRange: range.text,
              location: location.text,
            ),
        'تمت إضافة الفرع.',
      );
      return;
    }
    await _run(
      () => ref
          .read(printerControllerProvider.notifier)
          .updateBranch(
            branchId: branch.id,
            name: name.text,
            code: code.text,
            networkRange: range.text,
            location: location.text,
            status: status,
          ),
      'تم تعديل الفرع.',
    );
  }

  Future<void> _showMonthlyConsumptionDialog(BuildContext context) async {
    final now = DateTime.now();
    final overview = ref.read(printerControllerProvider).valueOrNull;
    final branches = overview?.branches ?? [];

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: _MonthlyConsumptionDialogContent(
            initialYear: now.year,
            initialMonth: now.month,
            initialBranchId: _selectedBranchId,
            branches: branches,
            onExportReport:
                (format, branchId, fromMonth, fromYear, toMonth, toYear) async {
                  try {
                    await ref
                        .read(printerControllerProvider.notifier)
                        .exportMonthlyReport(
                          format: format,
                          type: branchId == null ? 'global' : 'branch',
                          branchId: branchId,
                          fromMonth: fromMonth,
                          fromYear: fromYear,
                          toMonth: toMonth,
                          toYear: toYear,
                        );
                    if (context.mounted) {
                      _message(
                        'تم تصدير تقرير الاستهلاك بصيغة ${format.toUpperCase()} بنجاح.',
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      _message(e.toString(), error: true);
                    }
                  }
                },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final state = ref.watch(printerControllerProvider);
    final canManage = authUser?.canManagePrinterModule == true;
    final canSync = authUser?.canSyncPrinterModule == true;
    final canExport = authUser?.canExportPrinterReports == true;

    final body = state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorView(
        message: error.toString(),
        onRetry: () => ref.read(printerControllerProvider.notifier).refresh(),
      ),
      data: (data) {
        final visibleBranches = data.branches.where((branch) {
          if (_branchSearchQuery.isEmpty) return true;
          final query = _branchSearchQuery.toLowerCase();
          return branch.name.toLowerCase().contains(query) ||
              branch.code.toLowerCase().contains(query);
        }).toList();

        return _PrinterContent(
          data: data,
          branches: visibleBranches,
          totalBranchesCount:
              data.dashboard.totals['branches']?.toInt() ??
              data.branches.length,
          branchSearchController: _branchSearchController,
          authUser: authUser,
          scanningBranchId: _scanningBranchId,
          selectedBranchId: _selectedBranchId,
          selectedPrinterId: _selectedPrinterId,
          selectedDashboard: _selectedDashboard,
          busy: _busy,
          fullSyncRunning: _fullSyncRunning || _hasRunningFullSync(data),
          isSidebarCollapsed:
              _manualSidebarCollapsed ??
              (MediaQuery.of(context).size.width < 1100),
          onToggleSidebar: () {
            setState(() {
              final isCurrentlyCollapsed =
                  _manualSidebarCollapsed ??
                  (MediaQuery.of(context).size.width < 1100);
              _manualSidebarCollapsed = !isCurrentlyCollapsed;
            });
          },
          isRightSidebarCollapsed: _rightSidebarCollapsed,
          onToggleRightSidebar: () {
            setState(() => _rightSidebarCollapsed = !_rightSidebarCollapsed);
          },
          onBranchSelected: _selectBranch,
          onPrinterSelected: (printer) {
            setState(() {
              _selectedPrinterId = printer.id;
              _rightSidebarCollapsed = false;
            });
            _openPrinterDetails(printer);
          },
          onAddBranch: canManage ? () => _showBranchDialog() : null,
          onEditBranch: canManage
              ? (branch) => _showBranchDialog(branch: branch)
              : null,
          onDeleteBranch: canManage
              ? (branchId) async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => Directionality(
                      textDirection: TextDirection.rtl,
                      child: AlertDialog(
                        title: const Text('حذف الفرع'),
                        content: const Text(
                          'هل تريد حذف هذا الفرع بالكامل؟ سيتم حذف جميع الطابعات التابعة له أيضًا.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('إلغاء'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('حذف'),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (confirmed != true) {
                    return;
                  }
                  await _run(
                    () => ref
                        .read(printerControllerProvider.notifier)
                        .deleteBranch(branchId),
                    'تم حذف الفرع بنجاح.',
                  );
                  if (_selectedBranchId == branchId) {
                    _selectBranch(null);
                  }
                }
              : null,
          onFullSync: canSync ? _runFullSync : null,
          onStopFullSync: canSync ? _stopFullSync : null,
          onExportPdf: canExport
              ? () => _run(
                  () => ref
                      .read(printerControllerProvider.notifier)
                      .exportReport(
                        format: 'pdf',
                        type: _selectedBranchId == null ? 'global' : 'branch',
                        branchId: _selectedBranchId,
                      ),
                  'تم تصدير تقرير PDF.',
                )
              : null,
          onExportExcel: canExport
              ? () => _run(
                  () => ref
                      .read(printerControllerProvider.notifier)
                      .exportReport(
                        format: 'xlsx',
                        type: _selectedBranchId == null ? 'global' : 'branch',
                        branchId: _selectedBranchId,
                      ),
                  'تم تصدير تقرير Excel.',
                )
              : null,
          onShowMonthlyConsumption: canExport
              ? () => _showMonthlyConsumptionDialog(context)
              : null,
          onDiscover: canSync ? _runDiscover : null,
          onSyncPrinter: canSync
              ? (printerId) => _run(
                  () => ref
                      .read(printerControllerProvider.notifier)
                      .syncPrinter(printerId),
                  'تم تحديث بيانات الطابعة.',
                )
              : null,
          onDeletePrinter: canManage
              ? (printerId) async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => Directionality(
                      textDirection: TextDirection.rtl,
                      child: AlertDialog(
                        title: const Text('حذف الطابعة'),
                        content: const Text(
                          'هل تريد حذف هذه الطابعة من النظام؟',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('إلغاء'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('حذف'),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (confirmed != true) {
                    return;
                  }
                  await _run(
                    () => ref
                        .read(printerControllerProvider.notifier)
                        .deletePrinter(printerId),
                    'تم حذف الطابعة.',
                  );
                }
              : null,
        );
      },
    );

    if (widget.isWrapped) return body;
    return Scaffold(body: body);
  }
}

class _PrinterContent extends StatelessWidget {
  const _PrinterContent({
    required this.data,
    required this.branches,
    required this.totalBranchesCount,
    required this.branchSearchController,
    required this.authUser,
    required this.selectedBranchId,
    required this.selectedPrinterId,
    required this.scanningBranchId,
    required this.selectedDashboard,
    required this.busy,
    required this.fullSyncRunning,
    required this.isSidebarCollapsed,
    required this.onToggleSidebar,
    required this.isRightSidebarCollapsed,
    required this.onToggleRightSidebar,
    required this.onBranchSelected,
    required this.onPrinterSelected,
    required this.onAddBranch,
    required this.onEditBranch,
    required this.onDeleteBranch,
    required this.onFullSync,
    required this.onStopFullSync,
    required this.onExportPdf,
    required this.onExportExcel,
    required this.onShowMonthlyConsumption,
    required this.onDiscover,
    required this.onSyncPrinter,
    required this.onDeletePrinter,
  });

  final PrinterOverviewData data;
  final List<PrinterBranchItem> branches;
  final int totalBranchesCount;
  final TextEditingController branchSearchController;
  final AppUser? authUser;
  final String? selectedBranchId;
  final String? selectedPrinterId;
  final String? scanningBranchId;
  final PrinterDashboardData? selectedDashboard;
  final bool busy;
  final bool fullSyncRunning;
  final bool isSidebarCollapsed;
  final VoidCallback onToggleSidebar;
  final bool isRightSidebarCollapsed;
  final VoidCallback onToggleRightSidebar;
  final ValueChanged<String?> onBranchSelected;
  final ValueChanged<PrinterItem> onPrinterSelected;
  final VoidCallback? onAddBranch;
  final ValueChanged<PrinterBranchItem>? onEditBranch;
  final ValueChanged<String>? onDeleteBranch;
  final VoidCallback? onFullSync;
  final VoidCallback? onStopFullSync;
  final VoidCallback? onExportPdf;
  final VoidCallback? onExportExcel;
  final VoidCallback? onShowMonthlyConsumption;
  final ValueChanged<String>? onDiscover;
  final ValueChanged<String>? onSyncPrinter;
  final ValueChanged<String>? onDeletePrinter;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visiblePrinters = selectedBranchId == null
        ? data.printers
        : data.printers
              .where((item) => item.branchId == selectedBranchId)
              .toList();
    final selectedBranch = selectedBranchId == null
        ? null
        : data.branches
              .where((item) => item.id == selectedBranchId)
              .firstOrNull;
    final selectedPrinter = visiblePrinters
        .where((item) => item.id == selectedPrinterId)
        .firstOrNull;
    final visibleLogs = selectedBranchId == null
        ? data.logs
        : data.logs
              .where((item) => item['branchId']?.toString() == selectedBranchId)
              .toList();
    final visibleNotifications = selectedBranchId == null
        ? data.dashboard.notifications
        : selectedDashboard?.notifications ??
              data.dashboard.notifications
                  .where(
                    (item) => item['branchId']?.toString() == selectedBranchId,
                  )
                  .toList();
    final totals = selectedBranchId == null
        ? data.dashboard.totals
        : selectedDashboard?.totals ??
              _totalsForBranch(
                branch: selectedBranch,
                printers: visiblePrinters,
                notifications: visibleNotifications,
              );
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 16,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.print_rounded, size: 28),
                    SizedBox(width: 10),
                    Text(
                      'إدارة ومراقبة الطابعات',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ActionButton(
                      icon: fullSyncRunning
                          ? Icons.stop_circle_rounded
                          : Icons.refresh_rounded,
                      label: fullSyncRunning ? 'إيقاف' : 'مزامنة',
                      busy: busy,
                      onPressed: fullSyncRunning ? onStopFullSync : onFullSync,
                    ),
                    _ActionButton(
                      icon: Icons.picture_as_pdf_rounded,
                      label: 'PDF',
                      busy: busy,
                      onPressed: onExportPdf,
                    ),
                    _ActionButton(
                      icon: Icons.table_chart_rounded,
                      label: 'Excel',
                      busy: busy,
                      onPressed: onExportExcel,
                    ),
                    _ActionButton(
                      icon: Icons.calendar_month_rounded,
                      label: 'الاستهلاك الشهري',
                      busy: busy,
                      onPressed: onShowMonthlyConsumption,
                    ),
                    _ActionButton(
                      icon: Icons.add_rounded,
                      label: 'فرع',
                      busy: busy,
                      onPressed: onAddBranch,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _StatsGrid(totals: totals),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    width: isSidebarCollapsed ? 80 : 320,
                    child: _BranchPanel(
                      isCollapsed: isSidebarCollapsed,
                      onToggle: onToggleSidebar,
                      branches: branches,
                      totalBranchesCount: totalBranchesCount,
                      searchController: branchSearchController,
                      selectedBranchId: selectedBranchId,
                      scanningBranchId: scanningBranchId,
                      onSelected: onBranchSelected,
                      onDiscover: onDiscover,
                      onEditBranch: onEditBranch,
                      onDeleteBranch: onDeleteBranch,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _PrinterTable(
                      printers: visiblePrinters,
                      selectedPrinterId: selectedPrinterId,
                      onSelected: onPrinterSelected,
                      onSyncPrinter: onSyncPrinter,
                      onDeletePrinter: onDeletePrinter,
                    ),
                  ),
                  const SizedBox(width: 16),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    width: isRightSidebarCollapsed ? 80 : 300,
                    child: _SidePanel(
                      isCollapsed: isRightSidebarCollapsed,
                      onToggle: onToggleRightSidebar,
                      selectedBranch: selectedBranch,
                      selectedPrinter: selectedPrinter,
                      notifications: visibleNotifications,
                      logs: visibleLogs,
                      accent: colors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PrinterDetailsScreen extends ConsumerWidget {
  const PrinterDetailsScreen({super.key, required this.printer});

  final PrinterItem printer;

  Future<void> _runAction(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String done,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(_fixText(done)),
          ),
        );
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFDC2626),
            content: Text(error.toString()),
          ),
        );
    }
  }

  LinearGradient _printerStatusGradient(String status) {
    switch (status) {
      case 'online':
        return const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF047857)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'warning':
        return const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFB45309)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'error':
        return const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'offline':
      default:
        return const LinearGradient(
          colors: [Color(0xFF64748B), Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = _printerStatusColor(printer.status);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final extended = printer.extendedDetails;
    final product = _asMap(extended['product']);
    final usage = _asMap(extended['usage']);
    final supplies = _asListOfMaps(extended['supplies']);
    final events = _asListOfMaps(extended['events']);
    final jobs = _asListOfMaps(extended['jobs']);
    final rawKeyValues = _asListOfMaps(extended['rawKeyValues']);

    final hasColorToner =
        printer.tonerLevels['cyan'] != null ||
        printer.tonerLevels['magenta'] != null ||
        printer.tonerLevels['yellow'] != null;

    final hasScanner =
        (printer.lifetimeCounters['scanPages'] ?? 0) > 0 ||
        (printer.counters['scanPages'] ?? 0) > 0 ||
        printer.model.toLowerCase().contains('taskalfa') ||
        printer.model.toLowerCase().contains('mfp') ||
        printer.model.toLowerCase().contains('m479') ||
        printer.model.toLowerCase().contains('m227') ||
        printer.model.toLowerCase().contains('m428');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            elevation: 0,
            title: Text(
              printer.name.isEmpty ? printer.ipAddress : printer.name,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => _runAction(
                  context,
                  ref,
                  () => ref
                      .read(printerControllerProvider.notifier)
                      .syncPrinter(printer.id),
                  'تمت مزامنة بيانات الطابعة وتحديث العدادات بنجاح.',
                ),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('مزامنة فورية'),
              ),
              TextButton.icon(
                onPressed: () => _runAction(
                  context,
                  ref,
                  () => ref
                      .read(printerRepositoryProvider)
                      .exportPrinterReport(printer.id),
                  'تم تصدير تقرير الطابعة بصيغة PDF بنجاح.',
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('تقرير PDF'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Beautiful gradient card at the top
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: _printerStatusGradient(printer.status),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.print_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            printer.name.isEmpty
                                ? printer.ipAddress
                                : printer.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_city_rounded,
                                color: Colors.white70,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                printer.branchName,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Icon(
                                Icons.settings_ethernet_rounded,
                                color: Colors.white70,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                printer.ipAddress,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white30),
                          ),
                          child: Text(
                            _fixText(_printerStatus(printer.status)),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'الموديل: ${printer.model}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // TabBar navigation
              Container(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: colors.onPrimary,
                  unselectedLabelColor: colors.onSurfaceVariant,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  tabs: const [
                    Tab(text: 'العدادات والاستخدام'),
                    Tab(text: 'خراطيش الحبر والمستلزمات'),
                    Tab(text: 'تفاصيل الجهاز والشبكة'),
                    Tab(text: 'الصيانة وسجلات الأعطال'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Tab content area
              SizedBox(
                height: 620,
                child: TabBarView(
                  children: [
                    // Tab 1: Usage
                    _buildUsageTab(context, hasScanner),
                    // Tab 2: Toner
                    _buildTonerTab(context, hasColorToner, supplies),
                    // Tab 3: Device Info
                    _buildDeviceInfoTab(context, product, usage),
                    // Tab 4: Maintenance & Jobs
                    _buildMaintenanceTab(context, events, jobs, rawKeyValues),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsageTab(BuildContext context, bool hasScanner) {
    return ListView(
      physics: const ClampingScrollPhysics(),
      children: [
        const Text(
          'عدادات صفحات عمر الطابعة الإجمالية والعداد الحالي للمراجعة:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.2,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildMetricCard(
              context,
              title: 'إجمالي عدد الصفحات المطبوعة',
              value: printer.lifetimeCounters['totalPages'] ?? 0,
              subtitle: 'إجمالي صفحات العمر للجهاز',
              icon: Icons.description_rounded,
              iconColor: Colors.deepPurple,
            ),
            _buildMetricCard(
              context,
              title: 'العداد الحالي',
              value: printer.counters['totalPages'] ?? 0,
              subtitle: 'منذ آخر دورة صيانة أو تصفير',
              icon: Icons.onetwothree_rounded,
              iconColor: Colors.blue,
            ),
            _buildMetricCard(
              context,
              title: 'صفحات أحادية اللون (أسود)',
              value: printer.lifetimeCounters['monoPages'] ?? 0,
              subtitle: 'الصفحات المطبوعة باللون الأسود',
              icon: Icons.brightness_medium_rounded,
              iconColor: Colors.blueGrey,
            ),
            _buildMetricCard(
              context,
              title: 'صفحات ملونة (Color)',
              value: printer.lifetimeCounters['colorPages'] ?? 0,
              subtitle: 'الصفحات المطبوعة بالألوان كاملة',
              icon: Icons.color_lens_rounded,
              iconColor: Colors.orange,
            ),
            _buildMetricCard(
              context,
              title: 'طباعة على الوجهين (Duplex)',
              value: printer.lifetimeCounters['duplexPages'] ?? 0,
              subtitle: 'توفير الورق (وجهين تلقائيًا)',
              icon: Icons.library_books_rounded,
              iconColor: Colors.indigo,
            ),
            _buildMetricCard(
              context,
              title: 'صفحات التصوير (Copy)',
              value: printer.lifetimeCounters['copyPages'] ?? 0,
              subtitle: 'المستندات المنسوخة عبر الماسح',
              icon: Icons.copy_rounded,
              iconColor: Colors.teal,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Scan Pages display block
        if (hasScanner) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.teal.withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.scanner_rounded,
                    color: Colors.teal,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إحصائيات الماسح الضوئي (Scanner)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'هذه الطابعة مزودة بماسح ضوئي متقدم (سكانر). لقد تم مسح ضوئي لـ '
                        '${(printer.lifetimeCounters['scanPages'] ?? 0).toStringAsFixed(0)} '
                        'صفحة إجمالًا، ومسح '
                        '${(printer.counters['scanPages'] ?? 0).toStringAsFixed(0)} '
                        'صفحة في الفترة الحالية عبر وحدة تغذية المستندات (ADF) أو لوحة المسح الزجاجية المسطحة.',
                        style: TextStyle(
                          color: Colors.teal.shade800,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.teal,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        (printer.lifetimeCounters['scanPages'] ?? 0)
                            .toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'عملية مسح',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.amber, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'هذا الجهاز مسجل كطابعة مستقلة ولا يحتوي على وحدة مسح ضوئي (سكانر) مدمجة.',
                    style: TextStyle(color: Colors.amber, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required num value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTonerTab(
    BuildContext context,
    bool hasColorToner,
    List<Map<String, dynamic>> supplies,
  ) {
    final theme = Theme.of(context);

    return ListView(
      physics: const ClampingScrollPhysics(),
      children: [
        const Text(
          'حالة خراطيش الحبر المتبقية ونسب الاستهلاك:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 20),

        // CMYK cartridges container
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildTonerTube(
              context,
              colorName: 'أسود Black',
              colorCode: 'K',
              value: printer.tonerLevels['black'],
              fillColor: const Color(0xFF1E293B),
            ),
            if (hasColorToner) ...[
              _buildTonerTube(
                context,
                colorName: 'سماوي Cyan',
                colorCode: 'C',
                value: printer.tonerLevels['cyan'],
                fillColor: const Color(0xFF06B6D4),
              ),
              _buildTonerTube(
                context,
                colorName: 'أرجواني Magenta',
                colorCode: 'M',
                value: printer.tonerLevels['magenta'],
                fillColor: const Color(0xFFEC4899),
              ),
              _buildTonerTube(
                context,
                colorName: 'أصفر Yellow',
                colorCode: 'Y',
                value: printer.tonerLevels['yellow'],
                fillColor: const Color(0xFFEAB308),
              ),
            ] else ...[
              // Label for mono printers
              Container(
                width: 320,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                  ),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.opacity_rounded,
                      size: 48,
                      color: Colors.blueGrey,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'طابعة أحادية اللون (Monochrome)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'هذا الطراز يدعم خرطوشة حبر سوداء واحدة فقط. خراطيش الألوان (سماوي، أرجواني، أصفر) غير مدعومة في الماكينة.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),

        if (supplies.isNotEmpty) ...[
          const Divider(height: 32),
          const Text(
            'تفاصيل الخراطيش والمستلزمات المسترجعة من الطابعة:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 12),
          _DetailDataTable(
            columns: const [
              'الخرطوشة',
              'الحالة الحالية',
              'الرقم التسلسلي للقطعة',
              'النوع',
              'تاريخ التركيب لأول مرة',
              'الصفحات المطبوعة',
            ],

            rows: supplies
                .take(15)
                .map(
                  (item) => [
                    _text(item['color']),
                    _text(item['status']),
                    _text(item['serialNumber']),
                    _text(item['type']),
                    _text(item['firstInstallDate']),
                    _text(item['pagesPrinted']),
                  ],
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildTonerTube(
    BuildContext context, {
    required String colorName,
    required String colorCode,
    required Object? value,
    required Color fillColor,
  }) {
    final theme = Theme.of(context);
    num? number;
    if (value is num) {
      number = value;
    } else {
      number = num.tryParse(value?.toString() ?? '');
    }

    final double level = number == null
        ? 0
        : (number.clamp(0, 100) / 100).toDouble();
    final isLow = number != null && number < 15;
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLow
              ? Colors.red.withValues(alpha: 0.5)
              : theme.dividerColor.withValues(alpha: 0.15),
          width: isLow ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            colorName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 16),
          // Cylinder visual representation
          Container(
            width: 50,
            height: 160,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.grey.shade400, width: 2),
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Filled amount
                FractionallySizedBox(
                  heightFactor: level,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.only(
                        bottomLeft: const Radius.circular(23),
                        bottomRight: const Radius.circular(23),
                        topLeft: Radius.circular(level > 0.9 ? 23 : 0),
                        topRight: Radius.circular(level > 0.9 ? 23 : 0),
                      ),
                    ),
                  ),
                ),
                // Indicator Text
                Positioned(
                  top: 20,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: fillColor, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        colorCode,
                        style: TextStyle(
                          color: fillColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            number == null ? 'غير متوفر' : '${number.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isLow ? Colors.red : colors.onSurface,
            ),
          ),
          if (isLow) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 12,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'الحبر منخفض جدًا',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceInfoTab(
    BuildContext context,
    Map<String, dynamic> product,
    Map<String, dynamic> usage,
  ) {
    return ListView(
      physics: const ClampingScrollPhysics(),
      children: [
        _DetailSection(
          title: 'معلومات تعريف الجهاز الأساسية:',
          children: [
            _InfoLine(label: 'اسم المنتج والماكينة', value: printer.model),
            _InfoLine(
              label: 'الرقم التسلسلي للمصنع',
              value: printer.serialNumber,
            ),
            _InfoLine(
              label: 'عنوان الشبكة IP Address',
              value: printer.ipAddress,
            ),
            _InfoLine(label: 'اسم المضيف Hostname', value: printer.hostname),
            _InfoLine(label: 'الشركة المصنعة (Vendor)', value: printer.vendor),
            _InfoLine(
              label: 'تاريخ ووقت المزامنة الأخيرة',
              value: _dateText(printer.lastSyncAt),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (product.isNotEmpty) ...[
          _DetailSection(
            title: 'تفاصيل اللوحة والبرامج المثبتة (من صفحة الويب):',
            children: [
              ..._mapLines(product, const {
                'productName': 'اسم المنتج البديل',
                'productNumber': 'رقم الموديل الداخلي',
                'serviceId': 'معرّف الصيانة الخاص',
                'firmwareVersion': 'إصدار نظام التشغيل الأساسي (Firmware)',
                'engineFirmware': 'البرنامج الثابت لمحرك الطباعة',
                'region': 'الدولة والمنطقة المعتمدة',
                'memoryTotalKb': 'إجمالي الذاكرة العشوائية المتاحة (KB)',
                'installedPersonalities': 'اللغات ولغات الوظائف المثبتة',
              }),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMaintenanceTab(
    BuildContext context,
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> jobs,
    List<Map<String, dynamic>> rawKeyValues,
  ) {
    return ListView(
      physics: const ClampingScrollPhysics(),
      children: [
        _DetailSection(
          title: 'حالة الصيانة الحالية ومعدلات الأخطاء:',
          children: [
            _DynamicLine(
              label: 'إجمالي انحشارات الورق (Paper Jams)',
              values: printer.maintenance,
              keyName: 'paperJams',
            ),
            _DynamicLine(
              label: 'رسائل الخطأ النشطة',
              values: printer.maintenance,
              keyName: 'errorMessages',
            ),
            _DynamicLine(
              label: 'التحذيرات النشطة',
              values: printer.maintenance,
              keyName: 'warnings',
            ),
          ],
        ),

        if (events.isNotEmpty) ...[
          const SizedBox(height: 20),
          _DetailSection(
            title: 'سجل الأحداث البرمجية والتحذيرات:',
            children: [
              _DetailDataTable(
                columns: const [
                  'الكود المالي',
                  'النوع',
                  'التاريخ/الوقت',
                  'الدورات المطبوعة',
                  'الوصف والتفسير',
                ],
                rows: events
                    .take(15)
                    .map(
                      (item) => [
                        _text(item['code']),
                        _text(item['type']),
                        _text(item['dateTime']),
                        _text(item['cycles']),
                        _text(item['description']),
                      ],
                    )
                    .toList(),
              ),
            ],
          ),
        ],

        if (jobs.isNotEmpty) ...[
          const SizedBox(height: 20),
          _DetailSection(
            title: 'آخر الوظائف التي قامت بها الطابعة:',
            children: [
              _DetailDataTable(
                columns: const [
                  'اسم الوظيفة',
                  'اسم المستخدم المُرسل',
                  'حالة الوظيفة',
                  'تاريخ الاستقبال',
                ],
                rows: jobs
                    .take(15)
                    .map(
                      (item) => [
                        _text(item['name']),
                        _text(item['user']),
                        _text(item['status']),
                        _text(item['dateTime']),
                      ],
                    )
                    .toList(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _fixText(title),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _printerStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _fixText(_printerStatus(status)),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _TonerLine extends StatelessWidget {
  const _TonerLine({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    num? number;
    final raw = value;
    if (raw is num) {
      number = raw;
    } else {
      number = num.tryParse(raw?.toString() ?? '');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(_fixText(label))),
          Expanded(
            child: LinearProgressIndicator(
              value: number == null ? 0 : (number.clamp(0, 100) / 100),
              minHeight: 8,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            child: Text(number == null ? '-' : '${number.toStringAsFixed(0)}%'),
          ),
        ],
      ),
    );
  }
}

class _DetailDataTable extends StatelessWidget {
  const _DetailDataTable({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text('-', style: TextStyle(color: Colors.grey)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
          headingRowHeight: 44,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 72,
          columns: [
            for (final column in columns)
              DataColumn(
                label: Text(
                  column,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                cells: [
                  for (var index = 0; index < columns.length; index += 1)
                    DataCell(
                      SizedBox(
                        width: columns.length <= 2 ? 380 : 160,
                        child: Text(
                          index < row.length && row[index].trim().isNotEmpty
                              ? row[index]
                              : '-',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.totals});

  final Map<String, num> totals;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'الفروع النشطة',
        totals['branches'] ?? 0,
        Icons.account_tree_rounded,
        Colors.indigo,
      ),
      (
        'إجمالي الطابعات',
        totals['printers'] ?? 0,
        Icons.print_rounded,
        Colors.blue,
      ),
      (
        'طابعات متصلة',
        totals['onlinePrinters'] ?? 0,
        Icons.wifi_rounded,
        Colors.green,
      ),
      (
        'طابعات غير متصلة',
        totals['offlinePrinters'] ?? 0,
        Icons.wifi_off_rounded,
        Colors.red,
      ),
      (
        'إجمالي الصفحات المطبوعة',
        totals['totalPages'] ?? 0,
        Icons.description_rounded,
        Colors.purple,
      ),
      (
        'الصفحات التالفة (الهالك)',
        totals['wastePages'] ?? 0,
        Icons.delete_sweep_rounded,
        Colors.blueGrey,
      ),
      (
        'استخدام الشهر الحالي',
        totals['monthlyUsage'] ?? 0,
        Icons.calendar_month_rounded,
        Colors.teal,
      ),
      (
        'تنبيهات انخفاض الحبر',
        totals['tonerAlerts'] ?? 0,
        Icons.opacity_rounded,
        Colors.orange,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 90,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: isDark
                ? null
                : Border.all(color: Colors.black.withValues(alpha: 0.05)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: item.$4.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.$3, color: item.$4, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.$2.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BranchPanel extends StatelessWidget {
  const _BranchPanel({
    required this.isCollapsed,
    required this.onToggle,
    required this.branches,
    required this.totalBranchesCount,
    required this.searchController,
    required this.selectedBranchId,
    required this.scanningBranchId,
    required this.onSelected,
    required this.onDiscover,
    required this.onEditBranch,
    required this.onDeleteBranch,
  });

  final bool isCollapsed;
  final VoidCallback onToggle;
  final List<PrinterBranchItem> branches;
  final int totalBranchesCount;
  final TextEditingController searchController;
  final String? selectedBranchId;
  final String? scanningBranchId;
  final ValueChanged<String?> onSelected;
  final ValueChanged<String>? onDiscover;
  final ValueChanged<PrinterBranchItem>? onEditBranch;
  final ValueChanged<String>? onDeleteBranch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Panel(
      title: isCollapsed ? '' : 'فروع الشركة',
      trailing: IconButton(
        icon: Icon(
          isCollapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
          size: 20,
        ),
        onPressed: onToggle,
        tooltip: isCollapsed ? 'توسيع القائمة' : 'طي القائمة',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
      child: Column(
        children: [
          if (!isCollapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: ListenableBuilder(
                listenable: searchController,
                builder: (context, _) {
                  return TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'البحث عن فرع (الاسم أو الكود)...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () => searchController.clear(),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.1),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.15),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                  );
                },
              ),
            ),
          if (!isCollapsed) const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                _buildBranchItem(
                  title: isCollapsed ? '' : 'كل فروع الشركة',
                  subtitle: isCollapsed
                      ? ''
                      : 'جميع الطابعات المتوفرة ($totalBranchesCount فرع)',
                  selected: selectedBranchId == null,
                  onTap: () => onSelected(null),
                  icon: Icons.business_rounded,
                  isCollapsed: isCollapsed,
                ),
                for (final branch in branches)
                  _ScannerLoadingEffect(
                    scanning: branch.id == scanningBranchId,
                    child: _buildBranchItem(
                      title: branch.name,
                      subtitle: '${branch.code} | ${branch.networkRange}',
                      selected: selectedBranchId == branch.id,
                      onTap: () => onSelected(branch.id),
                      icon: Icons.location_on_rounded,
                      isCollapsed: isCollapsed,
                      trailing: isCollapsed
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (onEditBranch != null)
                                  IconButton(
                                    iconSize: 18,
                                    tooltip: 'تعديل بيانات الفرع',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => onEditBranch!(branch),
                                  ),
                                if (onDeleteBranch != null)
                                  IconButton(
                                    iconSize: 18,
                                    tooltip: 'حذف الفرع بالكامل',
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () => onDeleteBranch!(branch.id),
                                  ),
                                if (onDiscover != null)
                                  IconButton(
                                    iconSize: 18,
                                    tooltip:
                                        'البحث عن أجهزة بالفرع (SNMP Scan)',
                                    icon: const Icon(
                                      Icons.radar_rounded,
                                      color: Colors.teal,
                                    ),
                                    onPressed: () => onDiscover!(branch.id),
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

  Widget _buildBranchItem({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
    required IconData icon,
    Widget? trailing,
    bool isCollapsed = false,
  }) {
    if (isCollapsed) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Colors.blue.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Tooltip(
            message: title.isEmpty ? 'كل الفروع' : title,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Icon(
                icon,
                color: selected ? Colors.blue : Colors.grey,
                size: 28,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected
            ? Colors.blue.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: 280,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: selected ? Colors.blue : Colors.grey),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _fixText(title),
                          style: TextStyle(
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fixText(subtitle),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 8), trailing],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrinterTable extends StatelessWidget {
  const _PrinterTable({
    required this.printers,
    required this.selectedPrinterId,
    required this.onSelected,
    required this.onSyncPrinter,
    required this.onDeletePrinter,
  });

  final List<PrinterItem> printers;
  final String? selectedPrinterId;
  final ValueChanged<PrinterItem> onSelected;
  final ValueChanged<String>? onSyncPrinter;
  final ValueChanged<String>? onDeletePrinter;

  Widget _buildMiniTonerStatus(Map<String, dynamic> toner) {
    final List<Widget> dots = [];

    void addDot(String key, Color color) {
      final val = toner[key];
      if (val != null) {
        num? number;
        if (val is num) {
          number = val;
        } else {
          number = num.tryParse(val.toString());
        }

        if (number != null) {
          final isLow = number < 15;
          dots.add(
            Tooltip(
              message: '${key.toUpperCase()}: ${number.toStringAsFixed(0)}%',
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isLow ? 0.2 : 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isLow ? Colors.red : color,
                    width: isLow ? 2 : 1,
                  ),
                ),
                child: isLow
                    ? const Center(
                        child: Text(
                          '!',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          );
        }
      }
    }

    addDot('black', const Color(0xFF1E293B));
    addDot('cyan', const Color(0xFF06B6D4));
    addDot('magenta', const Color(0xFFEC4899));
    addDot('yellow', const Color(0xFFEAB308));

    if (dots.isEmpty) {
      return const Text(
        'لا تتوفر بيانات حبر',
        style: TextStyle(color: Colors.grey, fontSize: 10),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: dots);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (printers.isEmpty) {
      return const _Panel(
        title: 'قائمة الطابعات المسجلة',
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'لا توجد أي طابعات مسجلة في الفرع المحدد حاليًا. يرجى الضغط على زر (اكتشاف الطابعات) من الفروع لبدء فحص الشبكة التلقائي وإدخال الأجهزة المتاحة بنظام SNMP.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, height: 1.5),
            ),
          ),
        ),
      );
    }
    return _Panel(
      title: 'قائمة الطابعات المسجلة',
      child: ListView.separated(
        itemCount: printers.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: theme.dividerColor.withValues(alpha: 0.1),
        ),
        itemBuilder: (context, index) {
          final printer = printers[index];
          final statusColor = _printerStatusColor(printer.status);
          final isSelected = selectedPrinterId == printer.id;

          return Container(
            color: isSelected
                ? colors.primaryContainer.withValues(alpha: 0.15)
                : null,
            child: InkWell(
              onTap: () => onSelected(printer),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.print_rounded,
                        color: statusColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 12,
                        spacing: 12,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                printer.name.isEmpty
                                    ? printer.ipAddress
                                    : printer.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${printer.branchName} • ${printer.model} • S/N: ${printer.serialNumber}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildMiniTonerStatus(printer.tonerLevels),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'إجمالي: ${(printer.lifetimeCounters['totalPages'] ?? 0).toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if ((printer.lifetimeCounters['scanPages'] ??
                                          0) >
                                      0)
                                    Text(
                                      'مسح: ${(printer.lifetimeCounters['scanPages'] ?? 0).toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        color: Colors.teal,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                              if (onSyncPrinter != null)
                                IconButton(
                                  iconSize: 20,
                                  tooltip: 'تحديث فوري',
                                  icon: const Icon(Icons.sync_rounded),
                                  onPressed: () => onSyncPrinter!(printer.id),
                                ),
                              if (onDeletePrinter != null)
                                IconButton(
                                  iconSize: 20,
                                  tooltip: 'حذف',
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () => onDeletePrinter!(printer.id),
                                ),
                            ],
                          ),
                        ],
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
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.isCollapsed,
    required this.onToggle,
    required this.selectedBranch,
    required this.selectedPrinter,
    required this.notifications,
    required this.logs,
    required this.accent,
  });

  final bool isCollapsed;
  final VoidCallback onToggle;
  final PrinterBranchItem? selectedBranch;
  final PrinterItem? selectedPrinter;
  final List<Map<String, dynamic>> notifications;
  final List<Map<String, dynamic>> logs;
  final Color accent;

  Widget _buildSafeItem({
    required Widget icon,
    required String title,
    required String subtitle,
  }) {
    if (isCollapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Tooltip(
          message: '$title\n$subtitle',
          child: Center(child: icon),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: SizedBox(
        width: 260,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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

  @override
  Widget build(BuildContext context) {
    if (selectedPrinter != null) {
      return _PrinterDetailsPanel(
        printer: selectedPrinter!,
        isCollapsed: isCollapsed,
        onToggle: onToggle,
      );
    }
    return Column(
      children: [
        if (selectedBranch != null && !isCollapsed) ...[
          SizedBox(
            height: 180,
            child: _BranchDetailsPanel(branch: selectedBranch!),
          ),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: _Panel(
            title: isCollapsed ? '' : 'التنبيهات',
            trailing: IconButton(
              icon: Icon(
                isCollapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
                size: 20,
              ),
              onPressed: onToggle,
              tooltip: isCollapsed ? 'توسيع القائمة' : 'طي القائمة',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            child: notifications.isEmpty
                ? Center(
                    child: isCollapsed
                        ? const Icon(
                            Icons.notifications_off_rounded,
                            color: Colors.grey,
                          )
                        : const Text('لا توجد تنبيهات.'),
                  )
                : ListView.separated(
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = notifications[index];
                      return _buildSafeItem(
                        icon: Icon(
                          item['severity'] == 'error'
                              ? Icons.error_outline_rounded
                              : Icons.warning_amber_rounded,
                          color: item['severity'] == 'error'
                              ? Colors.red
                              : Colors.orange,
                          size: 20,
                        ),
                        title: item['title'] ?? '',
                        subtitle: item['message'] ?? '',
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _Panel(
            title: isCollapsed ? '' : 'سجل العمليات',
            child: logs.isEmpty
                ? Center(
                    child: isCollapsed
                        ? const Icon(Icons.history_rounded, color: Colors.grey)
                        : const Text('لا توجد عمليات.'),
                  )
                : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final item = logs[index];
                      return _buildSafeItem(
                        icon: const Icon(
                          Icons.sync_alt_rounded,
                          color: Colors.grey,
                          size: 20,
                        ),
                        title:
                            '${_syncScope(item['scope'])} | ${_syncStatus(item['status'])}',
                        subtitle:
                            'الأجهزة التي تمت مزامنتها: ${item['devicesSynced'] ?? 0}',
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _BranchDetailsPanel extends StatelessWidget {
  const _BranchDetailsPanel({required this.branch});

  final PrinterBranchItem branch;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'بيانات الفرع',
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _InfoLine(label: 'الاسم', value: branch.name),
          _InfoLine(label: 'الكود', value: branch.code),
          _InfoLine(label: 'الشبكة', value: branch.networkRange),
          _InfoLine(label: 'الموقع', value: branch.location),
          _InfoLine(label: 'الحالة', value: _branchStatus(branch.status)),
          _InfoLine(label: 'آخر مزامنة', value: _dateText(branch.lastSyncAt)),
        ],
      ),
    );
  }
}

class _PrinterDetailsPanel extends StatelessWidget {
  const _PrinterDetailsPanel({
    required this.printer,
    required this.isCollapsed,
    required this.onToggle,
  });

  final PrinterItem printer;
  final bool isCollapsed;
  final VoidCallback onToggle;

  static const double _infoLineHorizontalBreakpoint = 180;

  Widget _buildMiniProgressBar(
    BuildContext context,
    String label,
    Object? val,
    Color barColor,
  ) {
    num? number;
    if (val is num) {
      number = val;
    } else {
      number = num.tryParse(val?.toString() ?? '');
    }

    final double pct = number == null
        ? 0
        : (number.clamp(0, 100) / 100).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < _infoLineHorizontalBreakpoint;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 11)),
                    Text(
                      number == null ? '-' : '${number.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: number != null && number < 15
                            ? Colors.red
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    color: barColor,
                    backgroundColor: Colors.grey.withValues(alpha: 0.12),
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(label, style: const TextStyle(fontSize: 11)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    color: barColor,
                    backgroundColor: Colors.grey.withValues(alpha: 0.12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 30,
                child: Text(
                  number == null ? '-' : '${number.toStringAsFixed(0)}%',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: number != null && number < 15 ? Colors.red : null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _printerStatusColor(printer.status);
    final hasColor = printer.tonerLevels['cyan'] != null;

    final header = isCollapsed
        ? Center(
            child: Tooltip(
              message:
                  '${printer.name.isEmpty ? printer.ipAddress : printer.name} (${_printerStatus(printer.status)})',
              child: Icon(Icons.print_rounded, color: statusColor, size: 28),
            ),
          )
        : Row(
            children: [
              Icon(Icons.print_rounded, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  printer.name.isEmpty ? printer.ipAddress : printer.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _StatusBadge(status: printer.status),
            ],
          );

    return _Panel(
      title: isCollapsed ? '' : 'تفاصيل الطابعة السريعة',
      trailing: IconButton(
        icon: Icon(
          isCollapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
          size: 20,
        ),
        onPressed: onToggle,
        tooltip: isCollapsed ? 'توسيع القائمة' : 'طي القائمة',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          header,
          const SizedBox(height: 12),
          _InfoLine(label: 'الفرع والموقع', value: printer.branchName),
          _InfoLine(label: 'عنوان IP', value: printer.ipAddress),
          _InfoLine(label: 'الموديل', value: printer.model),
          _InfoLine(label: 'الرقم التسلسلي', value: printer.serialNumber),
          _InfoLine(label: 'آخر مزامنة', value: _dateText(printer.lastSyncAt)),
          if (!isCollapsed) ...[
            const Divider(height: 20),
            const Text(
              'قراءة العدادات الحالية',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 6),
          ],
          _CounterLine(
            label: 'إجمالي عداد الصفحات',
            values: printer.lifetimeCounters,
            keyName: 'totalPages',
          ),
          _CounterLine(
            label: 'صفحات أحادية اللون',
            values: printer.lifetimeCounters,
            keyName: 'monoPages',
          ),
          _CounterLine(
            label: 'صفحات ملونة',
            values: printer.lifetimeCounters,
            keyName: 'colorPages',
          ),
          _CounterLine(
            label: 'طباعة مزدوجة (Duplex)',
            values: printer.lifetimeCounters,
            keyName: 'duplexPages',
          ),
          _CounterLine(
            label: 'نسخ مستندات (Copy)',
            values: printer.lifetimeCounters,
            keyName: 'copyPages',
          ),
          _CounterLine(
            label: 'مسح ضوئي (Scan)',
            values: printer.lifetimeCounters,
            keyName: 'scanPages',
          ),
          if (!isCollapsed) ...[
            const Divider(height: 20),
            const Text(
              'حالة خراطيش الحبر المتبقية',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 6),
          ],
          _buildMiniProgressBar(
            context,
            'أسود Black',
            printer.tonerLevels['black'],
            const Color(0xFF1E293B),
          ),
          if (hasColor) ...[
            _buildMiniProgressBar(
              context,
              'سماوي Cyan',
              printer.tonerLevels['cyan'],
              const Color(0xFF06B6D4),
            ),
            _buildMiniProgressBar(
              context,
              'أرجواني Magenta',
              printer.tonerLevels['magenta'],
              const Color(0xFFEC4899),
            ),
            _buildMiniProgressBar(
              context,
              'أصفر Yellow',
              printer.tonerLevels['yellow'],
              const Color(0xFFEAB308),
            ),
          ],
          if (!isCollapsed) ...[
            const Divider(height: 20),
            const Text(
              'الصيانة والأعطال',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 6),
          ],
          _DynamicLine(
            label: 'مرات انحشار الورق',
            values: printer.maintenance,
            keyName: 'paperJams',
          ),
          _DynamicLine(
            label: 'أخطاء مسجلة',
            values: printer.maintenance,
            keyName: 'errorMessages',
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  static const double _infoLineHorizontalBreakpoint = 180;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < _infoLineHorizontalBreakpoint;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fixText(label),
                  style: TextStyle(
                    color: Theme.of(context).hintColor,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _fixText(value.trim().isEmpty ? '-' : value),
                  textDirection: RegExp(r'^[\d.:/-]+$').hasMatch(value)
                      ? TextDirection.ltr
                      : null,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                child: Text(
                  _fixText(label),
                  style: TextStyle(color: Theme.of(context).hintColor),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _fixText(value.trim().isEmpty ? '-' : value),
                  textDirection: RegExp(r'^[\d.:/-]+$').hasMatch(value)
                      ? TextDirection.ltr
                      : null,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CounterLine extends StatelessWidget {
  const _CounterLine({
    required this.label,
    required this.values,
    required this.keyName,
  });

  final String label;
  final Map<String, num> values;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    return _InfoLine(
      label: label,
      value: (values[keyName] ?? 0).toStringAsFixed(0),
    );
  }
}

class _DynamicLine extends StatelessWidget {
  const _DynamicLine({
    required this.label,
    required this.values,
    required this.keyName,
  });

  final String label;
  final Map<String, dynamic> values;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final value = values[keyName];
    final text = value is Iterable
        ? value.map((entry) => entry.toString()).join(', ')
        : value?.toString() ?? '-';
    return _InfoLine(label: label, value: text);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? null
            : Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _FullSyncProgressDialog extends StatefulWidget {
  const _FullSyncProgressDialog({
    required this.fetchStatus,
    required this.stopSync,
  });

  final Future<Map<String, dynamic>> Function() fetchStatus;
  final Future<void> Function() stopSync;

  @override
  State<_FullSyncProgressDialog> createState() =>
      _FullSyncProgressDialogState();
}

class _FullSyncProgressDialogState extends State<_FullSyncProgressDialog> {
  Timer? _timer;
  Map<String, dynamic> _status = const <String, dynamic>{
    'running': true,
    'status': 'running',
    'percent': 0,
    'processedPrinters': 0,
    'totalPrinters': 0,
    'onlinePrinters': 0,
    'offlinePrinters': 0,
  };
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _loadStatus());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final next = await widget.fetchStatus();
      if (!mounted) return;
      setState(() => _status = next);
      if (next['running'] != true) {
        _timer?.cancel();
      }
    } catch (_) {}
  }

  Future<void> _stop() async {
    setState(() => _stopping = true);
    try {
      await widget.stopSync();
      await _loadStatus();
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final running = _status['running'] == true;
    final status = _status['status']?.toString() ?? 'running';
    final percent = (_status['percent'] as num?)?.toDouble() ?? 0;
    final progress = (percent / 100).clamp(0.0, 1.0);
    final processed = _status['processedPrinters'] ?? 0;
    final total = _status['totalPrinters'] ?? 0;
    final online = _status['onlinePrinters'] ?? 0;
    final offline = _status['offlinePrinters'] ?? 0;
    final lastPrinter = _status['lastPrinter'];
    final lastPrinterText = lastPrinter is Map
        ? [
            lastPrinter['branchCode']?.toString(),
            lastPrinter['ipAddress']?.toString(),
            lastPrinter['status']?.toString(),
          ].where((item) => item != null && item.isNotEmpty).join(' | ')
        : '';

    return AlertDialog(
      title: Text(
        running
            ? 'مزامنة الطابعات'
            : status == 'success'
            ? 'اكتملت المزامنة'
            : 'توقفت المزامنة',
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: total == 0 && running ? null : progress,
              minHeight: 10,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  '${percent.round()}%',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '$processed / $total',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SyncChip(
                  label: 'متصل',
                  value: online.toString(),
                  color: Colors.green,
                ),
                _SyncChip(
                  label: 'غير متصل',
                  value: offline.toString(),
                  color: Colors.orange,
                ),
              ],
            ),
            if (lastPrinterText.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'آخر طابعة: $lastPrinterText',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
            if (!running) ...[
              const SizedBox(height: 14),
              Text(
                status == 'success'
                    ? 'تم تحديث بيانات الطابعات بنجاح.'
                    : 'تم إيقاف أو فشل جزء من المزامنة.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (running)
          TextButton.icon(
            onPressed: _stopping ? null : _stop,
            icon: _stopping
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.stop_circle_rounded),
            label: const Text('إيقاف'),
          ),
        if (!running)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_status),
            child: const Text('إغلاق'),
          ),
      ],
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.18),
        child: Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.busy,
    this.spinning = false,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final bool spinning;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: FilledButton.icon(
        onPressed: busy ? null : onPressed,
        icon: spinning
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : Icon(icon, size: 18),
        label: Text(_fixText(label)),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

String _syncScope(Object? value) {
  switch (value?.toString()) {
    case 'full':
      return 'النظام بالكامل';
    case 'branch':
      return 'فرع';
    case 'printer':
      return 'طابعة';
    default:
      return value?.toString() ?? '';
  }
}

String _syncStatus(Object? value) {
  switch (value?.toString()) {
    case 'success':
      return 'ناجحة';
    case 'failed':
      return 'فشلت';
    case 'running':
      return 'قيد التشغيل';
    default:
      return value?.toString() ?? '';
  }
}

Map<String, dynamic> _asMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _asListOfMaps(Object? raw) {
  if (raw is! Iterable) return const <Map<String, dynamic>>[];
  return raw.map(_asMap).where((item) => item.isNotEmpty).toList();
}

String _text(Object? value) {
  if (value == null) return '';
  if (value is Iterable) {
    return value.map(_text).where((item) => item.isNotEmpty).join(', ');
  }
  if (value is Map) {
    return value.entries
        .map((entry) => '${entry.key}: ${_text(entry.value)}')
        .where((item) => item.trim().isNotEmpty)
        .join(' | ');
  }
  return value.toString();
}

String _fixText(String value) {
  if (!value.contains('Ø') && !value.contains('Ù')) {
    return value;
  }
  try {
    return utf8.decode(latin1.encode(value), allowMalformed: true);
  } catch (_) {
    return value;
  }
}

List<Widget> _mapLines(
  Map<String, dynamic> values,
  Map<String, String> labels,
) {
  final children = <Widget>[];
  for (final entry in labels.entries) {
    final value = _text(values[entry.key]);
    if (value.trim().isEmpty) continue;
    children.add(_InfoLine(label: entry.value, value: value));
  }
  return children;
}

Map<String, num> _totalsForBranch({
  required PrinterBranchItem? branch,
  required List<PrinterItem> printers,
  required List<Map<String, dynamic>> notifications,
}) {
  final totalPages = printers.fold<num>(
    0,
    (sum, item) => sum + (item.lifetimeCounters['totalPages'] ?? 0),
  );
  // Do not use cumulative counters as monthly usage fallback
  const monthlyUsage = 0;
  return {
    'branches': branch == null ? 0 : 1,
    'printers': printers.length,
    'onlinePrinters': printers.where((item) => item.status == 'online').length,
    'offlinePrinters': printers.where((item) => item.status != 'online').length,
    'totalPages': totalPages,
    'wastePages': 0,
    'monthlyUsage': monthlyUsage,
    'tonerAlerts': notifications
        .where((item) => item['type']?.toString() == 'toner_low')
        .length,
  };
}

String _branchStatus(String value) {
  return value == 'inactive' ? 'غير نشط' : 'نشط';
}

String _printerStatus(String value) {
  switch (value) {
    case 'online':
      return 'متصلة';
    case 'warning':
      return 'تحتاج متابعة';
    case 'error':
      return 'بها خطأ';
    case 'offline':
      return 'غير متصلة';
    default:
      return value.trim().isEmpty ? 'غير معروفة' : value;
  }
}

Color _printerStatusColor(String value) {
  switch (value) {
    case 'online':
      return const Color(0xFF16A34A);
    case 'warning':
      return const Color(0xFFF59E0B);
    case 'error':
      return const Color(0xFFDC2626);
    default:
      return const Color(0xFF64748B);
  }
}

String _dateText(DateTime? value) {
  if (value == null) return '-';
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class _ScannerLoadingEffect extends StatefulWidget {
  const _ScannerLoadingEffect({required this.child, required this.scanning});

  final Widget child;
  final bool scanning;

  @override
  State<_ScannerLoadingEffect> createState() => _ScannerLoadingEffectState();
}

class _ScannerLoadingEffectState extends State<_ScannerLoadingEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.scanning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _ScannerLoadingEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scanning && !oldWidget.scanning) {
      _controller.repeat();
    } else if (!widget.scanning && oldWidget.scanning) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.scanning) {
      return widget.child;
    }
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = (0.5 - (_controller.value - 0.5).abs()) * 2;
        final shadowOpacity = 0.05 + 0.1 * pulse;
        final borderOpacity = 0.3 + 0.4 * pulse;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: shadowOpacity),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
            border: Border.all(
              color: color.withValues(alpha: borderOpacity),
              width: 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Stack(
              children: [
                child!,
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ScannerLaserPainter(
                        progress: _controller.value,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _ScannerLaserPainter extends CustomPainter {
  _ScannerLaserPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.3),
          color,
          color.withValues(alpha: 0.3),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 0.5, 0.55, 1.0],
      ).createShader(Rect.fromLTRB(0, y - 20, size.width, y + 20));

    canvas.drawRect(Rect.fromLTRB(0, y - 20, size.width, y + 20), paint);

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
  }

  @override
  bool shouldRepaint(covariant _ScannerLaserPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _MonthlyConsumptionDialogContent extends ConsumerStatefulWidget {
  const _MonthlyConsumptionDialogContent({
    required this.initialYear,
    required this.initialMonth,
    required this.initialBranchId,
    required this.branches,
    required this.onExportReport,
  });

  final int initialYear;
  final int initialMonth;
  final String? initialBranchId;
  final List<PrinterBranchItem> branches;
  final Future<void> Function(
    String format,
    String? branchId,
    int fromMonth,
    int fromYear,
    int toMonth,
    int toYear,
  )
  onExportReport;

  @override
  ConsumerState<_MonthlyConsumptionDialogContent> createState() =>
      _MonthlyConsumptionDialogContentState();
}

class _MonthlyConsumptionDialogContentState
    extends ConsumerState<_MonthlyConsumptionDialogContent> {
  late int _fromYear;
  late int _fromMonth;
  late int _toYear;
  late int _toMonth;
  String? _selectedBranchId;
  bool _isLoading = false;
  Map<String, dynamic>? _consumptionData;
  String? _errorMessage;

  static const int _sheetsPerReam = 500;
  static const int _sheetsPerClient = 16;
  final Map<String, int> _branchClientsMap = {};

  final List<int> _years = [2024, 2025, 2026, 2027, 2028];

  final List<Map<String, dynamic>> _months = const [
    {'value': 1, 'name': 'يناير'},
    {'value': 2, 'name': 'فبراير'},
    {'value': 3, 'name': 'مارس'},
    {'value': 4, 'name': 'أبريل'},
    {'value': 5, 'name': 'مايو'},
    {'value': 6, 'name': 'يونيو'},
    {'value': 7, 'name': 'يوليو'},
    {'value': 8, 'name': 'أغسطس'},
    {'value': 9, 'name': 'سبتمبر'},
    {'value': 10, 'name': 'أكتوبر'},
    {'value': 11, 'name': 'نوفمبر'},
    {'value': 12, 'name': 'ديسمبر'},
  ];

  @override
  void initState() {
    super.initState();
    _fromYear = widget.initialYear;
    _fromMonth = widget.initialMonth == 0 ? 1 : widget.initialMonth;
    _toYear = widget.initialYear;
    _toMonth = widget.initialMonth == 0 ? 12 : widget.initialMonth;
    _selectedBranchId = widget.initialBranchId;
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final data = await ref
          .read(printerRepositoryProvider)
          .fetchMonthlyConsumption(
            branchId: _selectedBranchId,
            fromMonth: _fromMonth,
            fromYear: _fromYear,
            toMonth: _toMonth,
            toYear: _toYear,
            forceRefresh: forceRefresh,
          );
      if (!mounted) return;
      setState(() {
        _consumptionData = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  String _getMonthName(int m) {
    return _months.firstWhere(
          (element) => element['value'] == m,
          orElse: () => {'name': m.toString()},
        )['name']
        as String;
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _requiredReams(int pages) {
    if (pages <= 0) return 0;
    return (pages / _sheetsPerReam).ceil();
  }

  int _estimatedClientsCeil(int pages) {
    if (pages <= 0) return 0;
    return (pages / _sheetsPerClient).ceil();
  }

  String _formatReams(int pages) {
    final double reams = pages / _sheetsPerReam;
    final int full = pages ~/ _sheetsPerReam;
    final int rem = pages % _sheetsPerReam;
    if (rem == 0) {
      return '${reams.toStringAsFixed(0)} رزمة';
    }

    return '${reams.toStringAsFixed(2)} رزمة ($full رزمة و$rem ورقة)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final monthsList = _consumptionData?['months'] as List?;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.calendar_month_rounded, size: 28),
          const SizedBox(width: 10),
          const Text('عرض وتقارير الاستهلاك الشهري والمحاسبة'),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(forceRefresh: true),
            tooltip: 'تحديث البيانات',
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 1180,
        height: 750,
        child: Column(
          children: [
            // Filter bar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'من:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _fromMonth,
                          decoration: const InputDecoration(
                            labelText: 'الشهر',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          items: _months
                              .map(
                                (m) => DropdownMenuItem<int>(
                                  value: m['value'] as int,
                                  child: Text(_fixText(m['name'] as String)),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _fromMonth = val);
                              _loadData();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _fromYear,
                          decoration: const InputDecoration(
                            labelText: 'السنة',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          items: _years
                              .map(
                                (y) => DropdownMenuItem<int>(
                                  value: y,
                                  child: Text(y.toString()),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _fromYear = val);
                              _loadData();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 24),
                      const Text(
                        'إلى:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _toMonth,
                          decoration: const InputDecoration(
                            labelText: 'الشهر',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          items: _months
                              .map(
                                (m) => DropdownMenuItem<int>(
                                  value: m['value'] as int,
                                  child: Text(_fixText(m['name'] as String)),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _toMonth = val);
                              _loadData();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _toYear,
                          decoration: const InputDecoration(
                            labelText: 'السنة',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          items: _years
                              .map(
                                (y) => DropdownMenuItem<int>(
                                  value: y,
                                  child: Text(y.toString()),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _toYear = val);
                              _loadData();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _selectedBranchId,
                          decoration: const InputDecoration(
                            labelText: 'الفرع',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('جميع الفروع'),
                            ),
                            ...widget.branches.map(
                              (b) => DropdownMenuItem<String?>(
                                value: b.id,
                                child: Text('${b.code} - ${b.name}'),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedBranchId = val);
                            _loadData();
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      _ActionButton(
                        icon: Icons.picture_as_pdf_rounded,
                        label: 'تصدير PDF',
                        busy: _isLoading,
                        onPressed: () => widget.onExportReport(
                          'pdf',
                          _selectedBranchId,
                          _fromMonth,
                          _fromYear,
                          _toMonth,
                          _toYear,
                        ),
                      ),
                      _ActionButton(
                        icon: Icons.table_chart_rounded,
                        label: 'تصدير Excel',
                        busy: _isLoading,
                        onPressed: () => widget.onExportReport(
                          'xlsx',
                          _selectedBranchId,
                          _fromMonth,
                          _fromYear,
                          _toMonth,
                          _toYear,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Accounting guidance notice
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calculate_outlined,
                    color: colors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ملاحظة المحاسبة الدقيقة: الرزمة = 500 ورقة | حصة العميل = 16 ورقة. يمكنك تعديل عدد العملاء للفرع في الجدول أدناه لحساب الفرق والهدر بدقة.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_selectedBranchId != null)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('الرجوع لجميع الفروع'),
                    onPressed: () {
                      setState(() => _selectedBranchId = null);
                      _loadData();
                    },
                  ),
                ),
              ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'خطأ في تحميل البيانات: $_errorMessage',
                                style: const TextStyle(color: Colors.red),
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _loadData,
                                child: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        )
                      : (monthsList == null ||
                            monthsList.isEmpty ||
                            !monthsList.any(
                              (m) =>
                                  (m['consumption'] as List?)?.isNotEmpty ??
                                  false,
                            ))
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text(
                              'لا توجد بيانات استهلاك مسجلة للفترة المحددة.\n'
                              'يرجى التأكد من مزامنة الطابعات بانتظام لتوليد قراءات العدادات.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, height: 1.6),
                            ),
                          ),
                        )
                      : _buildMonthsList(context, monthsList),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthsList(BuildContext context, List monthsList) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView.builder(
      itemCount: monthsList.length,
      itemBuilder: (context, index) {
        final mData = monthsList[index] as Map<String, dynamic>;
        final mYear = mData['year'] as int;
        final mMonth = mData['month'] as int;
        final consumptionList = mData['consumption'] as List? ?? [];

        if (consumptionList.isEmpty) return const SizedBox.shrink();

        int monthTotalPages = 0;
        int monthTotalClients = 0;
        int monthEnteredBranches = 0;
        for (final b in consumptionList) {
          final pages = _asInt(b['totalPages']);
          monthTotalPages += pages;
          final key = "${b['branchId'] ?? b['branchCode']}_${mYear}_$mMonth";
          final enteredClients = _branchClientsMap[key];
          if (enteredClients != null) {
            monthTotalClients += enteredClients;
            monthEnteredBranches += 1;
          }
        }

        final double monthTotalReams = monthTotalPages / _sheetsPerReam;
        final bool hasMonthClients = monthEnteredBranches > 0;
        final int monthExpectedPages = hasMonthClients
            ? monthTotalClients * _sheetsPerClient
            : 0;
        final int monthVariancePages = hasMonthClients
            ? monthTotalPages - monthExpectedPages
            : 0;
        final double monthVarianceReams = monthVariancePages / _sheetsPerReam;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: index == 0 || monthsList.length == 1,
              title: Row(
                children: [
                  Text(
                    'استهلاك ${_getMonthName(mMonth)} $mYear',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '📄 $monthTotalPages صفحة | 📦 ${monthTotalReams.toStringAsFixed(2)} رزمة',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.tertiaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '👥 $monthTotalClients عميل',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: colors.onTertiaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: !hasMonthClients
                          ? colors.surfaceContainerHighest.withValues(
                              alpha: 0.45,
                            )
                          : monthVariancePages > 0
                          ? Colors.red.withValues(alpha: 0.15)
                          : monthVariancePages < 0
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: !hasMonthClients
                            ? colors.outlineVariant
                            : monthVariancePages > 0
                            ? Colors.red.withValues(alpha: 0.4)
                            : monthVariancePages < 0
                            ? Colors.green.withValues(alpha: 0.4)
                            : Colors.blue.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      !hasMonthClients
                          ? 'أدخل عدد العملاء لحساب الفرق'
                          : monthVariancePages > 0
                          ? '⚠️ +$monthVariancePages ورقة (+${monthVarianceReams.toStringAsFixed(2)} رزمة هدر)'
                          : monthVariancePages < 0
                          ? '✅ $monthVariancePages ورقة توفير'
                          : '✨ استهلاك مطابق 100%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: !hasMonthClients
                            ? colors.onSurfaceVariant
                            : monthVariancePages > 0
                            ? Colors.red.shade800
                            : monthVariancePages < 0
                            ? Colors.green.shade800
                            : Colors.blue.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              children: [
                _buildDataTable(
                  context,
                  consumptionList,
                  year: mYear,
                  month: mMonth,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDataTable(
    BuildContext context,
    List consumptionList, {
    int? year,
    int? month,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (_selectedBranchId == null) {
      return Column(
        children: [
          Container(
            color: colors.primary.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: const [
                Expanded(
                  flex: 2,
                  child: Text(
                    'كود الفرع',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'اسم الفرع',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'الصفحات والمطبوعات',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'استهلاك الرزم (500 ورقة)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'عدد العملاء (يدوي/مقدر)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    'المستهدف (16 ورقة/عميل) والفرق',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...consumptionList.map((b) {
            final branchIdKey =
                "${b['branchId'] ?? b['branchCode']}_${year ?? _fromYear}_${month ?? _fromMonth}";
            final totalPages = _asInt(b['totalPages']);
            final monoPages = _asInt(b['monoPages']);
            final colorPages = _asInt(b['colorPages']);

            final estimatedClients = _estimatedClientsCeil(totalPages);
            final currentClients = _branchClientsMap[branchIdKey];
            final hasActualClients = currentClients != null;

            final double reamsExact = totalPages / _sheetsPerReam;
            final int fullReams = totalPages ~/ _sheetsPerReam;
            final int remPages = totalPages % _sheetsPerReam;
            final int requiredReams = _requiredReams(totalPages);

            final int expectedPages = hasActualClients
                ? currentClients * _sheetsPerClient
                : 0;
            final int variancePages = hasActualClients
                ? totalPages - expectedPages
                : 0;
            final double varianceReams = variancePages / _sheetsPerReam;

            return InkWell(
              onTap: () {
                setState(() => _selectedBranchId = b['branchId']?.toString());
                _loadData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        b['branchCode']?.toString() ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _fixText(b['branchName']?.toString() ?? '-'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$totalPages صفحة',
                            style: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                          Text(
                            '${b['printersCount'] ?? 0} طابعة ($monoPages أسود | $colorPages ألوان)',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${reamsExact.toStringAsFixed(2)} رزمة',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: Colors.deepOrange,
                            ),
                          ),
                          Text(
                            '($fullReams رزمة و $remPages ورقة)',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            'مطلوب محاسبيًا: $requiredReams رزمة',
                            style: TextStyle(fontSize: 11, color: colors.error),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        width: 90,
                        child: TextFormField(
                          initialValue: currentClients?.toString() ?? '',
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            hintText: estimatedClients.toString(),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            suffixText: 'عميل',
                            suffixStyle: const TextStyle(fontSize: 11),
                          ),
                          onChanged: (val) {
                            final trimmed = val.trim();
                            if (trimmed.isEmpty) {
                              setState(() {
                                _branchClientsMap.remove(branchIdKey);
                              });
                              return;
                            }
                            final parsed = int.tryParse(trimmed);
                            if (parsed != null && parsed >= 0) {
                              setState(() {
                                _branchClientsMap[branchIdKey] = parsed;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: !hasActualClients
                              ? colors.surfaceContainerHighest.withValues(
                                  alpha: 0.45,
                                )
                              : variancePages > 0
                              ? Colors.red.withValues(alpha: 0.08)
                              : variancePages < 0
                              ? Colors.green.withValues(alpha: 0.08)
                              : Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: !hasActualClients
                                ? colors.outlineVariant
                                : variancePages > 0
                                ? Colors.red.withValues(alpha: 0.3)
                                : variancePages < 0
                                ? Colors.green.withValues(alpha: 0.3)
                                : Colors.blue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'المستهدف: $expectedPages صفحة (${(expectedPages / _sheetsPerReam).toStringAsFixed(2)} رزمة)',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              !hasActualClients
                                  ? 'أدخل عدد العملاء الفعلي لحساب المستهدف والفرق'
                                  : variancePages > 0
                                  ? '⚠️ زيادة / هدر: +$variancePages ورقة (+${varianceReams.toStringAsFixed(2)} رزمة)'
                                  : variancePages < 0
                                  ? '✅ توفير: $variancePages ورقة (${varianceReams.toStringAsFixed(2)} رزمة)'
                                  : '✨ مطابق تماماً 100%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: !hasActualClients
                                    ? colors.onSurfaceVariant
                                    : variancePages > 0
                                    ? Colors.red.shade800
                                    : variancePages < 0
                                    ? Colors.green.shade800
                                    : Colors.blue.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      );
    } else {
      final printers = <Map<String, dynamic>>[];
      for (final b in consumptionList) {
        final prList = b['printers'] as List?;
        if (prList != null) {
          for (final p in prList) {
            if (p is Map<String, dynamic>) printers.add(p);
          }
        }
      }

      if (printers.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(
            child: Text('لا توجد طابعات مسجلة في هذا الفرع للفترة المحددة.'),
          ),
        );
      }

      return Column(
        children: [
          Container(
            color: colors.primary.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: const [
                Expanded(
                  flex: 3,
                  child: Text(
                    'اسم الطابعة',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'IP Address',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'الموديل',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'أبيض وأسود',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'ملون',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'الإجمالي (صفحة)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'استهلاك الرزم (500 ورقة)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'العملاء المقدرون (16 ورقة)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...printers.map((p) {
            final totalPages = _asInt(p['totalPages']);
            final double reams = totalPages / _sheetsPerReam;
            final int fullReams = totalPages ~/ _sheetsPerReam;
            final int remPages = totalPages % _sheetsPerReam;
            final int requiredReams = _requiredReams(totalPages);
            final int estClients = _estimatedClientsCeil(totalPages);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      _fixText(p['printerName']?.toString() ?? '-'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(p['ipAddress']?.toString() ?? '-'),
                  ),
                  Expanded(flex: 2, child: Text(p['model']?.toString() ?? '-')),
                  Expanded(
                    flex: 2,
                    child: Text((p['monoPages'] ?? 0).toString()),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text((p['colorPages'] ?? 0).toString()),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      totalPages.toString(),
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '${reams.toStringAsFixed(2)} رزمة '
                      '($fullReams رزمة و$remPages ورقة) | '
                      'مطلوب $requiredReams',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '$estClients عميل',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      );
    }
  }
}
