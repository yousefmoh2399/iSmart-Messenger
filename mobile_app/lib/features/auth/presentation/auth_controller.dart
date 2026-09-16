import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../data/auth_repository.dart';

enum AuthStatus { initializing, unauthenticated, authenticated }

class AuthState {
  const AuthState({required this.status, this.session, this.user, this.error});

  final AuthStatus status;
  final StoredAuthSession? session;
  final AppUser? user;
  final Object? error;

  AppUser? get valueOrNull => user;
  bool get isLoading => status == AuthStatus.initializing;

  T when<T>({
    required T Function() loading,
    required T Function(Object error, StackTrace stackTrace) error,
    required T Function(AppUser? user) data,
  }) {
    if (status == AuthStatus.initializing) {
      return loading();
    }
    final currentError = this.error;
    if (currentError != null && status == AuthStatus.unauthenticated) {
      return error(currentError, StackTrace.current);
    }
    return data(user);
  }
}

class AuthController extends Notifier<AuthState> {
  bool _isLoggingOut = false;
  Future<void>? _initFuture;

  @override
  AuthState build() {
    initializeAuth();
    return const AuthState(status: AuthStatus.initializing);
  }

  Future<void> initializeAuth() async {
    final activeInit = _initFuture;
    if (activeInit != null) {
      return activeInit;
    }

    final future = _initializeAuthInternal();
    _initFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initFuture, future)) {
        _initFuture = null;
      }
    }
  }

  Future<void> _initializeAuthInternal() async {
    final repository = ref.read(authRepositoryProvider);
    try {
      final user = await repository.restoreSession();
      if (user != null) {
        final session = await repository.getSession();
        state = AuthState(
          status: AuthStatus.authenticated,
          session: session,
          user: user,
        );
      } else {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    } catch (error) {
      final cachedUser = await repository.loadCachedUser();
      if (cachedUser != null) {
        final session = await repository.getSession();
        state = AuthState(
          status: AuthStatus.authenticated,
          session: session,
          user: cachedUser,
        );
      } else {
        state = AuthState(status: AuthStatus.unauthenticated, error: error);
      }
    }
  }

  Future<void> login({
    required String username,
    required String password,
    bool rememberUsername = false,
  }) async {
    try {
      final repository = ref.read(authRepositoryProvider);
      final user = await repository.login(
        username: username,
        password: password,
        rememberUsername: rememberUsername,
      );

      // Set state directly to authenticated — avoids re-running initializeAuth()
      // and the associated race condition with concurrent token reads.
      final session = await repository.getSession();
      state = AuthState(
        status: AuthStatus.authenticated,
        session: session,
        user: user,
      );

      // Invalidate all dependent providers AFTER the user's session is fully
      // established in the auth controller. This prevents providers from waking
      // up and reading an empty or unauthenticated state before the token is ready.
      ref.invalidate(chatOverviewControllerProvider);
      ref.invalidate(chatRealtimeControllerProvider);
      ref.invalidate(usersControllerProvider);
      ref.invalidate(remoteDocumentsControllerProvider);
      ref.invalidate(adminDocumentsControllerProvider);
      ref.invalidate(announcementsControllerProvider);
      ref.invalidate(adminAnnouncementsControllerProvider);
      ref.invalidate(ticketsControllerProvider);
      ref.invalidate(mobilePrinterControllerProvider);
      ref.invalidate(pendingUploadsControllerProvider);
      ref.invalidate(scanSessionControllerProvider);
    } catch (error, stackTrace) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> logout() async {
    if (_isLoggingOut) {
      return;
    }
    _isLoggingOut = true;
    try {
      debugPrint('[AuthController] Logging out...');
      ref.read(chatSocketServiceProvider).setPresenceOffline();
      ref.read(chatSocketServiceProvider).disconnect();

      await ref.read(pushNotificationServiceProvider).unregisterCurrentDevice();
      await ref.read(authRepositoryProvider).logout();

      state = const AuthState(status: AuthStatus.unauthenticated);
      debugPrint('[AuthController] Logged out successfully');
    } catch (e) {
      debugPrint('[AuthController] Logout error: $e');
      state = const AuthState(status: AuthStatus.unauthenticated);
      rethrow;
    } finally {
      _isLoggingOut = false;
    }
  }

  Future<void> refreshCurrentUser() async {
    final repository = ref.read(authRepositoryProvider);
    final token = await repository.getToken();
    final normalized = token?.trim();
    if (normalized == null ||
        normalized.isEmpty ||
        normalized.toLowerCase() == 'null') {
      return;
    }
    final user = await repository.fetchCurrentUser();
    final session = await repository.getSession();
    state = AuthState(
      status: AuthStatus.authenticated,
      session: session,
      user: user,
    );
  }

  Future<void> updateProfile({
    required String fullName,
    String? password,
  }) async {
    final repository = ref.read(authRepositoryProvider);
    final user = await repository.updateProfile(
      fullName: fullName,
      password: password,
    );
    final session = await repository.getSession();
    state = AuthState(
      status: AuthStatus.authenticated,
      session: session,
      user: user,
    );
  }

  Future<void> updateChatPreferences(ChatPreferences chatPreferences) async {
    final repository = ref.read(authRepositoryProvider);
    final user = await repository.updateChatPreferences(
      chatPreferences: chatPreferences,
    );
    final session = await repository.getSession();
    state = AuthState(
      status: AuthStatus.authenticated,
      session: session,
      user: user,
    );
  }

  Future<void> uploadAvatar(String filePath) async {
    final repository = ref.read(authRepositoryProvider);
    final user = await repository.uploadAvatar(filePath);
    final session = await repository.getSession();
    state = AuthState(
      status: AuthStatus.authenticated,
      session: session,
      user: user,
    );
  }
}
