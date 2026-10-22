import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/remote_document.dart';
import '../../../shared/providers/providers.dart';
import '../../auth/presentation/auth_controller.dart';

class DocumentsController extends AsyncNotifier<List<RemoteDocument>> {
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  bool _isUnauthorized(Object error) {
    if (error is ApiException && error.isUnauthorized) return true;
    if (error is DioException) {
      if (error.response?.statusCode == 401) return true;
      if (error.error is ApiException && (error.error as ApiException).isUnauthorized) return true;
    }
    return false;
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
    final auth = ref.watch(authControllerProvider);
    if (auth.status != AuthStatus.authenticated || auth.user == null) {
      return const <RemoteDocument>[];
    }
    try {
      return await _guardAuth(() async {
        final repository = ref.watch(documentRepositoryProvider);
        try {
          await repository.syncPendingLocalDocuments();
        } catch (_) {}
        final page = await repository.fetchDocumentsPage();
        _page = page.page;
        _hasMore = page.hasMore;
        return page.documents;
      });
    } catch (_) {
      return const <RemoteDocument>[];
    }
  }

  Future<void> refresh() async {
    final auth = ref.read(authControllerProvider);
    if (auth.status != AuthStatus.authenticated) return;
    try {
      final docs = await _guardAuth(() async {
        final repository = ref.read(documentRepositoryProvider);
        try {
          await repository.syncPendingLocalDocuments();
        } catch (_) {}
        final page = await repository.fetchDocumentsPage();
        _page = page.page;
        _hasMore = page.hasMore;
        return page.documents;
      });
      state = AsyncData(docs);
    } catch (_) {
      if (!state.hasValue) {
        state = const AsyncData(<RemoteDocument>[]);
      }
    }
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
  String? _search;
  final int _limit = 100;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _loadingMore;

  Future<void> setSearch(String? search) async {
    if (!_canReadAllDocuments()) return;
    _search = search?.trim();
    _page = 1;
    final current = state;
    state = const AsyncLoading<List<RemoteDocument>>().copyWithPrevious(current);
    state = await AsyncValue.guard(
      () => _guardAuth(() async {
        final page = await ref
            .read(documentRepositoryProvider)
            .fetchDocumentsPage(
              includeAll: true,
              search: _search,
              page: 1,
              limit: _limit,
            );
        _page = page.page;
        _hasMore = page.hasMore;
        return page.documents;
      }),
    );
  }

  bool _isUnauthorized(Object error) {
    if (error is ApiException && error.isUnauthorized) return true;
    if (error is DioException) {
      if (error.response?.statusCode == 401) return true;
      if (error.error is ApiException && (error.error as ApiException).isUnauthorized) return true;
    }
    return false;
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
    final auth = ref.watch(authControllerProvider);
    if (auth.status != AuthStatus.authenticated || auth.user == null) {
      return const [];
    }
    if (!_canReadAllDocuments(listen: true)) {
      return const [];
    }
    try {
      final page = await _guardAuth(
        () => ref
            .watch(documentRepositoryProvider)
            .fetchDocumentsPage(includeAll: true, search: _search, page: 1, limit: _limit),
      );
      _page = page.page;
      _hasMore = page.hasMore;
      return page.documents;
    } catch (_) {
      return const [];
    }
  }

  Future<void> refresh() async {
    final auth = ref.read(authControllerProvider);
    if (auth.status != AuthStatus.authenticated) return;
    if (!_canReadAllDocuments()) {
      state = const AsyncData(<RemoteDocument>[]);
      return;
    }
    try {
      final page = await _guardAuth(() async {
        final page = await ref
            .read(documentRepositoryProvider)
            .fetchDocumentsPage(includeAll: true, search: _search, page: 1, limit: _limit);
        _page = page.page;
        _hasMore = page.hasMore;
        return page.documents;
      });
      state = AsyncData(page);
    } catch (_) {
      if (!state.hasValue) {
        state = const AsyncData(<RemoteDocument>[]);
      }
    }
  }

  Future<void> loadMore() async {
    if (!_canReadAllDocuments() || !_hasMore || _loadingMore) return;
    final current = state.valueOrNull ?? const <RemoteDocument>[];
    _loadingMore = true;
    try {
      final page = await _guardAuth(
        () => ref
            .read(documentRepositoryProvider)
            .fetchDocumentsPage(includeAll: true, search: _search, page: _page + 1, limit: _limit),
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
