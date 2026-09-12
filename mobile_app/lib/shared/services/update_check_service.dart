import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../models/update_models.dart';

class UpdateCheckService {
  UpdateCheckService(this._apiClient);

  final ApiClient _apiClient;

  Map<String, dynamic> _extractData(Map<String, dynamic>? data) {
    return (data?['data'] as Map<String, dynamic>?) ?? (data ?? const {});
  }

  Future<MobileUpdateCheckResponse> checkForUpdates({
    required String deviceUid,
    required String currentVersion,
    required String branchCode,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/updates/mobile/check',
        data: {
          'deviceUid': deviceUid,
          'currentVersion': currentVersion,
          'branchCode': branchCode,
        },
        options: Options(extra: {'requestSource': 'mobileUpdate.check'}),
      );
      final payload = _extractData(response.data);
      return MobileUpdateCheckResponse.fromJson(payload);
    } catch (e) {
      debugPrint('Error checking for updates: $e');
      return const MobileUpdateCheckResponse(
        availableRelease: null,
        currentTask: null,
        requiresUpdate: false,
        isMandatory: false,
      );
    }
  }

  Future<void> downloadAndInstallApk({
    required String releaseId,
    required String fileName,
  }) async {
    try {
      // APK خط سير التنزيل والتثبيت
      // 1. تنزيل APK
      // 2. حفظه
      // 3. فتح intent التثبيت

      // دعني أترك هذا لاحقاً عندما نتحدث عن File handling
    } catch (e) {
      debugPrint('Error downloading/installing APK: $e');
      rethrow;
    }
  }

  Future<void> reportTaskProgress({
    required String taskId,
    required String deviceUid,
    required String status,
    required int progress,
    String? message,
  }) async {
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/updates/tasks/$taskId/progress',
        data: {
          'deviceUid': deviceUid,
          'status': status,
          'progress': progress,
          if (message != null && message.trim().isNotEmpty)
            'message': message.trim(),
        },
        options: Options(extra: {'requestSource': 'mobileUpdate.taskProgress'}),
      );
    } catch (e) {
      debugPrint('Error reporting task progress: $e');
    }
  }
}
