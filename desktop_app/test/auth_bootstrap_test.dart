import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_app/shared/providers/providers.dart';
import 'package:desktop_app/features/auth/presentation/auth_controller.dart';
import 'package:desktop_app/shared/models/app_user.dart';
import 'package:desktop_app/features/auth/data/auth_repository.dart';
import 'package:desktop_app/features/auth/data/session_store.dart';

class FakeAuthRepository implements AuthRepository {
  bool restoreSessionCalled = false;
  AppUser? mockUser;

  @override
  Future<AppUser?> restoreSession() async {
    restoreSessionCalled = true;
    return mockUser;
  }

  @override
  Future<StoredAuthSession?> getSession() async {
    if (mockUser == null) return null;
    return const StoredAuthSession(
      accessToken: 'dummy_token',
      refreshToken: 'dummy_refresh',
      userId: '1',
      generation: 2,
    );
  }

  @override
  Future<String?> getToken() async => 'dummy_token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Auth Bootstrap Tests', () {
    test('Successful bootstrap transitions to authenticated', () async {
      final fakeRepo = FakeAuthRepository();
      fakeRepo.mockUser = AppUser(
        id: 'user1',
        username: 'test_user',
        fullName: 'Test User',
        role: 'user',
        departmentId: null,
        branchId: null,
        branchCode: 'main',
        isOnline: true,
        presenceStatus: 'online',
        isActive: true,
        avatarUrl: null,
        lastSeen: null,
        lastActiveAt: null,
        maxAttachmentSizeMB: 20,
        permissions: const {},
        chatPreferences: ChatPreferences.defaults,
      );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );

      final state = container.read(authControllerProvider);
      expect(state.status, equals(AuthStatus.initializing));

      await container.read(authControllerProvider.notifier).initializeAuth();
      final finalState = container.read(authControllerProvider);
      expect(finalState.status, equals(AuthStatus.authenticated));
      expect(finalState.user?.username, equals('testuser'));
    });

    test('Failed bootstrap transitions to unauthenticated', () async {
      final fakeRepo = FakeAuthRepository();
      fakeRepo.mockUser = null;

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );

      final state = container.read(authControllerProvider);
      expect(state.status, equals(AuthStatus.initializing));

      await container.read(authControllerProvider.notifier).initializeAuth();
      final finalState = container.read(authControllerProvider);
      expect(finalState.status, equals(AuthStatus.unauthenticated));
    });
  });
}
