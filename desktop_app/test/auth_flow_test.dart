import 'dart:async';
import 'dart:convert';

import 'package:desktop_app/core/network/api_client.dart';
import 'package:desktop_app/features/auth/data/auth_session_manager.dart';
import 'package:desktop_app/features/auth/data/session_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAdapter implements HttpClientAdapter {
  int refreshCallCount = 0;
  int protectedCallCount = 0;
  int retryCallCount = 0;
  int clearSessionCount = 0;
  int refreshStatusCode = 200;
  bool shouldThrowTimeoutOnRefresh = false;
  bool retryAlsoReturns401 = false;

  Future<ResponseBody> Function(RequestOptions options)? fetchDelegate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (fetchDelegate != null) {
      return fetchDelegate!(options);
    }

    final path = options.path;
    if (path.contains('/api/auth/refresh')) {
      refreshCallCount++;
      if (shouldThrowTimeoutOnRefresh) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      }
      if (refreshStatusCode != 200) {
        return ResponseBody.fromString('Unauthorized', refreshStatusCode);
      }
      return ResponseBody.fromString(
        jsonEncode({'token': 'new-token', 'refreshToken': 'new-refresh'}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }

    final auth = options.headers['Authorization'];
    if (auth == 'Bearer old-token') {
      protectedCallCount++;
      return ResponseBody.fromString('Unauthorized', 401);
    }
    if (auth == 'Bearer new-token') {
      retryCallCount++;
      return ResponseBody.fromString(
        retryAlsoReturns401 ? 'Unauthorized' : '{"ok":true}',
        retryAlsoReturns401 ? 401 : 200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }

    return ResponseBody.fromString('OK', 200);
  }

  @override
  void close({bool force = false}) {}
}

class Harness {
  Harness(this.store, this.manager, this.refreshService);

  final SessionStore store;
  final AuthSessionManager manager;
  final AuthRefreshService refreshService;
}

Future<Harness> buildHarness(MockAdapter adapter) async {
  final store = SessionStore();
  await store.saveToken('old-token');
  await store.saveRefreshToken('valid-refresh');

  final refreshService = AuthRefreshService(baseUrl: 'http://localhost');
  refreshService.dio.httpClientAdapter = adapter;
  final manager = AuthSessionManager(
    tokenStorage: store,
    refreshService: refreshService,
    onSessionCleared: () {
      adapter.clearSessionCount++;
    },
  );
  return Harness(store, manager, refreshService);
}

ApiClient buildClient(AuthSessionManager manager, MockAdapter adapter) {
  final client = ApiClient(
    baseUrl: 'http://localhost',
    sessionManager: manager,
  );
  client.dio.httpClientAdapter = adapter;
  return client;
}

Future<void> ignoreRequestFailure(Future<Response<dynamic>> future) async {
  try {
    await future;
  } catch (_) {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Concurrent 401s in one ApiClient trigger one refresh', () async {
    final adapter = MockAdapter();
    final harness = await buildHarness(adapter);
    final apiClient = buildClient(harness.manager, adapter);

    final requests = List.generate(
      5,
      (_) => apiClient.dio.get('/api/users/me'),
    );
    final responses = await Future.wait(requests);

    expect(adapter.refreshCallCount, 1);
    expect(adapter.protectedCallCount, 5);
    expect(adapter.retryCallCount, 5);
    expect(responses.length, 5);
    expect(await harness.store.loadToken(), 'new-token');
  });

  test('Multiple ApiClient instances share one refresh future', () async {
    final adapter = MockAdapter();
    final harness = await buildHarness(adapter);
    final clients = List.generate(
      3,
      (_) => buildClient(harness.manager, adapter),
    );

    final requests = [
      for (final client in clients)
        for (var i = 0; i < 2; i++) client.dio.get('/api/users/me'),
    ];
    await Future.wait(requests);

    expect(adapter.refreshCallCount, 1);
    expect(adapter.protectedCallCount, 6);
    expect(adapter.retryCallCount, 6);
  });

  test('Late 401 retries with latest token without refresh or clear', () async {
    final adapter = MockAdapter();
    final harness = await buildHarness(adapter);
    final apiClient = buildClient(harness.manager, adapter);

    adapter.fetchDelegate = (options) async {
      if (options.path.contains('/api/users/me') &&
          options.extra['retriedWithLatestToken'] != true) {
        adapter.protectedCallCount++;
        await harness.manager.updateTokens(
          accessToken: 'new-token',
          refreshToken: 'new-refresh',
        );
        return ResponseBody.fromString('Unauthorized', 401);
      }
      adapter.retryCallCount++;
      return ResponseBody.fromString(
        '{"ok":true}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    };

    final response = await apiClient.dio.get('/api/users/me');

    expect(response.statusCode, 200);
    expect(adapter.refreshCallCount, 0);
    expect(adapter.clearSessionCount, 0);
    expect(adapter.protectedCallCount, 1);
    expect(adapter.retryCallCount, 1);
  });

  test('Refresh 401 clears session once for concurrent waiters', () async {
    final adapter = MockAdapter()..refreshStatusCode = 401;
    final harness = await buildHarness(adapter);
    final apiClient = buildClient(harness.manager, adapter);

    final requests = List.generate(
      5,
      (_) => ignoreRequestFailure(apiClient.dio.get('/api/users/me')),
    );
    await Future.wait(requests);

    expect(adapter.refreshCallCount, 1);
    expect(adapter.clearSessionCount, 1);
    expect(await harness.store.loadToken(), isNull);
  });

  test('Refresh timeout keeps session for later retry', () async {
    final adapter = MockAdapter()..shouldThrowTimeoutOnRefresh = true;
    final harness = await buildHarness(adapter);
    final apiClient = buildClient(harness.manager, adapter);

    await ignoreRequestFailure(apiClient.dio.get('/api/users/me'));

    expect(adapter.refreshCallCount, 1);
    expect(adapter.clearSessionCount, 0);
    expect(await harness.store.loadToken(), 'old-token');
  });

  test('Refresh 500 keeps session', () async {
    final adapter = MockAdapter()..refreshStatusCode = 500;
    final harness = await buildHarness(adapter);
    final apiClient = buildClient(harness.manager, adapter);

    await ignoreRequestFailure(apiClient.dio.get('/api/users/me'));

    expect(adapter.refreshCallCount, 1);
    expect(adapter.clearSessionCount, 0);
    expect(await harness.store.loadToken(), 'old-token');
  });

  test('FormData request is not replayed after refresh', () async {
    final adapter = MockAdapter();
    final harness = await buildHarness(adapter);
    final apiClient = buildClient(harness.manager, adapter);

    Object? thrown;
    try {
      await apiClient.dio.post(
        '/api/users/me/avatar',
        data: FormData.fromMap({'file': 'x'}),
      );
    } catch (error) {
      thrown = error;
    }

    expect(adapter.refreshCallCount, 1);
    expect(adapter.retryCallCount, 0);
    expect(adapter.clearSessionCount, 0);
    expect(thrown, isA<DioException>());
    expect(
      (thrown as DioException).error,
      isA<RequestNotReplayableException>(),
    );
  });

  test('Stream request is not replayed after refresh', () async {
    final adapter = MockAdapter();
    final harness = await buildHarness(adapter);
    final apiClient = buildClient(harness.manager, adapter);

    Object? thrown;
    try {
      await apiClient.dio.post(
        '/api/files/upload',
        data: Stream<List<int>>.fromIterable([
          [1, 2, 3],
        ]),
      );
    } catch (error) {
      thrown = error;
    }

    expect(adapter.refreshCallCount, 1);
    expect(adapter.retryCallCount, 0);
    expect(adapter.clearSessionCount, 0);
    expect(thrown, isA<DioException>());
    expect(
      (thrown as DioException).error,
      isA<RequestNotReplayableException>(),
    );
  });

  test('Retried request is not refreshed twice', () async {
    final adapter = MockAdapter()..retryAlsoReturns401 = true;
    final harness = await buildHarness(adapter);
    final apiClient = buildClient(harness.manager, adapter);

    await ignoreRequestFailure(apiClient.dio.get('/api/users/me'));

    expect(adapter.refreshCallCount, 1);
    expect(adapter.retryCallCount, 1);
  });
}
