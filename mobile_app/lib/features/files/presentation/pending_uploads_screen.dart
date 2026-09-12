import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import 'upload_summary_screen.dart';

class PendingUploadsScreen extends ConsumerWidget {
  const PendingUploadsScreen({super.key, this.hideAppBar = false});

  final bool hideAppBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingState = ref.watch(pendingUploadsControllerProvider);

    final body = pendingState.when(
      loading: () => ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ShimmerSkeleton(height: 126, borderRadius: 16),
          SizedBox(height: 12),
          ShimmerSkeleton(height: 126, borderRadius: 16),
          SizedBox(height: 12),
          ShimmerSkeleton(height: 126, borderRadius: 16),
        ],
      ),
      error: (error, stackTrace) => Center(child: Text(error.toString())),
      data: (pendingUploads) {
        if (pendingUploads.isEmpty) {
          return const Center(child: Text('لا توجد ملفات محلية محفوظة'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: pendingUploads.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final pendingUpload = pendingUploads[index];
            return _PendingUploadCard(pendingUpload: pendingUpload);
          },
        );
      },
    );

    if (hideAppBar) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الملفات المحلية'),
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(pendingUploadsControllerProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _PendingUploadCard extends ConsumerWidget {
  const _PendingUploadCard({required this.pendingUpload});

  final PendingUpload pendingUpload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pendingUpload.fileName,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('عدد الصفحات: ${pendingUpload.pageCount}'),
                Text('الحجم: ${formatFileSize(pendingUpload.fileSize)}'),
                Text('التاريخ: ${formatDate(pendingUpload.createdAt)}'),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            UploadSummaryScreen(pendingUpload: pendingUpload),
                      ),
                    );
                  },
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('إرسال ومشاركة'),
                ),
                OutlinedButton.icon(
                  onPressed: () => OpenFilex.open(pendingUpload.filePath),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('فتح محليًا'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref
                        .read(pendingUploadsControllerProvider.notifier)
                        .removeById(pendingUpload.id);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('حذف'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
