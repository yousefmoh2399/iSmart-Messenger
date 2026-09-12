import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../features/chat/data/chat_socket_service.dart';

const int kMaxInlineFileSaveBytes = 30 * 1024 * 1024;
const int kAdminInlineFileSaveBytes = 200 * 1024 * 1024;

class RemoteDesktopStorageStatus {
  const RemoteDesktopStorageStatus({
    required this.hasDesktop,
    required this.autoSaveAfterScan,
  });

  final bool hasDesktop;
  final bool autoSaveAfterScan;
}

class RemoteDesktopFileSaveResult {
  const RemoteDesktopFileSaveResult({
    required this.success,
    required this.message,
    required this.jobId,
    required this.savedPath,
  });

  final bool success;
  final String message;
  final String? jobId;
  final String? savedPath;
}

typedef RemoteDesktopTransferProgressCallback =
    void Function(RemoteDesktopTransferProgress progress);

class RemoteDesktopTransferProgress {
  const RemoteDesktopTransferProgress({
    required this.stage,
    required this.progress,
    required this.message,
  });

  final String stage;
  final double progress;
  final String message;
}

class RemoteDesktopFileService {
  RemoteDesktopFileService(this._socket, this._apiClient);

  final ChatSocketService _socket;
  final ApiClient _apiClient;
  RemoteDesktopStorageStatus? _cachedStatus;
  DateTime? _cachedStatusAt;
  static const Duration _statusCacheTtl = Duration(seconds: 20);

  Future<RemoteDesktopStorageStatus> fetchStatus() async {
    final now = DateTime.now();
    final hasFreshCache =
        _cachedStatus != null &&
        _cachedStatusAt != null &&
        now.difference(_cachedStatusAt!) <= _statusCacheTtl;

    for (var attempt = 0; attempt < 3; attempt++) {
      final response = await _socket.emitWithAck(
        'desktop_storage:get',
        {},
        timeout: const Duration(seconds: 12),
      );

      final ok = response['ok'] == true && response['success'] == true;
      if (ok) {
        final data = response['data'] is Map
            ? Map<String, dynamic>.from(response['data'] as Map)
            : const <String, dynamic>{};
        final status = RemoteDesktopStorageStatus(
          hasDesktop: data['hasDesktop'] == true,
          autoSaveAfterScan: data['autoSaveAfterScan'] == true,
        );
        _cachedStatus = status;
        _cachedStatusAt = DateTime.now();
        return status;
      }

      final errorMessage = '${response['error'] ?? ''}'.toLowerCase();
      final isSocketTransient =
          errorMessage.contains('not connected') ||
          errorMessage.contains('ack timeout');
      if (isSocketTransient && hasFreshCache) {
        // Avoid false "no desktop connected" while socket is reconnecting.
        return _cachedStatus!;
      }

      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }

    if (hasFreshCache) {
      return _cachedStatus!;
    }

    return const RemoteDesktopStorageStatus(
      hasDesktop: false,
      autoSaveAfterScan: false,
    );
  }

  Future<RemoteDesktopFileSaveResult> requestSaveFromLocalFile({
    required String filePath,
    String? fileName,
    String? mimeType,
    String source = 'mobile_local_file_transfer',
    int maxInlineFileBytes = kMaxInlineFileSaveBytes,
    Duration completionTimeout = const Duration(seconds: 40),
    Duration? ackTimeout,
    RemoteDesktopTransferProgressCallback? onProgress,
  }) async {
    _notifyProgress(
      onProgress,
      stage: 'validating',
      progress: 0.05,
      message: 'Preparing file...',
    );

    final file = File(filePath);
    final exists = await file.exists();
    if (!exists) {
      _notifyProgress(
        onProgress,
        stage: 'failed',
        progress: 1,
        message: 'File not found on this device.',
      );
      return const RemoteDesktopFileSaveResult(
        success: false,
        message: 'الملف غير موجود على الجهاز.',
        jobId: null,
        savedPath: null,
      );
    }

    final size = await file.length();
    if (size > maxInlineFileBytes) {
      _notifyProgress(
        onProgress,
        stage: 'failed',
        progress: 1,
        message: 'File exceeds the direct transfer limit.',
      );
      return const RemoteDesktopFileSaveResult(
        success: false,
        message: 'حجم الملف كبير. تجاوزت حد الإرسال المباشر المسموح لحسابك.',
        jobId: null,
        savedPath: null,
      );
    }

    _notifyProgress(
      onProgress,
      stage: 'reading',
      progress: 0.12,
      message: 'Reading file from mobile...',
    );
    final bytes = await file.readAsBytes();
    _notifyProgress(
      onProgress,
      stage: 'encoding',
      progress: 0.42,
      message: 'Preparing direct transfer to desktop...',
    );
    final inlineFileBase64 = base64Encode(bytes);

    return _requestAndAwaitResult(
      payload: {
        'inlineFileBase64': inlineFileBase64,
        'fileName': fileName ?? file.uri.pathSegments.last,
        'mimeType': mimeType,
        'fileSize': size,
        'source': source,
      },
      completionTimeout: completionTimeout,
      ackTimeout: ackTimeout ?? const Duration(seconds: 45),
      onProgress: onProgress,
    );
  }

  Future<RemoteDesktopFileSaveResult> requestSaveFromDownloadUrl({
    required String downloadUrl,
    required String fileName,
    String? mimeType,
    String source = 'mobile_download_url_transfer',
    Duration completionTimeout = const Duration(seconds: 40),
    Duration ackTimeout = const Duration(seconds: 30),
    RemoteDesktopTransferProgressCallback? onProgress,
  }) async {
    _notifyProgress(
      onProgress,
      stage: 'sending',
      progress: 0.6,
      message: 'Sending save request...',
    );
    return _requestAndAwaitResult(
      payload: {
        'downloadUrl': downloadUrl,
        'fileName': fileName,
        'mimeType': mimeType,
        'source': source,
      },
      completionTimeout: completionTimeout,
      ackTimeout: ackTimeout,
      onProgress: onProgress,
    );
  }

  Future<RemoteDesktopFileSaveResult> _requestAndAwaitResult({
    required Map<String, dynamic> payload,
    required Duration completionTimeout,
    required Duration ackTimeout,
    RemoteDesktopTransferProgressCallback? onProgress,
  }) async {
    _notifyProgress(
      onProgress,
      stage: 'sending',
      progress: 0.78,
      message: 'Sending save request...',
    );
    final ack = await _socket.emitWithAck(
      'file_save_request',
      payload,
      timeout: ackTimeout,
    );

    final ackOk = ack['ok'] == true && ack['success'] == true;
    final ackData = ack['data'] is Map
        ? Map<String, dynamic>.from(ack['data'] as Map)
        : const <String, dynamic>{};
    final jobId = ackData['jobId']?.toString();

    if (!ackOk || jobId == null || jobId.isEmpty) {
      _notifyProgress(
        onProgress,
        stage: 'failed',
        progress: 1,
        message: ack['error']?.toString() ?? 'Unable to send file.',
      );
      return RemoteDesktopFileSaveResult(
        success: false,
        message:
            ack['error']?.toString() ?? 'تعذر إرسال الملف إلى تطبيق الكمبيوتر.',
        jobId: jobId,
        savedPath: null,
      );
    }

    StreamSubscription<ChatSocketEvent>? progressSubscription;
    _notifyProgress(
      onProgress,
      stage: 'waiting_desktop',
      progress: 0.84,
      message: 'Waiting for desktop app...',
    );

    try {
      progressSubscription = _socket.events.listen((event) {
        if (event.type != 'file_save_progress' ||
            event.payload['jobId']?.toString() != jobId) {
          return;
        }
        final progressValue =
            (event.payload['progress'] as num?)?.toDouble() ?? 0;
        final progress = progressValue.clamp(0, 1).toDouble();
        _notifyProgress(
          onProgress,
          stage: event.payload['stage']?.toString() ?? 'waiting_desktop',
          progress: 0.84 + (progress * 0.14),
          message:
              event.payload['message']?.toString() ??
              'Waiting for desktop app...',
        );
      });

      final status = await _socket.events
          .firstWhere(
            (event) =>
                event.type == 'file_save_status' &&
                event.payload['jobId']?.toString() == jobId,
          )
          .timeout(completionTimeout);

      final success = status.payload['success'] == true;
      _notifyProgress(
        onProgress,
        stage: success ? 'completed' : 'failed',
        progress: 1,
        message: success ? 'File saved on desktop.' : 'Desktop save failed.',
      );

      return RemoteDesktopFileSaveResult(
        success: success,
        message:
            status.payload['message']?.toString() ??
            (success
                ? 'تم حفظ الملف على الكمبيوتر.'
                : 'تعذر حفظ الملف على الكمبيوتر.'),
        jobId: jobId,
        savedPath: status.payload['savedPath']?.toString(),
      );
    } on TimeoutException {
      _notifyProgress(
        onProgress,
        stage: 'failed',
        progress: 1,
        message: 'Desktop response timeout.',
      );
      return const RemoteDesktopFileSaveResult(
        success: false,
        message: 'انتهت مهلة انتظار رد الكمبيوتر على عملية الحفظ.',
        jobId: null,
        savedPath: null,
      );
    } finally {
      await progressSubscription?.cancel();
    }
  }

  // ignore: unused_element
  Future<Map<String, dynamic>> _uploadTemporaryTransfer({
    required String filePath,
    required String fileName,
    required String? mimeType,
    required String source,
    required int fileSizeBytes,
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      'fileName': fileName,
      if (mimeType != null && mimeType.trim().isNotEmpty)
        'mimeType': mimeType.trim(),
      'source': source,
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat/transfers',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        connectTimeout: _uploadTimeoutForBytes(fileSizeBytes),
        sendTimeout: _uploadTimeoutForBytes(fileSizeBytes),
        receiveTimeout: _uploadTimeoutForBytes(fileSizeBytes),
      ),
      onSendProgress: onProgress,
    );
    final payload = response.data ?? const <String, dynamic>{};
    final data = payload['data'] is Map<String, dynamic>
        ? payload['data'] as Map<String, dynamic>
        : (payload['data'] is Map
              ? Map<String, dynamic>.from(payload['data'] as Map)
              : payload);
    final transfer = data['transfer'] is Map<String, dynamic>
        ? data['transfer'] as Map<String, dynamic>
        : Map<String, dynamic>.from(data['transfer'] as Map? ?? const {});
    if ((transfer['id']?.toString().trim().isEmpty ?? true)) {
      throw Exception('تعذر تجهيز نقل الملف إلى الكمبيوتر.');
    }
    return transfer;
  }

  Duration _uploadTimeoutForBytes(int bytes) {
    final megaBytes = bytes / (1024 * 1024);
    final minutes = megaBytes <= 8 ? 2 : (2 + (megaBytes / 12).ceil());
    final clampedMinutes = minutes.clamp(2, 15);
    return Duration(minutes: clampedMinutes);
  }

  void _notifyProgress(
    RemoteDesktopTransferProgressCallback? onProgress, {
    required String stage,
    required double progress,
    required String message,
  }) {
    if (onProgress == null) {
      return;
    }
    final normalized = progress.clamp(0, 1).toDouble();
    onProgress(
      RemoteDesktopTransferProgress(
        stage: stage,
        progress: normalized,
        message: message,
      ),
    );
  }
}
