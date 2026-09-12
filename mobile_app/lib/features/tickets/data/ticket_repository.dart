import '../../../core/network/api_client.dart';
import '../models/ticket_models.dart';
import 'ticket_response_parser.dart';

class TicketRepository {
  TicketRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<TicketOverviewData> fetchOverview({
    String? scope,
    String? status,
    String? priority,
    String? query,
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
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
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
    final settings = TicketSettingsData.fromJson(
      readObject(asStringKeyedMap(settingsResponse.data), 'settings'),
    );

    return TicketOverviewData(tickets: tickets, settings: settings);
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
    final settingsResponse = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/tickets/settings',
    );
    final settings = TicketSettingsData.fromJson(
      readObject(asStringKeyedMap(settingsResponse.data), 'settings'),
    );
    final meta = readMeta(body);
    final canManage = meta['canManage'] == true || settings.canManage;

    return TicketDetailsData(
      ticket: ticket,
      updates: updates,
      settings: settings,
      canManage: canManage,
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
        if (internalNote) 'visibility': 'internal',
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
      response.data?['settings'] as Map<String, dynamic>?,
    );
  }

  Future<TicketSupportUsersData> fetchSupportUsers() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/tickets/support-users',
    );

    final users = (response.data?['users'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TicketSupportUser.fromJson)
        .toList();
    final supportAgentIds =
        (response.data?['supportAgentIds'] as List<dynamic>? ?? const [])
            .map((entry) => entry.toString())
            .toList();

    return TicketSupportUsersData(
      users: users,
      supportAgentIds: supportAgentIds,
    );
  }

  Future<TicketSettingsData> updateSupportAgents(
    List<String> supportAgentIds,
  ) async {
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/tickets/settings',
      data: {'supportAgentIds': supportAgentIds},
    );
    return TicketSettingsData.fromJson(
      response.data?['settings'] as Map<String, dynamic>?,
    );
  }

  Future<List<TicketActor>> fetchDepartmentHandlers(
    String departmentId, {
    String handlerType = 'complaint',
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/tickets/settings/departments/$departmentId/handlers',
      queryParameters: {'handlerType': handlerType},
    );
    final body = asStringKeyedMap(response.data);
    return readObjectList(body, 'users').map(TicketActor.fromJson).toList();
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
    final body = asStringKeyedMap(response.data);
    return readObjectList(body, 'users').map(TicketActor.fromJson).toList();
  }
}
