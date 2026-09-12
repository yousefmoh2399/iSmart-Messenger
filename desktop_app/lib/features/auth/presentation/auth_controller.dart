import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../data/session_store.dart';

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
      await web_bridge.electronDebugLog('auth-controller', 'build:error', {
        'error': error.toString(),
      });
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

  _LoginCredentialsKey? _activeCredentials;
  Future<void>? _activeLoginFuture;

  Future<void> login({
    required String username,
    required String password,
    bool rememberUsername = false,
  }) async {
    final credentials = _LoginCredentialsKey(
      username: username.trim().toLowerCase(),
      password: password,
    );

    final activeFuture = _activeLoginFuture;
    if (activeFuture != null && _activeCredentials == credentials) {
      return activeFuture;
    }

    final future = () async {
      try {
        final repository = ref.read(authRepositoryProvider);
        final user = await repository.login(
          username: username,
          password: password,
          rememberUsername: rememberUsername,
        );
        await web_bridge.electronDebugLog(
          'auth-controller',
          'login:state-user',
          {'userId': user.id, 'username': user.username},
        );
        ref.read(activeConversationIdProvider.notifier).state = null;
        ref.invalidate(chatOverviewControllerProvider);
        ref.invalidate(chatRealtimeControllerProvider);
        ref.invalidate(usersControllerProvider);
        ref.invalidate(documentsControllerProvider);
        ref.invalidate(adminDocumentsControllerProvider);
        ref.invalidate(announcementsControllerProvider);
        ref.invalidate(adminAnnouncementsControllerProvider);
        ref.invalidate(ticketsControllerProvider);
        ref.invalidate(printerControllerProvider);
        final session = await repository.getSession();
        state = AuthState(
          status: AuthStatus.authenticated,
          session: session,
          user: user,
        );
      } catch (error, stackTrace) {
        await web_bridge.electronDebugLog('auth-controller', 'login:error', {
          'error': error.toString(),
        });
        state = const AuthState(status: AuthStatus.unauthenticated);
        Error.throwWithStackTrace(error, stackTrace);
      }
    }();

    _activeCredentials = credentials;
    _activeLoginFuture = future;

    return future.whenComplete(() {
      if (identical(_activeLoginFuture, future)) {
        _activeLoginFuture = null;
        _activeCredentials = null;
      }
    });
  }

  Future<void> logout() async {
    if (_isLoggingOut) {
      return;
    }
    _isLoggingOut = true;
    final chatSocket = ref.read(chatSocketServiceProvider);
    final authRepository = ref.read(authRepositoryProvider);
    final activeConversation = ref.read(activeConversationIdProvider.notifier);
    try {
      activeConversation.state = null;
      try {
        chatSocket.setPresenceOffline();
        chatSocket.disconnect();
      } catch (_) {}
      try {
        await authRepository.logout();
      } catch (_) {}
      state = const AuthState(status: AuthStatus.unauthenticated);
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

  Future<void> uploadAvatar(
    String filePath, {
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    final repository = ref.read(authRepositoryProvider);
    final user = await repository.uploadAvatar(
      filePath,
      fileBytes: fileBytes,
      fileName: fileName,
    );
    final session = await repository.getSession();
    state = AuthState(
      status: AuthStatus.authenticated,
      session: session,
      user: user,
    );
  }
}

class _LoginCredentialsKey {
  const _LoginCredentialsKey({required this.username, required this.password});

  final String username;
  final String password;

  @override
  bool operator ==(Object other) {
    return other is _LoginCredentialsKey &&
        other.username == username &&
        other.password == password;
  }

  @override
  int get hashCode => Object.hash(username, password);
}
