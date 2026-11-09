import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../models/system_monitor_models.dart';

class SystemMonitorRepository {
  SystemMonitorRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<SystemTelemetryStats> getSystemStats() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/admin/system-monitor/stats',
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    return SystemTelemetryStats.fromJson(data);
  }

  Future<PaginatedResponse<DeviceSession>> getConnections({
    int page = 1,
    int limit = 50,
    String status = 'all',
    String clientType = 'all',
    String search = '',
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/admin/system-monitor/connections',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (status != 'all') 'status': status,
        if (clientType != 'all') 'clientType': clientType,
        if (search.trim().isNotEmpty) 'search': search.trim(),
      },
    );

    final data = response.data?['data'] as Map<String, dynamic>;
    final sessionsList = (data['sessions'] as List<dynamic>?) ?? [];
    final pagination = data['pagination'] as Map<String, dynamic>? ?? {};

    return PaginatedResponse<DeviceSession>(
      items: sessionsList
          .map((e) => DeviceSession.fromJson(e as Map<String, dynamic>))
          .toList(),
      page: pagination['page'] as int? ?? page,
      limit: pagination['limit'] as int? ?? limit,
      total: pagination['total'] as int? ?? 0,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }

  Future<PaginatedResponse<ClientErrorLog>> getErrors({
    int page = 1,
    int limit = 50,
    String? userId,
    String? sessionId,
    bool? resolved,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/admin/system-monitor/errors',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (userId != null) 'userId': userId,
        if (sessionId != null) 'sessionId': sessionId,
        if (resolved != null) 'resolved': resolved,
      },
    );

    final data = response.data?['data'] as Map<String, dynamic>;
    final errorsList = (data['errors'] as List<dynamic>?) ?? [];
    final pagination = data['pagination'] as Map<String, dynamic>? ?? {};

    return PaginatedResponse<ClientErrorLog>(
      items: errorsList
          .map((e) => ClientErrorLog.fromJson(e as Map<String, dynamic>))
          .toList(),
      page: pagination['page'] as int? ?? page,
      limit: pagination['limit'] as int? ?? limit,
      total: pagination['total'] as int? ?? 0,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }

  Future<ClientErrorLog> resolveError(String id) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/admin/system-monitor/errors/$id/resolve',
    );
    return ClientErrorLog.fromJson(
      response.data?['data'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteAllErrors() async {
    await _apiClient.dio.delete<dynamic>('/api/admin/system-monitor/errors');
  }

  Future<BranchesDeploymentData> getBranchesDeployment({String? targetVersion}) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/admin/system-monitor/branches-deployment',
      queryParameters: {
        if (targetVersion != null && targetVersion.trim().isNotEmpty)
          'targetVersion': targetVersion.trim(),
      },
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    return BranchesDeploymentData.fromJson(data);
  }

  Future<RequestTelemetryData> getRequestTelemetry() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/admin/system-monitor/request-telemetry',
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    return RequestTelemetryData.fromJson(data);
  }

  Future<void> exportDeploymentReport({String format = 'xlsx', String? targetVersion, String? scope}) async {
    final response = await _apiClient.dio.get<dynamic>(
      '/api/admin/system-monitor/reports/export',
      queryParameters: {
        'format': format,
        if (targetVersion != null && targetVersion.trim().isNotEmpty)
          'targetVersion': targetVersion.trim(),
        if (scope != null && scope.trim().isNotEmpty)
          'scope': scope.trim(),
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
    final ext = format == 'pdf' ? 'pdf' : 'xlsx';
    final mime = format == 'pdf'
        ? 'application/pdf'
        : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    await web_bridge.downloadBytes(
      bytes: bytes,
      fileName: '${scope == "outdated" ? "ismart-outdated-devices" : "ismart-branches-deployment"}-${DateTime.now().millisecondsSinceEpoch}.$ext',
      mimeType: mime,
    );
  }
Future<AdminPollsData> getAdminPolls({
    String search = '',
    String status = 'all',
    int page = 1,
    int limit = 50,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/admin/system-monitor/polls',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (status != 'all') 'status': status,
      },
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    return AdminPollsData.fromJson(data);
  }

  Future<void> exportAdminPoll(
    String pollId, {
    String format = 'xlsx',
    String title = 'poll',
  }) async {
    final response = await _apiClient.dio.get<dynamic>(
      '/api/admin/system-monitor/polls/$pollId/export',
      queryParameters: {'format': format},
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null) return;
    final bytes = data is Uint8List
        ? data
        : data is List<int>
            ? Uint8List.fromList(data)
            : Uint8List.fromList(const <int>[]);
    final ext = format == 'pdf' ? 'pdf' : 'xlsx';
    final mime = format == 'pdf'
        ? 'application/pdf'
        : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    final safeTitle = title.replaceAll(RegExp(r'[\/:*?"<>|\s]+'), '_');
    await web_bridge.downloadBytes(
      bytes: bytes,
      fileName: '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.$ext',
      mimeType: mime,
    );
  }

  Future<void> seedDefaultPolls() async {
    await _apiClient.dio.post<dynamic>('/api/admin/system-monitor/polls/seed');
  }

  Future<void> togglePollStatus(String pollId) async {
    await _apiClient.dio.patch<dynamic>(
      '/api/admin/system-monitor/polls/$pollId/toggle-status',
    );
  }

  Future<void> createPoll({
    required String question,
    required List<String> options,
    bool isAnonymous = false,
    bool isMultipleChoice = false,
    String? conversationId,
  }) async {
    await _apiClient.dio.post<dynamic>(
      '/api/admin/system-monitor/polls',
      data: {
        'question': question,
        'options': options,
        'isAnonymous': isAnonymous,
        'isMultipleChoice': isMultipleChoice,
        if (conversationId != null) 'conversationId': conversationId,
      },
    );
  }
}
