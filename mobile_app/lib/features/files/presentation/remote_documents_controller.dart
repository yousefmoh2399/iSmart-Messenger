import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/remote_document.dart';
import '../../../shared/providers/providers.dart';
import '../../auth/presentation/auth_controller.dart';

class RemoteDocumentsController extends AsyncNotifier<List<RemoteDocument>> {
  void resetState() { state = const AsyncLoading(); }
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _loadingMore;

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
          () => ref.read(authControllerProvider.notifier).logoutIfSessionGone(),
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<List<RemoteDocument>> build() async {
    ref.watch(serverRecoveryRevisionProvider);
    final authState = ref.watch(authControllerProvider);
    if (authState.status != AuthStatus.authenticated || authState.user == null) {
      return const <RemoteDocument>[];
    }
    try {
      final page = await _guardAuth(
        () => ref.watch(documentRepositoryProvider).fetchDocumentsPage(),
      );
      _page = page.page;
      _hasMore = page.hasMore;
      return page.documents;
    } catch (_) {
      try {
        final repo = ref.read(documentRepositoryProvider);
        final page = await repo.fetchDocumentsPage();
        _page = page.page;
        _hasMore = page.hasMore;
        return page.documents;
      } catch (_) {
        return const <RemoteDocument>[];
      }
    }
  }

  Future<void> refresh() async {
    final authState = ref.read(authControllerProvider);
    if (authState.status != AuthStatus.authenticated) return;
    try {
      final page = await _guardAuth(() async {
        final page = await ref
            .read(documentRepositoryProvider)
            .fetchDocumentsPage();
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
  void resetState() { state = const AsyncLoading(); }

  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _loadingMore;

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
          () => ref.read(authControllerProvider.notifier).logoutIfSessionGone(),
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
    final authState = ref.watch(authControllerProvider);
    if (authState.status != AuthStatus.authenticated || authState.user == null) {
      return const [];
    }
    if (!_canReadAllDocuments(listen: true)) {
      return const [];
    }
    try {
      final page = await _guardAuth(
        () => ref
            .watch(documentRepositoryProvider)
            .fetchDocumentsPage(includeAll: true),
      );
      _page = page.page;
      _hasMore = page.hasMore;
      return page.documents;
    } catch (_) {
      return const [];
    }
  }

  Future<void> refresh() async {
    if (!_canReadAllDocuments()) {
      state = const AsyncData(<RemoteDocument>[]);
      return;
    }
    try {
      final page = await _guardAuth(() async {
        final page = await ref
            .read(documentRepositoryProvider)
            .fetchDocumentsPage(includeAll: true);
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






