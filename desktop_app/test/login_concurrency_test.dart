import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_app/core/network/api_client.dart';
import 'package:desktop_app/features/auth/data/auth_repository.dart';
import 'package:desktop_app/features/auth/data/session_store.dart';
import 'package:desktop_app/features/auth/data/auth_session_manager.dart';

class MockSessionStore extends SessionStore {
  StoredAuthSession? activeSession;
  String? rememberedUsername;
  bool rememberEnabled = false;

  @override
  Future<StoredAuthSession?> readSession() async => activeSession;

  @override
  Future<void> writeSession(StoredAuthSession session) async {
    activeSession = session;
  }

  @override
  Future<StoredAuthTokens> readTokens() async {
    return StoredAuthTokens(
      accessToken: activeSession?.accessToken,
      refreshToken: activeSession?.refreshToken,
    );
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
    String? userId,
    int? generation,
  }) async {
    activeSession = StoredAuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      userId: userId ?? activeSession?.userId ?? '',
      generation: generation ?? ((activeSession?.generation ?? 0) + 1),
    );
  }

  @override
  Future<void> saveRememberedUsername(String username, bool remember) async {
    rememberedUsername = username;
    rememberEnabled = remember;
  }

  @override
  Future<void> clearToken() async {
    activeSession = null;
  }
}

class MockAuthRefreshService extends AuthRefreshService {
  MockAuthRefreshService() : super(baseUrl: 'http://localhost:8000');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('Login Concurrency and Session Persistence Tests', () {
    late MockSessionStore mockStore;
    late AuthSessionManager sessionManager;
    late ApiClient apiClient;
    late AuthRepository repository;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockStore = MockSessionStore();
      apiClient = ApiClient(baseUrl: 'http://localhost:8000');
      sessionManager = AuthSessionManager(
        tokenStorage: mockStore,
        refreshService: MockAuthRefreshService(),
      );
      repository = AuthRepository(
        apiClient,
        mockStore,
        sessionManager: sessionManager,
        onSessionCleared: () {},
      );
    });

    test(
      'Failed login attempt does not delete existing valid session',
      () async {
        mockStore.activeSession = const StoredAuthSession(
          accessToken: 'valid-token',
          refreshToken: 'valid-refresh',
          userId: 'user-123',
          generation: 1,
        );

        apiClient.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 401,
                    data: {'message': 'invalid credentials'},
                  ),
                ),
              );
            },
          ),
        );

        try {
          await repository.login(username: 'test', password: 'bad-password');
          fail('Should have failed login');
        } catch (_) {
          expect(mockStore.activeSession?.accessToken, equals('valid-token'));
          expect(
            mockStore.activeSession?.refreshToken,
            equals('valid-refresh'),
          );
        }
      },
    );

    test(
      'Stale login attempt completes but is ignored (latest attempt wins)',
      () async {
        int requestCount = 0;
        apiClient.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              requestCount++;
              if (requestCount == 1) {
                await Future<void>.delayed(const Duration(milliseconds: 30));
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'token': 'token-a',
                      'refreshToken': 'refresh-a',
                      'user': {'id': 'user-a', 'username': 'user-a'},
                    },
                  ),
                );
              } else {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'token': 'token-b',
                      'refreshToken': 'refresh-b',
                      'user': {'id': 'user-b', 'username': 'user-b'},
                    },
                  ),
                );
              }
            },
          ),
        );

        final futureA = repository.login(
          username: 'user-a',
          password: 'password',
        );
        final futureB = repository.login(
          username: 'user-b',
          password: 'password',
        );

        final userB = await futureB;
        expect(userB.id, equals('user-b'));
        expect(mockStore.activeSession?.accessToken, equals('token-b'));

        try {
          await futureA;
          fail('Attempt A should have thrown StaleLoginAttemptException');
        } catch (e) {
          expect(e, isA<StaleLoginAttemptException>());
        }

        expect(mockStore.activeSession?.accessToken, equals('token-b'));
      },
    );
  });
}
