import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/providers/providers.dart';

class PendingUploadsController extends AsyncNotifier<List<PendingUpload>> {
  void resetState() {
    state = const AsyncLoading();
  }

  bool _isSyncing = false;

  @override
  Future<List<PendingUpload>> build() async {
    return ref.read(localDocumentStoreProvider).loadAllLocalDocuments();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(localDocumentStoreProvider).loadAllLocalDocuments(),
    );
  }

  Future<PendingUpload> importLocalPdf({
    required String sourcePath,
    String? fileName,
  }) async {
    final imported = await ref
        .read(localDocumentStoreProvider)
        .importLocalPdfFile(sourcePath: sourcePath, fileName: fileName);
    await refresh();
    return imported;
  }

  Future<void> removeById(String id, {String? filePath}) async {
    await ref
        .read(localDocumentStoreProvider)
        .deleteLocalDocument(id, filePath: filePath);
    await refresh();
  }

  Future<int> syncAllPendingUploads({int maxItems = 10}) async {
    if (_isSyncing) {
      return 0;
    }
    _isSyncing = true;
    var uploadedCount = 0;
    try {
      final repository = ref.read(documentRepositoryProvider);
      final localStore = ref.read(localDocumentStoreProvider);
      final pending = await localStore.loadPendingUploads();
      if (pending.isEmpty) {
        return 0;
      }

      final toSync = pending.take(maxItems);
      for (final item in toSync) {
        try {
          await repository.uploadPendingDocument(item);
          await localStore.removePendingUpload(item.id);
          uploadedCount++;
        } catch (_) {
          // Keep failed items in queue for a later retry.
        }
      }

      await ref.read(remoteDocumentsControllerProvider.notifier).refresh();
      await refresh();
      return uploadedCount;
    } finally {
      _isSyncing = false;
    }
  }
}
