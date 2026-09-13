import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../models/printer_models.dart';

class PrinterRepository {
  PrinterRepository(this._apiClient);

  final ApiClient _apiClient;

  // In‑memory cache for overview and dashboard data
  PrinterOverviewData? _cachedOverview;
  PrinterDashboardData? _cachedDashboard;

  Future<PrinterOverviewData> fetchOverview() async {
    try {
      final responses = await Future.wait([
        _apiClient.dio.get<Map<String, dynamic>>('/api/printers/dashboard'),
        _apiClient.dio.get<Map<String, dynamic>>('/api/printers/branches'),
        _apiClient.dio.get<Map<String, dynamic>>('/api/printers/printers'),
        _apiClient.dio.get<Map<String, dynamic>>('/api/printers/sync/logs'),
      ]);
      final dashboard = PrinterDashboardData.fromJson(_body(responses[0].data));
      final branches = _list(
        _body(responses[1].data)['branches'],
      ).map((entry) => PrinterBranchItem.fromJson(_map(entry))).toList();
      final printers = _list(
        _body(responses[2].data)['printers'],
      ).map((entry) => PrinterItem.fromJson(_map(entry))).toList();
      final logs = _list(_body(responses[3].data)['logs']).map(_map).toList();
      final overview = PrinterOverviewData(
        dashboard: dashboard,
        branches: branches,
        printers: printers,
        logs: logs,
      );
      _cachedOverview = overview;
      return overview;
    } on ApiException catch (_) {
      if (_cachedOverview != null) return _cachedOverview!;
      rethrow;
    }
  }

  final Map<String, PrinterDashboardData> _cachedDashboards = {};

  Future<PrinterDashboardData> fetchDashboard({String? branchId}) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/printers/dashboard',
        queryParameters: {
          if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
        },
      );
      final dashboard = PrinterDashboardData.fromJson(_body(response.data));
      _cachedDashboards[branchId ?? 'global'] = dashboard;
      return dashboard;
    } on ApiException catch (_) {
      final cached = _cachedDashboards[branchId ?? 'global'];
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<PrinterDetailsData> fetchPrinterDetails(String printerId) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/printers/printers/$printerId',
    );
    return PrinterDetailsData.fromJson(_body(response.data));
  }

  Future<void> createBranch({
    required String name,
    required String code,
    required String networkRange,
    required String location,
  }) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/printers/branches',
      data: {
        'name': name.trim(),
        'code': code.trim(),
        'networkRange': networkRange.trim(),
        'location': location.trim(),
      },
    );
  }

  Future<void> updateBranch({
    required String branchId,
    required String name,
    required String code,
    required String networkRange,
    required String location,
    required String status,
  }) async {
    await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/printers/branches/$branchId',
      data: {
        'name': name.trim(),
        'code': code.trim(),
        'networkRange': networkRange.trim(),
        'location': location.trim(),
        'status': status,
      },
    );
  }

  Future<void> deleteBranch(String branchId) async {
    await _apiClient.dio.delete<Map<String, dynamic>>(
      '/api/printers/branches/$branchId',
    );
  }

  Future<void> discoverBranch(String branchId) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/printers/branches/$branchId/discover',
    );
  }

  Future<void> fullSync() async {
    await _apiClient.dio.post<Map<String, dynamic>>('/api/printers/sync/full');
  }

  Future<void> stopFullSync() async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/printers/sync/full/stop',
    );
  }

  Future<Map<String, dynamic>> fetchFullSyncStatus() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/printers/sync/full/status',
    );
    return _map(_body(response.data)['status']);
  }

  Future<void> syncPrinter(String printerId) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/printers/printers/$printerId/sync',
    );
  }

  Future<void> deletePrinter(String printerId) async {
    await _apiClient.dio.delete<Map<String, dynamic>>(
      '/api/printers/printers/$printerId',
    );
  }

  Future<void> exportReport({
    required String format,
    String? type,
    String? branchId,
    String? printerId,
    int? fromMonth,
    int? fromYear,
    int? toMonth,
    int? toYear,
  }) async {
    final response = await _apiClient.dio.get<dynamic>(
      '/api/printers/reports/export',
      queryParameters: {
        'format': format,
        if (type != null) 'type': type,
        if (branchId != null) 'branchId': branchId,
        if (printerId != null) 'printerId': printerId,
        if (fromMonth != null) 'fromMonth': fromMonth,
        if (fromYear != null) 'fromYear': fromYear,
        if (toMonth != null) 'toMonth': toMonth,
        if (toYear != null) 'toYear': toYear,
      },
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null) return;
    final bytes = data is Uint8List
        ? data
        : data is List<int>
        ? Uint8List.fromList(data)
        : Uint8List.fromList(const <int>[]);
    final suffix = (fromYear != null) ? '-$fromYear' : '';
    await web_bridge.downloadBytes(
      bytes: bytes,
      fileName: 'printer-$type-report$suffix.$format',
      mimeType: format == 'xlsx'
          ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          : 'application/pdf',
    );
  }

  Future<void> exportPrinterReport(String printerId, {int? month, int? year}) {
    return exportReport(
      format: 'pdf',
      type: 'printer',
      printerId: printerId,
      fromMonth: month,
      fromYear: year,
      toMonth: month,
      toYear: year,
    );
  }

  final Map<ConsumptionRequestKey, Future<Map<String, dynamic>>>
  _inFlightConsumption = {};
  final Map<
    ConsumptionRequestKey,
    ({Map<String, dynamic> data, DateTime timestamp})
  >
  _consumptionCache = {};

  Future<Map<String, dynamic>> fetchMonthlyConsumption({
    String? branchId,
    String? printerId,
    int? fromMonth,
    int? fromYear,
    int? toMonth,
    int? toYear,
    bool forceRefresh = false,
  }) async {
    final key = ConsumptionRequestKey(
      branchId: branchId,
      printerId: printerId,
      fromMonth: fromMonth,
      fromYear: fromYear,
      toMonth: toMonth,
      toYear: toYear,
    );

    if (!forceRefresh) {
      final cached = _consumptionCache[key];
      if (cached != null) {
        final age = DateTime.now().difference(cached.timestamp);
        if (age < const Duration(seconds: 15)) {
          return cached.data;
        }
      }
    }

    final active = _inFlightConsumption[key];
    if (active != null) {
      return active;
    }

    final future = () async {
      try {
        final response = await _apiClient.dio.get<Map<String, dynamic>>(
          '/api/printers/consumption',
          queryParameters: {
            if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
            if (printerId != null && printerId.isNotEmpty)
              'printerId': printerId,
            if (fromMonth != null) 'fromMonth': fromMonth,
            if (fromYear != null) 'fromYear': fromYear,
            if (toMonth != null) 'toMonth': toMonth,
            if (toYear != null) 'toYear': toYear,
          },
        );
        final result = _body(response.data);
        _consumptionCache[key] = (data: result, timestamp: DateTime.now());
        return result;
      } catch (_) {
        rethrow;
      }
    }();

    _inFlightConsumption[key] = future;

    return future.whenComplete(() {
      if (identical(_inFlightConsumption[key], future)) {
        _inFlightConsumption.remove(key);
      }
    });
  }

  Map<String, dynamic> _body(Map<String, dynamic>? raw) {
    final root = raw ?? const <String, dynamic>{};
    final data = root['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return root;
  }

  Map<String, dynamic> _map(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  List<dynamic> _list(Object? raw) => raw is List ? raw : const <dynamic>[];
}

class ConsumptionRequestKey {
  const ConsumptionRequestKey({
    this.branchId,
    this.printerId,
    this.fromMonth,
    this.fromYear,
    this.toMonth,
    this.toYear,
  });

  final String? branchId;
  final String? printerId;
  final int? fromMonth;
  final int? fromYear;
  final int? toMonth;
  final int? toYear;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConsumptionRequestKey &&
          runtimeType == other.runtimeType &&
          branchId == other.branchId &&
          printerId == other.printerId &&
          fromMonth == other.fromMonth &&
          fromYear == other.fromYear &&
          toMonth == other.toMonth &&
          toYear == other.toYear;

  @override
  int get hashCode =>
      Object.hash(branchId, printerId, fromMonth, fromYear, toMonth, toYear);
}
