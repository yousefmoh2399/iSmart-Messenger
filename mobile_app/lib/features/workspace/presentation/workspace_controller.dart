import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/providers.dart';
import '../../chat/data/chat_socket_service.dart';
import '../data/workspace_repository.dart';
import '../models/workspace_doc.dart';
import 'workspace_templates.dart';

final workspaceRepositoryProvider = Provider<WorkspaceRepository>((ref) {
  return WorkspaceRepository();
});

final workspaceDocsProvider =
    StateNotifierProvider<WorkspaceDocsNotifier, AsyncValue<List<WorkspaceDoc>>>(
  (ref) {
    final repo = ref.watch(workspaceRepositoryProvider);
    final user = ref.watch(currentUserProvider);
    final userId = user?.id ?? '';
    return WorkspaceDocsNotifier(ref: ref, repo: repo, userId: userId);
  },
);

class WorkspaceDocsNotifier extends StateNotifier<AsyncValue<List<WorkspaceDoc>>> {
  WorkspaceDocsNotifier({
    required this.ref,
    required this.repo,
    required this.userId,
  }) : super(const AsyncValue.loading()) {
    if (userId.isNotEmpty) {
      _listenToSocketSync();
      loadDocs();
    } else {
      state = const AsyncValue.data([]);
    }
  }

  final Ref ref;
  final WorkspaceRepository repo;
  final String userId;
  StreamSubscription<ChatSocketEvent>? _socketSub;

  void _listenToSocketSync() {
    _socketSub?.cancel();
    final socketService = ref.read(chatSocketServiceProvider);
    _socketSub = socketService.events.listen((event) {
      if (!mounted) return;
      if (event.type == 'workspace_docs_updated') {
        final rawList = event.payload['docs'];
        if (rawList is List) {
          final parsed = rawList
              .whereType<Map>()
              .map((e) => WorkspaceDoc.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          state = AsyncValue.data(parsed);
          unawaited(repo.saveDocs(userId, parsed));
        }
      } else if (event.type == 'socket_connected') {
        unawaited(_pullFromServer());
      }
    });
  }

  Future<void> _pullFromServer() async {
    try {
      final sock = ref.read(chatSocketServiceProvider).socket;
      if (sock == null || !sock.connected) return;
      sock.emitWithAck('workspace:get_docs', const <String, dynamic>{}, ack: (res) {
        if (!mounted) return;
        try {
          if (res is Map && res['ok'] == true && res['data'] is Map) {
            final raw = (res['data'] as Map)['docs'];
            if (raw is List && raw.isNotEmpty) {
              final remoteDocs = raw
                  .whereType<Map>()
                  .map(
                    (e) => WorkspaceDoc.fromJson(Map<String, dynamic>.from(e)),
                  )
                  .toList();
              if (remoteDocs.isNotEmpty) {
                state = AsyncValue.data(remoteDocs);
                unawaited(repo.saveDocs(userId, remoteDocs));
                return;
              }
            } else {
              final localDocs = state.valueOrNull ?? const <WorkspaceDoc>[];
              if (localDocs.isNotEmpty) {
                unawaited(_pushToServer(localDocs));
              }
            }
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<void> _pushToServer(List<WorkspaceDoc> docs) async {
    try {
      final sock = ref.read(chatSocketServiceProvider).socket;
      if (sock == null || !sock.connected) return;
      sock.emit('workspace:sync_docs', {
        'docs': docs.map((d) => d.toJson()).toList(),
      });
    } catch (_) {}
  }

  Future<void> _persistAndSync(List<WorkspaceDoc> docs) async {
    await repo.saveDocs(userId, docs);
    unawaited(_pushToServer(docs));
  }

  Future<void> loadDocs() async {
    state = const AsyncValue.loading();
    try {
      final docs = await repo.getDocs(userId);
      state = AsyncValue.data(docs);
      unawaited(_pullFromServer());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    super.dispose();
  }

  Future<WorkspaceDoc> createDoc({
    String? title,
    String? icon,
    String? coverColor,
    String? category,
    List<WorkspaceBlock>? blocks,
  }) async {
    final current = state.valueOrNull ?? [];
    final newDoc = WorkspaceDoc(
      userId: userId,
      title: title ?? 'بدون عنوان',
      icon: icon ?? '📝',
      coverColor: coverColor ?? '0xFFE2E8F0',
      category: category ?? 'عام',
      blocks: blocks ??
          [
            WorkspaceBlock(
              type: WorkspaceBlockType.text,
              content: '',
            ),
          ],
    );

    final updated = [newDoc, ...current];
    state = AsyncValue.data(updated);
    await _persistAndSync(updated);
    return newDoc;
  }

  Future<WorkspaceDoc> createFromTemplate(WorkspaceTemplate template) async {
    final current = state.valueOrNull ?? [];
    final newDoc = WorkspaceDoc(
      userId: userId,
      title: template.title,
      icon: template.icon,
      coverColor: template.coverColor,
      category: template.category,
      blocks: template.blocksBuilder(),
    );

    final updated = [newDoc, ...current];
    state = AsyncValue.data(updated);
    await _persistAndSync(updated);
    return newDoc;
  }

  Future<void> updateDoc(WorkspaceDoc doc) async {
    final current = state.valueOrNull ?? [];
    final index = current.indexWhere((d) => d.id == doc.id);
    if (index == -1) return;

    final next = List<WorkspaceDoc>.from(current);
    doc.updatedAt = DateTime.now();
    next[index] = doc;

    // Keep sorted
    next.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });

    state = AsyncValue.data(next);
    await _persistAndSync(next);
  }

  Future<void> togglePin(String docId) async {
    final current = state.valueOrNull ?? [];
    final index = current.indexWhere((d) => d.id == docId);
    if (index == -1) return;

    final doc = current[index];
    final updatedDoc = doc.copyWith(isPinned: !doc.isPinned);
    await updateDoc(updatedDoc);
  }

  Future<void> toggleFavorite(String docId) async {
    final current = state.valueOrNull ?? [];
    final index = current.indexWhere((d) => d.id == docId);
    if (index == -1) return;

    final doc = current[index];
    final updatedDoc = doc.copyWith(isFavorite: !doc.isFavorite);
    await updateDoc(updatedDoc);
  }

  Future<void> toggleTodoItem(String docId, String blockId) async {
    final current = state.valueOrNull ?? [];
    final docIndex = current.indexWhere((d) => d.id == docId);
    if (docIndex == -1) return;

    final doc = current[docIndex];
    final blockIndex = doc.blocks.indexWhere((b) => b.id == blockId);
    if (blockIndex == -1) return;

    final block = doc.blocks[blockIndex];
    block.isChecked = !block.isChecked;

    await updateDoc(doc);
  }

  Future<void> duplicateDoc(String docId) async {
    final current = state.valueOrNull ?? [];
    final doc = current.firstWhere((d) => d.id == docId);

    final clonedBlocks = doc.blocks
        .map(
          (b) => WorkspaceBlock(
            type: b.type,
            content: b.content,
            isChecked: b.isChecked,
            calloutIcon: b.calloutIcon,
          ),
        )
        .toList();

    final duplicated = WorkspaceDoc(
      userId: userId,
      title: '${doc.title} (نسخة)',
      icon: doc.icon,
      coverColor: doc.coverColor,
      category: doc.category,
      isPinned: false,
      isFavorite: false,
      blocks: clonedBlocks,
    );

    final updated = [duplicated, ...current];
    state = AsyncValue.data(updated);
    await _persistAndSync(updated);
  }

  Future<void> deleteDoc(String docId) async {
    final current = state.valueOrNull ?? [];
    final updated = current.where((d) => d.id != docId).toList();
    state = AsyncValue.data(updated);
    await _persistAndSync(updated);
  }
}
