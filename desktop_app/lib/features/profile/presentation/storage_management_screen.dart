import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/providers.dart';
import '../data/storage_cleaner_service.dart';

class DesktopStorageManagementScreen extends ConsumerStatefulWidget {
  const DesktopStorageManagementScreen({super.key});

  @override
  ConsumerState<DesktopStorageManagementScreen> createState() =>
      _DesktopStorageManagementScreenState();
}

class _DesktopStorageManagementScreenState
    extends ConsumerState<DesktopStorageManagementScreen> {
  StorageBreakdown? _breakdown;
  bool _isLoading = true;
  bool _isCleaning = false;
  int _retentionDays = 30;
  bool _cleanOnLogout = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final preferences = ref.read(userPreferencesControllerProvider).valueOrNull;
    final service = ref.read(storageCleanerServiceProvider);
    final breakdown = await service.calculateBreakdown(
      customLocalStoragePath: preferences?.localStorageDirectoryPath,
    );
    final retention = await service.getRetentionDays();
    final cleanOnLogout = await service.getCleanOnLogout();

    if (mounted) {
      setState(() {
        _breakdown = breakdown;
        _retentionDays = retention;
        _cleanOnLogout = cleanOnLogout;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleCleanAll() async {
    final confirmed = await _confirmDialog(
      title: 'تنظيف شامل للذاكرة المؤقتة (Cache Cleaner)',
      message:
          'سيتم مسح كافة ملفات الكاش والمعاينات المؤقتة لتسريع التطبيق والكمبيوتر.\nكافة محادثاتك وسجل الرسائل ستظل محفوظة بالكامل دون أي مساس.',
      confirmLabel: 'تنظيف شامل للذاكرة',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isCleaning = true);
    HapticFeedback.mediumImpact();

    final preferences = ref.read(userPreferencesControllerProvider).valueOrNull;
    final service = ref.read(storageCleanerServiceProvider);
    await service.clearAll(
      customLocalStoragePath: preferences?.localStorageDirectoryPath,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تنظيف الذاكرة المؤقتة بنجاح وتسريع أداء التطبيق!'),
          backgroundColor: Color(0xFF34C759),
        ),
      );
      await _loadData();
      setState(() => _isCleaning = false);
    }
  }

  Future<void> _handleCleanCategory(StorageCategory category, String name) async {
    final confirmed = await _confirmDialog(
      title: 'مسح $name',
      message:
          'سيتم مسح الملفات المؤقتة الخاصة بـ $name.\nلن يتم حذف أي نصوص من محادثاتك.',
      confirmLabel: 'مسح الملفات',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isCleaning = true);
    HapticFeedback.selectionClick();

    final preferences = ref.read(userPreferencesControllerProvider).valueOrNull;
    final service = ref.read(storageCleanerServiceProvider);
    await service.clearCategory(
      category,
      customLocalStoragePath: preferences?.localStorageDirectoryPath,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم مسح $name بنجاح!'),
          duration: const Duration(seconds: 2),
        ),
      );
      await _loadData();
      setState(() => _isCleaning = false);
    }
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF3B30), size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                message,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(
                      'إلغاء',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3B30),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(confirmLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result == true;
  }

  void _showRetentionPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'فترة الاحتفاظ بالملفات المؤقتة',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 14),
              ...[
                (30, '30 يوماً (موصى به)'),
                (60, '60 يوماً'),
                (90, '90 يوماً'),
                (0, 'دائم (بدون حذف تلقائي)'),
              ].map((item) {
                final isSelected = _retentionDays == item.$1;
                return ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: Icon(
                    isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: isSelected ? const Color(0xFF007AFF) : Colors.grey,
                  ),
                  title: Text(item.$2, style: const TextStyle(fontSize: 13.5)),
                  onTap: () async {
                    final service = ref.read(storageCleanerServiceProvider);
                    await service.setRetentionDays(item.$1);
                    setState(() => _retentionDays = item.$1);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final breakdown = _breakdown ?? const StorageBreakdown();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'إدارة مساحة التخزين والكاش',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث الحساب',
            onPressed: _isLoading || _isCleaning ? null : _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  children: [
                    // ── Hero Storage Breakdown Card ────────────────────────
                    _buildStorageHeroCard(breakdown, isDark),
                    const SizedBox(height: 14),

                    // ── One-Tap Quick Clean Card ───────────────────────────
                    _buildQuickCleanCard(breakdown, isDark),
                    const SizedBox(height: 22),

                    // ── Detailed Breakdown Inset Group ─────────────────────
                    _buildSectionHeader('تفاصيل الذاكرة المؤقتة على جهاز الكمبيوتر', isDark),
                    const SizedBox(height: 8),
                    _buildBreakdownInsetGroup(breakdown, isDark),
                    const SizedBox(height: 22),

                    // ── Auto-Clean Settings Inset Group ────────────────────
                    _buildSectionHeader('التحكم التلقائي والسياسات', isDark),
                    const SizedBox(height: 8),
                    _buildSettingsInsetGroup(isDark),
                    const SizedBox(height: 22),

                    // ── Safety Guarantee Banner ────────────────────────────
                    _buildSafetyBanner(isDark),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _buildStorageHeroCard(StorageBreakdown breakdown, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E5EA),
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'المساحة المستهلكة بالملفات المؤقتة والكاش',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    breakdown.formattedTotal,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.speed_rounded, size: 15, color: Color(0xFF007AFF)),
                    SizedBox(width: 5),
                    Text(
                      'قابل للتحرير الفوري',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Multi-Segment Visual Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: _buildSegmentedBar(breakdown),
            ),
          ),
          const SizedBox(height: 14),

          // Legend Row
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildLegendDot(
                color: const Color(0xFF5856D6),
                label: 'الكاش وChromium',
                size: breakdown.formattedAppCache,
                isDark: isDark,
              ),
              _buildLegendDot(
                color: const Color(0xFF007AFF),
                label: 'الصور والوسائط',
                size: breakdown.formattedMedia,
                isDark: isDark,
              ),
              _buildLegendDot(
                color: const Color(0xFFFF9500),
                label: 'الصوتيات والمسودات',
                size: breakdown.formattedAudio,
                isDark: isDark,
              ),
              _buildLegendDot(
                color: const Color(0xFF34C759),
                label: 'المستندات والمعاينات',
                size: breakdown.formattedDocuments,
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedBar(StorageBreakdown breakdown) {
    final total = breakdown.totalBytes;
    if (total <= 0) {
      return Container(color: const Color(0xFFE5E5EA));
    }

    final cacheFlex = (breakdown.appCacheBytes / total * 100).round().clamp(1, 100);
    final mediaFlex = (breakdown.mediaBytes / total * 100).round().clamp(1, 100);
    final audioFlex = (breakdown.audioBytes / total * 100).round().clamp(1, 100);
    final docFlex = (breakdown.documentsBytes / total * 100).round().clamp(1, 100);

    return Row(
      children: [
        if (breakdown.appCacheBytes > 0)
          Expanded(
            flex: cacheFlex,
            child: Container(color: const Color(0xFF5856D6)),
          ),
        if (breakdown.mediaBytes > 0)
          Expanded(
            flex: mediaFlex,
            child: Container(color: const Color(0xFF007AFF)),
          ),
        if (breakdown.audioBytes > 0)
          Expanded(
            flex: audioFlex,
            child: Container(color: const Color(0xFFFF9500)),
          ),
        if (breakdown.documentsBytes > 0)
          Expanded(
            flex: docFlex,
            child: Container(color: const Color(0xFF34C759)),
          ),
      ],
    );
  }

  Widget _buildLegendDot({
    required Color color,
    required String label,
    required String size,
    required bool isDark,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ($size)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickCleanCard(StorageBreakdown breakdown, bool isDark) {
    final hasSpace = breakdown.totalBytes > 0;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E5EA),
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF34C759).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.cleaning_services_rounded, color: Color(0xFF34C759), size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تسريع البرنامج وتحرير مساحة القرص',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasSpace
                      ? 'يمكن تحرير ${breakdown.formattedTotal} فوراً دون أي مساس بنصوص الرسائل والمحادثات'
                      : 'الذاكرة المؤقتة نظيفة تماماً ولا توجد ملفات مهملة',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: hasSpace && !_isCleaning ? _handleCleanAll : null,
            icon: const Icon(Icons.bolt_rounded, size: 20),
            label: Text(
              hasSpace ? 'تنظيف شامل (${breakdown.formattedTotal})' : 'الذاكرة نظيفة',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownInsetGroup(StorageBreakdown breakdown, bool isDark) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E5EA),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          _buildCategoryTile(
            icon: Icons.cached_rounded,
            iconColor: const Color(0xFF5856D6),
            title: 'كاش البرنامج ومتصفح Electron',
            subtitle: 'الملفات المؤقتة وبيانات الجلسات التمهيدية',
            sizeText: breakdown.formattedAppCache,
            hasFiles: breakdown.appCacheBytes > 0,
            onClear: () => _handleCleanCategory(StorageCategory.appCache, 'كاش البرنامج'),
            isDark: isDark,
          ),
          Divider(height: 0.5, indent: 64, color: isDark ? Colors.white12 : const Color(0xFFE5E5EA)),
          _buildCategoryTile(
            icon: Icons.image_rounded,
            iconColor: const Color(0xFF007AFF),
            title: 'الصور والوسائط المؤقتة',
            subtitle: 'معاينات ومصغرات الصور المحفوظة محلياً',
            sizeText: breakdown.formattedMedia,
            hasFiles: breakdown.mediaBytes > 0,
            onClear: () => _handleCleanCategory(StorageCategory.media, 'الصور والوسائط المؤقتة'),
            isDark: isDark,
          ),
          Divider(height: 0.5, indent: 64, color: isDark ? Colors.white12 : const Color(0xFFE5E5EA)),
          _buildCategoryTile(
            icon: Icons.mic_rounded,
            iconColor: const Color(0xFFFF9500),
            title: 'الملاحظات الصوتية المؤقتة',
            subtitle: 'التسجيلات المستمع إليها ومسودات الصوت',
            sizeText: breakdown.formattedAudio,
            hasFiles: breakdown.audioBytes > 0,
            onClear: () => _handleCleanCategory(StorageCategory.audio, 'الملاحظات الصوتية المؤقتة'),
            isDark: isDark,
          ),
          Divider(height: 0.5, indent: 64, color: isDark ? Colors.white12 : const Color(0xFFE5E5EA)),
          _buildCategoryTile(
            icon: Icons.description_rounded,
            iconColor: const Color(0xFF34C759),
            title: 'المستندات والمرفقات',
            subtitle: 'معاينات PDF والمستندات المؤقتة المحملة',
            sizeText: breakdown.formattedDocuments,
            hasFiles: breakdown.documentsBytes > 0,
            onClear: () => _handleCleanCategory(StorageCategory.documents, 'المستندات المؤقتة'),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String sizeText,
    required bool hasFiles,
    required VoidCallback onClear,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            sizeText,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: hasFiles && !_isCleaning ? onClear : null,
            child: const Text('مسح', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsInsetGroup(bool isDark) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E5EA),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.timer_outlined, color: Color(0xFF007AFF), size: 18),
            ),
            title: const Text('الاحتفاظ بالملفات المؤقتة', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _retentionDays == 0 ? 'دائم' : '$_retentionDays يوماً',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF007AFF), fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_left_rounded, size: 20, color: Colors.grey),
              ],
            ),
            onTap: _showRetentionPicker,
          ),
          Divider(height: 0.5, indent: 64, color: isDark ? Colors.white12 : const Color(0xFFE5E5EA)),
          SwitchListTile.adaptive(
            value: _cleanOnLogout,
            onChanged: (val) async {
              final service = ref.read(storageCleanerServiceProvider);
              await service.setCleanOnLogout(val);
              setState(() => _cleanOnLogout = val);
            },
            secondary: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.logout_rounded, color: Color(0xFFFF9500), size: 18),
            ),
            title: const Text('مسح الكاش عند تسجيل الخروج', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: const Text('تفريغ الكاش والذاكرة المؤقتة تلقائياً عند قفل الجلسة على جهاز الكمبيوتر', style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF34C759).withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF34C759).withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: Color(0xFF34C759), size: 24),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'محادثاتك ورسائلك في أمان تام',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF34C759)),
                ),
                SizedBox(height: 4),
                Text(
                  'عملية تنظيف الذاكرة المؤقتة تمسح الملفات الزائدة وغير الضرورية على جهاز الكمبيوتر فقط لتسريعه، ولا تؤثر مطلقاً على نصوص الرسائل أو جهات الاتصال أو تاريخ المحادثات، ويمكن إعادة تحميل أي ملف تم مسح الكاش الخاص به في أي وقت.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF2E7D32)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
