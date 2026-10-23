import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/storage_cleaner_service.dart';

class StorageManagementScreen extends ConsumerStatefulWidget {
  const StorageManagementScreen({super.key});

  @override
  ConsumerState<StorageManagementScreen> createState() =>
      _StorageManagementScreenState();
}

class _StorageManagementScreenState
    extends ConsumerState<StorageManagementScreen> {
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
    final service = ref.read(storageCleanerServiceProvider);
    final breakdown = await service.calculateBreakdown();
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
      title: 'تنظيف شامل للذاكرة المؤقتة',
      message:
          'سيتم مسح كافة ملفات الكاش والوسائط المؤقتة بأمان.\nمحادثاتك ورسائلك ستظل محفوظة بالكامل دون أي مساس.',
      confirmLabel: 'تنظيف شامل',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isCleaning = true);
    HapticFeedback.mediumImpact();

    final service = ref.read(storageCleanerServiceProvider);
    await service.clearAll();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تنظيف الذاكرة المؤقتة بنجاح وتسريع التطبيق!'),
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

    final service = ref.read(storageCleanerServiceProvider);
    await service.clearCategory(category);

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
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF3B30),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                confirmLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  void _showRetentionPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'فترة الاحتفاظ بالملفات المؤقتة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected
                      ? const Color(0xFF007AFF)
                      : (isDark ? Colors.white30 : Colors.black26),
                ),
                title: Text(
                  item.$2,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final breakdown = _breakdown ?? const StorageBreakdown();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text(
          'إدارة مساحة التخزين',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
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
          ? const Center(child: CircularProgressIndicator.adaptive())
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    // ── Hero Storage Breakdown Card ────────────────────────
                    _buildAppleStorageHeroCard(breakdown, isDark),
                    const SizedBox(height: 14),

                    // ── One-Tap Quick Clean Card ───────────────────────────
                    _buildQuickCleanCard(breakdown, isDark),
                    const SizedBox(height: 20),

                    // ── Detailed Breakdown Inset Group ─────────────────────
                    _buildSectionHeader('تفاصيل الذاكرة المؤقتة', isDark),
                    const SizedBox(height: 8),
                    _buildBreakdownInsetGroup(breakdown, isDark),
                    const SizedBox(height: 20),

                    // ── Auto-Clean Settings Inset Group ────────────────────
                    _buildSectionHeader('التحكم التلقائي والسياسات', isDark),
                    const SizedBox(height: 8),
                    _buildSettingsInsetGroup(isDark),
                    const SizedBox(height: 20),

                    // ── Safety Guarantee Banner ────────────────────────────
                    _buildSafetyBanner(isDark),
                    const SizedBox(height: 32),
                  ],
                ),
                if (_isCleaning)
                  Container(
                    color: Colors.black38,
                    child: const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator.adaptive(),
                              SizedBox(height: 16),
                              Text('جارٍ تنظيف الذاكرة المؤقتة وتسريع التطبيق...'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
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

  Widget _buildAppleStorageHeroCard(StorageBreakdown breakdown, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E5EA),
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.all(18),
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
                    'المساحة المستهلكة مؤقتاً',
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
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.speed_rounded, size: 14, color: Color(0xFF007AFF)),
                    SizedBox(width: 4),
                    Text(
                      'قابل للتحرير',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Multi-Segment Visual Bar (Apple iOS Storage Bar)
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: SizedBox(
              height: 12,
              child: _buildSegmentedBar(breakdown),
            ),
          ),
          const SizedBox(height: 14),

          // Legend Row
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _buildLegendDot(
                color: const Color(0xFF5856D6),
                label: 'الكاش',
                size: breakdown.formattedAppCache,
                isDark: isDark,
              ),
              _buildLegendDot(
                color: const Color(0xFF007AFF),
                label: 'الصور',
                size: breakdown.formattedMedia,
                isDark: isDark,
              ),
              _buildLegendDot(
                color: const Color(0xFFFF9500),
                label: 'الصوتيات',
                size: breakdown.formattedAudio,
                isDark: isDark,
              ),
              _buildLegendDot(
                color: const Color(0xFF34C759),
                label: 'المستندات',
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
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$label ($size)',
          style: TextStyle(
            fontSize: 11.5,
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
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E5EA),
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.cleaning_services_rounded,
                  color: Color(0xFF34C759),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تسريع التطبيق وتحرير الذاكرة',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasSpace
                          ? 'يمكن تحرير ${breakdown.formattedTotal} بأمان تام'
                          : 'الذاكرة المؤقتة نظيفة والجهاز يعمل بأفضل كفاءة',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: hasSpace && !_isCleaning ? _handleCleanAll : null,
            icon: const Icon(Icons.bolt_rounded, size: 20),
            label: Text(
              hasSpace
                  ? 'تنظيف شامل بنقرة واحدة (${breakdown.formattedTotal})'
                  : 'الذاكرة المؤقتة فارغة',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
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
            title: 'الذاكرة المؤقتة للتطبيق (App Cache)',
            subtitle: 'الملفات التمهيدية وبيانات التصفح المؤقتة',
            sizeText: breakdown.formattedAppCache,
            hasFiles: breakdown.appCacheBytes > 0,
            onClear: () => _handleCleanCategory(
              StorageCategory.appCache,
              'الذاكرة المؤقتة للكاش',
            ),
            isDark: isDark,
          ),
          Divider(
            height: 0.5,
            indent: 58,
            color: isDark ? Colors.white12 : const Color(0xFFE5E5EA),
          ),
          _buildCategoryTile(
            icon: Icons.image_rounded,
            iconColor: const Color(0xFF007AFF),
            title: 'الصور والوسائط المؤقتة',
            subtitle: 'المصغرات والمعاينات المحفوظة محلياً',
            sizeText: breakdown.formattedMedia,
            hasFiles: breakdown.mediaBytes > 0,
            onClear: () => _handleCleanCategory(
              StorageCategory.media,
              'الصور والوسائط المؤقتة',
            ),
            isDark: isDark,
          ),
          Divider(
            height: 0.5,
            indent: 58,
            color: isDark ? Colors.white12 : const Color(0xFFE5E5EA),
          ),
          _buildCategoryTile(
            icon: Icons.mic_rounded,
            iconColor: const Color(0xFFFF9500),
            title: 'الملاحظات الصوتية المؤقتة',
            subtitle: 'التسجيلات المستمع إليها ومسودات الصوت',
            sizeText: breakdown.formattedAudio,
            hasFiles: breakdown.audioBytes > 0,
            onClear: () => _handleCleanCategory(
              StorageCategory.audio,
              'الملاحظات الصوتية المؤقتة',
            ),
            isDark: isDark,
          ),
          Divider(
            height: 0.5,
            indent: 58,
            color: isDark ? Colors.white12 : const Color(0xFFE5E5EA),
          ),
          _buildCategoryTile(
            icon: Icons.description_rounded,
            iconColor: const Color(0xFF34C759),
            title: 'المستندات والمرفقات',
            subtitle: 'معاينات PDF والمستندات المؤقتة',
            sizeText: breakdown.formattedDocuments,
            hasFiles: breakdown.documentsBytes > 0,
            onClear: () => _handleCleanCategory(
              StorageCategory.documents,
              'المستندات المؤقتة',
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            sizeText,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(48, 28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: hasFiles && !_isCleaning ? onClear : null,
            child: const Text('مسح', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsInsetGroup(bool isDark) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
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
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.timer_outlined, color: Color(0xFF007AFF), size: 18),
            ),
            title: const Text('الاحتفاظ بالملفات المؤقتة', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _retentionDays == 0 ? 'دائم' : '$_retentionDays يوماً',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF007AFF), fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_left_rounded, size: 18, color: Colors.grey),
              ],
            ),
            onTap: _showRetentionPicker,
          ),
          Divider(
            height: 0.5,
            indent: 58,
            color: isDark ? Colors.white12 : const Color(0xFFE5E5EA),
          ),
          SwitchListTile.adaptive(
            value: _cleanOnLogout,
            onChanged: (val) async {
              final service = ref.read(storageCleanerServiceProvider);
              await service.setCleanOnLogout(val);
              setState(() => _cleanOnLogout = val);
            },
            secondary: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.logout_rounded, color: Color(0xFFFF9500), size: 18),
            ),
            title: const Text('مسح الكاش عند تسجيل الخروج', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('تفريغ الذاكرة المؤقتة تلقائياً عند قفل الجلسة', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
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
          Icon(
            Icons.shield_outlined,
            color: Color(0xFF34C759),
            size: 22,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'محادثاتك ورسائلك في أمان تام',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF34C759),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'عملية تنظيف الذاكرة المؤقتة تمسح الملفات غير الضرورية على الهاتف فقط لتسريعه، ولا تؤثر مطلقاً على نصوص الرسائل أو جهات الاتصال أو تاريخ المحادثات.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
