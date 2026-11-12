import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/system_monitor_models.dart';
import '../system_monitor_controller.dart';
import 'n8n_workflow_diagram_widget.dart';
import '../live_operations_topology_screen.dart';

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
  final TextEditingController _targetVersionCtrl = TextEditingController();
  String _filterType = 'all'; // 'all', 'exact', 'older', 'not_installed'
  String _appliedTargetVersion = '1.1.21';
  bool _initializedTarget = false;
  bool _showTopologyMap = false;
  bool _showRequestsStream = false;

  @override
  void initState() {
    super.initState();
    final initialVer = widget.state.deploymentData?.summary.targetAppVersion ??
        widget.state.deploymentData?.summary.currentAppVersion;
    if (initialVer != null && initialVer.isNotEmpty) {
      _targetVersionCtrl.text = initialVer;
      _appliedTargetVersion = initialVer;
      _initializedTarget = true;
    }
  }

  @override
  void didUpdateWidget(covariant BranchesDeploymentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_initializedTarget) {
      final initialVer = widget.state.deploymentData?.summary.targetAppVersion ??
          widget.state.deploymentData?.summary.currentAppVersion;
      if (initialVer != null && initialVer.isNotEmpty) {
        _targetVersionCtrl.text = initialVer;
        _appliedTargetVersion = initialVer;
        _initializedTarget = true;
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _targetVersionCtrl.dispose();
    super.dispose();
  }

  void _applyTargetVersion([String? newVersion]) {
    final ver = (newVersion ?? _targetVersionCtrl.text).trim();
    if (ver.isEmpty) return;
    _targetVersionCtrl.text = ver;
    setState(() {
      _appliedTargetVersion = ver;
    });
    widget.notifier.refreshDeployment(targetVersion: ver);
  }

  Future<void> _handleExport(
    String format, {
    String? scope,
    List<String>? branchCodes,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final isOutdated = scope == 'outdated';
    final isPerBranch = scope == 'per_branch';
    messenger.showSnackBar(
      SnackBar(
        content: Text(isOutdated
            ? 'جاري إعداد وتصدير كشف أجهزة الكمبيوتر القديمة Excel...'
            : isPerBranch
                ? 'جاري إنشاء ملف إكسيل مقسم بالفروع مع تفاصيل الأجهزة...'
                : 'جاري إعداد وتصدير تقرير ${format == "pdf" ? "PDF" : "Excel"}...'),
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      await widget.notifier.exportReport(
        format,
        targetVersion: _appliedTargetVersion,
        scope: scope,
        branchCodes: branchCodes,
      );
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(isOutdated
                ? '✅ تم تصدير كشف الأجهزة القديمة بنجاح وحفظه في مجلد التنزيلات!'
                : isPerBranch
                    ? '✅ تم تصدير تقرير الفروع المقسم Excel بنجاح وحفظه في مجلد التنزيلات!'
                    : '✅ تم تصدير تقرير ${format == "pdf" ? "PDF" : "Excel"} بنجاح وحفظه!'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('❌ تعذر تصدير الملف: $e'),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _openLiveTopologyScreen(BuildContext context) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, anim, secAnim) => LiveOperationsTopologyScreen(
          state: widget.state,
          notifier: widget.notifier,
          isDark: widget.isDark,
          cs: widget.cs,
        ),
        transitionsBuilder: (context, anim, secAnim, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  void _showChangeTargetVersionDialog(BuildContext context, List<String> detectedVersions) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.tune_rounded, color: Color(0xFF0284C7), size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'تحديد الإصدار المعتمد للفحص',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'أدخل رقم الإصدار الرسمي المطلوب مقارعته وفرز الأجهزة المطابقة أو القديمة بناءً عليه:',
                style: TextStyle(fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _targetVersionCtrl,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0284C7),
                ),
                decoration: InputDecoration(
                  hintText: '1.1.21',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              if (detectedVersions.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'نسخ مكتشفة على الشبكة:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: detectedVersions.map((v) {
                    return ActionChip(
                      label: Text('v$v', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      onPressed: () {
                        _targetVersionCtrl.text = v;
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(fontSize: 13.5)),
            ),
            ElevatedButton(
              onPressed: () {
                _applyTargetVersion();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('تطبيق التغيير', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }

  void _showPerBranchExportDialog(
    BuildContext context,
    List<BranchDeploymentItem> allBranches,
    String targetVer,
  ) {
    if (allBranches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد فروع متاحة للتصدير حالياً'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final isDark = widget.isDark;
    final Set<String> selectedCodes = allBranches.map((b) => b.branchCode).toSet();
    String branchSearch = '';

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final filteredBranches = allBranches.where((b) {
              if (branchSearch.trim().isEmpty) return true;
              final q = branchSearch.trim().toLowerCase();
              return b.branchName.toLowerCase().contains(q) ||
                  b.branchCode.toLowerCase().contains(q);
            }).toList();

            final totalSelected = selectedCodes.length;
            final isAllSelected = selectedCodes.length == allBranches.length;
            final outdatedBranchesCount = allBranches.where((b) => b.outdatedDevicesCount > 0).length;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: isDark ? const Color(0xFF131926) : Colors.white,
              child: Container(
                width: 680,
                constraints: const BoxConstraints(maxHeight: 640),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.view_carousel_rounded, color: Color(0xFF0284C7), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'تصدير إكسيل مقسم بالفروع (ورقة لكل فرع)',
                                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'يحتوي الملف على ملخص مقارنة الفروع + صفحة مخصصة لكل فرع بالأجهزة وحالة التحديث',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Quick Select Actions & Filter
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Search Box
                          SizedBox(
                            height: 38,
                            child: TextField(
                              onChanged: (val) {
                                setDialogState(() {
                                  branchSearch = val;
                                });
                              },
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                              decoration: InputDecoration(
                                hintText: 'بحث باسم الفرع أو الكود...',
                                hintStyle: TextStyle(
                                  fontSize: 12.5,
                                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                ),
                                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Action Chips
                          Row(
                            children: [
                              // Select All
                              InkWell(
                                onTap: () {
                                setDialogState(() {
                                  selectedCodes.addAll(allBranches.map((b) => b.branchCode));
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isAllSelected
                                      ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                                      : (isDark ? const Color(0xFF1E293B) : Colors.white),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isAllSelected
                                        ? const Color(0xFF0284C7)
                                        : (isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFCBD5E1)),
                                  ),
                                ),
                                child: Text(
                                  'تحديد كافة الفروع (${allBranches.length})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isAllSelected ? FontWeight.w800 : FontWeight.w600,
                                    color: isAllSelected ? const Color(0xFF0284C7) : null,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Deselect All
                            InkWell(
                              onTap: () {
                                setDialogState(() {
                                  selectedCodes.clear();
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFCBD5E1),
                                  ),
                                ),
                                child: const Text(
                                  'إلغاء التحديد',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Only Outdated
                            if (outdatedBranchesCount > 0)
                              InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    selectedCodes.clear();
                                    for (final b in allBranches) {
                                      if (b.outdatedDevicesCount > 0) {
                                        selectedCodes.add(b.branchCode);
                                      }
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    'الفروع ذات النسخ القديمة فقط ($outdatedBranchesCount) ⚠️',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Scrollable Branch List
                  Expanded(
                    child: filteredBranches.isEmpty
                        ? Center(
                            child: Text(
                              'لا توجد فروع مطابقة للبحث',
                              style: TextStyle(
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListView.separated(
                              itemCount: filteredBranches.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                              ),
                              itemBuilder: (context, index) {
                                final branch = filteredBranches[index];
                                final isChecked = selectedCodes.contains(branch.branchCode);
                                final hasOutdated = branch.outdatedDevicesCount > 0;

                                return InkWell(
                                  onTap: () {
                                    setDialogState(() {
                                      if (isChecked) {
                                        selectedCodes.remove(branch.branchCode);
                                      } else {
                                        selectedCodes.add(branch.branchCode);
                                      }
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: isChecked,
                                          activeColor: const Color(0xFF0284C7),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          onChanged: (val) {
                                            setDialogState(() {
                                              if (val == true) {
                                                selectedCodes.add(branch.branchCode);
                                              } else {
                                                selectedCodes.remove(branch.branchCode);
                                              }
                                            });
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                branch.branchName,
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              Text(
                                                'كود: ${branch.branchCode} • ${branch.devicesCount} محطة عمل',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (hasOutdated)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                                              ),
                                            ),
                                            child: Text(
                                              '⚠️ ${branch.outdatedDevicesCount} قديم',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFFEF4444),
                                              ),
                                            ),
                                          )
                                        else if (branch.isInstalled)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              '✅ محدث',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF10B981),
                                              ),
                                            ),
                                          )
                                        else
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'غير مثبت',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),

                  // Footer actions
                  Row(
                    children: [
                      Text(
                        'تم اختيار $totalSelected فرع من أصل ${allBranches.length}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('إلغاء', style: TextStyle(fontSize: 13.5)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: totalSelected == 0
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _handleExport(
                                  'xlsx',
                                  scope: 'per_branch',
                                  branchCodes: isAllSelected ? null : selectedCodes.toList(),
                                );
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: Text(
                          isAllSelected
                              ? 'تصدير كافة الفروع (${allBranches.length} صفحة)'
                              : 'تصدير الفروع المحددة ($totalSelected صفحة)',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

  String _formatTimeAgo(DateTime? dt) {
    if (dt == null) return 'غير متوفر';
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

    final deployment = state.deploymentData;
    final summary = deployment?.summary;
    final telemetry = state.requestTelemetry;
    final stats = state.stats;

    final allBranches = deployment?.branches ?? [];
    final query = _searchCtrl.text.trim().toLowerCase();
    final targetVer = _appliedTargetVersion;

    final detectedVersions = (summary?.versionBreakdown.keys ?? [])
        .where((v) => v != 'unknown' && v != 'غير محدد' && v.trim().isNotEmpty)
        .toList();
    if (!detectedVersions.contains('1.1.21')) {
      detectedVersions.add('1.1.21');
    }
    detectedVersions.sort((a, b) => compareAppVersions(b, a));

    final totalExactDevs = allBranches.fold<int>(
      0,
      (sum, b) =>
          sum +
          b.devices
              .where((d) => compareAppVersions(d.appVersion, targetVer) == 0)
              .length,
    );
    final totalOlderDevs = allBranches.fold<int>(
      0,
      (sum, b) =>
          sum +
          b.devices
              .where((d) => compareAppVersions(d.appVersion, targetVer) < 0)
              .length,
    );

    final exactBranchesCount = allBranches
        .where((b) => b.devices.any(
            (d) => compareAppVersions(d.appVersion, targetVer) == 0))
        .length;
    final olderBranchesCount = allBranches
        .where((b) => b.devices.any(
            (d) => compareAppVersions(d.appVersion, targetVer) < 0))
        .length;
    final pendingCount = allBranches.where((b) => !b.isInstalled).length;

    final filteredBranches = allBranches.where((b) {
      if (_filterType == 'exact') {
        final hasExact = b.devices.any(
            (d) => compareAppVersions(d.appVersion, targetVer) == 0);
        if (!hasExact) return false;
      } else if (_filterType == 'older') {
        final hasOlder = b.devices.any(
            (d) => compareAppVersions(d.appVersion, targetVer) < 0);
        if (!hasOlder) return false;
      } else if (_filterType == 'not_installed') {
        if (b.isInstalled) return false;
      }
      if (query.isNotEmpty) {
        final matchesName = b.branchName.toLowerCase().contains(query);
        final matchesCode = b.branchCode.toLowerCase().contains(query);
        final matchesUser = b.devices.any((d) =>
            d.fullName.toLowerCase().contains(query) ||
            d.username.toLowerCase().contains(query) ||
            d.hostname.toLowerCase().contains(query));
        return matchesName || matchesCode || matchesUser;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Executive Apple Hero Metric Cards
        _buildHeroKpiRow(
          summary: summary,
          isDark: isDark,
          cs: cs,
          targetVer: targetVer,
          totalExactDevs: totalExactDevs,
          totalOlderDevs: totalOlderDevs,
        ),
        const SizedBox(height: 16),

        // 2. Outdated Version Action Alert (Only shown when outdated machines exist)
        if (totalOlderDevs > 0) ...[
          _buildOutdatedAlertBanner(
            totalOlderDevs: totalOlderDevs,
            targetVer: targetVer,
            isDark: isDark,
            onFilterOlder: () {
              _showAllOutdatedDevicesModal(context, allBranches, targetVer, isDark);
            },
            onExportExcel: () {
              _handleExport('xlsx', scope: 'outdated');
            },
          ),
          const SizedBox(height: 16),
        ],

        // 3. Unified Clean Apple Toolbar (Search, Filter Pills, Target Version, Export Buttons)
        _buildUnifiedToolbar(
          state: state,
          notifier: notifier,
          allBranches: allBranches,
          allCount: allBranches.length,
          exactBranchesCount: exactBranchesCount,
          exactDevsCount: totalExactDevs,
          olderBranchesCount: olderBranchesCount,
          olderDevsCount: totalOlderDevs,
          pendingCount: pendingCount,
          targetVersion: targetVer,
          detectedVersions: detectedVersions,
          isDark: isDark,
          cs: cs,
        ),
        const SizedBox(height: 16),

        // 4. Interactive Network Topology Toggle Card
        _buildTopologyToggleCard(
          isDark: isDark,
          cs: cs,
          summary: summary,
          telemetry: telemetry,
          stats: stats,
        ),
        const SizedBox(height: 16),

        // 5. Fleet Table / Cards
        if (state.isLoadingDeployment && allBranches.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (filteredBranches.isEmpty)
          _buildEmptyBranchesCard(isDark)
        else
          _buildEnterpriseFleetTable(filteredBranches, isDark, cs, targetVer),

        const SizedBox(height: 20),

        // 6. Optional Live Server Request Stream (Collapsible)
        _buildLiveRequestsStreamCard(telemetry, isDark, cs),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 1. HERO METRIC KPI CARDS
  // ---------------------------------------------------------------------------
  Widget _buildHeroKpiRow({
    required BranchDeploymentSummary? summary,
    required bool isDark,
    required ColorScheme cs,
    required String targetVer,
    required int totalExactDevs,
    required int totalOlderDevs,
  }) {
    final adoptionPercent = summary?.adoptionPercentage ?? 0;
    final installedBranches = summary?.installedBranchesCount ?? 0;
    final totalBranches = summary?.totalBranches ?? 0;
    final totalDevs = summary?.totalInstalledDevices ?? 0;
    final onlineDevs = summary?.totalOnlineDevices ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 920;
        final cardSpacing = 12.0;
        final cardWidth = isCompact
            ? (constraints.maxWidth - cardSpacing) / 2
            : (constraints.maxWidth - (cardSpacing * 3)) / 4;

        final cards = [
          // Card 1: Adoption
          _buildMetricCard(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.hub_rounded,
            accentColor: const Color(0xFF2563EB),
            title: 'نسبة التغطية بالفروع',
            value: '$adoptionPercent%',
            subtitle: '$installedBranches فرع مثبت من أصل $totalBranches',
            badge: '$installedBranches نشط',
            badgeColor: const Color(0xFF2563EB),
          ),
          // Card 2: Workstations
          _buildMetricCard(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.computer_rounded,
            accentColor: const Color(0xFF0284C7),
            title: 'محطات العمل الفعلية',
            value: '$totalDevs محطة',
            subtitle: '$onlineDevs متصل الآن بالشبكة',
            badge: '🟢 $onlineDevs متصل',
            badgeColor: const Color(0xFF10B981),
          ),
          // Card 3: Target Version Match
          _buildMetricCard(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.verified_user_rounded,
            accentColor: const Color(0xFF10B981),
            title: 'مطابقة الإصدار المعتمد',
            value: '$totalExactDevs مطابق',
            subtitle: 'مطابق لـ v$targetVer المعتمد',
            badge: totalDevs > 0 ? '${((totalExactDevs / totalDevs) * 100).round()}% معتمد' : '0%',
            badgeColor: const Color(0xFF10B981),
          ),
          // Card 4: Outdated Machines
          _buildMetricCard(
            isDark: isDark,
            width: cardWidth,
            icon: Icons.warning_amber_rounded,
            accentColor: totalOlderDevs > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
            title: 'أجهزة بنسخ قديمة',
            value: '$totalOlderDevs قديم',
            subtitle: totalOlderDevs > 0 ? 'تتطلب التحديث العاجل لـ v$targetVer' : 'كافة الأجهزة محدثة بالكامل',
            badge: totalOlderDevs > 0 ? '⚠️ $totalOlderDevs جهاز' : '✅ 100% متوافق',
            badgeColor: totalOlderDevs > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
          ),
        ];

        if (isCompact) {
          return Column(
            children: [
              Row(children: [cards[0], SizedBox(width: cardSpacing), cards[1]]),
              const SizedBox(height: 12),
              Row(children: [cards[2], SizedBox(width: cardSpacing), cards[3]]),
            ],
          );
        }

        return Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) SizedBox(width: cardSpacing),
              cards[i],
            ],
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required bool isDark,
    required double width,
    required IconData icon,
    required Color accentColor,
    required String title,
    required String value,
    required String subtitle,
    String? badge,
    Color? badgeColor,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131926) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
          width: 1.0,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? accentColor).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: badgeColor ?? accentColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. OUTDATED ALERT BANNER
  // ---------------------------------------------------------------------------
  Widget _buildOutdatedAlertBanner({
    required int totalOlderDevs,
    required String targetVer,
    required bool isDark,
    required VoidCallback onFilterOlder,
    required VoidCallback onExportExcel,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF241416) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 800;

          final infoCol = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFEF4444),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تنبيه متابعة الأجهزة: تم رصد $totalOlderDevs محطة عمل تعمل بنسخ قديمة',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'يجب تحديث هذه المحطات إلى النسخة المعتمدة (v$targetVer) لضمان استقرار الرسائل وسرعة الاتصال.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final buttons = Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: onFilterOlder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.list_alt_rounded, size: 16),
                label: Text(
                  'عرض كشف الأجهزة القديمة ($totalOlderDevs)',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onExportExcel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: BorderSide(color: const Color(0xFFDC2626).withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.table_chart_rounded, size: 16),
                label: const Text(
                  'تصدير كشف القديمة Excel',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                infoCol,
                const SizedBox(height: 12),
                buttons,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: infoCol),
              const SizedBox(width: 16),
              buttons,
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. UNIFIED ACTION BAR (Search, Filters, Target Ver, Exports)
  // ---------------------------------------------------------------------------
  Widget _buildUnifiedToolbar({
    required SystemMonitorState state,
    required SystemMonitorController notifier,
    required List<BranchDeploymentItem> allBranches,
    required int allCount,
    required int exactBranchesCount,
    required int exactDevsCount,
    required int olderBranchesCount,
    required int olderDevsCount,
    required int pendingCount,
    required String targetVersion,
    required List<String> detectedVersions,
    required bool isDark,
    required ColorScheme cs,
  }) {
    final isExporting = state.isExportingReport;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131926) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 960;

          // Search Field
          final searchWidget = SizedBox(
            width: isCompact ? constraints.maxWidth : 300,
            height: 42,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'بحث باسم الفرع، الكود، أو الموظف...',
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                filled: true,
                fillColor: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
            ),
          );

          // Filter Pills
          final filterPills = Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildFilterChoice('all', 'جميع الفروع ($allCount)'),
              _buildFilterChoice(
                'older',
                'نسخ قديمة ($olderDevsCount جهاز) ⚠️',
                isWarning: olderDevsCount > 0,
              ),
              _buildFilterChoice(
                'exact',
                'محدثة بالكامل ($exactDevsCount جهاز) ✅',
              ),
              _buildFilterChoice('not_installed', 'بانتظار التثبيت ($pendingCount)'),
            ],
          );

          // Version & Export actions
          final actionButtons = Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Target version button
              OutlinedButton.icon(
                onPressed: () => _showChangeTargetVersionDialog(context, detectedVersions),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0284C7),
                  side: BorderSide(color: const Color(0xFF0284C7).withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.rule_folder_rounded, size: 16),
                label: Text(
                  'المعتمد: v$targetVersion',
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.w700),
                ),
              ),

              // Excel Export
              FilledButton.icon(
                onPressed: isExporting
                    ? null
                    : () => _handleExport('xlsx'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: isExporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.table_chart_rounded, size: 16),
                label: const Text(
                  'تصدير إكسيل',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),

              // Excel Export per Branch
              FilledButton.icon(
                onPressed: isExporting || allBranches.isEmpty
                    ? null
                    : () => _showPerBranchExportDialog(context, allBranches, targetVersion),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: isExporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.view_carousel_rounded, size: 16),
                label: const Text(
                  'تصدير إكسيل بالفروع',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),

              // PDF Export
              FilledButton.icon(
                onPressed: isExporting
                    ? null
                    : () => _handleExport('pdf'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: isExporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: const Text(
                  'تصدير PDF',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchWidget,
                const SizedBox(height: 12),
                filterPills,
                const SizedBox(height: 12),
                actionButtons,
              ],
            );
          }

          return Row(
            children: [
              searchWidget,
              const SizedBox(width: 14),
              Expanded(child: filterPills),
              const SizedBox(width: 14),
              actionButtons,
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChoice(
    String key,
    String label, {
    bool isWarning = false,
  }) {
    final isSelected = _filterType == key;
    final isDark = widget.isDark;

    Color bg;
    Color border;
    Color textColor;

    if (isSelected) {
      if (isWarning) {
        bg = const Color(0xFFEF4444).withValues(alpha: 0.15);
        border = const Color(0xFFEF4444).withValues(alpha: 0.6);
        textColor = const Color(0xFFEF4444);
      } else {
        bg = isDark ? const Color(0xFF2563EB).withValues(alpha: 0.2) : const Color(0xFF2563EB).withValues(alpha: 0.1);
        border = const Color(0xFF2563EB);
        textColor = const Color(0xFF2563EB);
      }
    } else {
      if (isWarning) {
        bg = const Color(0xFFEF4444).withValues(alpha: 0.06);
        border = const Color(0xFFEF4444).withValues(alpha: 0.25);
        textColor = const Color(0xFFEF4444);
      } else {
        bg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
        border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
        textColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
      }
    }

    return InkWell(
      onTap: () => setState(() => _filterType = key),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. INTERACTIVE NETWORK TOPOLOGY TOGGLE CARD
  // ---------------------------------------------------------------------------
  Widget _buildTopologyToggleCard({
    required bool isDark,
    required ColorScheme cs,
    required BranchDeploymentSummary? summary,
    required RequestTelemetryData? telemetry,
    required dynamic stats,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131926) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6D5A).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.hub_rounded, color: Color(0xFFFF6D5A), size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'خريطة العمارة والشبكة التفاعلية (n8n Workflow Map)',
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'مخطط تفاعلي حي لمسار تدفق الرسائل وسيرفرات الفروع وقواعد البيانات',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showTopologyMap = !_showTopologyMap;
                    });
                  },
                  icon: Icon(_showTopologyMap ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 16),
                  label: Text(
                    _showTopologyMap ? 'إخفاء الخريطة' : 'إظهار الخريطة',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'فتح بكامل الشاشة',
                  onPressed: () => _openLiveTopologyScreen(context),
                  icon: const Icon(Icons.fullscreen_rounded, size: 20),
                ),
              ],
            ),
          ),
          if (_showTopologyMap) ...[
            const Divider(height: 1),
            N8nWorkflowDiagramWidget(
              summary: summary,
              telemetry: telemetry,
              stats: stats,
              isDark: isDark,
              onOpenFullscreen: () => _openLiveTopologyScreen(context),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. ENTERPRISE FLEET TABLE
  // ---------------------------------------------------------------------------
  Widget _buildEnterpriseFleetTable(
    List<BranchDeploymentItem> branches,
    bool isDark,
    ColorScheme cs,
    String targetVersion,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131926) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Table Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              color: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'الفرع والكود',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'موقف التثبيت',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'محطات العمل',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'موقف التحديث والإصدارات',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'آخر نشاط',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 140,
                    child: Text(
                      'الإجراءات',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Rows
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: branches.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF1F5F9),
              ),
              itemBuilder: (context, index) {
                final b = branches[index];
                final isInstalled = b.isInstalled;
                final branchOlderDevs = b.devices
                    .where((d) => compareAppVersions(d.appVersion, targetVersion) < 0)
                    .length;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      // Branch name & code
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                b.branchCode.isNotEmpty ? b.branchCode : 'BR',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                b.branchName,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Status pill
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isInstalled
                                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                  : (isDark ? const Color(0xFF1F2937) : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isInstalled
                                    ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                    : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isInstalled ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isInstalled ? 'تم التثبيت' : 'بانتظار التثبيت',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isInstalled
                                        ? const Color(0xFF10B981)
                                        : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Workstations
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Text(
                              '${b.devicesCount} جهاز',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                              ),
                            ),
                            if (b.onlineDevicesCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '🟢 ${b.onlineDevicesCount} متصل',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Version & Compatibility
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: !isInstalled
                              ? const Text('-', style: TextStyle(fontSize: 13, color: Colors.grey))
                              : branchOlderDevs > 0
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.warning_amber_rounded,
                                            size: 15,
                                            color: Color(0xFFEF4444),
                                          ),
                                          const SizedBox(width: 5),
                                          Flexible(
                                            child: Text(
                                              'يوجد $branchOlderDevs أجهزة قديمة ⚠️',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFFEF4444),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.verified_rounded,
                                            size: 15,
                                            color: Color(0xFF10B981),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            'محدث بالكامل (v$targetVersion) ✅',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF10B981),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                        ),
                      ),

                      // Last activity
                      Expanded(
                        flex: 2,
                        child: Text(
                          _formatTimeAgo(b.lastActivityAt),
                          style: TextStyle(
                            fontSize: 13.5,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ),

                      // Actions
                      SizedBox(
                        width: 140,
                        child: FilledButton.tonal(
                          onPressed: b.devices.isEmpty && b.installedUsers.isEmpty
                              ? null
                              : () => _showBranchDevicesModal(context, b, isDark, targetVersion),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            'تفاصيل الأجهزة (${b.devicesCount})',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyBranchesCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131926) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 44,
            color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
          ),
          const SizedBox(height: 12),
          Text(
            'لا توجد فروع أو أجهزة تطابق معايير البحث الحالية',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5.5 ALL OUTDATED WORKSTATIONS MODAL
  // ---------------------------------------------------------------------------
  void _showAllOutdatedDevicesModal(
    BuildContext context,
    List<BranchDeploymentItem> allBranches,
    String targetVersion,
    bool isDark,
  ) {
    // Collect all outdated computer workstations
    final List<Map<String, dynamic>> allOutdated = [];
    for (final b in allBranches) {
      for (final d in b.devices) {
        if (compareAppVersions(d.appVersion, targetVersion) < 0) {
          allOutdated.add({
            'branch': b,
            'device': d,
          });
        }
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = allOutdated.where((item) {
              if (searchQuery.isEmpty) return true;
              final BranchDeploymentItem b = item['branch'] as BranchDeploymentItem;
              final BranchDeviceItem d = item['device'] as BranchDeviceItem;
              final q = searchQuery.toLowerCase();
              return b.branchName.toLowerCase().contains(q) ||
                  b.branchCode.toLowerCase().contains(q) ||
                  d.fullName.toLowerCase().contains(q) ||
                  d.username.toLowerCase().contains(q) ||
                  d.hostname.toLowerCase().contains(q) ||
                  d.appVersion.toLowerCase().contains(q);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (_, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF131926) : Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      // Handle
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFEF4444),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'كشف حصر أجهزة الكمبيوتر ذات الإصدارات القديمة (${allOutdated.length} جهاز)',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'أجهزة كمبيوتر ومحطات عمل تتطلب التحديث للنسخة المعتمدة (v$targetVersion) • بدون تكرار',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Quick Export Button inside the modal
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _handleExport('xlsx', scope: 'outdated');
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.table_chart_rounded, size: 16),
                              label: const Text(
                                'تصدير هذا الكشف Excel',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close_rounded, size: 22),
                            ),
                          ],
                        ),
                      ),
                      // Search bar inside modal
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'بحث سريع بالموظف، الفرع، أو اسم الكمبيوتر...',
                            prefixIcon: const Icon(Icons.search_rounded, size: 18),
                            isDense: true,
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                              ),
                            ),
                          ),
                          onChanged: (val) {
                            setModalState(() {
                              searchQuery = val.trim();
                            });
                          },
                        ),
                      ),
                      const Divider(height: 16),
                      // Table content
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 48,
                                      color: Color(0xFF10B981),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      allOutdated.isEmpty
                                          ? 'ممتاز! جميع أجهزة الكمبيوتر محدثة للنسخة المعتمدة v$targetVersion'
                                          : 'لا توجد أجهزة مطابقة للبحث داخل الكشف',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF1F5F9),
                                ),
                                itemBuilder: (context, idx) {
                                  final item = filtered[idx];
                                  final BranchDeploymentItem b = item['branch'] as BranchDeploymentItem;
                                  final BranchDeviceItem d = item['device'] as BranchDeviceItem;

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Row(
                                      children: [
                                        // Index
                                        Container(
                                          width: 32,
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${idx + 1}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Branch
                                        Expanded(
                                          flex: 2,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      b.branchCode.isNotEmpty ? b.branchCode : 'BR',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontFamily: 'monospace',
                                                        fontWeight: FontWeight.w800,
                                                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      b.branchName,
                                                      style: TextStyle(
                                                        fontSize: 13.5,
                                                        fontWeight: FontWeight.w700,
                                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        // User
                                        Expanded(
                                          flex: 2,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                d.fullName.isNotEmpty ? d.fullName : (d.username.isNotEmpty ? d.username : 'غير محدد'),
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (d.username.isNotEmpty)
                                                Text(
                                                  '@${d.username}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        // Workstation / Hostname
                                        Expanded(
                                          flex: 2,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.computer_rounded,
                                                size: 16,
                                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  d.hostname.isNotEmpty ? d.hostname : 'PC-Workstation',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontFamily: 'monospace',
                                                    fontWeight: FontWeight.w600,
                                                    color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // App Version
                                        Expanded(
                                          flex: 2,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.warning_amber_rounded,
                                                  size: 13,
                                                  color: Color(0xFFEF4444),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'v${d.appVersion}',
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    fontFamily: 'monospace',
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFFEF4444),
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                const Text(
                                                  'قديم',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFFEF4444),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Status
                                        Container(
                                          width: 90,
                                          alignment: Alignment.centerLeft,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 7,
                                                height: 7,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: d.isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                d.isOnline ? 'متصل الآن' : 'غير متصل',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: d.isOnline
                                                      ? const Color(0xFF10B981)
                                                      : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                                ),
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
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 6. BRANCH DEVICES DETAIL MODAL
  // ---------------------------------------------------------------------------
  void _showBranchDevicesModal(
    BuildContext context,
    BranchDeploymentItem branch,
    bool isDark,
    String targetVersion,
  ) {
    final outdatedDevices = branch.devices
        .where((d) => compareAppVersions(d.appVersion, targetVersion) < 0)
        .toList();
    final upToDateDevices = branch.devices
        .where((d) => compareAppVersions(d.appVersion, targetVersion) >= 0)
        .toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131926) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Title Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'محطات عمل ومستخدمي فرع: ${branch.branchName}',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'كود الفرع: ${branch.branchCode}  •  إجمالي الأجهزة: ${branch.devicesCount} محطة  •  المتصلين: ${branch.onlineDevicesCount}',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, size: 22),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Content List
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Outdated Devices Section First!
                        if (outdatedDevices.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'أجهزة بنسخ قديمة تتطلب التحديث (${outdatedDevices.length} جهاز):',
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...outdatedDevices.map((d) => _buildDeviceCard(d, isDark, targetVersion, true)),
                          const SizedBox(height: 18),
                        ],

                        // Up to date Devices
                        if (upToDateDevices.isNotEmpty) ...[
                          Text(
                            'المحطات المحدثة بالكامل (${upToDateDevices.length} جهاز):',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...upToDateDevices.map((d) => _buildDeviceCard(d, isDark, targetVersion, false)),
                        ],

                        if (branch.devices.isEmpty && branch.installedUsers.isNotEmpty) ...[
                          Text(
                            'المستخدمين المسجلين بالفرع (${branch.installedUsers.length}):',
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          ...branch.installedUsers.map((u) => _buildUserCard(u, isDark)),
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

  Widget _buildDeviceCard(
    BranchDeviceItem d,
    bool isDark,
    String targetVersion,
    bool isOutdated,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOutdated
              ? const Color(0xFFEF4444).withValues(alpha: 0.4)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          width: isOutdated ? 1.4 : 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: d.isOnline
                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                  : (isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.computer_rounded,
              color: d.isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      d.hostname,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: isOutdated
                            ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                            : const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isOutdated
                            ? 'v${d.appVersion} (قديم يتطلب تحديث) ⚠️'
                            : 'v${d.appVersion} (معتمد) ✅',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                          color: isOutdated ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'الموظف: ${d.fullName.isNotEmpty ? d.fullName : d.username}  •  المسمى: ${d.workstationType}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'عنوان IP: ${d.ipAddress}  •  النظام: ${d.os} ${d.osVersion}  •  آخر ظهور: ${_formatTimeAgo(d.lastSeenAt)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: d.isOnline
                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                  : (isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              d.isOnline ? '🟢 متصل الآن' : '⚪ غير متصل',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: d.isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(InstalledUserItem u, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.15),
            child: Text(
              u.fullName.isNotEmpty ? u.fullName.characters.first : 'U',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF2563EB)),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'الحساب: @${u.username}  •  المسمى: ${u.jobTitle}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatTimeAgo(u.lastActiveAt),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 7. OPTIONAL LIVE SERVER REQUEST STREAM
  // ---------------------------------------------------------------------------
  Widget _buildLiveRequestsStreamCard(
    RequestTelemetryData? telemetry,
    bool isDark,
    ColorScheme cs,
  ) {
    final recent = telemetry?.recentRequests ?? [];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF090D16) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.sync_alt_rounded, color: Color(0xFF38BDF8), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سجل حركة واستجابة طلبات الخادم المباشرة (API Telemetry Stream)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'مراقبة فورية لأداء ومعدل طلبات الخادم (RPS: ${telemetry?.rps.toStringAsFixed(1) ?? "0"} req/s  •  Latency: ${telemetry?.avgLatencyMs ?? 14}ms)',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showRequestsStream = !_showRequestsStream;
                      });
                    },
                    icon: Icon(_showRequestsStream ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
                    label: Text(
                      _showRequestsStream ? 'طي السجل' : 'عرض السجل (${recent.length})',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            if (_showRequestsStream) ...[
              const Divider(height: 1),
              if (recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('جاري استقبال طلبات الـ API من الخادم...', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: recent.take(8).length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  ),
                  itemBuilder: (context, index) {
                    final req = recent[index];
                    final isOk = req.statusCode >= 200 && req.statusCode < 300;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text(
                            '${req.timestamp.hour.toString().padLeft(2, '0')}:${req.timestamp.minute.toString().padLeft(2, '0')}:${req.timestamp.second.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              req.method,
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w800, color: Color(0xFF0284C7)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              req.path,
                              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${req.statusCode}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              color: isOk ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${req.durationMs}ms',
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
