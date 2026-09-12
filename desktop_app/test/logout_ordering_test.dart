import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/features/auth/data/auth_repository.dart';
import 'package:desktop_app/features/auth/data/session_store.dart';
import 'package:desktop_app/features/auth/data/auth_session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_app/core/network/api_client.dart';
import 'package:dio/dio.dart';

class FakeSessionStore implements SessionStore {
  bool cleared = false;
  StoredAuthSession? session = const StoredAuthSession(
    accessToken: 'test_token',
    refreshToken: 'test_refresh',
    userId: '123',
    generation: 1,
  );

  @override
  Future<StoredAuthSession?> readSession() async => session;

  Future<void> clearSession() async {
    cleared = true;
    session = null;
  }

  @override
  Future<void> clearToken() async {
    cleared = true;
    session = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSessionManager implements AuthSessionManager {
  FakeSessionManager(this.store);
  final FakeSessionStore store;

  @override
  Future<void> initialize() async {}

  @override
  String? get accessToken => 'test_token';

  @override
  int get tokenGeneration => 1;

  @override
  Future<void> clearSessionOnce({String reason = 'unknown'}) async {
    await store.clearToken();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LogoutDio extends DioMixin implements Dio {
  bool postCalled = false;
  Object? pendingError;
  bool sessionClearedAtPostTime = false;
  FakeSessionStore? store;

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    if (path == '/api/auth/logout') {
      postCalled = true;
      if (store != null) {
        sessionClearedAtPostTime = store!.cleared;
      }
      if (pendingError != null) {
        throw pendingError!;
      }
      return Response(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: <String, dynamic>{} as T,
      );
    }
    throw UnimplementedError();
  }
}

class FakeApiClient implements ApiClient {
  FakeApiClient(this.dio);

  @override
  final Dio dio;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('Logout Ordering Tests', () {
    test('Wipes local session AFTER server revoke request is sent', () async {
      final dio = LogoutDio();
      final store = FakeSessionStore();
      dio.store = store;

      final client = FakeApiClient(dio);
      final manager = FakeSessionManager(store);

      final repository = AuthRepository(client, store, sessionManager: manager);

      await repository.logout();

      expect(dio.postCalled, isTrue);
      expect(dio.sessionClearedAtPostTime, isFalse); // Wiped AFTER post call
      expect(store.cleared, isTrue);
    });

    test(
      'Wipes local session even when server revoke fails (try/finally)',
      () async {
        final dio = LogoutDio();
        final store = FakeSessionStore();
        dio.store = store;
        dio.pendingError = DioException(
          requestOptions: RequestOptions(path: '/api/auth/logout'),
          type: DioExceptionType.badResponse,
        );

        final client = FakeApiClient(dio);
        final manager = FakeSessionManager(store);

        final repository = AuthRepository(
          client,
          store,
          sessionManager: manager,
        );

        await repository.logout();

        expect(dio.postCalled, isTrue);
        expect(store.cleared, isTrue); // Wiped in finally block
      },
    );
  });
}
