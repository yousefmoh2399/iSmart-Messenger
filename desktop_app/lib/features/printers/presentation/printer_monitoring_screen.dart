import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../../../shared/providers/providers.dart';
import '../../reports/presentation/custom_report_export_dialog.dart';
import '../../reports/presentation/report_templates_controller.dart';
import '../../reports/presentation/report_templates_screen.dart';
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

  Future<void> _openCustomExportDialog({String defaultFormat = 'xlsx'}) async {
    final result = await CustomReportExportDialog.show(
      context: context,
      reportType: 'printer_consumption',
      title: 'تصدير تقرير الطابعات ${_selectedBranchId == null ? "(كل الفروع)" : ""}',
    );
    if (result != null) {
      await _run(
        () => ref.read(printerControllerProvider.notifier).exportReport(
          format: result.format,
          type: _selectedBranchId == null ? 'global' : 'branch',
          branchId: _selectedBranchId,
          templateId: result.templateId,
        ),
        'تم تصدير تقرير الطابعات بصيغة ${result.format.toUpperCase()} بنجاح.',
      );
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


  String _generateDesktopThermalTestReceiptHtml({
    required String printerName,
    required String ipAddress,
    required String branchName,
    required String status,
    required num totalPages,
  }) {
    final now = DateTime.now();
    final timestampStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    return '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="utf-8">
<title>اختبار الطابعة الحرارية</title>
<style>
  @page { size: 80mm auto; margin: 0; }
  body {
    font-family: 'Segoe UI', Tahoma, Arial, sans-serif;
    width: 72mm; max-width: 290px; margin: 0 auto; padding: 8px 6px;
    color: #000; background: #fff; font-size: 12px; line-height: 1.35;
    -webkit-print-color-adjust: exact;
  }
  .receipt-header { text-align: center; border-bottom: 2px dashed #000; padding-bottom: 6px; margin-bottom: 8px; }
  .brand-title { font-size: 17px; font-weight: 900; letter-spacing: 0.5px; margin: 2px 0; }
  .brand-sub { font-size: 11px; font-weight: 600; color: #333; }
  .receipt-title {
    font-size: 13px; font-weight: 800; margin-top: 6px; padding: 2px 4px;
    background: #000; color: #fff; display: inline-block; border-radius: 3px;
  }
  .data-grid { margin: 8px 0; }
  .data-row { display: flex; justify-content: space-between; margin: 3px 0; font-size: 11.5px; }
  .data-row .k { font-weight: 700; color: #222; }
  .data-row .v { font-weight: 600; direction: ltr; text-align: left; }
  .dash-sep { border-top: 1px dashed #000; margin: 7px 0; }
  .test-box { border: 1px solid #000; padding: 6px 4px; margin: 7px 0; text-align: center; background: #fafafa; }
  .test-title { font-size: 10.5px; font-weight: bold; margin-bottom: 4px; }
  .test-sample { font-family: 'Courier New', Courier, monospace; font-size: 10px; letter-spacing: 0.5px; line-height: 1.25; }
  .solid-bar { background: #000; height: 9px; margin: 6px 0 2px 0; }
  .bar-caption { font-size: 9px; color: #444; }
  .status-verdict { text-align: center; font-size: 12px; font-weight: 900; border: 2px solid #000; padding: 5px; margin: 8px 0; letter-spacing: 0.5px; }
  .receipt-footer { text-align: center; border-top: 2px dashed #000; padding-top: 6px; margin-top: 6px; font-size: 10px; color: #333; }
</style>
</head>
<body>
  <div class="receipt-header">
    <div class="brand-title">iSmart Messenger</div>
    <div class="brand-sub">نظام إدارة ومراقبة الطابعات الذكية</div>
    <div class="receipt-title">ورقة اختبار حرارية فورية</div>
  </div>
  <div class="data-grid">
    <div class="data-row"><span class="k">الطابعة:</span><span class="v">$printerName</span></div>
    <div class="data-row"><span class="k">عنوان IP:</span><span class="v">$ipAddress</span></div>
    <div class="data-row"><span class="k">الفرع:</span><span class="v">$branchName</span></div>
    <div class="data-row"><span class="k">الحالة:</span><span class="v">$status</span></div>
    <div class="data-row"><span class="k">العداد الإجمالي:</span><span class="v">$totalPages ورقة</span></div>
    <div class="data-row"><span class="k">تاريخ الاختبار:</span><span class="v">$timestampStr</span></div>
  </div>
  <div class="dash-sep"></div>
  <div class="test-box">
    <div class="test-title">[ فحص محاذاة وجودة الرأس الحراري ]</div>
    <div class="test-sample">
      0123456789 - ABCDEFGHIJKLMNOPQRSTUVWXYZ<br>
      أ ب ت ث ج ح خ د ذ ر ز س ش ص ض ط ظ ع غ<br>
      !@#\$%^&*()_+=-[]{};':",./&lt;&gt;?
    </div>
    <div class="solid-bar"></div>
    <div class="bar-caption">فحص كثافة الحبر والخطوط الحرارية 100%</div>
  </div>
  <div class="status-verdict">[ ✓ PRINTER HARDWARE TEST PASSED ]</div>
  <div class="receipt-footer">
    تم إصدار ورقة الفحص بنجاح بنقرة واحدة من لوحة التحكم<br>
    iSmart Unified Desktop Print Engine
  </div>
</body>
</html>
''';
  }

  Future<void> _printTestReceipt(PrinterItem printer) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final totalPages = printer.lifetimeCounters['totalPages'] ?? 0;
      final html = _generateDesktopThermalTestReceiptHtml(
        printerName: printer.name,
        ipAddress: printer.ipAddress,
        branchName: printer.branchName,
        status: printer.status == 'online' ? '🟢 متصلة وجاهزة' : '🔴 غير متصلة',
        totalPages: totalPages,
      );
      final bytes = utf8.encode(html);
      await web_bridge.printBytes(
        bytes: bytes,
        fileName: 'thermal_test_${printer.name.replaceAll(' ', '_')}.html',
        mimeType: 'text/html',
        printerName: printer.name,
      );
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            backgroundColor: const Color(0xFF10B981),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text('تم إرسال ورقة الاختبار الحرارية إلى الطابعة "${printer.name}" بنجاح.'),
              ],
            ),
          ),
        );
    } catch (err) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            backgroundColor: const Color(0xFFDC2626),
            content: Text('تعذر إرسال أمر الطباعة: $err'),
          ),
        );
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
    final authUser = ref.read(authControllerProvider).valueOrNull;
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
            isAdmin: authUser?.isAdmin == true,
            onExportReport:
                (format, branchId, fromMonth, fromYear, toMonth, toYear, templateId, sheetsPerClient) async {
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
                          templateId: templateId,
                          sheetsPerClient: sheetsPerClient,
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
              ? () => _openCustomExportDialog(defaultFormat: 'pdf')
              : null,
          onExportExcel: canExport
              ? () => _openCustomExportDialog(defaultFormat: 'xlsx')
              : null,
          onOpenReportTemplates: authUser?.isAdmin == true
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ReportTemplatesScreen(
                        initialReportType: 'printer_consumption',
                      ),
                    ),
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
    this.onTestPrint,
    this.onOpenReportTemplates,
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
  final ValueChanged<PrinterItem>? onTestPrint;
  final VoidCallback? onOpenReportTemplates;

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
            if (data.isOffline)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.wifi_off_rounded, color: colors.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'الخادم غير متاح حالياً. يتم عرض بيانات مخزنة وقد لا تكون الأحدث.',
                        style: TextStyle(color: colors.onErrorContainer, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Consumer(
                      builder: (context, ref, child) {
                        return FilledButton.icon(
                          onPressed: () => ref.read(printerControllerProvider.notifier).refresh(),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('إعادة المحاولة'),
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.error,
                            foregroundColor: colors.onError,
                            visualDensity: VisualDensity.compact,
                          ),
                        );
                      }
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1C1C1E)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Theme.of(context).brightness == Brightness.dark
                    ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                    : Border.all(color: Colors.black.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.print_rounded,
                      color: Color(0xFF007AFF),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'إدارة ومراقبة الطابعات',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'مراقبة فورية لأجهزة الطباعة، استهلاك الورق، ومستوى الأحبار عبر بروتوكول SNMP',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _ActionButton(
                        icon: fullSyncRunning
                            ? Icons.stop_circle_rounded
                            : Icons.refresh_rounded,
                        label: fullSyncRunning ? 'إيقاف المزامنة' : 'مزامنة الشبكة',
                        busy: busy,
                        onPressed: fullSyncRunning ? onStopFullSync : onFullSync,
                      ),
                      _ActionButton(
                        icon: Icons.calendar_month_rounded,
                        label: 'الاستهلاك الشهري والمحاسبة',
                        busy: busy,
                        onPressed: onShowMonthlyConsumption,
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
                      if (authUser?.isAdmin == true)
                        _ActionButton(
                          icon: Icons.tune_rounded,
                          label: 'قوالب التقارير',
                          busy: busy,
                          onPressed: onOpenReportTemplates,
                        ),
                      _ActionButton(
                        icon: Icons.add_rounded,
                        label: 'إضافة فرع',
                        busy: busy,
                        onPressed: onAddBranch,
                      ),
                    ],
                  ),
                ],
              ),
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
                      onTestPrint: onTestPrint,
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

class PrinterDetailsScreen extends ConsumerStatefulWidget {
  const PrinterDetailsScreen({super.key, required this.printer});

  final PrinterItem printer;

  @override
  ConsumerState<PrinterDetailsScreen> createState() =>
      _PrinterDetailsScreenState();
}

class _PrinterDetailsScreenState extends ConsumerState<PrinterDetailsScreen> {
  late PrinterItem _printer;
  int _selectedTab = 0;
  bool _isSyncing = false;
  bool _isExporting = false;
  bool _isPrintingTestReceipt = false;

  Future<void> _printThermalTestReceipt() async {
    if (_isPrintingTestReceipt) return;
    setState(() => _isPrintingTestReceipt = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final totalPages = _printer.lifetimeCounters['totalPages'] ?? 0;
      final html = '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="utf-8">
<title>اختبار الطابعة الحرارية</title>
<style>
  @page { size: 80mm auto; margin: 0; }
  body {
    font-family: 'Segoe UI', Tahoma, Arial, sans-serif;
    width: 72mm; max-width: 290px; margin: 0 auto; padding: 8px 6px;
    color: #000; background: #fff; font-size: 12px; line-height: 1.35;
    -webkit-print-color-adjust: exact;
  }
  .receipt-header { text-align: center; border-bottom: 2px dashed #000; padding-bottom: 6px; margin-bottom: 8px; }
  .brand-title { font-size: 17px; font-weight: 900; letter-spacing: 0.5px; margin: 2px 0; }
  .brand-sub { font-size: 11px; font-weight: 600; color: #333; }
  .receipt-title {
    font-size: 13px; font-weight: 800; margin-top: 6px; padding: 2px 4px;
    background: #000; color: #fff; display: inline-block; border-radius: 3px;
  }
  .data-grid { margin: 8px 0; }
  .data-row { display: flex; justify-content: space-between; margin: 3px 0; font-size: 11.5px; }
  .data-row .k { font-weight: 700; color: #222; }
  .data-row .v { font-weight: 600; direction: ltr; text-align: left; }
  .dash-sep { border-top: 1px dashed #000; margin: 7px 0; }
  .test-box { border: 1px solid #000; padding: 6px 4px; margin: 7px 0; text-align: center; background: #fafafa; }
  .test-title { font-size: 10.5px; font-weight: bold; margin-bottom: 4px; }
  .test-sample { font-family: 'Courier New', Courier, monospace; font-size: 10px; letter-spacing: 0.5px; line-height: 1.25; }
  .solid-bar { background: #000; height: 9px; margin: 6px 0 2px 0; }
  .bar-caption { font-size: 9px; color: #444; }
  .status-verdict { text-align: center; font-size: 12px; font-weight: 900; border: 2px solid #000; padding: 5px; margin: 8px 0; letter-spacing: 0.5px; }
  .receipt-footer { text-align: center; border-top: 2px dashed #000; padding-top: 6px; margin-top: 6px; font-size: 10px; color: #333; }
</style>
</head>
<body>
  <div class="receipt-header">
    <div class="brand-title">iSmart Messenger</div>
    <div class="brand-sub">نظام إدارة ومراقبة الطابعات الذكية</div>
    <div class="receipt-title">ورقة اختبار حرارية فورية</div>
  </div>
  <div class="data-grid">
    <div class="data-row"><span class="k">الطابعة:</span><span class="v">${_printer.name}</span></div>
    <div class="data-row"><span class="k">عنوان IP:</span><span class="v">${_printer.ipAddress}</span></div>
    <div class="data-row"><span class="k">الفرع:</span><span class="v">${_printer.branchName}</span></div>
    <div class="data-row"><span class="k">الحالة:</span><span class="v">${_printer.status == 'online' ? '🟢 متصلة وجاهزة' : '🔴 غير متصلة'}</span></div>
    <div class="data-row"><span class="k">العداد الإجمالي:</span><span class="v">$totalPages ورقة</span></div>
    <div class="data-row"><span class="k">تاريخ الاختبار:</span><span class="v">${DateTime.now().toString().split('.')[0]}</span></div>
  </div>
  <div class="dash-sep"></div>
  <div class="test-box">
    <div class="test-title">[ فحص محاذاة وجودة الرأس الحراري ]</div>
    <div class="test-sample">
      0123456789 - ABCDEFGHIJKLMNOPQRSTUVWXYZ<br>
      أ ب ت ث ج ح خ د ذ ر ز س ش ص ض ط ظ ع غ<br>
      !@#\$%^&*()_+=-[]{};':",./&lt;&gt;?
    </div>
    <div class="solid-bar"></div>
    <div class="bar-caption">فحص كثافة الحبر والخطوط الحرارية 100%</div>
  </div>
  <div class="status-verdict">[ ✓ PRINTER HARDWARE TEST PASSED ]</div>
  <div class="receipt-footer">
    تم إصدار ورقة الفحص بنجاح بنقرة واحدة من لوحة التحكم<br>
    iSmart Unified Desktop Print Engine
  </div>
</body>
</html>
''';
      final bytes = utf8.encode(html);
      await web_bridge.printBytes(
        bytes: bytes,
        fileName: 'thermal_test_${_printer.name.replaceAll(' ', '_')}.html',
        mimeType: 'text/html',
        printerName: _printer.name,
      );
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            backgroundColor: const Color(0xFF10B981),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text('تم إرسال ورقة الاختبار الحرارية إلى الطابعة "${_printer.name}" بنجاح.'),
              ],
            ),
          ),
        );
    } catch (err) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            backgroundColor: const Color(0xFFDC2626),
            content: Text('تعذر إرسال أمر الطباعة: $err'),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _isPrintingTestReceipt = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _printer = widget.printer;
  }

  Future<void> _refreshDetails() async {
    try {
      final details = await ref
          .read(printerRepositoryProvider)
          .fetchPrinterDetails(_printer.id);
      if (mounted) {
        setState(() {
          _printer = details.printer;
        });
      }
    } catch (_) {}
  }

  Future<void> _syncNow() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(printerControllerProvider.notifier)
          .syncPrinter(_printer.id);
      await _refreshDetails();
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            backgroundColor: const Color(0xFF16A34A),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  _fixText('تمت مزامنة بيانات الطابعة وتحديث العدادات والأحبار بنجاح.'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            backgroundColor: const Color(0xFFDC2626),
            content: Text(error.toString()),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _exportReport() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(printerRepositoryProvider)
          .exportPrinterReport(_printer.id);
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            backgroundColor: const Color(0xFF007AFF),
            content: Row(
              children: [
                const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  _fixText('تم تصدير تقرير الطابعة بصيغة PDF بنجاح.'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            backgroundColor: const Color(0xFFDC2626),
            content: Text(error.toString()),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _openWebUI() async {
    final ip = _printer.ipAddress.trim();
    if (ip.isEmpty) return;
    final uri = Uri.parse(ip.startsWith('http') ? ip : 'http://$ip');
    final messenger = ScaffoldMessenger.of(context);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('تعذر فتح الرابط: $uri'),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('خطأ أثناء فتح صفحة الطابعة: $e'),
            ),
          );
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    if (text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Row(
            children: [
              const Icon(Icons.copy_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('تم نسخ $label إلى الحافظة'),
            ],
          ),
        ),
      );
  }

  String _formatNumber(num? value) {
    if (value == null) return '0';
    final str = value.toInt().toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return str.replaceAllMapped(reg, (Match m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final extended = _printer.extendedDetails;
    final product = _asMap(extended['product']);
    final usage = _asMap(extended['usage']);
    final supplies = _asListOfMaps(extended['supplies']);
    final events = _asListOfMaps(extended['events']);
    final jobs = _asListOfMaps(extended['jobs']);
    final rawKeyValues = _asListOfMaps(extended['rawKeyValues']);

    final hasColorToner =
        _printer.tonerLevels['cyan'] != null ||
        _printer.tonerLevels['magenta'] != null ||
        _printer.tonerLevels['yellow'] != null;

    final hasScanner =
        (_printer.lifetimeCounters['scanPages'] ?? 0) > 0 ||
        (_printer.counters['scanPages'] ?? 0) > 0 ||
        _printer.model.toLowerCase().contains('taskalfa') ||
        _printer.model.toLowerCase().contains('mfp') ||
        _printer.model.toLowerCase().contains('m479') ||
        _printer.model.toLowerCase().contains('m227') ||
        _printer.model.toLowerCase().contains('m428');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFF7F8FA),
        appBar: _buildAppleAppBar(isDark),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          children: [
            // Apple Hero Device Card
            _buildAppleHeroCard(isDark),
            const SizedBox(height: 20),

            // macOS-Style Segmented Tab Bar
            _buildMacOSTabBar(isDark),
            const SizedBox(height: 20),

            // Tab Content (Expands naturally without height constraint)
            if (_selectedTab == 0)
              _buildUsageTab(isDark, hasScanner)
            else if (_selectedTab == 1)
              _buildTonerTab(isDark, hasColorToner, supplies)
            else if (_selectedTab == 2)
              _buildDeviceInfoTab(isDark, product, usage)
            else
              _buildMaintenanceTab(isDark, events, jobs, rawKeyValues),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppleAppBar(bool isDark) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161618) : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Back Button (Apple macOS pill style)
              Tooltip(
                message: 'العودة للوحة مراقبة الطابعات',
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF242426)
                          : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Title and Breadcrumbs
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'أسطول الطابعات والشبكة',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_left_rounded,
                          size: 14,
                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _printer.branchName.isEmpty ? 'المكتب الرئيسي' : _printer.branchName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _printer.name.isEmpty ? _printer.ipAddress : _printer.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildStatusDot(_printer.status),
                      ],
                    ),
                  ],
                ),
              ),

              // Actions
              if (_printer.ipAddress.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Tooltip(
                    message: 'فتح صفحة ويب الطابعة (Web UI) في المتصفح',
                    child: OutlinedButton.icon(
                      onPressed: _openWebUI,
                      icon: const Icon(Icons.language_rounded, size: 16),
                      label: const Text('صفحة الويب للمعدة'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? Colors.white : Colors.black87,
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.1),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),

              // Sync Button
              FilledButton.tonalIcon(
                onPressed: _isSyncing ? null : _syncNow,
                icon: _isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 17),
                label: Text(_isSyncing ? 'جارِ المزامنة...' : 'مزامنة فورية'),
                style: FilledButton.styleFrom(
                  backgroundColor: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFE5E5EA),
                  foregroundColor: isDark ? Colors.white : Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Instant Thermal Test Print Button
              FilledButton.icon(
                onPressed: _isPrintingTestReceipt ? null : _printThermalTestReceipt,
                icon: _isPrintingTestReceipt
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.receipt_long_rounded, size: 17),
                label: Text(
                  _isPrintingTestReceipt ? 'جارِ الطباعة...' : 'طباعة ورقة اختبار حرارية',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // PDF Export Button (Apple primary blue)
              FilledButton.icon(
                onPressed: _isExporting ? null : _exportReport,
                icon: _isExporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 17),
                label: Text(_isExporting ? 'جارِ التصدير...' : 'تقرير PDF'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusDot(String status) {
    final color = _printerStatusColor(status);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildAppleHeroCard(bool isDark) {
    final statusColor = _printerStatusColor(_printer.status);
    final totalLifetime = _printer.lifetimeCounters['totalPages'] ?? 0;
    final totalCurrent = _printer.counters['totalPages'] ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Crisp Printer Icon Tile
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF007AFF).withValues(alpha: 0.2),
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.print_rounded,
                color: Color(0xFF007AFF),
                size: 38,
              ),
            ),
          ),
          const SizedBox(width: 20),

          // Core Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _printer.name.isEmpty ? _printer.ipAddress : _printer.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _printer.vendor.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _printer.model.isEmpty ? 'طابعة شبكية عامة' : _printer.model,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),

                // Apple Meta Chips Row
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildMetaChip(
                      icon: Icons.settings_ethernet_rounded,
                      label: _printer.ipAddress,
                      isDark: isDark,
                      onTap: () => _copyToClipboard(_printer.ipAddress, 'عنوان IP'),
                      tooltip: 'انقر لنسخ عنوان IP',
                    ),
                    _buildMetaChip(
                      icon: Icons.location_on_outlined,
                      label: _printer.branchName.isEmpty ? 'المكتب الرئيسي' : _printer.branchName,
                      isDark: isDark,
                    ),
                    if (_printer.hostname.isNotEmpty)
                      _buildMetaChip(
                        icon: Icons.dns_outlined,
                        label: _printer.hostname,
                        isDark: isDark,
                        onTap: () => _copyToClipboard(_printer.hostname, 'اسم المضيف'),
                        tooltip: 'انقر لنسخ Hostname',
                      ),
                    if (_printer.lastSyncAt != null)
                      _buildMetaChip(
                        icon: Icons.schedule_rounded,
                        label: 'آخر مزامنة: ${_dateText(_printer.lastSyncAt)}',
                        isDark: isDark,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),

          // Status & Quick Health Overview
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Apple Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: isDark ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _fixText(_printerStatus(_printer.status)),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Lifetime Total Counter Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF242426) : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.speed_rounded,
                      size: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'إجمالي العمر: ${_formatNumber(totalLifetime)} صفحة',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.grey[300] : Colors.grey[800],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Current Cycle Counter
              Text(
                'العداد الحالي: ${_formatNumber(totalCurrent)} صفحة',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String label,
    required bool isDark,
    VoidCallback? onTap,
    String? tooltip,
  }) {
    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242426) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[300] : Colors.grey[800],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 5),
            Icon(
              Icons.copy_rounded,
              size: 11,
              color: isDark ? Colors.grey[500] : Colors.grey[500],
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      chip = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: chip,
      );
    }

    if (tooltip != null) {
      chip = Tooltip(message: tooltip, child: chip);
    }

    return chip;
  }

  Widget _buildMacOSTabBar(bool isDark) {
    final tabs = [
      {'title': 'العدادات والاستهلاك', 'icon': Icons.speed_rounded},
      {'title': 'خراطيش الحبر والمستلزمات', 'icon': Icons.water_drop_rounded},
      {'title': 'مواصفات الجهاز والشبكة', 'icon': Icons.settings_ethernet_rounded},
      {'title': 'سجلات الصيانة والأعطال', 'icon': Icons.build_circle_outlined},
    ];

    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: _buildMacOSTabItem(
                title: tabs[i]['title'] as String,
                icon: tabs[i]['icon'] as IconData,
                isSelected: _selectedTab == i,
                isDark: isDark,
                onTap: () => setState(() => _selectedTab = i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMacOSTabItem({
    required String title,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF2C2C2E) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1.5),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? (isDark ? Colors.white : const Color(0xFF007AFF))
                  : (isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.grey[400] : Colors.grey[600]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: العدادات والاستهلاك
  // -------------------------------------------------------------
  Widget _buildUsageTab(bool isDark, bool hasScanner) {
    final totalPages = _printer.lifetimeCounters['totalPages'] ?? 0;
    final monoPages = _printer.lifetimeCounters['monoPages'] ?? 0;
    final colorPages = _printer.lifetimeCounters['colorPages'] ?? 0;
    final duplexPages = _printer.lifetimeCounters['duplexPages'] ?? 0;
    final copyPages = _printer.lifetimeCounters['copyPages'] ?? 0;
    final currentPages = _printer.counters['totalPages'] ?? 0;

    final monoPercent = totalPages > 0 ? ((monoPages / totalPages) * 100).toStringAsFixed(1) : '0';
    final colorPercent = totalPages > 0 ? ((colorPages / totalPages) * 100).toStringAsFixed(1) : '0';
    final duplexPercent = totalPages > 0 ? ((duplexPages / totalPages) * 100).toStringAsFixed(1) : '0';
    final paperSavedSheets = (duplexPages / 2).floor();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 18,
              color: isDark ? Colors.grey[400] : Colors.grey[700],
            ),
            const SizedBox(width: 8),
            Text(
              'العدادات الرسمية لصفحات عمر الطابعة ودورة الفحص الحالية:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.grey[300] : Colors.grey[800],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 6 Apple Metric Cards Grid
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth < 900 ? 2 : 3;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: crossAxisCount == 3 ? 2.1 : 1.9,
              children: [
                _buildAppleMetricCard(
                  isDark: isDark,
                  title: 'إجمالي صفحات عمر الطابعة',
                  value: _formatNumber(totalPages),
                  subtitle: 'إجمالي المطبوعات منذ بدء تشغيل الماكينة',
                  icon: Icons.print_rounded,
                  accentColor: const Color(0xFF5856D6), // Apple Purple
                  badgeText: 'العداد الكلي',
                ),
                _buildAppleMetricCard(
                  isDark: isDark,
                  title: 'العداد الحالي للدورة',
                  value: _formatNumber(currentPages),
                  subtitle: 'منذ آخر دورة صيانة أو تصفير للفترة',
                  icon: Icons.speed_rounded,
                  accentColor: const Color(0xFF007AFF), // Apple Blue
                  badgeText: 'الدورة النشطة',
                ),
                _buildAppleMetricCard(
                  isDark: isDark,
                  title: 'صفحات أحادية اللون (أسود)',
                  value: _formatNumber(monoPages),
                  subtitle: 'تشكل $monoPercent% من إجمالي المطبوعات',
                  icon: Icons.contrast_rounded,
                  accentColor: const Color(0xFF64748B), // Apple Slate
                  badgeText: '$monoPercent%',
                ),
                _buildAppleMetricCard(
                  isDark: isDark,
                  title: 'صفحات ملونة بالكامل (Color)',
                  value: _formatNumber(colorPages),
                  subtitle: 'تشكل $colorPercent% من إجمالي المطبوعات',
                  icon: Icons.palette_outlined,
                  accentColor: const Color(0xFFFF9500), // Apple Orange
                  badgeText: '$colorPercent%',
                ),
                _buildAppleMetricCard(
                  isDark: isDark,
                  title: 'طباعة على الوجهين (Duplex)',
                  value: _formatNumber(duplexPages),
                  subtitle: 'وفرت $paperSavedSheets ورقة بنظام الوجهين التلقائي',
                  icon: Icons.auto_stories_outlined,
                  accentColor: const Color(0xFF34C759), // Apple Green
                  badgeText: 'توفير $duplexPercent%',
                ),
                _buildAppleMetricCard(
                  isDark: isDark,
                  title: 'صفحات التصوير والنسخ (Copy)',
                  value: _formatNumber(copyPages),
                  subtitle: 'المستندات المصورة عبر وحدة النسخ بالماكينة',
                  icon: Icons.copy_all_rounded,
                  accentColor: const Color(0xFF00C7BE), // Apple Cyan
                  badgeText: 'نسخ ضوئي',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),

        // Scanner Stats Block (for MFP / TaskAlfa models)
        if (hasScanner) ...[
          _buildAppleScannerCard(isDark),
          const SizedBox(height: 20),
        ] else ...[
          _buildNoScannerBanner(isDark),
          const SizedBox(height: 20),
        ],

        // Duplex & Eco Efficiency Card
        _buildAppleEcoCard(
          isDark: isDark,
          duplexPages: duplexPages,
          totalPages: totalPages,
          paperSavedSheets: paperSavedSheets,
          duplexPercent: duplexPercent,
        ),
      ],
    );
  }

  Widget _buildAppleMetricCard({
    required bool isDark,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    String? badgeText,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: isDark ? 0.15 : 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAppleScannerCard(bool isDark) {
    final lifetimeScans = _printer.lifetimeCounters['scanPages'] ?? 0;
    final currentScans = _printer.counters['scanPages'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF30B0C7).withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF30B0C7).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF30B0C7).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.scanner_rounded,
              color: Color(0xFF30B0C7),
              size: 32,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      'إحصائيات الماسح الضوئي المتقدم (Multifunction Scanner)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF30B0C7),
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.verified_rounded, size: 16, color: Color(0xFF30B0C7)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'هذه الطابعة مجهزة بوحدة تغذية تلقائية للمستندات (ADF) ولوحة مسح ضوئي زجاجية مسطحة. '
                  'تم إنجاز ${_formatNumber(lifetimeScans)} عملية مسح ضوئي إجمالاً، ومسح ${_formatNumber(currentScans)} صفحة خلال دورة الفحص الحالية.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[300] : const Color(0xFF0F5B66),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF30B0C7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatNumber(lifetimeScans),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'عملية مسح ضوئي',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoScannerBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            size: 22,
          ),
          const SizedBox(width: 12),
          Text(
            'هذا الطراز مسجل كطابعة أحادية الغرض (Single Function Printer) ولا يحتوي على ماسح ضوئي.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey[400] : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppleEcoCard({
    required bool isDark,
    required num duplexPages,
    required num totalPages,
    required int paperSavedSheets,
    required String duplexPercent,
  }) {
    final progress = totalPages > 0 ? (duplexPages / totalPages).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.eco_rounded,
                  color: Color(0xFF34C759),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'كفاءة الطباعة المزدوجة وتوفير الورق (Eco & Duplex Efficiency)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'تم توفير ما يعادل $paperSavedSheets ورقة كاملة (~${(paperSavedSheets / 500).toStringAsFixed(1)} رزمة ورقية) عبر الطباعة التلقائية على الوجهين.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$duplexPercent%',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF34C759),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.toDouble(),
              minHeight: 8,
              backgroundColor: isDark
                  ? const Color(0xFF2C2C2E)
                  : const Color(0xFFE5E5EA),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34C759)),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 2: خراطيش الحبر والمستلزمات
  // -------------------------------------------------------------
  Widget _buildTonerTab(
    bool isDark,
    bool hasColorToner,
    List<Map<String, dynamic>> supplies,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.water_drop_rounded,
              size: 18,
              color: isDark ? Colors.grey[400] : Colors.grey[700],
            ),
            const SizedBox(width: 8),
            Text(
              'حالة ومستويات خراطيش الحبر المتبقية بنظام القياس اللحظي (CMYK):',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.grey[300] : Colors.grey[800],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Apple Liquid Glass Capsule Gauges
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildAppleTonerCapsule(
                colorName: 'أسود Black',
                colorCode: 'K',
                value: _printer.tonerLevels['black'],
                gradientColors: const [Color(0xFF1E293B), Color(0xFF0F172A)],
                isDark: isDark,
              ),
              if (hasColorToner) ...[
                _buildAppleTonerCapsule(
                  colorName: 'سماوي Cyan',
                  colorCode: 'C',
                  value: _printer.tonerLevels['cyan'],
                  gradientColors: const [Color(0xFF06B6D4), Color(0xFF0284C7)],
                  isDark: isDark,
                ),
                _buildAppleTonerCapsule(
                  colorName: 'أرجواني Magenta',
                  colorCode: 'M',
                  value: _printer.tonerLevels['magenta'],
                  gradientColors: const [Color(0xFFEC4899), Color(0xFFBE185D)],
                  isDark: isDark,
                ),
                _buildAppleTonerCapsule(
                  colorName: 'أصفر Yellow',
                  colorCode: 'Y',
                  value: _printer.tonerLevels['yellow'],
                  gradientColors: const [Color(0xFFFACC15), Color(0xFFEAB308)],
                  isDark: isDark,
                ),
              ] else ...[
                // Informational Mono Card
                Container(
                  width: 380,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF242426) : const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.opacity_rounded,
                          size: 36,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'طابعة أحادية اللون (Monochrome)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'هذا الطراز يدعم خرطوشة حبر سوداء واحدة فقط ذات سعة عالية. خراطيش الألوان (سماوي، أرجواني، أصفر) غير مدمجة في هذا الجهاز.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Supplies Inset Table
        if (supplies.isNotEmpty) ...[
          _DetailSection(
            title: 'تفاصيل الخراطيش والمستلزمات المسترجعة من الطابعة:',
            children: [
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
          ),
        ],
      ],
    );
  }

  Widget _buildAppleTonerCapsule({
    required String colorName,
    required String colorCode,
    required Object? value,
    required List<Color> gradientColors,
    required bool isDark,
  }) {
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
    final isCritical = number != null && number < 5;

    return Container(
      width: 145,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242426) : const Color(0xFFF9F9FB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCritical
              ? const Color(0xFFFF3B30)
              : isLow
                  ? const Color(0xFFFF9500)
                  : isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05),
          width: isCritical || isLow ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradientColors),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    colorCode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  colorName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Apple Liquid Capsule
          Container(
            width: 48,
            height: 150,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161618) : const Color(0xFFE5E5EA),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08),
                width: 1.5,
              ),
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Liquid fill
                FractionallySizedBox(
                  heightFactor: level,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradientColors,
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: const Radius.circular(22),
                        bottomRight: const Radius.circular(22),
                        topLeft: Radius.circular(level > 0.95 ? 22 : 4),
                        topRight: Radius.circular(level > 0.95 ? 22 : 4),
                      ),
                    ),
                  ),
                ),

                // Glass Specular Shine Overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.25),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.05),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Percentage Number
          Text(
            number == null ? 'غير متوفر' : '${number.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: isCritical
                  ? const Color(0xFFFF3B30)
                  : isLow
                      ? const Color(0xFFFF9500)
                      : (isDark ? Colors.white : Colors.black87),
            ),
          ),
          const SizedBox(height: 6),

          // Status Badge Pill
          _buildTonerStatusPill(number),
        ],
      ),
    );
  }

  Widget _buildTonerStatusPill(num? number) {
    if (number == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'غير مقاس',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
      );
    }

    if (number < 5) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'فارغ تقريبًا ⚠️',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Color(0xFFFF3B30),
          ),
        ),
      );
    }

    if (number < 15) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFF9500).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'حبر منخفض ⚠️',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Color(0xFFFF9500),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF34C759).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'مستوى آمن ✓',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Color(0xFF34C759),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 3: مواصفات الجهاز والشبكة
  // -------------------------------------------------------------
  Widget _buildDeviceInfoTab(
    bool isDark,
    Map<String, dynamic> product,
    Map<String, dynamic> usage,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailSection(
          title: 'معلومات تعريف الجهاز والهوية المصنعية:',
          children: [
            _buildAppleSettingsRow(
              icon: Icons.print_rounded,
              label: 'اسم المنتج والموديل',
              value: _printer.model.isEmpty ? 'طابعة غير محددة' : _printer.model,
              isDark: isDark,
            ),
            _buildAppleSettingsRow(
              icon: Icons.tag_rounded,
              label: 'الرقم التسلسلي للمصنع (Serial Number)',
              value: _printer.serialNumber,
              isDark: isDark,
              onCopy: () => _copyToClipboard(_printer.serialNumber, 'الرقم التسلسلي'),
            ),
            _buildAppleSettingsRow(
              icon: Icons.business_rounded,
              label: 'الشركة المصنعة (Vendor)',
              value: _printer.vendor,
              isDark: isDark,
            ),
            _buildAppleSettingsRow(
              icon: Icons.settings_ethernet_rounded,
              label: 'عنوان الشبكة IP Address',
              value: _printer.ipAddress,
              isDark: isDark,
              onCopy: () => _copyToClipboard(_printer.ipAddress, 'عنوان IP'),
            ),
            _buildAppleSettingsRow(
              icon: Icons.dns_outlined,
              label: 'اسم المضيف Hostname',
              value: _printer.hostname,
              isDark: isDark,
              onCopy: () => _copyToClipboard(_printer.hostname, 'اسم المضيف'),
            ),
            _buildAppleSettingsRow(
              icon: Icons.schedule_rounded,
              label: 'تاريخ ووقت المزامنة الأخيرة',
              value: _dateText(_printer.lastSyncAt),
              isDark: isDark,
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (product.isNotEmpty) ...[
          _DetailSection(
            title: 'تفاصيل البرمجيات الثابتة واللوحة الإلكترونية (Firmware & Board):',
            children: [
              ..._mapAppleLines(product, const {
                'productName': 'اسم المنتج البديل',
                'productNumber': 'رقم الموديل الداخلي',
                'serviceId': 'معرّف الصيانة الخاص (Service ID)',
                'firmwareVersion': 'إصدار نظام التشغيل الأساسي (Firmware)',
                'engineFirmware': 'البرنامج الثابت لمحرك الطباعة (Engine)',
                'region': 'الدولة والمنطقة المعتمدة',
                'memoryTotalKb': 'إجمالي الذاكرة العشوائية المتاحة (RAM KB)',
                'installedPersonalities': 'اللغات ولغات الوظائف المثبتة',
              }, isDark),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAppleSettingsRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
    VoidCallback? onCopy,
  }) {
    final cleanValue = value.trim().isEmpty ? '-' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF242426) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 260,
            child: Text(
              _fixText(label),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[400] : Colors.grey[700],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _fixText(cleanValue),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              textDirection: RegExp(r'^[a-zA-Z0-9.:/-]+$').hasMatch(cleanValue)
                  ? TextDirection.ltr
                  : null,
            ),
          ),
          if (onCopy != null && cleanValue != '-') ...[
            Tooltip(
              message: 'نسخ للقائمة',
              child: IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 14),
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _mapAppleLines(
    Map<String, dynamic> values,
    Map<String, String> labels,
    bool isDark,
  ) {
    final children = <Widget>[];
    for (final entry in labels.entries) {
      final value = _text(values[entry.key]);
      if (value.trim().isEmpty) continue;
      children.add(
        _buildAppleSettingsRow(
          icon: Icons.memory_rounded,
          label: entry.value,
          value: value,
          isDark: isDark,
        ),
      );
    }
    return children;
  }

  // -------------------------------------------------------------
  // TAB 4: سجلات الصيانة والأعطال
  // -------------------------------------------------------------
  Widget _buildMaintenanceTab(
    bool isDark,
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> jobs,
    List<Map<String, dynamic>> rawKeyValues,
  ) {
    final paperJams = _printer.maintenance['paperJams'] ?? 0;
    final errorMessages = _printer.maintenance['errorMessages'];
    final warnings = _printer.maintenance['warnings'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.build_circle_outlined,
              size: 18,
              color: isDark ? Colors.grey[400] : Colors.grey[700],
            ),
            const SizedBox(width: 8),
            Text(
              'حالة المستشعرات الميكانيكية وسجلات الأعطال والتحذيرات:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.grey[300] : Colors.grey[800],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Diagnostic KPI Strip
        Row(
          children: [
            Expanded(
              child: _buildDiagnosticTile(
                title: 'انحشارات الورق (Paper Jams)',
                value: '$paperJams',
                statusText: (paperJams is num && paperJams > 0)
                    ? 'تم تسجيل انحشار ورق'
                    : 'لا توجد انحشارات مسجلة ✓',
                icon: Icons.layers_clear_outlined,
                color: (paperJams is num && paperJams > 0)
                    ? const Color(0xFFFF9500)
                    : const Color(0xFF34C759),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildDiagnosticTile(
                title: 'رسائل الخطأ النشطة',
                value: errorMessages?.toString() ?? '0',
                statusText: errorMessages != null && errorMessages.toString() != '0' && errorMessages.toString().isNotEmpty
                    ? 'يلزم فحص فني'
                    : 'النظام يعمل بكفاءة ✓',
                icon: Icons.error_outline_rounded,
                color: errorMessages != null && errorMessages.toString() != '0' && errorMessages.toString().isNotEmpty
                    ? const Color(0xFFFF3B30)
                    : const Color(0xFF34C759),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildDiagnosticTile(
                title: 'التحذيرات والتنبيهات',
                value: warnings?.toString() ?? '0',
                statusText: warnings != null && warnings.toString() != '0' && warnings.toString().isNotEmpty
                    ? 'تنبيهات نشطة'
                    : 'المستشعرات بحالة طبيعية ✓',
                icon: Icons.warning_amber_rounded,
                color: warnings != null && warnings.toString() != '0' && warnings.toString().isNotEmpty
                    ? const Color(0xFFFF9500)
                    : const Color(0xFF007AFF),
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        if (events.isNotEmpty) ...[
          _DetailSection(
            title: 'سجل الأحداث البرمجية والتحذيرات (Event Log):',
            children: [
              _DetailDataTable(
                columns: const [
                  'الكود',
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
          const SizedBox(height: 20),
        ],

        if (jobs.isNotEmpty) ...[
          _DetailSection(
            title: 'آخر الوظائف المنفذة بالطابعة (Recent Jobs):',
            children: [
              _DetailDataTable(
                columns: const [
                  'اسم الوظيفة',
                  'المستخدم المُرسل',
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
        ] else if (events.isEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: Color(0xFF34C759),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'لا توجد سجلات أعطال أو بلاغات صيانة نشطة',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'الماكينة تعمل بحالة تشغيلية ممتازة وكافة مستشعرات التغذية والحبر طبيعية.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDiagnosticTile({
    required String title,
    required String value,
    required String statusText,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// Apple Inset Grouped Section & Tables
// -------------------------------------------------------------
class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _fixText(title),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 16),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _fixText(_printerStatus(status)),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
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
    final isDark = theme.brightness == Brightness.dark;

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Text(
          'لا توجد سجلات متاحة حاليًا',
          style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600]),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            isDark ? const Color(0xFF242426) : const Color(0xFFF2F2F7),
          ),
          headingRowHeight: 46,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 74,
          horizontalMargin: 16,
          columnSpacing: 24,
          columns: [
            for (final column in columns)
              DataColumn(
                label: Text(
                  column,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
          rows: [
            for (var rIdx = 0; rIdx < rows.length; rIdx++)
              DataRow(
                color: WidgetStateProperty.all(
                  rIdx % 2 == 1
                      ? (isDark
                          ? Colors.white.withValues(alpha: 0.02)
                          : Colors.black.withValues(alpha: 0.015))
                      : Colors.transparent,
                ),
                cells: [
                  for (var index = 0; index < columns.length; index += 1)
                    DataCell(
                      SizedBox(
                        width: columns.length <= 2 ? 380 : 160,
                        child: Text(
                          index < rows[rIdx].length && rows[rIdx][index].trim().isNotEmpty
                              ? rows[rIdx][index]
                              : '-',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: index == 0 ? FontWeight.w700 : FontWeight.w500,
                            color: isDark ? Colors.grey[300] : Colors.grey[800],
                          ),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final printersCount = (totals['printers'] ?? 0).toInt();
    final onlineCount = (totals['onlinePrinters'] ?? 0).toInt();
    final offlineCount = (totals['offlinePrinters'] ?? 0).toInt();
    final branchesCount = (totals['branches'] ?? 0).toInt();

    final monthlyPages = (totals['monthlyUsage'] ?? 0).toInt();
    final monthlyReams = monthlyPages / 500;

    final totalPages = (totals['totalPages'] ?? 0).toInt();
    final wastePages = (totals['wastePages'] ?? 0).toInt();

    final tonerAlerts = (totals['tonerAlerts'] ?? 0).toInt();

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 900 ? 2 : 4;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: crossAxisCount == 4 ? 2.35 : 2.1,
          children: [
            _buildStatCard(
              context: context,
              isDark: isDark,
              title: 'أسطول الطابعات والشبكة',
              value: '$printersCount طابعة',
              icon: Icons.print_rounded,
              iconColor: const Color(0xFF007AFF),
              bottomContent: Row(
                children: [
                  _buildMiniBadge(
                    dotColor: const Color(0xFF34C759),
                    text: '$onlineCount متصلة',
                    bgColor: const Color(0xFF34C759).withValues(alpha: 0.12),
                    textColor: isDark ? const Color(0xFF30D158) : const Color(0xFF248A3D),
                  ),
                  const SizedBox(width: 6),
                  _buildMiniBadge(
                    dotColor: offlineCount > 0 ? const Color(0xFFFF3B30) : const Color(0xFF8E8E93),
                    text: '$offlineCount غير متصلة',
                    bgColor: (offlineCount > 0 ? const Color(0xFFFF3B30) : const Color(0xFF8E8E93)).withValues(alpha: 0.1),
                    textColor: offlineCount > 0
                        ? (isDark ? const Color(0xFFFF453A) : const Color(0xFFD70015))
                        : Colors.grey,
                  ),
                  const Spacer(),
                  Text(
                    '$branchesCount فرع',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            _buildStatCard(
              context: context,
              isDark: isDark,
              title: 'استهلاك الشهر الحالي',
              value: '$monthlyPages ورقة',
              icon: Icons.calendar_month_rounded,
              iconColor: const Color(0xFF34C759),
              bottomContent: Row(
                children: [
                  _buildMiniBadge(
                    dotColor: const Color(0xFF34C759),
                    text: '~${monthlyReams.toStringAsFixed(1)} رزمة (500 ورقة)',
                    bgColor: const Color(0xFF34C759).withValues(alpha: 0.12),
                    textColor: isDark ? const Color(0xFF30D158) : const Color(0xFF248A3D),
                  ),
                ],
              ),
            ),
            _buildStatCard(
              context: context,
              isDark: isDark,
              title: 'إجمالي العداد التراكمي',
              value: '$totalPages صفحة',
              icon: Icons.speed_rounded,
              iconColor: const Color(0xFF5856D6),
              bottomContent: Row(
                children: [
                  _buildMiniBadge(
                    dotColor: wastePages > 0 ? const Color(0xFFFF9500) : const Color(0xFF5856D6),
                    text: 'الهالك المسجل: $wastePages ورقة',
                    bgColor: const Color(0xFF5856D6).withValues(alpha: 0.1),
                    textColor: isDark ? const Color(0xFF5E5CE6) : const Color(0xFF3634A3),
                  ),
                ],
              ),
            ),
            _buildStatCard(
              context: context,
              isDark: isDark,
              title: 'الأحبار والمستهلكات',
              value: tonerAlerts > 0 ? '$tonerAlerts تنبيه حبر' : 'المستويات آمنة',
              icon: Icons.opacity_rounded,
              iconColor: tonerAlerts > 0 ? const Color(0xFFFF9500) : const Color(0xFF007AFF),
              bottomContent: Row(
                children: [
                  if (tonerAlerts > 0)
                    _buildMiniBadge(
                      dotColor: const Color(0xFFFF9500),
                      text: 'يلزم استبدال أحبار قريباً',
                      bgColor: const Color(0xFFFF9500).withValues(alpha: 0.15),
                      textColor: isDark ? const Color(0xFFFF9F0A) : const Color(0xFFC93400),
                    )
                  else
                    _buildMiniBadge(
                      dotColor: const Color(0xFF34C759),
                      text: 'جميع الخراطيش بمستوى آمن ✓',
                      bgColor: const Color(0xFF34C759).withValues(alpha: 0.12),
                      textColor: isDark ? const Color(0xFF30D158) : const Color(0xFF248A3D),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required BuildContext context,
    required bool isDark,
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Widget bottomContent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.08))
            : Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomContent,
        ],
      ),
    );
  }

  Widget _buildMiniBadge({
    required Color dotColor,
    required String text,
    required Color bgColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
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
    this.onTestPrint,
  });

  final List<PrinterItem> printers;
  final String? selectedPrinterId;
  final ValueChanged<PrinterItem> onSelected;
  final ValueChanged<String>? onSyncPrinter;
  final ValueChanged<String>? onDeletePrinter;
  final ValueChanged<PrinterItem>? onTestPrint;

  Widget _buildVendorAvatar(PrinterItem printer, bool isOnline) {
    final brand = (printer.model + ' ' + printer.name).toLowerCase();
    String label = 'PRN';
    Color brandColor = const Color(0xFF007AFF);
    if (brand.contains('kyocera')) {
      label = 'KYO';
      brandColor = const Color(0xFFD32F2F);
    } else if (brand.contains('hp') || brand.contains('hewlett') || brand.contains('laserjet')) {
      label = 'HP';
      brandColor = const Color(0xFF0288D1);
    } else if (brand.contains('canon')) {
      label = 'CAN';
      brandColor = const Color(0xFFC2185B);
    } else if (brand.contains('brother')) {
      label = 'BRO';
      brandColor = const Color(0xFF1976D2);
    } else if (brand.contains('xerox')) {
      label = 'XRX';
      brandColor = const Color(0xFFE53935);
    } else if (brand.contains('ricoh')) {
      label = 'RIC';
      brandColor = const Color(0xFFE64A19);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: brandColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: brandColor.withValues(alpha: 0.2)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: brandColor,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Positioned(
          bottom: -1,
          left: -1,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: isOnline ? const Color(0xFF34C759) : const Color(0xFF8E8E93),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTonerCapsules(Map<String, dynamic> toner, bool isDark) {
    final keys = [
      ('black', 'K', const Color(0xFF1E293B)),
      ('cyan', 'C', const Color(0xFF0284C7)),
      ('magenta', 'M', const Color(0xFFDB2777)),
      ('yellow', 'Y', const Color(0xFFCA8A04)),
    ];

    final List<Widget> bars = [];
    for (final entry in keys) {
      final key = entry.$1;
      final label = entry.$2;
      final color = entry.$3;

      final val = toner[key];
      if (val == null) continue;
      num? numVal;
      if (val is num) {
        numVal = val;
      } else {
        numVal = num.tryParse(val.toString());
      }
      if (numVal == null) continue;

      final pct = numVal.clamp(0, 100);
      final isLow = pct < 15;

      bars.add(
        Tooltip(
          message: '$key: ${pct.toStringAsFixed(0)}%',
          child: Container(
            width: 48,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: isLow
                  ? Colors.red.withValues(alpha: 0.12)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05)),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isLow ? Colors.red : color.withValues(alpha: 0.3),
                width: isLow ? 1.5 : 1,
              ),
            ),
            child: Stack(
              children: [
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (pct / 100.0).clamp(0.05, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isLow
                          ? Colors.red.withValues(alpha: 0.4)
                          : color.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    '$label ${pct.toInt()}%',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: isLow
                          ? Colors.red
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (bars.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'بدون بيانات حبر',
          style: TextStyle(fontSize: 10, color: Colors.grey),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: bars);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
      title: 'قائمة الطابعات المسجلة (${printers.length})',
      child: ListView.separated(
        itemCount: printers.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: theme.dividerColor.withValues(alpha: 0.08),
        ),
        itemBuilder: (context, index) {
          final printer = printers[index];
          final isSelected = selectedPrinterId == printer.id;
          final isOnline = printer.status.toLowerCase() == 'online';

          return Container(
            color: isSelected
                ? const Color(0xFF007AFF).withValues(alpha: 0.08)
                : null,
            child: InkWell(
              onTap: () => onSelected(printer),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildVendorAvatar(printer, isOnline),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 10,
                        spacing: 12,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    printer.name.isEmpty
                                        ? printer.ipAddress
                                        : printer.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF007AFF)
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      printer.ipAddress,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF007AFF),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${printer.branchName} • ${printer.model} • S/N: ${printer.serialNumber}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildTonerCapsules(printer.tonerLevels, isDark),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.description_outlined,
                                        size: 14,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${(printer.lifetimeCounters['totalPages'] ?? 0).toInt()} ورقة',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if ((printer.lifetimeCounters['scanPages'] ?? 0) > 0)
                                    Text(
                                      'مسح: ${(printer.lifetimeCounters['scanPages'] ?? 0).toInt()}',
                                      style: const TextStyle(
                                        color: Colors.teal,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (onTestPrint != null)
                                    IconButton(
                                      iconSize: 20,
                                      tooltip: 'طباعة ورقة اختبار حرارية فورية',
                                      icon: const Icon(
                                        Icons.receipt_long_rounded,
                                        color: Color(0xFF10B981),
                                      ),
                                      onPressed: () => onTestPrint!(printer),
                                    ),
                                  if (onSyncPrinter != null)
                                    IconButton(
                                      iconSize: 20,
                                      tooltip: 'تحديث فوري (SNMP Sync)',
                                      icon: const Icon(Icons.sync_rounded),
                                      onPressed: () => onSyncPrinter!(printer.id),
                                    ),
                                  if (onDeletePrinter != null)
                                    IconButton(
                                      iconSize: 20,
                                      tooltip: 'حذف الطابعة',
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () => onDeletePrinter!(printer.id),
                                    ),
                                  const Icon(
                                    Icons.chevron_left_rounded,
                                    size: 20,
                                    color: Colors.grey,
                                  ),
                                ],
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
    this.isAdmin = false,
  });

  final int initialYear;
  final int initialMonth;
  final String? initialBranchId;
  final List<PrinterBranchItem> branches;
  final bool isAdmin;
  final Future<void> Function(
    String format,
    String? branchId,
    int fromMonth,
    int fromYear,
    int toMonth,
    int toYear,
    String? templateId,
    int? sheetsPerClient,
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
  String? _selectedTemplateId;
  bool _isLoading = false;
  Map<String, dynamic>? _consumptionData;
  String? _errorMessage;

  static const int _sheetsPerReam = 500;
  int _sheetsPerClient = 16;
  late final TextEditingController _sheetsPerClientController;
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
    _sheetsPerClient = 16;
    _sheetsPerClientController = TextEditingController(text: '16');
    _fromYear = widget.initialYear;
    _fromMonth = widget.initialMonth == 0 ? 1 : widget.initialMonth;
    _toYear = widget.initialYear;
    _toMonth = widget.initialMonth == 0 ? 12 : widget.initialMonth;
    _selectedBranchId = widget.initialBranchId;
    _loadData();
  }

  @override
  void dispose() {
    _sheetsPerClientController.dispose();
    super.dispose();
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
            sheetsPerClient: _sheetsPerClient,
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
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final templatesAsync = ref.watch(reportTemplatesProvider('printer_consumption'));
                            return templatesAsync.when(
                              data: (templates) => DropdownButtonFormField<String?>(
                                value: _selectedTemplateId,
                                isDense: true,
                                decoration: const InputDecoration(
                                  labelText: 'قالب التقرير (اختياري)',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('القالب الافتراضي'),
                                  ),
                                  ...templates.map(
                                    (t) => DropdownMenuItem<String?>(
                                      value: t.id,
                                      child: Text(t.name),
                                    ),
                                  ),
                                ],
                                onChanged: (val) => setState(() => _selectedTemplateId = val),
                              ),
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            );
                          },
                        ),
                      ),
                      if (widget.isAdmin)
                        IconButton(
                          tooltip: 'تخصيص قوالب التقارير',
                          icon: const Icon(Icons.tune_rounded),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ReportTemplatesScreen(
                                initialReportType: 'printer_consumption',
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 155,
                        child: TextFormField(
                          controller: _sheetsPerClientController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'ورقة / عميل',
                            hintText: '16',
                            prefixIcon: const Icon(Icons.description_outlined, size: 18),
                            suffixText: 'ورقة',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val.trim());
                            if (parsed != null && parsed > 0 && parsed != _sheetsPerClient) {
                              setState(() {
                                _sheetsPerClient = parsed;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
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
                          _selectedTemplateId,
                          _sheetsPerClient,
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
                          _selectedTemplateId,
                          _sheetsPerClient,
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
                      'ملاحظة المحاسبة الدقيقة: الرزمة = 500 ورقة | معدل استهلاك العميل المعتمد = $_sheetsPerClient ورقة. يمكنك تعديل هذا المعدل في الحقل أعلاه في أي وقت لحساب الفرق والعملاء والهدر تلقائياً.',
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
