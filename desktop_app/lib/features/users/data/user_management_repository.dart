import '../../../core/network/api_client.dart';
import '../../../shared/models/managed_user.dart';
import '../../auth/data/auth_repository.dart';

class ManagedUsersPage {
  const ManagedUsersPage({
    required this.users,
    required this.page,
    required this.limit,
    required this.hasMore,
  });

  final List<ManagedUser> users;
  final int page;
  final int limit;
  final bool hasMore;
}

class UserManagementRepository {
  UserManagementRepository(this._apiClient, this._authRepository);

  final ApiClient _apiClient;
  final AuthRepository _authRepository;

  Future<ManagedUsersPage> fetchUsersPage({
    String? search,
    String? departmentId,
    String? branchId,
    String? role,
    String? status,
    int page = 1,
    int limit = 50,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/admin/users',
      queryParameters: {
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (departmentId != null && departmentId.isNotEmpty)
          'departmentId': departmentId,
        if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
        if (role != null && role.isNotEmpty) 'role': role,
        if (status != null && status.isNotEmpty) 'status': status,
        'page': page,
        'limit': limit,
      },
    );

    final body = response.data ?? const <String, dynamic>{};
    final nested = body['data'];
    final list =
        (nested is Map<String, dynamic> ? nested['users'] : null) ??
        body['users'] ??
        const [];
    if (list is! List) {
      return ManagedUsersPage(
        users: const [],
        page: page,
        limit: limit,
        hasMore: false,
      );
    }
    final pagination =
        body['pagination'] ??
        (nested is Map<String, dynamic> ? nested['pagination'] : null);
    return ManagedUsersPage(
      users: list
          .whereType<Map<String, dynamic>>()
          .map(ManagedUser.fromJson)
          .toList(),
      page: pagination is Map ? (pagination['page'] as int? ?? page) : page,
      limit: pagination is Map ? (pagination['limit'] as int? ?? limit) : limit,
      hasMore: pagination is Map ? pagination['hasMore'] == true : false,
    );
  }

  Future<List<ManagedUser>> fetchUsers({
    String? search,
    String? departmentId,
    String? branchId,
    String? role,
    String? status,
    int page = 1,
    int limit = 50,
  }) async {
    final result = await fetchUsersPage(
      search: search,
      departmentId: departmentId,
      branchId: branchId,
      role: role,
      status: status,
      page: page,
      limit: limit,
    );
    return result.users;
  }

  Future<ManagedUser> createUser({
    required String username,
    required String fullName,
    required String password,
    required String role,
    String? departmentId,
    List<String>? departmentIds,
    String? branchId,
    int? maxAttachmentSizeMB,
    Map<String, bool>? permissions,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/admin/users',
      data: {
        'username': username,
        'fullName': fullName,
        'password': password,
        'role': role,
        if (permissions != null) 'permissions': permissions,
        if (departmentId != null && departmentId.isNotEmpty)
          'departmentId': departmentId,
        if (departmentIds != null && departmentIds.isNotEmpty)
          'departmentIds': departmentIds,
        if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
        if (maxAttachmentSizeMB != null)
          'maxAttachmentSizeMB': maxAttachmentSizeMB,
      },
    );

    return ManagedUser.fromJson(response.data?['user'] as Map<String, dynamic>);
  }

  Future<ManagedUser> updateUser({
    required String userId,
    String? username,
    String? fullName,
    String? password,
    String? role,
    String? departmentId,
    List<String>? departmentIds,
    String? branchId,
    int? maxAttachmentSizeMB,
    Map<String, bool>? permissions,
  }) async {
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/admin/users/$userId',
      data: {
        if (username != null) 'username': username,
        if (fullName != null) 'fullName': fullName,
        if (password != null && password.isNotEmpty) 'password': password,
        if (role != null) 'role': role,
        if (permissions != null) 'permissions': permissions,
        if (departmentId != null) 'departmentId': departmentId,
        if (departmentIds != null) 'departmentIds': departmentIds,
        if (branchId != null) 'branchId': branchId,
        if (maxAttachmentSizeMB != null) 'maxAttachmentSizeMB': maxAttachmentSizeMB,
      },
    );

    return ManagedUser.fromJson(response.data?['user'] as Map<String, dynamic>);
  }

  Future<ManagedUser> updateUserStatus({
    required String userId,
    required bool isActive,
  }) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/admin/users/$userId/status',
      data: {'isActive': isActive},
    );

    return ManagedUser.fromJson(response.data?['user'] as Map<String, dynamic>);
  }

  Future<ManagedUser> resetPassword({
    required String userId,
    required String password,
  }) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/admin/users/$userId/reset-password',
      data: {'password': password},
    );

    return ManagedUser.fromJson(response.data?['user'] as Map<String, dynamic>);
  }

  Future<void> deleteUser(String userId) async {
    await _apiClient.dio.delete<void>('/api/admin/users/$userId');
  }

  Future<void> forceLogoutAllDevices(String userId) async {
    await _apiClient.dio.post<void>('/api/admin/users/$userId/logout-all');
  }
}
