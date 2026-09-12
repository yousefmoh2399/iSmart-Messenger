import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/core/network/api_client.dart';
import 'package:desktop_app/features/auth/data/session_store.dart';
import 'package:desktop_app/features/auth/data/auth_session_manager.dart';

class MockSessionStore extends SessionStore {
  String? mockToken;
  String? mockRefreshToken;

  @override
  Future<StoredAuthSession?> readSession() async {
    return StoredAuthSession(
      accessToken: mockToken ?? '',
      refreshToken: mockRefreshToken ?? '',
      userId: 'test_user_id',
      generation: 0,
    );
  }

  @override
  Future<StoredAuthTokens> readTokens() async {
    return StoredAuthTokens(accessToken: mockToken, refreshToken: mockRefreshToken);
  }

  @override
  Future<String?> loadToken() async => mockToken;

  @override
  Future<String?> loadRefreshToken() async => mockRefreshToken;
}

class MockAuthRefreshService extends AuthRefreshService {
  MockAuthRefreshService() : super(baseUrl: 'http://localhost:8000');
}

void main() {
  group('ApiClient Auth Guard Tests', () {
    late MockSessionStore mockStore;
    late AuthSessionManager sessionManager;

    setUp(() {
      mockStore = MockSessionStore();
      sessionManager = AuthSessionManager(
        tokenStorage: mockStore,
        refreshService: MockAuthRefreshService(),
      );
    });

    test('Requests requiring authentication are rejected locally if token is missing', () async {
      mockStore.mockToken = null;
      final apiClient = ApiClient(baseUrl: 'http://localhost:8000', sessionManager: sessionManager);

      try {
        await apiClient.dio.get<void>('/api/printers/printers');
        fail('Should have thrown exception');
      } catch (e) {
        expect(e.toString(), contains('Missing or invalid authentication token'));
      }
    });

    test('Requests requiring authentication are rejected locally if token is literal "null"', () async {
      mockStore.mockToken = 'null';
      final apiClient = ApiClient(baseUrl: 'http://localhost:8000', sessionManager: sessionManager);

      try {
        await apiClient.dio.get<void>('/api/printers/printers');
        fail('Should have thrown exception');
      } catch (e) {
        expect(e.toString(), contains('Missing or invalid authentication token'));
      }
    });

    test('Public endpoints are not rejected even if token is missing', () async {
      mockStore.mockToken = null;

      final apiClient = ApiClient(baseUrl: 'http://localhost:8000', sessionManager: sessionManager);
      apiClient.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response<Map<String, dynamic>>(
            requestOptions: options,
            data: {'status': 'ok'},
            statusCode: 200,
          ));
        },
      ));

      final response = await apiClient.dio.get<Map<String, dynamic>>('/api/auth/login');
      expect(response.statusCode, equals(200));
      expect(response.data?['status'], equals('ok'));
    });
  });
}
