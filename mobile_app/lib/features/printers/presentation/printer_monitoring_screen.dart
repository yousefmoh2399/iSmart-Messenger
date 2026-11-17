import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';

/// Enum representing the 4 Smart Status Signals for printers.
enum _PrinterSmartStatus {
  onlineReady, // 🟢 متصلة وجاهزة
  paperLow,    // 🟡 تنبيه: الورق شارف على النفاد
  tonerLow,    // 🟠 الحبر منخفض
  offline,     // 🔴 غير متصلة بالشبكة
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
    extends ConsumerState<MobilePrinterMonitoringScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _printingPrinterIds = <String>{};

  // Tab 0 Filters
  final TextEditingController _printerSearchController = TextEditingController();
  int _selectedPrinterStatusFilter = 0; // 0: الكل, 1: متصلة, 2: تحذيرات, 3: غير متصلة
  String? _selectedBranchFilterId; // null = all branches
  String? _selectedBranchFilterName;

  // Tab 1 Filters
  final TextEditingController _branchSearchController = TextEditingController();

  // Tab 2 Filters
  int _selectedAlertSeverityFilter = 0; // 0: الكل, 1: حرجة, 2: تحذيرات

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _printerSearchController.dispose();
    _branchSearchController.dispose();
    super.dispose();
  }

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
    final relatedNotifs = notifications.where((n) {
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

  void _showPrinterDetailsModal(Map<String, dynamic> printer, _PrinterSmartStatus status) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
        final name = printer['printerName']?.toString() ?? printer['ipAddress']?.toString() ?? 'طابعة';
        final ip = printer['ipAddress']?.toString() ?? '-';
        final branch = printer['branchName']?.toString() ?? 'بدون فرع';
        final model = printer['model']?.toString() ?? printer['vendor']?.toString() ?? 'SNMP Generic';
        final serial = printer['serialNumber']?.toString() ?? '-';
        final mac = printer['macAddress']?.toString() ?? '-';
        final hostname = printer['hostname']?.toString() ?? '-';
        final confidence = printer['identityConfidence']?.toString() ?? 'normal';
        final totalPages = (printer['lifetimeCounters'] as Map?)?['totalPages'] ?? 0;
        final anomalies = (printer['anomalyFlags'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList();

        return Directionality(
          textDirection: TextDirection.rtl,
          child: DraggableScrollableSheet(
            initialChildSize: 0.72,
            minChildSize: 0.4,
            maxChildSize: 0.94,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildBrandAvatar(name, status),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$branch • $ip',
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
                    // Status Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: status.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: status.color.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(status.icon, color: status.color, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            status.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: status.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _SectionTitle(title: 'بيانات ومواصفات الجهاز (Hardware Specs)'),
                    const SizedBox(height: 8),
                    _buildDetailsGroup(isDark, [
                      ('اسم الموديل / المصنع', model),
                      ('الرقم التسلسلي (Serial No)', serial),
                      ('عنوان الماك (MAC Address)', mac),
                      ('اسم المضيف (Hostname)', hostname),
                      ('عنوان IP', ip),
                      ('الفرع التابع له', branch),
                      ('إجمالي عداد الصفحات', '$totalPages ورقة'),
                      ('درجة موثوقية الهوية', confidence),
                    ]),
                    if (anomalies.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const _SectionTitle(title: 'الملاحظات والوسوم الذكية (Anomalies)'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: anomalies.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text(
                                  tag,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.receipt_long_rounded, size: 20),
                        label: const Text(
                          'طباعة ورقة اختبار حرارية الآن',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _printThermalTestReceipt(printer: printer, status: status);
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDetailsGroup(bool isDark, List<(String, String)> items) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final isLast = entry.key == items.length - 1;
          final item = entry.value;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.$1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      item.$2,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 14,
                  color: isDark ? Colors.white10 : Colors.black12,
                ),
            ],
          );
        }).toList(),
      ),
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
    final scaffoldBg = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: scaffoldBg,
        appBar: AppBar(
          title: const Text(
            'منظومة الطابعات الذكية',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          backgroundColor: scaffoldBg,
          scrolledUnderElevation: 0,
          actions: [
            if (canSync)
              IconButton(
                tooltip: 'مزامنة الطابعات الفورية',
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  try {
                    await ref
                        .read(mobilePrinterControllerProvider.notifier)
                        .fullSync();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تمت مزامنة وتحديث بيانات كافة الطابعات بنجاح.'),
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
            IconButton(
              tooltip: 'تحديث الشاشة',
              onPressed: () {
                HapticFeedback.selectionClick();
                ref.read(mobilePrinterControllerProvider.notifier).refresh();
              },
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: _buildAppleSegmentedTabBar(isDark, cs),
          ),
        ),
        body: state.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              Row(
                children: [
                  Expanded(child: ShimmerSkeleton(height: 90, borderRadius: 14)),
                  SizedBox(width: 12),
                  Expanded(child: ShimmerSkeleton(height: 90, borderRadius: 14)),
                ],
              ),
              SizedBox(height: 16),
              ShimmerSkeleton(height: 48, borderRadius: 12),
              SizedBox(height: 16),
              ShimmerSkeleton(height: 140, borderRadius: 16),
              SizedBox(height: 12),
              ShimmerSkeleton(height: 140, borderRadius: 16),
              SizedBox(height: 12),
              ShimmerSkeleton(height: 140, borderRadius: 16),
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
            final allPrinters = data.printers;
            final branches = data.branches;
            final notifications = data.notifications;
            final totals = data.totals;

            // Classify all printers
            final printersWithStatus = allPrinters.map((p) {
              final smartStatus = _resolveStatus(p, notifications);
              return (printer: p, status: smartStatus);
            }).toList();

            return TabBarView(
              controller: _tabController,
              children: [
                // TAB 0: ALL PRINTERS
                _buildPrintersTab(
                  printersWithStatus: printersWithStatus,
                  branches: branches,
                  cardBg: cardBg,
                  isDark: isDark,
                  cs: cs,
                ),

                // TAB 1: BRANCHES
                _buildBranchesTab(
                  branches: branches,
                  allPrintersWithStatus: printersWithStatus,
                  cardBg: cardBg,
                  isDark: isDark,
                  cs: cs,
                ),

                // TAB 2: ALERTS & EVENTS
                _buildAlertsTab(
                  notifications: notifications,
                  cardBg: cardBg,
                  isDark: isDark,
                  cs: cs,
                ),

                // TAB 3: TELEMETRY & METRICS
                _buildMetricsTab(
                  totals: totals,
                  totalPrinters: printersWithStatus.length,
                  onlineCount: printersWithStatus.where((e) => e.status == _PrinterSmartStatus.onlineReady).length,
                  offlineCount: printersWithStatus.where((e) => e.status == _PrinterSmartStatus.offline).length,
                  warningsCount: printersWithStatus.where((e) => e.status == _PrinterSmartStatus.paperLow || e.status == _PrinterSmartStatus.tonerLow).length,
                  cardBg: cardBg,
                  isDark: isDark,
                  cs: cs,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // APPLE SLIDING SEGMENTED TAB BAR
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildAppleSegmentedTabBar(bool isDark, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        indicator: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        labelColor: isDark ? Colors.white : Colors.black87,
        unselectedLabelColor: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366),
        labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(
            height: 34,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.print_rounded, size: 16),
                SizedBox(width: 4),
                Text('الطابعات'),
              ],
            ),
          ),
          Tab(
            height: 34,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_tree_rounded, size: 16),
                SizedBox(width: 4),
                Text('الفروع'),
              ],
            ),
          ),
          Tab(
            height: 34,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_rounded, size: 16),
                SizedBox(width: 4),
                Text('التنبيهات'),
              ],
            ),
          ),
          Tab(
            height: 34,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.analytics_rounded, size: 16),
                SizedBox(width: 4),
                Text('الإحصائيات'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 0: ALL PRINTERS (Search, Filter, Full List)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildPrintersTab({
    required List<({Map<String, dynamic> printer, _PrinterSmartStatus status})> printersWithStatus,
    required List<Map<String, dynamic>> branches,
    required Color cardBg,
    required bool isDark,
    required ColorScheme cs,
  }) {
    final query = _printerSearchController.text.trim().toLowerCase();

    // 1. Status Filter
    var filtered = printersWithStatus.where((item) {
      switch (_selectedPrinterStatusFilter) {
        case 1:
          return item.status == _PrinterSmartStatus.onlineReady;
        case 2:
          return item.status == _PrinterSmartStatus.paperLow || item.status == _PrinterSmartStatus.tonerLow;
        case 3:
          return item.status == _PrinterSmartStatus.offline;
        case 0:
        default:
          return true;
      }
    }).toList();

    // 2. Branch Filter
    if (_selectedBranchFilterId != null) {
      filtered = filtered.where((item) {
        final bId = item.printer['branchId']?.toString() ?? '';
        return bId == _selectedBranchFilterId;
      }).toList();
    }

    // 3. Search Query
    if (query.isNotEmpty) {
      filtered = filtered.where((item) {
        final name = (item.printer['printerName']?.toString() ?? '').toLowerCase();
        final ip = (item.printer['ipAddress']?.toString() ?? '').toLowerCase();
        final branch = (item.printer['branchName']?.toString() ?? '').toLowerCase();
        final model = (item.printer['model']?.toString() ?? '').toLowerCase();
        return name.contains(query) || ip.contains(query) || branch.contains(query) || model.contains(query);
      }).toList();
    }

    final totalCount = printersWithStatus.length;
    final onlineCount = printersWithStatus.where((e) => e.status == _PrinterSmartStatus.onlineReady).length;
    final warningsCount = printersWithStatus.where((e) => e.status == _PrinterSmartStatus.paperLow || e.status == _PrinterSmartStatus.tonerLow).length;
    final offlineCount = printersWithStatus.where((e) => e.status == _PrinterSmartStatus.offline).length;

    return RefreshIndicator(
      onRefresh: () => ref.read(mobilePrinterControllerProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // 1. Apple-style Search Bar
          _buildSearchBar(
            controller: _printerSearchController,
            hint: 'ابحث باسم الطابعة، عنوان IP، الموديل، أو الفرع...',
            isDark: isDark,
            onChanged: (val) => setState(() {}),
          ),
          const SizedBox(height: 10),

          // 2. Active Branch Filter Capsule (if selected)
          if (_selectedBranchFilterId != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.filter_alt_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'مصفاة حسب: ${_selectedBranchFilterName ?? "الفرع"}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedBranchFilterId = null;
                        _selectedBranchFilterName = null;
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Text(
                            'إلغاء',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.close_rounded, size: 14, color: cs.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 3. Status Filter Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusPill(0, 'الكل', totalCount, cs.primary, isDark),
                const SizedBox(width: 8),
                _buildStatusPill(1, '🟢 متصلة', onlineCount, const Color(0xFF10B981), isDark),
                const SizedBox(width: 8),
                _buildStatusPill(2, '⚠️ تنبيهات', warningsCount, const Color(0xFFF59E0B), isDark),
                const SizedBox(width: 8),
                _buildStatusPill(3, '🔴 غير متصلة', offlineCount, const Color(0xFFEF4444), isDark),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 4. Header with real-time count
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'كافة الطابعات (${filtered.length} من أصل $totalCount)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (query.isNotEmpty || _selectedPrinterStatusFilter != 0 || _selectedBranchFilterId != null)
                TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _printerSearchController.clear();
                      _selectedPrinterStatusFilter = 0;
                      _selectedBranchFilterId = null;
                      _selectedBranchFilterName = null;
                    });
                  },
                  child: const Text('إعادة ضبط الكل', style: TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // 5. Printers Cards List
          if (printersWithStatus.isEmpty)
            _EmptyState(
              cardBg: cardBg,
              icon: Icons.print_disabled_rounded,
              text: 'لا توجد أي طابعات مسجلة في المنظومة حتى الآن.',
            )
          else if (filtered.isEmpty)
            _EmptyState(
              cardBg: cardBg,
              icon: Icons.filter_alt_off_rounded,
              text: 'لا توجد طابعات مطابقة لمعايير البحث أو الفلتر.',
            )
          else
            ...filtered.map((item) {
              final printer = item.printer;
              final smartStatus = item.status;
              final printerId = printer['id']?.toString() ?? printer['_id']?.toString() ?? printer['ipAddress']?.toString() ?? '';
              final isPrinting = _printingPrinterIds.contains(printerId);

              return _InteractivePrinterCard(
                printer: printer,
                smartStatus: smartStatus,
                cardBg: cardBg,
                isDark: isDark,
                isPrinting: isPrinting,
                onTestPrint: () => _printThermalTestReceipt(printer: printer, status: smartStatus),
                onPreview: () {
                  final pName = printer['printerName']?.toString() ?? printer['ipAddress']?.toString() ?? 'طابعة';
                  final pIp = printer['ipAddress']?.toString() ?? 'غير معروف';
                  final pBranch = printer['branchName']?.toString() ?? 'بدون فرع';
                  final pPages = (printer['lifetimeCounters'] as Map?)?['totalPages'] ?? 0;
                  _showReceiptPreviewModal(
                    printerName: pName,
                    ipAddress: pIp,
                    branchName: pBranch,
                    status: smartStatus,
                    totalPages: pPages is num ? pPages : 0,
                  );
                },
                onDetails: () => _showPrinterDetailsModal(printer, smartStatus),
              );
            }),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 1: BRANCHES (Per-Branch Overview & Drilldown)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildBranchesTab({
    required List<Map<String, dynamic>> branches,
    required List<({Map<String, dynamic> printer, _PrinterSmartStatus status})> allPrintersWithStatus,
    required Color cardBg,
    required bool isDark,
    required ColorScheme cs,
  }) {
    final query = _branchSearchController.text.trim().toLowerCase();

    final filteredBranches = branches.where((b) {
      if (query.isEmpty) return true;
      final name = (b['name']?.toString() ?? '').toLowerCase();
      final code = (b['code']?.toString() ?? '').toLowerCase();
      return name.contains(query) || code.contains(query);
    }).toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(mobilePrinterControllerProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // Search
          _buildSearchBar(
            controller: _branchSearchController,
            hint: 'ابحث باسم الفرع أو الكود...',
            isDark: isDark,
            onChanged: (val) => setState(() {}),
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'فروع الشبكة (${filteredBranches.length} فرع)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (filteredBranches.isEmpty)
            _EmptyState(
              cardBg: cardBg,
              icon: Icons.store_mall_directory_outlined,
              text: 'لا توجد فروع تطابق البحث.',
            )
          else
            ...filteredBranches.map((b) {
              final branchId = b['id']?.toString() ?? b['_id']?.toString() ?? '';
              final branchName = b['name']?.toString() ?? 'فرع';
              final branchCode = b['code']?.toString() ?? '-';

              // Calculate branch printers statistics
              final branchPrinters = allPrintersWithStatus.where((p) {
                final pBid = p.printer['branchId']?.toString() ?? '';
                final pBname = p.printer['branchName']?.toString() ?? '';
                return (branchId.isNotEmpty && pBid == branchId) || pBname == branchName;
              }).toList();

              final bTotalPrinters = branchPrinters.length;
              final bOnline = branchPrinters.where((p) => p.status == _PrinterSmartStatus.onlineReady).length;
              final bOffline = branchPrinters.where((p) => p.status == _PrinterSmartStatus.offline).length;
              final bWarnings = branchPrinters.where((p) => p.status == _PrinterSmartStatus.paperLow || p.status == _PrinterSmartStatus.tonerLow).length;
              final bPages = branchPrinters.fold<num>(0, (sum, p) => sum + ((p.printer['lifetimeCounters'] as Map?)?['totalPages'] ?? 0));

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            branchCode,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: cs.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            branchName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: bOffline == 0 && bTotalPrinters > 0
                                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            bTotalPrinters == 0
                                ? 'بدون طابعات'
                                : (bOffline == 0 ? 'جاهزية 100%' : '$bOnline متصلة'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: bOffline == 0 && bTotalPrinters > 0
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Metrics Strip
                    Row(
                      children: [
                        _buildBranchMiniStat('الطابعات', '$bTotalPrinters', Icons.print_outlined, isDark),
                        const SizedBox(width: 8),
                        _buildBranchMiniStat('متصلة', '$bOnline', Icons.wifi_rounded, isDark, valColor: const Color(0xFF10B981)),
                        const SizedBox(width: 8),
                        _buildBranchMiniStat('تنبيهات', '$bWarnings', Icons.warning_amber_rounded, isDark, valColor: const Color(0xFFF59E0B)),
                        const SizedBox(width: 8),
                        _buildBranchMiniStat('العداد', '$bPages', Icons.layers_outlined, isDark),
                      ],
                    ),

                    const SizedBox(height: 14),
                    // Action button: Filter & View Printers of this branch
                    SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 16),
                        label: Text('عرض طابعات هذا الفرع ($bTotalPrinters)', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _selectedBranchFilterId = branchId;
                            _selectedBranchFilterName = branchName;
                            _tabController.animateTo(0);
                          });
                        },
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildBranchMiniStat(String label, String value, IconData icon, bool isDark, {Color? valColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 11, color: Colors.grey),
                const SizedBox(width: 2),
                Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: valColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 2: ALERTS & EVENTS (Apple Inset Grouped)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildAlertsTab({
    required List<Map<String, dynamic>> notifications,
    required Color cardBg,
    required bool isDark,
    required ColorScheme cs,
  }) {
    final filtered = notifications.where((n) {
      if (_selectedAlertSeverityFilter == 1) {
        return n['severity']?.toString() == 'critical';
      } else if (_selectedAlertSeverityFilter == 2) {
        return n['severity']?.toString() != 'critical';
      }
      return true;
    }).toList();

    final criticalCount = notifications.where((n) => n['severity']?.toString() == 'critical').length;
    final warningCount = notifications.length - criticalCount;

    return RefreshIndicator(
      onRefresh: () => ref.read(mobilePrinterControllerProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // Filter pills
          Row(
            children: [
              _buildSeverityPill(0, 'الكل', notifications.length, cs.primary, isDark),
              const SizedBox(width: 8),
              _buildSeverityPill(1, 'حرجة 🔴', criticalCount, const Color(0xFFEF4444), isDark),
              const SizedBox(width: 8),
              _buildSeverityPill(2, 'تحذيرات 🟡', warningCount, const Color(0xFFF59E0B), isDark),
            ],
          ),
          const SizedBox(height: 16),

          if (filtered.isEmpty)
            _EmptyState(
              cardBg: cardBg,
              icon: Icons.check_circle_outline_rounded,
              text: 'لا توجد أي تنبيهات أو إشعارات حالياً. المنظومة مستقرة تماماً.',
            )
          else
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                children: filtered.asMap().entries.map((entry) {
                  final isLast = entry.key == filtered.length - 1;
                  final notif = entry.value;
                  final isCritical = notif['severity']?.toString() == 'critical';
                  final title = notif['title']?.toString() ?? 'تنبيه طابعة';
                  final message = notif['message']?.toString() ?? '';
                  final createdAt = notif['createdAt'] != null
                      ? DateTime.tryParse(notif['createdAt'].toString())
                      : null;
                  final timeStr = createdAt != null ? _formatDateCompact(createdAt) : '';

                  return Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (isCritical ? Colors.red : Colors.orange).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isCritical ? Icons.error_rounded : Icons.warning_amber_rounded,
                            color: isCritical ? Colors.red : Colors.orange,
                            size: 20,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                            ),
                            if (timeStr.isNotEmpty)
                              Text(
                                timeStr,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            message,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      if (!isLast)
                        Divider(
                          height: 0.5,
                          thickness: 0.5,
                          indent: 60,
                          color: isDark ? Colors.white10 : Colors.black12,
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSeverityPill(int index, String label, int count, Color color, bool isDark) {
    final isSelected = _selectedAlertSeverityFilter == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedAlertSeverityFilter = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: isDark ? 0.25 : 0.12) : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : (isDark ? Colors.white10 : Colors.black12),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? (isDark ? Colors.white : color) : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.3) : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? (isDark ? Colors.white : color) : (isDark ? Colors.white60 : Colors.black54),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 3: TELEMETRY & METRICS (Apple Bento Grid)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildMetricsTab({
    required Map<String, num> totals,
    required int totalPrinters,
    required int onlineCount,
    required int offlineCount,
    required int warningsCount,
    required Color cardBg,
    required bool isDark,
    required ColorScheme cs,
  }) {
    final branchesCount = totals['branches'] ?? 0;
    final totalPages = totals['totalPages'] ?? 0;
    final wastePages = totals['wastePages'] ?? 0;
    final monthlyUsage = totals['monthlyUsage'] ?? 0;
    final readinessPct = totalPrinters > 0 ? ((onlineCount / totalPrinters) * 100).round() : 100;

    return RefreshIndicator(
      onRefresh: () => ref.read(mobilePrinterControllerProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // 1. Overall Health Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'جاهزية منظومة الطباعة',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    Text(
                      '$readinessPct%',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF10B981)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: totalPrinters > 0 ? (onlineCount / totalPrinters) : 1,
                    minHeight: 8,
                    backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF10B981)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$onlineCount متصلة من أصل $totalPrinters طابعة',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    Text(
                      '$offlineCount غير متصلة',
                      style: TextStyle(fontSize: 12, color: offlineCount > 0 ? Colors.red : Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Bento KPI Cards
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'فروع الشبكة',
                  value: branchesCount,
                  icon: Icons.account_tree_rounded,
                  color: Colors.blue,
                  cardBg: cardBg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: 'إجمالي الطابعات',
                  value: totalPrinters,
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
                  title: 'استهلاك الشهر',
                  value: monthlyUsage,
                  icon: Icons.calendar_month_rounded,
                  color: const Color(0xFF10B981),
                  cardBg: cardBg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: 'الهالك المقدر',
                  value: wastePages,
                  icon: Icons.delete_sweep_rounded,
                  color: Colors.red,
                  cardBg: cardBg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3. Lifetime Counters Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.speed_rounded, color: Colors.teal, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('العدادات الإجمالية للشبكة', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                        Text('Lifetime Printed Counters', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 24),
                _receiptRow('إجمالي الأوراق المطبوعة كلياً:', '$totalPages ورقة'),
                _receiptRow('طابعات بحاجة لصيانة أو حبر:', '$warningsCount طابعات'),
                _receiptRow('الطابعات المتاحة للطباعة الفورية:', '$onlineCount طابعة'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildSearchBar({
    required TextEditingController controller,
    required String hint,
    required bool isDark,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 12.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildStatusPill(int index, String label, int count, Color activeColor, bool isDark) {
    final isSelected = _selectedPrinterStatusFilter == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedPrinterStatusFilter = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: isDark ? 0.25 : 0.12)
                : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? activeColor : (isDark ? Colors.white10 : Colors.black12),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? Colors.white : activeColor)
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected ? activeColor.withValues(alpha: 0.3) : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? (isDark ? Colors.white : activeColor) : (isDark ? Colors.white60 : Colors.black54),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateCompact(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
    return '${dt.month}/${dt.day}';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// INTERACTIVE PRINTER CARD
// ══════════════════════════════════════════════════════════════════════════════
class _InteractivePrinterCard extends StatelessWidget {
  const _InteractivePrinterCard({
    required this.printer,
    required this.smartStatus,
    required this.cardBg,
    required this.isDark,
    required this.isPrinting,
    required this.onTestPrint,
    required this.onPreview,
    required this.onDetails,
  });

  final Map<String, dynamic> printer;
  final _PrinterSmartStatus smartStatus;
  final Color cardBg;
  final bool isDark;
  final bool isPrinting;
  final VoidCallback onTestPrint;
  final VoidCallback onPreview;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final printerName = printer['printerName']?.toString() ?? printer['ipAddress']?.toString() ?? 'طابعة مجهولة';
    final branchName = printer['branchName']?.toString() ?? 'بدون فرع';
    final ipAddress = printer['ipAddress']?.toString() ?? '';
    final model = printer['model']?.toString() ?? printer['vendor']?.toString() ?? '';
    final totalPages = (printer['lifetimeCounters'] as Map?)?['totalPages'] ?? 0;
    final tonerLevels = printer['tonerLevels'] is Map ? printer['tonerLevels'] as Map : null;

    final brandAvatar = _buildBrandAvatar(printerName, smartStatus, isDark: isDark);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: smartStatus == _PrinterSmartStatus.onlineReady
              ? (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06))
              : smartStatus.color.withValues(alpha: 0.3),
          width: smartStatus == _PrinterSmartStatus.onlineReady ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Avatar + Title & Branch + Actions
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
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            branchName,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (ipAddress.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: ipAddress));
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
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    ipAddress,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.primary,
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
                // Details button
                IconButton(
                  tooltip: 'مواصفات وتفاصيل الطابعة',
                  icon: Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: onDetails,
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

            const SizedBox(height: 10),

            // Smart Status Capsule
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: smartStatus.color.withValues(alpha: isDark ? 0.16 : 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: smartStatus.color.withValues(alpha: 0.22)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: smartStatus.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: smartStatus.color.withValues(alpha: 0.5),
                          blurRadius: 5,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(smartStatus.icon, size: 15, color: smartStatus.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      smartStatus.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : smartStatus.color,
                      ),
                    ),
                  ),
                  if (model.isNotEmpty)
                    Text(
                      model,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Metrics row: Lifetime pages & Toner meters
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.layers_outlined,
                          size: 15,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'العداد: ',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '$totalPages',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 2),
                        const Text(' ورقة', style: TextStyle(fontSize: 10.5, color: Colors.grey)),
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

            const SizedBox(height: 12),

            // Action Button: Direct Thermal Print Test
            SizedBox(
              width: double.infinity,
              height: 40,
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
                        : Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: isPrinting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                      )
                    : const Icon(Icons.receipt_long_rounded, size: 17),
                label: Text(
                  isPrinting ? 'جارِ إرسال أمر الطباعة...' : 'طباعة ورقة اختبار حرارية فورية',
                  style: TextStyle(
                    fontSize: 12.5,
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
                : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
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
              color: isLow ? Colors.red : (isDark ? Colors.white70 : Colors.black87),
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

Widget _buildBrandAvatar(String name, _PrinterSmartStatus status, {bool isDark = false}) {
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
        width: 42,
        height: 42,
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
            fontSize: 12.5,
          ),
        ),
      ),
      Positioned(
        bottom: -1,
        left: -1,
        child: Container(
          width: 11,
          height: 11,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2, left: 2, bottom: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13.5,
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
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 42,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
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
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value.toStringAsFixed(0),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
