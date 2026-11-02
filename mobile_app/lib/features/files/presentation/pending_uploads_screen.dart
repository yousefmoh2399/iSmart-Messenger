import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../scanner/presentation/scanner_session_screen.dart';
import 'upload_summary_screen.dart';

class PendingUploadsScreen extends ConsumerStatefulWidget {
  const PendingUploadsScreen({super.key, this.hideAppBar = false});

  final bool hideAppBar;

  @override
  ConsumerState<PendingUploadsScreen> createState() =>
      _PendingUploadsScreenState();
}

class _PendingUploadsScreenState extends ConsumerState<PendingUploadsScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(pendingUploadsControllerProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _importLocalPdf() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      final pickedPath = result?.files.singleOrNull?.path;
      if (pickedPath == null || pickedPath.isEmpty) {
        return;
      }
      final pickedName = result?.files.singleOrNull?.name;
      final imported = await ref
          .read(pendingUploadsControllerProvider.notifier)
          .importLocalPdf(sourcePath: pickedPath, fileName: pickedName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم استيراد "${imported.fileName}" إلى الملفات المحلية'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر استيراد الملف: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _confirmDelete(PendingUpload item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFFF3B30)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'حذف الملف المحلي',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف "${item.fileName}" من ذاكرة الهاتف المحلية؟',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف الملف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(pendingUploadsControllerProvider.notifier)
        .removeById(item.id, filePath: item.filePath);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف الملف المحلي بنجاح')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingState = ref.watch(pendingUploadsControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    final body = Container(
      color: scaffoldBg,
      child: pendingState.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            ShimmerSkeleton(height: 140, borderRadius: 22),
            SizedBox(height: 14),
            ShimmerSkeleton(height: 120, borderRadius: 18),
            SizedBox(height: 12),
            ShimmerSkeleton(height: 120, borderRadius: 18),
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
                  size: 48,
                  color: Color(0xFFFF3B30),
                ),
                const SizedBox(height: 12),
                Text(
                  'حدث خطأ أثناء تحميل الملفات المحلية',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref
                      .read(pendingUploadsControllerProvider.notifier)
                      .refresh(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
        data: (allFiles) {
          final query = _searchController.text.trim().toLowerCase();
          final filtered = query.isEmpty
              ? allFiles
              : allFiles
                    .where((f) => f.fileName.toLowerCase().contains(query))
                    .toList();
          final totalSize = allFiles.fold<int>(0, (sum, f) => sum + f.fileSize);

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(pendingUploadsControllerProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
              children: [
                // Bento Header Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: borderCol),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.folder_special_rounded,
                              color: Colors.white,
                              size: 25,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'خزنة الملفات المحلية',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'جميع ملفات PDF الممسوحة والمحفوظة على هاتفك جاهزة للفتح أو الإرسال',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _LocalStatTile(
                              label: 'إجمالي الملفات',
                              value: '${allFiles.length} ملف',
                              icon: Icons.picture_as_pdf_rounded,
                              color: const Color(0xFF007AFF),
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _LocalStatTile(
                              label: 'المساحة المستخدمة',
                              value: formatFileSize(totalSize),
                              icon: Icons.sd_storage_rounded,
                              color: const Color(0xFFF59E0B),
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const ScannerSessionScreen(),
                                  ),
                                );
                                if (mounted) {
                                  await ref
                                      .read(
                                        pendingUploadsControllerProvider
                                            .notifier,
                                      )
                                      .refresh();
                                }
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF007AFF),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              icon: const Icon(
                                Icons.document_scanner_rounded,
                                size: 18,
                              ),
                              label: const Text(
                                'مسح مستند جديد',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: _isImporting ? null : _importLocalPdf,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(
                                  0xFFF59E0B,
                                ).withValues(alpha: 0.14),
                                foregroundColor: const Color(0xFFD97706),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              icon: const Icon(
                                Icons.file_upload_outlined,
                                size: 18,
                              ),
                              label: Text(
                                _isImporting
                                    ? 'جاري الاستيراد...'
                                    : 'استيراد PDF',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (allFiles.isNotEmpty) ...[
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'ابحث باسم الملف المحلي...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            )
                          : null,
                      filled: true,
                      fillColor: cardBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: borderCol),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: borderCol),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (filtered.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 42,
                    ),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderCol),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFF59E0B,
                            ).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.folder_open_rounded,
                            size: 34,
                            color: Color(0xFFD97706),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          allFiles.isEmpty
                              ? 'لا توجد ملفات محلية محفوظة حالياً'
                              : 'لا توجد ملفات مطابقة للبحث',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          allFiles.isEmpty
                              ? 'ابدأ بمسح مستند جديد بالكاميرا أو استورد ملف PDF من جهازك ليظهر هنا فوراً.'
                              : 'جرب البحث بكلمة أخرى أو امسح نص البحث.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  for (final item in filtered) ...[
                    _LocalDocumentBentoCard(
                      pendingUpload: item,
                      isDark: isDark,
                      cardBg: cardBg,
                      borderCol: borderCol,
                      onOpen: () => OpenFilex.open(item.filePath),
                      onUploadAndShare: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                UploadSummaryScreen(pendingUpload: item),
                          ),
                        );
                        if (mounted) {
                          await ref
                              .read(pendingUploadsControllerProvider.notifier)
                              .refresh();
                        }
                      },
                      onQuickShare: () async {
                        await Share.shareXFiles([
                          XFile(item.filePath, name: item.fileName),
                        ], text: item.fileName);
                      },
                      onDelete: () => _confirmDelete(item),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          );
        },
      ),
    );

    if (widget.hideAppBar) return body;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text(
          'ملفاتي المحلية',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'تحديث الملفات المحلية',
            onPressed: () =>
                ref.read(pendingUploadsControllerProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _LocalStatTile extends StatelessWidget {
  const _LocalStatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
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

class _LocalDocumentBentoCard extends StatelessWidget {
  const _LocalDocumentBentoCard({
    required this.pendingUpload,
    required this.isDark,
    required this.cardBg,
    required this.borderCol,
    required this.onOpen,
    required this.onUploadAndShare,
    required this.onQuickShare,
    required this.onDelete,
  });

  final PendingUpload pendingUpload;
  final bool isDark;
  final Color cardBg;
  final Color borderCol;
  final VoidCallback onOpen;
  final VoidCallback onUploadAndShare;
  final VoidCallback onQuickShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Color(0xFFEF4444),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pendingUpload.fileName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _MetaBadge(
                            icon: Icons.sd_storage_outlined,
                            text: formatFileSize(pendingUpload.fileSize),
                            isDark: isDark,
                          ),
                          _MetaBadge(
                            icon: Icons.layers_outlined,
                            text: '${pendingUpload.pageCount} صفحة',
                            isDark: isDark,
                          ),
                          _MetaBadge(
                            icon: Icons.schedule_rounded,
                            text: formatDate(pendingUpload.createdAt),
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: borderCol),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onUploadAndShare,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                  label: const Text(
                    'رفع / طباعة / إرسال',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                icon: const Icon(Icons.visibility_rounded, size: 16),
                label: const Text(
                  'فتح',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'مشاركة سريعة',
                onPressed: onQuickShare,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.ios_share_rounded, size: 17),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'حذف الملف',
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(
                    0xFFFF3B30,
                  ).withValues(alpha: 0.1),
                  foregroundColor: const Color(0xFFFF3B30),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({
    required this.icon,
    required this.text,
    required this.isDark,
  });

  final IconData icon;
  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
