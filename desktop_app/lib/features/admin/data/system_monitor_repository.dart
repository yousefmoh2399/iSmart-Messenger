import '../../../core/network/api_client.dart';
import '../models/system_monitor_models.dart';

class SystemMonitorRepository {
  SystemMonitorRepository(this._apiClient);

  final ApiClient _apiClient;

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
      items: sessionsList.map((e) => DeviceSession.fromJson(e as Map<String, dynamic>)).toList(),
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
      items: errorsList.map((e) => ClientErrorLog.fromJson(e as Map<String, dynamic>)).toList(),
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
    return ClientErrorLog.fromJson(response.data?['data'] as Map<String, dynamic>);
  }

  Future<void> deleteAllErrors() async {
    await _apiClient.dio.delete<dynamic>('/api/admin/system-monitor/errors');
  }
}
