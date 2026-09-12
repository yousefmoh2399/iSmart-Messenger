import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/core/network/api_client.dart';
import 'package:desktop_app/features/printers/data/printer_repository.dart';

void main() {
  group('Printer Consumption Deduplication and Caching Tests', () {
    late ApiClient apiClient;
    late PrinterRepository repository;
    int apiRequestsCount = 0;

    setUp(() {
      apiRequestsCount = 0;
      apiClient = ApiClient(baseUrl: 'http://localhost:8000');
      repository = PrinterRepository(apiClient);

      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            apiRequestsCount++;
            // A short delay to allow concurrent requests to overlap and deduplicate
            await Future<void>.delayed(const Duration(milliseconds: 20));
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'status': 'success',
                  'data': {
                    'months': [
                      {'month': 1, 'pages': 100},
                    ],
                  },
                },
              ),
            );
          },
        ),
      );
    });

    test(
      'Concurrent identical requests share the same Future (single-flight)',
      () async {
        final f1 = repository.fetchMonthlyConsumption(
          branchId: 'branch-1',
          fromMonth: 1,
          fromYear: 2026,
          toMonth: 12,
          toYear: 2026,
        );
        final f2 = repository.fetchMonthlyConsumption(
          branchId: 'branch-1',
          fromMonth: 1,
          fromYear: 2026,
          toMonth: 12,
          toYear: 2026,
        );
        final f3 = repository.fetchMonthlyConsumption(
          branchId: 'branch-1',
          fromMonth: 1,
          fromYear: 2026,
          toMonth: 12,
          toYear: 2026,
        );

        final results = await Future.wait([f1, f2, f3]);

        // Only 1 API request should have hit the interceptor
        expect(apiRequestsCount, equals(1));
        expect(results[0]['months'][0]['pages'], equals(100));
        expect(results[1]['months'][0]['pages'], equals(100));
        expect(results[2]['months'][0]['pages'], equals(100));
      },
    );

    test(
      'Short-term cache returns cached data immediately within 15 seconds',
      () async {
        final f1 = repository.fetchMonthlyConsumption(
          branchId: 'branch-1',
          fromMonth: 1,
          fromYear: 2026,
          toMonth: 12,
          toYear: 2026,
        );
        await f1;
        expect(apiRequestsCount, equals(1));

        // Second request immediately after should be cached
        final f2 = repository.fetchMonthlyConsumption(
          branchId: 'branch-1',
          fromMonth: 1,
          fromYear: 2026,
          toMonth: 12,
          toYear: 2026,
        );
        final data = await f2;
        expect(apiRequestsCount, equals(1));
        expect(data['months'][0]['pages'], equals(100));
      },
    );

    test('Bypass cache when forceRefresh is true', () async {
      final f1 = repository.fetchMonthlyConsumption(
        branchId: 'branch-1',
        fromMonth: 1,
        fromYear: 2026,
      );
      await f1;
      expect(apiRequestsCount, equals(1));

      // Fetch again with forceRefresh = true
      final f2 = repository.fetchMonthlyConsumption(
        branchId: 'branch-1',
        fromMonth: 1,
        fromYear: 2026,
        forceRefresh: true,
      );
      await f2;

      expect(apiRequestsCount, equals(2));
    });
  });
}
