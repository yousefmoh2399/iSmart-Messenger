import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/document_paper_size.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/models/scan_session.dart';
import '../../../shared/providers/providers.dart';
import '../data/pdf_builder_service.dart';

class ScanSessionController extends AsyncNotifier<ScanSession?> {
  void resetState() { state = const AsyncLoading(); }

  @override
  Future<ScanSession?> build() async {
    return ref.read(localDocumentStoreProvider).loadDraft();
  }

  Future<void> ensureSession() async {
    if (state.valueOrNull != null) return;
    final session = ScanSession.create();
    await ref.read(localDocumentStoreProvider).saveDraft(session);
    state = AsyncData(session);
  }

  Future<void> addPage(ScanPage page) async {
    final session = state.valueOrNull ?? ScanSession.create();
    final updated = session.copyWith(pages: [...session.pages, page]);
    await ref.read(localDocumentStoreProvider).saveDraft(updated);
    state = AsyncData(updated);
  }

  Future<void> replacePage(String pageId, ScanPage newPage) async {
    final session = state.valueOrNull;
    if (session == null) return;

    final currentPage = session.pages.firstWhere(
      (page) => page.id == pageId,
      orElse: () => newPage,
    );
    if (currentPage.imagePath != newPage.imagePath) {
      await ref
          .read(localDocumentStoreProvider)
          .deletePageFile(currentPage.imagePath);
    }

    final updated = session.copyWith(
      pages: session.pages
          .map((page) => page.id == pageId ? newPage : page)
          .toList(),
    );
    await ref.read(localDocumentStoreProvider).saveDraft(updated);
    state = AsyncData(updated);
  }

  Future<void> rotatePage(String pageId) async {
    final session = state.valueOrNull;
    if (session == null) return;

    final targetPage = session.pages.firstWhere((page) => page.id == pageId);
    await ref
        .read(imageProcessingServiceProvider)
        .rotateFileInPlace(targetPage.imagePath);
    final updated = session.copyWith(pages: [...session.pages]);
    await ref.read(localDocumentStoreProvider).saveDraft(updated);
    state = AsyncData(updated);
  }

  Future<void> deletePage(String pageId) async {
    final session = state.valueOrNull;
    if (session == null) return;

    final targetPage = session.pages.firstWhere((page) => page.id == pageId);
    await ref
        .read(localDocumentStoreProvider)
        .deletePageFile(targetPage.imagePath);
    final updatedPages = session.pages
        .where((page) => page.id != pageId)
        .toList();

    if (updatedPages.isEmpty) {
      await clearSession();
      return;
    }

    final updated = session.copyWith(pages: updatedPages);
    await ref.read(localDocumentStoreProvider).saveDraft(updated);
    state = AsyncData(updated);
  }

  Future<void> reorderPages(int oldIndex, int newIndex) async {
    final session = state.valueOrNull;
    if (session == null) return;

    final items = [...session.pages];
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    final updated = session.copyWith(pages: items);
    await ref.read(localDocumentStoreProvider).saveDraft(updated);
    state = AsyncData(updated);
  }

  Future<void> updatePagePaperSize(
    String pageId,
    DocumentPaperSize paperSize,
  ) async {
    final session = state.valueOrNull;
    if (session == null) return;

    final updated = session.copyWith(
      pages: session.pages
          .map(
            (page) =>
                page.id == pageId ? page.copyWith(paperSize: paperSize) : page,
          )
          .toList(),
    );
    await ref.read(localDocumentStoreProvider).saveDraft(updated);
    state = AsyncData(updated);
  }

  Future<PendingUpload> saveCurrentSession(
    String fileName, {
    String? saveDirectoryPath,
    bool applyEnhancement = false,
  }) async {
    final session = state.valueOrNull;
    if (session == null || session.pages.isEmpty) {
      throw Exception('لا توجد صفحات لحفظها.');
    }

    final pdfBytes = await ref
        .read(pdfBuilderServiceProvider)
        .buildPdf(
          imagePaths: session.pages.map((page) => page.imagePath).toList(),
          paperSizes: session.pages.map((page) => page.paperSize).toList(),
          applyEnhancement: applyEnhancement,
        );

    final pending = await ref
        .read(localDocumentStoreProvider)
        .createPendingUpload(
          fileName: fileName,
          pdfBytes: pdfBytes,
          pageCount: session.pages.length,
          saveDirectoryPath: saveDirectoryPath,
        );

    await ref.read(localDocumentStoreProvider).clearDraft();
    await ref.read(localDocumentStoreProvider).clearSessionFiles(session.id);
    state = const AsyncData(null);
    return pending;
  }

  Future<void> clearSession() async {
    final session = state.valueOrNull;
    if (session != null) {
      await ref.read(localDocumentStoreProvider).clearSessionFiles(session.id);
    }
    await ref.read(localDocumentStoreProvider).clearDraft();
    state = const AsyncData(null);
  }

  Future<void> startNewEmptySession() async {
    await clearSession();
    await ensureSession();
  }
}





