import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/shared/services/app_settings_repository.dart';
import 'package:desktop_app/core/network/api_client.dart';
import 'package:dio/dio.dart';

class FakeDio extends DioMixin implements Dio {
  int getCalls = 0;
  Completer<Response<Map<String, dynamic>>>? completer;
  Object? pendingError;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    getCalls++;
    if (pendingError != null) {
      throw pendingError!;
    }
    final c = Completer<Response<T>>();
    completer = c as Completer<Response<Map<String, dynamic>>>;
    return c.future;
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
  group('AppSettingsRepository Deduplication Tests', () {
    test(
      'Simultaneous fetch calls return identical Future (single-flight)',
      () async {
        final fakeDio = FakeDio();
        final fakeClient = FakeApiClient(fakeDio);
        final repository = AppSettingsRepository(apiClient: fakeClient);

        final f1 = repository.fetchDefaults(forceRefresh: true);
        final f2 = repository.fetchDefaults();

        expect(fakeDio.getCalls, equals(1));

        fakeDio.completer?.complete(
          Response(
            requestOptions: RequestOptions(path: '/api/app-settings'),
            data: {
              'settings': {'desktopBaseUrl': 'http://localhost:8000'},
            },
            statusCode: 200,
          ),
        );

        final r1 = await f1;
        final r2 = await f2;

        expect(r1.desktopBaseUrl, equals('http://localhost:8000'));
        expect(r2.desktopBaseUrl, equals('http://localhost:8000'));
      },
    );

    test('Error cases are NOT cached', () async {
      final fakeDio = FakeDio();
      final fakeClient = FakeApiClient(fakeDio);
      final repository = AppSettingsRepository(apiClient: fakeClient);

      fakeDio.pendingError = DioException(
        requestOptions: RequestOptions(path: '/api/app-settings'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/api/app-settings'),
          statusCode: 500,
        ),
      );

      await expectLater(
        repository.fetchDefaults(forceRefresh: true),
        throwsA(isA<DioException>()),
      );
      expect(fakeDio.getCalls, equals(1));

      // Second request should call the API again
      fakeDio.pendingError = null;
      final f3 = repository.fetchDefaults(forceRefresh: true);
      expect(fakeDio.getCalls, equals(2));

      fakeDio.completer?.complete(
        Response(
          requestOptions: RequestOptions(path: '/api/app-settings'),
          data: {
            'settings': {'desktopBaseUrl': 'http://localhost:9000'},
          },
          statusCode: 200,
        ),
      );

      final r3 = await f3;
      expect(r3.desktopBaseUrl, equals('http://localhost:9000'));
    });
  });
}
