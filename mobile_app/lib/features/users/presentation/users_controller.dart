import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/models/managed_user.dart';
import '../../../shared/providers/providers.dart';

class UsersController extends AsyncNotifier<List<ManagedUser>> {
  void resetState() { state = const AsyncLoading(); }
  Future<void>? _refreshFuture;
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  Future<T> _guardAuth<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      if (error is ApiException && error.isUnauthorized) {
        Future<void>.microtask(
          () => ref.read(authControllerProvider.notifier).logout(),
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<bool> _waitForAuthenticatedSession() async {
    ref.watch(authCredentialsRevisionProvider);
    final authUser = ref.watch(currentUserProvider);
    if (authUser == null) {
      return false;
    }
    final token = await ref.watch(authTokenProvider.future);
    if (token == null || token.trim().isEmpty) {
      throw const ApiException(
        'انتهت صلاحية الجلسة أو فشل التحقق. سجل الدخول مرة أخرى.',
        statusCode: 401,
      );
    }
    return true;
  }

  bool _canReadManagedUsers({bool listen = false}) {
    final user = listen
        ? ref.watch(currentUserProvider)
        : ref.read(currentUserProvider);
    return user != null &&
        (user.isAdmin || user.role == 'manager' || user.can('canCreateUsers'));
  }

  @override
  Future<List<ManagedUser>> build() async {
    ref.watch(serverRecoveryRevisionProvider);
    final hasSession = await _waitForAuthenticatedSession();
    if (!hasSession) {
      return const [];
    }
    if (!_canReadManagedUsers(listen: true)) {
      return const [];
    }
    final page = await _guardAuth(
      () => ref.read(userManagementRepositoryProvider).fetchUsersPage(),
    );
    _page = page.page;
    _hasMore = page.hasMore;
    return page.users;
  }

  Future<void> refresh() async {
    if (_refreshFuture != null) {
      return _refreshFuture!;
    }
    final current = state;
    final future = () async {
      state = const AsyncLoading<List<ManagedUser>>().copyWithPrevious(current);
      state = await AsyncValue.guard(() async {
        final hasSession = await _waitForAuthenticatedSession();
        if (!hasSession) {
          return const <ManagedUser>[];
        }
        if (!_canReadManagedUsers()) {
          return const <ManagedUser>[];
        }
        final page = await _guardAuth(
          () => ref.read(userManagementRepositoryProvider).fetchUsersPage(),
        );
        _page = page.page;
        _hasMore = page.hasMore;
        return page.users;
      });
    }();
    _refreshFuture = future;
    try {
      await future;
    } finally {
      _refreshFuture = null;
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || _loadingMore) return;
    final current = state.valueOrNull ?? const <ManagedUser>[];
    _loadingMore = true;
    try {
      final page = await _guardAuth(
        () => ref
            .read(userManagementRepositoryProvider)
            .fetchUsersPage(page: _page + 1),
      );
      _page = page.page;
      _hasMore = page.hasMore;
      final byId = <String, ManagedUser>{
        for (final user in current) user.id: user,
        for (final user in page.users) user.id: user,
      };
      state = AsyncData(byId.values.toList());
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> deleteUser(String userId) async {
    final current = state.valueOrNull ?? <ManagedUser>[];
    state = const AsyncLoading<List<ManagedUser>>().copyWithPrevious(
      AsyncData(current),
    );
    state = await AsyncValue.guard(() async {
      await _guardAuth(
        () => ref.read(userManagementRepositoryProvider).deleteUser(userId),
      );
      return _guardAuth(
        () => ref.read(userManagementRepositoryProvider).fetchUsers(),
      );
    });
  }

  Future<void> logoutUserAll(String userId) async {
    final current = state.valueOrNull ?? <ManagedUser>[];
    state = const AsyncLoading<List<ManagedUser>>().copyWithPrevious(
      AsyncData(current),
    );
    state = await AsyncValue.guard(() async {
      await _guardAuth(
        () => ref.read(userManagementRepositoryProvider).logoutUserAll(userId),
      );
      return _guardAuth(
        () => ref.read(userManagementRepositoryProvider).fetchUsers(),
      );
    });
  }
}





