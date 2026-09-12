import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart';
import '../models/ticket_models.dart';
import 'ticket_response_parser.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;

class TicketRepository {
  TicketRepository(this._apiClient, this._authRepository);

  final ApiClient _apiClient;
  final AuthRepository _authRepository;

  Future<TicketOverviewData> fetchOverview({
    String? scope,
    String? status,
    String? priority,
    String? q,
    String? ticketType,
    int limit = 120,
  }) async {
    final ticketsResponse = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/tickets',
      queryParameters: {
        if (scope != null && scope.trim().isNotEmpty) 'scope': scope.trim(),
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        if (priority != null && priority.trim().isNotEmpty)
          'priority': priority.trim(),
        if (ticketType != null && ticketType.trim().isNotEmpty)
          'ticketType': ticketType.trim(),
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        'limit': limit,
      },
    );

    final settingsResponse = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/tickets/settings',
    );

    final ticketsBody = asStringKeyedMap(ticketsResponse.data);
    final tickets = readTicketsList(
      ticketsBody,
    ).map(TicketItem.fromJson).toList();
    final settingsBody = asStringKeyedMap(settingsResponse.data);
    final settings = TicketSettingsData.fromJson(
      readObject(settingsBody, 'settings'),
    );
    final meta = readMeta(ticketsBody);

    return TicketOverviewData(
      tickets: tickets,
      settings: settings,
      canManage: meta['canManage'] == true || settings.canManage,
    );
  }

  Future<TicketDetailsData> fetchTicketDetails(String ticketId) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/tickets/$ticketId',
    );
    final body = asStringKeyedMap(response.data);
    final ticket = TicketItem.fromJson(readTicketMap(body));
    final updates = readUpdatesList(
      body,
    ).map(TicketUpdateItem.fromJson).toList();
    final settings = await fetchSettings();
    final meta = readMeta(body);

    return TicketDetailsData(
      ticket: ticket,
      updates: updates,
      settings: settings,
      canManage: meta['canManage'] == true || settings.canManage,
    );
  }

  Future<TicketItem> createTicket({
    required String title,
    required String description,
    String priority = 'normal',
    String ticketType = 'ticket',
    String? targetDepartmentId,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/tickets',
      data: {
        'title': title.trim(),
        'description': description.trim(),
        'priority': priority,
        'ticketType': ticketType,
        if (targetDepartmentId != null)
          'targetDepartmentId': targetDepartmentId,
      },
    );

    return parseTicketItem(asStringKeyedMap(response.data));
  }

  Future<TicketDetailsData> addComment({
    required String ticketId,
    required String message,
    bool internalNote = false,
  }) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/tickets/$ticketId/comments',
      data: {
        'message': message.trim(),
        'visibility': internalNote ? 'internal' : 'public',
      },
    );
    return fetchTicketDetails(ticketId);
  }

  Future<TicketDetailsData> updateStatus({
    required String ticketId,
    required String status,
  }) async {
    await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/tickets/$ticketId/status',
      data: {'status': status},
    );
    return fetchTicketDetails(ticketId);
  }

  Future<TicketDetailsData> assignTicket({
    required String ticketId,
    String? assignedToId,
  }) async {
    await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/tickets/$ticketId/assignee',
      data: {'assignedToId': assignedToId},
    );
    return fetchTicketDetails(ticketId);
  }

  Future<TicketSettingsData> fetchSettings() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/tickets/settings',
    );
    return TicketSettingsData.fromJson(
      readObject(asStringKeyedMap(response.data), 'settings'),
    );
  }

  Future<TicketSupportUsersData> fetchSupportUsers() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/tickets/support-users',
    );

    final body = asStringKeyedMap(response.data);
    final merged = mergeResponseBody(body);
    final users = readObjectList(
      body,
      'users',
    ).map(TicketSupportUser.fromJson).toList();
    final supportAgentIds =
        (merged['supportAgentIds'] as List<dynamic>? ??
                body['supportAgentIds'] as List<dynamic>? ??
                const [])
            .map((entry) => entry.toString())
            .where((entry) => entry.isNotEmpty)
            .toList();

    return TicketSupportUsersData(
      users: users,
      supportAgentIds: supportAgentIds,
    );
  }

  Future<TicketSettingsData> updateSupportAgents(
    List<String> supportAgentIds, {
    Map exportPermissionsByUserId = const {},
  }) async {
    final reportExporters = exportPermissionsByUserId.entries
        .map((entry) => {'userId': entry.key, 'ticketTypes': entry.value})
        .toList();
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/tickets/settings',
      data: {
        'supportAgentIds': supportAgentIds,
        'reportExporters': reportExporters,
      },
    );
    return TicketSettingsData.fromJson(
      readObject(asStringKeyedMap(response.data), 'settings'),
    );
  }

  Future<void> exportTicketsReport({
    String ticketType = 'ticket',
    String? status,
    String? priority,
    String? q,
  }) async {
    final response = await _apiClient.dio.get<Object>(
      '/api/tickets/reports/export',
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        if (priority != null && priority.trim().isNotEmpty)
          'priority': priority.trim(),
        'ticketType': ticketType,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      },
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    final bytes = data is Uint8List
        ? data
        : data is List<int>
        ? Uint8List.fromList(data)
        : Uint8List.fromList(const <int>[]);
    await web_bridge.downloadBytes(
      bytes: bytes,
      fileName:
          '${ticketType == 'ticket'
              ? 'tickets'
              : ticketType == 'complaint'
              ? 'complaints'
              : 'suggestions'}-report.csv',
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  Future<Map<String, List<Map<String, String>>>>
  fetchDepartmentHandlerAssignments({String handlerType = 'complaint'}) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/tickets/settings/department-handler-assignments',
      queryParameters: {'handlerType': handlerType},
    );
    final raw = readObject(asStringKeyedMap(response.data), 'assignments');
    final assignments = <String, List<Map<String, String>>>{};
    for (final entry in raw.entries) {
      final departments = (entry.value as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => {
              'departmentId': item['departmentId']?.toString() ?? '',
              'departmentName': item['departmentName']?.toString() ?? '',
            },
          )
          .toList();
      assignments[entry.key] = departments;
    }
    return assignments;
  }

  Future<List<TicketActor>> fetchDepartmentHandlers(
    String departmentId, {
    String handlerType = 'complaint',
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/tickets/settings/departments/$departmentId/handlers',
      queryParameters: {'handlerType': handlerType},
    );
    return readObjectList(
      asStringKeyedMap(response.data),
      'users',
    ).map(TicketActor.fromJson).toList();
  }

  Future<List<TicketActor>> updateDepartmentHandlers(
    String departmentId,
    List<String> handlerIds, {
    String handlerType = 'complaint',
  }) async {
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/tickets/settings/departments/$departmentId/handlers',
      data: {'handlerIds': handlerIds, 'handlerType': handlerType},
    );
    return readObjectList(
      asStringKeyedMap(response.data),
      'users',
    ).map(TicketActor.fromJson).toList();
  }
}
