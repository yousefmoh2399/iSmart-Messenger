import '../../../core/network/api_client.dart';
import '../../../shared/models/admin_announcement.dart';

class AnnouncementRepository {
  AnnouncementRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<AdminAnnouncement>> fetchAnnouncements({
    bool includeInactive = false,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/announcements',
      queryParameters: {if (includeInactive) 'includeInactive': true},
    );

    final list =
        response.data?['announcements'] as List<dynamic>? ?? const <dynamic>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(AdminAnnouncement.fromJson)
        .toList();
  }

  Future<AdminAnnouncement> createAnnouncement({
    required String title,
    required String message,
    required String tone,
    required bool isPinned,
    required bool isActive,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/announcements',
      data: {
        'title': title,
        'message': message,
        'tone': tone,
        'isPinned': isPinned,
        'isActive': isActive,
      },
    );

    return AdminAnnouncement.fromJson(
      response.data?['announcement'] as Map<String, dynamic>,
    );
  }

  Future<AdminAnnouncement> updateAnnouncement({
    required String announcementId,
    required String title,
    required String message,
    required String tone,
    required bool isPinned,
    required bool isActive,
  }) async {
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/announcements/$announcementId',
      data: {
        'title': title,
        'message': message,
        'tone': tone,
        'isPinned': isPinned,
        'isActive': isActive,
      },
    );

    return AdminAnnouncement.fromJson(
      response.data?['announcement'] as Map<String, dynamic>,
    );
  }

  Future<AdminAnnouncement> updateAnnouncementStatus({
    required String announcementId,
    required bool isActive,
  }) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/announcements/$announcementId/status',
      data: {'isActive': isActive},
    );

    return AdminAnnouncement.fromJson(
      response.data?['announcement'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteAnnouncement(String announcementId) async {
    await _apiClient.dio.delete<void>('/api/announcements/$announcementId');
  }
}
