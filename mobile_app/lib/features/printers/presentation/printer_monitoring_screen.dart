import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';

/// Enum representing the 4 Smart Status Signals requested for the printers.
enum _PrinterSmartStatus {
  onlineReady, // 🟢 متصلة وجاهزة
  paperLow, // 🟡 تنبيه: الورق شارف على النفاد
  tonerLow, // 🟠 الحبر منخفض
  offline, // 🔴 غير متصلة بالشبكة
}

extension _PrinterSmartStatusExt on _PrinterSmartStatus {
  String get label {
    switch (this) {
      case _PrinterSmartStatus.onlineReady:
        return 'متصلة وجاهزة';
      case _PrinterSmartStatus.paperLow:
        return 'تنبيه: الورق شارف على النفاد';
      case _PrinterSmartStatus.tonerLow:
        return 'تنبيه: الحبر منخفض';
      case _PrinterSmartStatus.offline:
        return 'غير متصلة بالشبكة';
    }
  }

  String get shortLabel {
    switch (this) {
      case _PrinterSmartStatus.onlineReady:
        return 'متصلة';
      case _PrinterSmartStatus.paperLow:
        return 'ورق منخفض';
      case _PrinterSmartStatus.tonerLow:
        return 'حبر منخفض';
      case _PrinterSmartStatus.offline:
        return 'غير متصلة';
    }
  }

  Color get color {
    switch (this) {
      case _PrinterSmartStatus.onlineReady:
        return const Color(0xFF10B981); // Emerald Green
      case _PrinterSmartStatus.paperLow:
        return const Color(0xFFF59E0B); // Amber Yellow
      case _PrinterSmartStatus.tonerLow:
        return const Color(0xFFF97316); // Orange
      case _PrinterSmartStatus.offline:
        return const Color(0xFFEF4444); // Red
    }
  }

  IconData get icon {
    switch (this) {
      case _PrinterSmartStatus.onlineReady:
        return Icons.check_circle_rounded;
      case _PrinterSmartStatus.paperLow:
        return Icons.description_outlined;
      case _PrinterSmartStatus.tonerLow:
        return Icons.opacity_rounded;
      case _PrinterSmartStatus.offline:
        return Icons.wifi_off_rounded;
    }
  }
}

class MobilePrinterMonitoringScreen extends ConsumerStatefulWidget {
  const MobilePrinterMonitoringScreen({super.key});

  @override
  ConsumerState<MobilePrinterMonitoringScreen> createState() =>
      _MobilePrinterMonitoringScreenState();
}

class _MobilePrinterMonitoringScreenState
    extends ConsumerState<MobilePrinterMonitoringScreen> {
  final Set<String> _printingPrinterIds = <String>{};
  int _selectedFilterIndex = 0; // 0: الكل, 1: متصلة, 2: تحذيرات, 3: غير متصلة

  _PrinterSmartStatus _resolveStatus(
    Map<String, dynamic> printer,
    List<Map<String, dynamic>> notifications,
  ) {
    final status = printer['status']?.toString().toLowerCase();
    final isOnline = status == 'online';
    if (!isOnline) {
      return _PrinterSmartStatus.offline;
    }

    final printerId =
        printer['id']?.toString() ?? printer['_id']?.toString() ?? '';
    final relatedNotifs =
        notifications.where((n) {
          final pId = n['printerId']?.toString() ?? '';
          return pId.isNotEmpty && pId == printerId;
        }).toList();

    final maintenance =
        printer['maintenance'] is Map ? printer['maintenance'] as Map : const {};
    final extended =
        printer['extendedDetails'] is Map
            ? printer['extendedDetails'] as Map
            : const {};
    final anomalyFlags = (printer['anomalyFlags'] as List<dynamic>? ?? const [])
        .map((e) => e.toString().toLowerCase())
        .toList();

    // Check Paper Low
    final hasPaperNotif = relatedNotifs.any((n) {
      final t = (n['type']?.toString() ?? '').toLowerCase();
      final m = (n['message']?.toString() ?? '').toLowerCase();
      final tit = (n['title']?.toString() ?? '').toLowerCase();
      return t.contains('paper') ||
          m.contains('ورق') ||
          tit.contains('ورق') ||
          m.contains('paper');
    });

    final isPaperLow =
        maintenance['paperLow'] == true ||
        extended['paperLow'] == true ||
        extended['paperStatus']?.toString().toLowerCase() == 'low' ||
        anomalyFlags.any((f) => f.contains('paper') || f.contains('ورق')) ||
        hasPaperNotif;

    if (isPaperLow) {
      return _PrinterSmartStatus.paperLow;
    }

    // Check Toner Low
    final hasTonerNotif = relatedNotifs.any((n) {
      final t = (n['type']?.toString() ?? '').toLowerCase();
      final m = (n['message']?.toString() ?? '').toLowerCase();
      final tit = (n['title']?.toString() ?? '').toLowerCase();
      return t.contains('toner') ||
          m.contains('حبر') ||
          tit.contains('حبر') ||
          m.contains('toner');
    });

    bool isTonerLow =
        maintenance['tonerLow'] == true ||
        anomalyFlags.any((f) => f.contains('toner') || f.contains('حبر')) ||
        hasTonerNotif;

    final tonerLevels =
        printer['tonerLevels'] is Map ? printer['tonerLevels'] as Map : const {};
    if (!isTonerLow && tonerLevels.isNotEmpty) {
      for (final val in tonerLevels.values) {
        num? numVal;
        if (val is num) {
          numVal = val;
        } else if (val != null) {
          numVal = num.tryParse(val.toString());
        }
        if (numVal != null && numVal <= 15) {
          isTonerLow = true;
          break;
        }
      }
    }

    if (isTonerLow) {
      return _PrinterSmartStatus.tonerLow;
    }

    return _PrinterSmartStatus.onlineReady;
  }

  String _generateThermalTestReceiptHtml({
    required String printerName,
    required String ipAddress,
    required String branchName,
    required _PrinterSmartStatus smartStatus,
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
  @page {
    size: 80mm auto;
    margin: 0;
  }
  body {
    font-family: 'Segoe UI', Tahoma, Arial, sans-serif;
    width: 72mm;
    max-width: 290px;
    margin: 0 auto;
    padding: 8px 6px;
    color: #000;
    background: #fff;
    font-size: 12px;
    line-height: 1.35;
    -webkit-print-color-adjust: exact;
  }
  .receipt-header {
    text-align: center;
    border-bottom: 2px dashed #000;
    padding-bottom: 6px;
    margin-bottom: 8px;
  }
  .brand-title {
    font-size: 17px;
    font-weight: 900;
    letter-spacing: 0.5px;
    margin: 2px 0;
  }
  .brand-sub {
    font-size: 11px;
    font-weight: 600;
    color: #333;
  }
  .receipt-title {
    font-size: 13px;
    font-weight: 800;
    margin-top: 6px;
    padding: 2px 4px;
    background: #000;
    color: #fff;
    display: inline-block;
    border-radius: 3px;
  }
  .data-grid {
    margin: 8px 0;
  }
  .data-row {
    display: flex;
    justify-content: space-between;
    margin: 3px 0;
    font-size: 11.5px;
  }
  .data-row .k {
    font-weight: 700;
    color: #222;
  }
  .data-row .v {
    font-weight: 600;
    direction: ltr;
    text-align: left;
  }
  .dash-sep {
    border-top: 1px dashed #000;
    margin: 7px 0;
  }
  .test-box {
    border: 1px solid #000;
    padding: 6px 4px;
    margin: 7px 0;
    text-align: center;
    background: #fafafa;
  }
  .test-title {
    font-size: 10.5px;
    font-weight: bold;
    margin-bottom: 4px;
  }
  .test-sample {
    font-family: 'Courier New', Courier, monospace;
    font-size: 10px;
    letter-spacing: 0.5px;
    line-height: 1.25;
  }
  .solid-bar {
    background: #000;
    height: 9px;
    margin: 6px 0 2px 0;
  }
  .bar-caption {
    font-size: 9px;
    color: #444;
  }
  .status-verdict {
    text-align: center;
    font-size: 12px;
    font-weight: 900;
    border: 2px solid #000;
    padding: 5px;
    margin: 8px 0;
    letter-spacing: 0.5px;
  }
  .receipt-footer {
    text-align: center;
    border-top: 2px dashed #000;
    padding-top: 6px;
    margin-top: 6px;
    font-size: 10px;
    color: #333;
  }
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
    <div class="data-row"><span class="k">الحالة الذكية:</span><span class="v">${smartStatus.label}</span></div>
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

  <div class="status-verdict">
    [ ✓ PRINTER HARDWARE TEST PASSED ]
  </div>

  <div class="receipt-footer">
    تم إصدار ورقة الفحص بنجاح بنقرة واحدة من التطبيق<br>
    iSmart Unified Print Subsystem
  </div>
</body>
</html>
''';
  }

  Future<void> _printThermalTestReceipt({
    required Map<String, dynamic> printer,
    required _PrinterSmartStatus status,
  }) async {
    final printerId =
        printer['id']?.toString() ??
        printer['_id']?.toString() ??
        printer['ipAddress']?.toString() ??
        'unknown';
    final printerName =
        printer['printerName']?.toString() ??
        printer['ipAddress']?.toString() ??
        'طابعة مجهولة';
    final ipAddress = printer['ipAddress']?.toString() ?? 'غير معروف';
    final branchName = printer['branchName']?.toString() ?? 'بدون فرع';
    final totalPages =
        (printer['lifetimeCounters'] as Map?)?['totalPages'] ?? 0;

    if (_printingPrinterIds.contains(printerId)) {
      return;
    }

    HapticFeedback.lightImpact();

    setState(() {
      _printingPrinterIds.add(printerId);
    });

    try {
      final html = _generateThermalTestReceiptHtml(
        printerName: printerName,
        ipAddress: ipAddress,
        branchName: branchName,
        smartStatus: status,
        totalPages: totalPages is num ? totalPages : 0,
      );

      final printService = ref.read(remotePrintServiceProvider);
      final result = await printService.requestPrintFromHtml(
        htmlContent: html,
        fileName: 'thermal_test_${printerName.replaceAll(' ', '_')}.html',
        preferredPrinterName: printerName,
      );

      if (!mounted) return;

      if (result.success) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تم إرسال أمر طباعة ورقة الاختبار إلى "$printerName" بنجاح.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1F2937),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: Text(
              result.message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            action: SnackBarAction(
              label: 'معاينة',
              textColor: const Color(0xFF60A5FA),
              onPressed: () => _showReceiptPreviewModal(
                printerName: printerName,
                ipAddress: ipAddress,
                branchName: branchName,
                status: status,
                totalPages: totalPages is num ? totalPages : 0,
              ),
            ),
          ),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: Text(
              'حدث خطأ: $err',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _printingPrinterIds.remove(printerId);
        });
      }
    }
  }

  void _showReceiptPreviewModal({
    required String printerName,
    required String ipAddress,
    required String branchName,
    required _PrinterSmartStatus status,
    required num totalPages,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: status.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.receipt_long_rounded,
                        color: status.color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'معاينة ورقة الاختبار الحرارية (80mm)',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            printerName,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF121214)
                        : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'iSmart Messenger POS Network',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'تقرير اختبار الجاهزية الحرارية الفورية',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const Divider(height: 20),
                      _receiptRow('اسم الطابعة:', printerName),
                      _receiptRow('عنوان الشبكة IP:', ipAddress),
                      _receiptRow('الفرع المسجل:', branchName),
                      _receiptRow('حالة الإشارة الذكية:', status.label),
                      _receiptRow('إجمالي العداد:', '$totalPages ورقة'),
                      const Divider(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.black12,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '[ ✓ PRINTER HARDWARE TEST OK ]',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.print_rounded, size: 20),
                    label: const Text(
                      'إعادة إرسال أمر الطباعة الآن',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _printThermalTestReceipt(
                        printer: {
                          'id': printerName,
                          'printerName': printerName,
                          'ipAddress': ipAddress,
                          'branchName': branchName,
                          'lifetimeCounters': {'totalPages': totalPages},
                        },
                        status: status,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _receiptRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            key,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final canSync = user?.canSyncPrinterModule == true;
    final state = ref.watch(mobilePrinterControllerProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg =
        isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: scaffoldBg,
        appBar: AppBar(
          title: const Text(
            'مراقبة الطابعات',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: scaffoldBg,
          scrolledUnderElevation: 0,
          actions: [
            if (canSync)
              IconButton(
                tooltip: 'مزامنة الطابعات',
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  try {
                    await ref
                        .read(mobilePrinterControllerProvider.notifier)
                        .fullSync();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم تحديث بيانات الطابعات بنجاح.'),
                        ),
                      );
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.sync_rounded),
              ),
          ],
        ),
        body: state.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              Row(
                children: [
                  Expanded(
                    child: ShimmerSkeleton(height: 100, borderRadius: 16),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ShimmerSkeleton(height: 100, borderRadius: 16),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ShimmerSkeleton(height: 100, borderRadius: 16),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ShimmerSkeleton(height: 100, borderRadius: 16),
                  ),
                ],
              ),
              SizedBox(height: 32),
              ShimmerSkeleton(width: 120, height: 20, borderRadius: 8),
              SizedBox(height: 12),
              ShimmerSkeleton(height: 160, borderRadius: 18),
              SizedBox(height: 12),
              ShimmerSkeleton(height: 160, borderRadius: 18),
            ],
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.red,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () =>
                        ref.read(mobilePrinterControllerProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
          data: (data) {
            final notifications = data.notifications;
            final allPrinters = data.printers;

            // Classify printers by smart status
            final printersWithStatus = allPrinters.map((p) {
              final smartStatus = _resolveStatus(p, notifications);
              return (printer: p, status: smartStatus);
            }).toList();

            final totalPrintersCount = printersWithStatus.length;
            final onlinePrintersCount = printersWithStatus
                .where((e) => e.status == _PrinterSmartStatus.onlineReady)
                .length;
            final warningsPrintersCount = printersWithStatus
                .where(
                  (e) =>
                      e.status == _PrinterSmartStatus.paperLow ||
                      e.status == _PrinterSmartStatus.tonerLow,
                )
                .length;
            final offlinePrintersCount = printersWithStatus
                .where((e) => e.status == _PrinterSmartStatus.offline)
                .length;

            // Apply selected filter
            final filteredPrinters = printersWithStatus.where((item) {
              switch (_selectedFilterIndex) {
                case 1:
                  return item.status == _PrinterSmartStatus.onlineReady;
                case 2:
                  return item.status == _PrinterSmartStatus.paperLow ||
                      item.status == _PrinterSmartStatus.tonerLow;
                case 3:
                  return item.status == _PrinterSmartStatus.offline;
                case 0:
                default:
                  return true;
              }
            }).toList();

            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(mobilePrinterControllerProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 40,
                ),
                children: [
                  // Stats Grid
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'الفروع',
                          value: data.totals['branches'] ?? 0,
                          icon: Icons.account_tree_rounded,
                          color: Colors.blue,
                          cardBg: cardBg,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          title: 'الطابعات',
                          value: data.totals['printers'] ?? 0,
                          icon: Icons.print_rounded,
                          color: Colors.purple,
                          cardBg: cardBg,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'المتصلة',
                          value: data.totals['onlinePrinters'] ?? 0,
                          icon: Icons.wifi_rounded,
                          color: const Color(0xFF10B981),
                          cardBg: cardBg,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          title: 'الهالك',
                          value: data.totals['wastePages'] ?? 0,
                          icon: Icons.delete_sweep_rounded,
                          color: Colors.red,
                          cardBg: cardBg,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Section Title & Quick Filters
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _SectionTitle(title: 'طابعات الفروع والجاهزية'),
                      Text(
                        '${allPrinters.length} مسجلة',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Filter Segmented Bar
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterPill(
                          index: 0,
                          label: 'الكل',
                          count: totalPrintersCount,
                          activeColor: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                          index: 1,
                          label: '🟢 متصلة',
                          count: onlinePrintersCount,
                          activeColor: const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                          index: 2,
                          label: '⚠️ تنبيهات',
                          count: warningsPrintersCount,
                          activeColor: const Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                          index: 3,
                          label: '🔴 غير متصلة',
                          count: offlinePrintersCount,
                          activeColor: const Color(0xFFEF4444),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Printers List
                  if (allPrinters.isEmpty)
                    _EmptyState(
                      cardBg: cardBg,
                      icon: Icons.print_disabled_rounded,
                      text: 'لا توجد طابعات مسجلة. شغل الاكتشاف من الديسكتوب.',
                    )
                  else if (filteredPrinters.isEmpty)
                    _EmptyState(
                      cardBg: cardBg,
                      icon: Icons.filter_alt_off_rounded,
                      text: 'لا توجد طابعات تطابق هذا الفلتر.',
                    )
                  else
                    ...filteredPrinters.map((item) {
                      final printer = item.printer;
                      final smartStatus = item.status;
                      final printerId =
                          printer['id']?.toString() ??
                          printer['_id']?.toString() ??
                          printer['ipAddress']?.toString() ??
                          '';
                      final isPrinting = _printingPrinterIds.contains(printerId);

                      return _InteractivePrinterCard(
                        printer: printer,
                        smartStatus: smartStatus,
                        cardBg: cardBg,
                        isDark: isDark,
                        isPrinting: isPrinting,
                        onTestPrint: () => _printThermalTestReceipt(
                          printer: printer,
                          status: smartStatus,
                        ),
                        onPreview: () {
                          final pName =
                              printer['printerName']?.toString() ??
                              printer['ipAddress']?.toString() ??
                              'طابعة';
                          final pIp =
                              printer['ipAddress']?.toString() ?? 'غير معروف';
                          final pBranch =
                              printer['branchName']?.toString() ?? 'بدون فرع';
                          final pPages =
                              (printer['lifetimeCounters'] as Map?)?['totalPages'] ??
                              0;
                          _showReceiptPreviewModal(
                            printerName: pName,
                            ipAddress: pIp,
                            branchName: pBranch,
                            status: smartStatus,
                            totalPages: pPages is num ? pPages : 0,
                          );
                        },
                      );
                    }),

                  const SizedBox(height: 28),
                  const _SectionTitle(title: 'التنبيهات وسجل الإشعارات'),
                  const SizedBox(height: 8),
                  if (notifications.isEmpty)
                    _EmptyState(
                      cardBg: cardBg,
                      icon: Icons.notifications_off_rounded,
                      text: 'لا توجد تنبيهات حالياً.',
                    )
                  else
                    Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Column(
                        children: notifications.asMap().entries.map((entry) {
                          final isLast = entry.key == notifications.length - 1;
                          final notif = entry.value;
                          final isCritical =
                              notif['severity']?.toString() == 'critical';

                          return Column(
                            children: [
                              ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (isCritical
                                            ? Colors.red
                                            : Colors.orange)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.notifications_active_rounded,
                                    color: isCritical
                                        ? Colors.red
                                        : Colors.orange,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  notif['title']?.toString() ?? 'تنبيه طابعة',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14.5,
                                  ),
                                ),
                                subtitle: Text(
                                  notif['message']?.toString() ?? '',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (!isLast)
                                const Divider(
                                  height: 0.5,
                                  thickness: 0.5,
                                  indent: 56,
                                ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required int index,
    required String label,
    required int count,
    required Color activeColor,
  }) {
    final isSelected = _selectedFilterIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _selectedFilterIndex = index;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: isDark ? 0.25 : 0.15)
                : (isDark
                    ? const Color(0xFF1C1C1E)
                    : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06)),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? Colors.white : activeColor)
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor.withValues(alpha: 0.3)
                      : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? (isDark ? Colors.white : activeColor)
                        : (isDark ? Colors.white60 : Colors.black54),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An interactive Apple-styled card representing a single branch printer
/// with Smart Status Signals and instant thermal test print button.
class _InteractivePrinterCard extends StatelessWidget {
  const _InteractivePrinterCard({
    required this.printer,
    required this.smartStatus,
    required this.cardBg,
    required this.isDark,
    required this.isPrinting,
    required this.onTestPrint,
    required this.onPreview,
  });

  final Map<String, dynamic> printer;
  final _PrinterSmartStatus smartStatus;
  final Color cardBg;
  final bool isDark;
  final bool isPrinting;
  final VoidCallback onTestPrint;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final printerName =
        printer['printerName']?.toString() ??
        printer['ipAddress']?.toString() ??
        'طابعة مجهولة';
    final branchName = printer['branchName']?.toString() ?? 'بدون فرع';
    final ipAddress = printer['ipAddress']?.toString() ?? '';
    final totalPages =
        (printer['lifetimeCounters'] as Map?)?['totalPages'] ?? 0;
    final tonerLevels =
        printer['tonerLevels'] is Map ? printer['tonerLevels'] as Map : null;

    final brandAvatar = _buildBrandAvatar(printerName, smartStatus);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: smartStatus == _PrinterSmartStatus.onlineReady
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06))
              : smartStatus.color.withValues(alpha: 0.3),
          width: smartStatus == _PrinterSmartStatus.onlineReady ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Avatar + Title & Branch + Status Dot
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                brandAvatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        printerName,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            branchName,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (ipAddress.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: ipAddress),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('تم نسخ الـ IP: $ipAddress'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lan_outlined,
                                    size: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    ipAddress,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Preview receipt icon
                IconButton(
                  tooltip: 'معاينة ورقة الاختبار',
                  icon: Icon(
                    Icons.remove_red_eye_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: onPreview,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Smart Status Capsule (الإشارة الذكية)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: smartStatus.color.withValues(alpha: isDark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: smartStatus.color.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: smartStatus.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: smartStatus.color.withValues(alpha: 0.6),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 9),
                  Icon(smartStatus.icon, size: 16, color: smartStatus.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      smartStatus.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : smartStatus.color,
                      ),
                    ),
                  ),
                  Text(
                    smartStatus.shortLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: smartStatus.color,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Metrics row: Lifetime pages & Toner bars
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.layers_outlined,
                          size: 16,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'العداد: ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '$totalPages',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Text(
                          ' ورقة',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                if (tonerLevels != null && tonerLevels.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _buildTonerMeters(tonerLevels, isDark),
                ],
              ],
            ),

            const SizedBox(height: 14),

            // Direct Action Button: "طباعة ورقة اختبار حرارية فورية" بنقرة واحدة
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: smartStatus == _PrinterSmartStatus.offline
                      ? (isDark ? Colors.white10 : Colors.grey.shade200)
                      : (isDark
                          ? const Color(0xFF2C2C2E)
                          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)),
                  foregroundColor: smartStatus == _PrinterSmartStatus.offline
                      ? Colors.grey
                      : Theme.of(context).colorScheme.primary,
                  elevation: 0,
                  side: BorderSide(
                    color: smartStatus == _PrinterSmartStatus.offline
                        ? Colors.transparent
                        : Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: isPrinting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF10B981),
                        ),
                      )
                    : const Icon(Icons.receipt_long_rounded, size: 19),
                label: Text(
                  isPrinting
                      ? 'جارِ إرسال أمر الطباعة...'
                      : 'طباعة ورقة اختبار حرارية فورية',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: smartStatus == _PrinterSmartStatus.offline
                        ? Colors.grey
                        : (isDark ? Colors.white : Theme.of(context).colorScheme.primary),
                  ),
                ),
                onPressed: isPrinting ? null : onTestPrint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandAvatar(String name, _PrinterSmartStatus status) {
    final lower = name.toLowerCase();
    String brandCode = 'PRN';
    Color brandColor = const Color(0xFF007AFF);

    if (lower.contains('hp') || lower.contains('laserjet')) {
      brandCode = 'HP';
      brandColor = const Color(0xFF0288D1);
    } else if (lower.contains('epson') || lower.contains('tm-t')) {
      brandCode = 'EPS';
      brandColor = const Color(0xFF1B365D);
    } else if (lower.contains('canon')) {
      brandCode = 'CAN';
      brandColor = const Color(0xFFC2185B);
    } else if (lower.contains('brother')) {
      brandCode = 'BRO';
      brandColor = const Color(0xFF1976D2);
    } else if (lower.contains('kyocera')) {
      brandCode = 'KYO';
      brandColor = const Color(0xFFD32F2F);
    } else if (lower.contains('thermal') || lower.contains('pos') || lower.contains('xprinter')) {
      brandCode = 'POS';
      brandColor = const Color(0xFF0D9488);
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
            brandCode,
            style: TextStyle(
              color: brandColor,
              fontWeight: FontWeight.w900,
              fontSize: 13,
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
              color: status.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTonerMeters(Map<dynamic, dynamic> toner, bool isDark) {
    final keys = [
      ('black', 'K', const Color(0xFF1E293B)),
      ('cyan', 'C', const Color(0xFF0284C7)),
      ('magenta', 'M', const Color(0xFFDB2777)),
      ('yellow', 'Y', const Color(0xFFCA8A04)),
    ];

    final widgets = <Widget>[];
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
      final isLow = pct <= 15;

      widgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          margin: const EdgeInsets.only(left: 3),
          decoration: BoxDecoration(
            color: isLow
                ? Colors.red.withValues(alpha: 0.15)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04)),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isLow ? Colors.red : color.withValues(alpha: 0.3),
              width: isLow ? 1.2 : 0.8,
            ),
          ),
          child: Text(
            '$label ${pct.toInt()}%',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: isLow
                  ? Colors.red
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      );
    }

    if (widgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(mainAxisSize: MainAxisSize.min, children: widgets);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4, left: 4, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.cardBg,
    required this.icon,
    required this.text,
  });
  final Color cardBg;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 48,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.cardBg,
  });

  final String title;
  final num value;
  final IconData icon;
  final Color color;
  final Color cardBg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value.toStringAsFixed(0),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
