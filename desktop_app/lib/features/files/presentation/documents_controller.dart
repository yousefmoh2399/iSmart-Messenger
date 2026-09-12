import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/remote_document.dart';
import '../../../shared/providers/providers.dart';

class DocumentsController extends AsyncNotifier<List<RemoteDocument>> {
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  bool _isUnauthorized(Object error) {
    return error is ApiException && error.isUnauthorized;
  }

  Future<T> _guardAuth<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      if (_isUnauthorized(error)) {
        Future<void>.microtask(
          () => ref.read(authControllerProvider.notifier).logout(),
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<List<RemoteDocument>> build() async {
    ref.watch(serverRecoveryRevisionProvider);
    return _guardAuth(() async {
      final repository = ref.watch(documentRepositoryProvider);
      await repository.syncPendingLocalDocuments();
      final page = await repository.fetchDocumentsPage();
      _page = page.page;
      _hasMore = page.hasMore;
      return page.documents;
    });
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _guardAuth(() async {
        final repository = ref.read(documentRepositoryProvider);
        await repository.syncPendingLocalDocuments();
        final page = await repository.fetchDocumentsPage();
        _page = page.page;
        _hasMore = page.hasMore;
        return page.documents;
      }),
    );
  }

  Future<void> loadMore() async {
    if (!_hasMore || _loadingMore) return;
    final current = state.valueOrNull ?? const <RemoteDocument>[];
    _loadingMore = true;
    try {
      final page = await _guardAuth(
        () => ref
            .read(documentRepositoryProvider)
            .fetchDocumentsPage(page: _page + 1),
      );
      _page = page.page;
      _hasMore = page.hasMore;
      final byId = <String, RemoteDocument>{
        for (final document in current) document.id: document,
        for (final document in page.documents) document.id: document,
      };
      state = AsyncData(byId.values.toList());
    } finally {
      _loadingMore = false;
    }
  }
}

class AdminDocumentsController extends AsyncNotifier<List<RemoteDocument>> {
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  bool _isUnauthorized(Object error) {
    return error is ApiException && error.isUnauthorized;
  }

  Future<T> _guardAuth<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      if (_isUnauthorized(error)) {
        Future<void>.microtask(
          () => ref.read(authControllerProvider.notifier).logout(),
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  bool _canReadAllDocuments({bool listen = false}) {
    final user = listen
        ? ref.watch(currentUserProvider)
        : ref.read(currentUserProvider);
    return user?.isAdmin == true;
  }

  @override
  Future<List<RemoteDocument>> build() async {
    ref.watch(serverRecoveryRevisionProvider);
    if (!_canReadAllDocuments(listen: true)) {
      return const [];
    }
    final page = await _guardAuth(
      () => ref
          .watch(documentRepositoryProvider)
          .fetchDocumentsPage(includeAll: true),
    );
    _page = page.page;
    _hasMore = page.hasMore;
    return page.documents;
  }

  Future<void> refresh() async {
    if (!_canReadAllDocuments()) {
      state = const AsyncData(<RemoteDocument>[]);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _guardAuth(() async {
        final page = await ref
            .read(documentRepositoryProvider)
            .fetchDocumentsPage(includeAll: true);
        _page = page.page;
        _hasMore = page.hasMore;
        return page.documents;
      }),
    );
  }

  Future<void> loadMore() async {
    if (!_canReadAllDocuments() || !_hasMore || _loadingMore) return;
    final current = state.valueOrNull ?? const <RemoteDocument>[];
    _loadingMore = true;
    try {
      final page = await _guardAuth(
        () => ref
            .read(documentRepositoryProvider)
            .fetchDocumentsPage(includeAll: true, page: _page + 1),
      );
      _page = page.page;
      _hasMore = page.hasMore;
      final byId = <String, RemoteDocument>{
        for (final document in current) document.id: document,
        for (final document in page.documents) document.id: document,
      };
      state = AsyncData(byId.values.toList());
    } finally {
      _loadingMore = false;
    }
  }
}
