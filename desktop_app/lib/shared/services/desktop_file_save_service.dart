import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/network/api_client.dart';
import '../../core/network/media_url_resolver.dart';
import '../../features/auth/data/auth_repository.dart';
import 'local_media_storage_service.dart';
import 'web_platform_bridge.dart' as web_bridge;

class DesktopFileSaveResult {
  const DesktopFileSaveResult({
    required this.success,
    required this.message,
    required this.savedPath,
  });

  final bool success;
  final String message;
  final String? savedPath;
}

class DesktopFileSaveService {
  DesktopFileSaveService({
    required ApiClient apiClient,
    required AuthRepository authRepository,
  }) : _apiClient = apiClient,
       _authRepository = authRepository;

  final ApiClient _apiClient;
  final AuthRepository _authRepository;

  Future<DesktopFileSaveResult> executeSaveJob(
    Map<String, dynamic> payload, {
    String? preferredDirectoryPath,
    void Function({
      required String stage,
      required double progress,
      required String message,
      String? savedPath,
    })?
    onProgress,
  }) async {
    final fileName = (payload['fileName']?.toString().trim().isNotEmpty == true)
        ? payload['fileName'].toString().trim()
        : 'file';
    final mimeType = payload['mimeType']?.toString().trim();
    if (kIsWeb) {
      return _executeWebSaveJob(
        payload,
        fileName: fileName,
        mimeType: mimeType,
        preferredDirectoryPath: preferredDirectoryPath,
        onProgress: onProgress,
      );
    }

    final String outputPath;
    try {
      final safeName = _sanitizeFileName(
        fileName,
        mimeType,
        downloadUrl: payload['downloadUrl']?.toString(),
      );
      if (preferredDirectoryPath?.trim().isNotEmpty == true) {
        outputPath = await _resolveOutputPath(
          fileName: safeName,
          mimeType: mimeType,
          downloadUrl: payload['downloadUrl']?.toString(),
          preferredDirectoryPath: preferredDirectoryPath,
        );
      } else {
        final selectedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'حفظ الملف الوارد',
          fileName: safeName,
          lockParentWindow: true,
        );

        if (selectedPath == null || selectedPath.trim().isEmpty) {
          return const DesktopFileSaveResult(
            success: false,
            message: 'تم إلغاء الحفظ بواسطة المستخدم.',
            savedPath: null,
          );
        }
        outputPath = selectedPath;
      }
    } catch (error) {
      return DesktopFileSaveResult(
        success: false,
        message: error.toString(),
        savedPath: null,
      );
    }

    try {
      final inlineFileBase64 =
          payload['inlineFileBase64']?.toString().trim() ?? '';
      if (inlineFileBase64.isNotEmpty) {
        onProgress?.call(
          stage: 'receiving',
          progress: 0.18,
          message: 'جارٍ تجهيز الملف الوارد...',
        );
        final bytes = base64Decode(inlineFileBase64);
        onProgress?.call(
          stage: 'saving',
          progress: 0.82,
          message: 'جارٍ حفظ الملف على الكمبيوتر...',
        );
        await File(outputPath).writeAsBytes(bytes, flush: true);
      } else {
        final downloadUrl = payload['downloadUrl']?.toString().trim() ?? '';
        if (downloadUrl.isEmpty) {
          return const DesktopFileSaveResult(
            success: false,
            message: 'No file payload was provided.',
            savedPath: null,
          );
        }
        await _downloadFile(
          url: downloadUrl,
          outputPath: outputPath,
          onProgress: (received, total) {
            final ratio = total <= 0
                ? 0.0
                : (received / total).clamp(0, 1).toDouble();
            onProgress?.call(
              stage: 'downloading',
              progress: 0.12 + (ratio * 0.76),
              message: total > 0
                  ? 'جارٍ تنزيل الملف ${(ratio * 100).toStringAsFixed(0)}%'
                  : 'جارٍ تنزيل الملف...',
            );
          },
        );
      }

      onProgress?.call(
        stage: 'completed',
        progress: 1,
        message: 'تم حفظ الملف على الكمبيوتر.',
        savedPath: outputPath,
      );
      return DesktopFileSaveResult(
        success: true,
        message: 'تم حفظ الملف على الكمبيوتر بنجاح.',
        savedPath: outputPath,
      );
    } catch (error) {
      return DesktopFileSaveResult(
        success: false,
        message: error.toString(),
        savedPath: null,
      );
    }
  }

  Future<DesktopFileSaveResult> _executeWebSaveJob(
    Map<String, dynamic> payload, {
    required String fileName,
    required String? mimeType,
    required String? preferredDirectoryPath,
    void Function({
      required String stage,
      required double progress,
      required String message,
      String? savedPath,
    })?
    onProgress,
  }) async {
    try {
      final safeName = _sanitizeFileName(
        fileName,
        mimeType,
        downloadUrl: payload['downloadUrl']?.toString(),
      );
      final inlineFileBase64 =
          payload['inlineFileBase64']?.toString().trim() ?? '';
      if (inlineFileBase64.isNotEmpty) {
        onProgress?.call(
          stage: 'receiving',
          progress: 0.25,
          message: 'جاري تجهيز الملف الوارد...',
        );
        await web_bridge.downloadBytes(
          bytes: base64Decode(inlineFileBase64),
          fileName: safeName,
          mimeType: mimeType,
          preferredDirectoryPath: preferredDirectoryPath,
        );
      } else {
        final downloadUrl = payload['downloadUrl']?.toString().trim() ?? '';
        if (downloadUrl.isEmpty) {
          return const DesktopFileSaveResult(
            success: false,
            message: 'No file payload was provided.',
            savedPath: null,
          );
        }
        final bytes = await _downloadFileBytes(
          url: downloadUrl,
          onProgress: (received, total) {
            final ratio = total <= 0
                ? 0.0
                : (received / total).clamp(0, 1).toDouble();
            onProgress?.call(
              stage: 'downloading',
              progress: 0.12 + (ratio * 0.76),
              message: total > 0
                  ? 'جاري تنزيل الملف ${(ratio * 100).toStringAsFixed(0)}%'
                  : 'جاري تنزيل الملف...',
            );
          },
        );
        await web_bridge.downloadBytes(
          bytes: bytes,
          fileName: safeName,
          mimeType: mimeType,
          preferredDirectoryPath: preferredDirectoryPath,
        );
      }
      onProgress?.call(
        stage: 'completed',
        progress: 1,
        message: 'تم تجهيز الملف للتنزيل من المتصفح.',
        savedPath: safeName,
      );
      return DesktopFileSaveResult(
        success: true,
        message:
            'تم تجهيز الملف للتنزيل. المتصفح سيحفظه حسب إعدادات التنزيل عند المستخدم.',
        savedPath: safeName,
      );
    } catch (error) {
      return DesktopFileSaveResult(
        success: false,
        message: error.toString(),
        savedPath: null,
      );
    }
  }

  Future<String> _resolveOutputPath({
    required String fileName,
    required String? mimeType,
    required String? downloadUrl,
    required String? preferredDirectoryPath,
  }) async {
    final safeName = _sanitizeFileName(
      fileName,
      mimeType,
      downloadUrl: downloadUrl,
    );
    final outputDirectory = await _resolveOutputDirectory(
      preferredDirectoryPath,
    );
    final baseName = p.basenameWithoutExtension(safeName);
    final extension = p.extension(safeName);

    var candidate = p.join(outputDirectory.path, '$baseName$extension');
    var counter = 1;
    while (await File(candidate).exists()) {
      candidate = p.join(
        outputDirectory.path,
        '$baseName ($counter)$extension',
      );
      counter += 1;
    }
    return candidate;
  }

  Future<Directory> _resolveOutputDirectory(
    String? preferredDirectoryPath,
  ) async {
    final normalizedPreferred = preferredDirectoryPath?.trim();
    if (normalizedPreferred != null && normalizedPreferred.isNotEmpty) {
      final directory = Directory(normalizedPreferred);
      await directory.create(recursive: true);
      return directory;
    }

    return const LocalMediaStorageService().documentsDirectory();
  }

  String _sanitizeFileName(
    String input,
    String? mimeType, {
    String? downloadUrl,
  }) {
    final cleaned = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (cleaned.isNotEmpty && p.extension(cleaned).isNotEmpty) {
      return cleaned;
    }
    final fallbackExt = _resolveFallbackExtension(
      mimeType: mimeType,
      downloadUrl: downloadUrl,
    );
    final stem = cleaned.isEmpty ? 'file' : cleaned;
    return '$stem$fallbackExt';
  }

  String _resolveFallbackExtension({
    required String? mimeType,
    required String? downloadUrl,
  }) {
    final byMime = switch ((mimeType ?? '').toLowerCase()) {
      'application/pdf' => '.pdf',
      _ when (mimeType ?? '').toLowerCase().startsWith('image/') => '.jpg',
      _ => '',
    };
    if (byMime.isNotEmpty) {
      return byMime;
    }

    final byUrl = _extensionFromUrl(downloadUrl);
    if (byUrl != null) {
      return byUrl;
    }

    return '.pdf';
  }

  String? _extensionFromUrl(String? url) {
    final value = url?.trim() ?? '';
    if (value.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return null;
    }
    final ext = p.extension(uri.path).toLowerCase();
    if (ext.isEmpty || ext == '.') {
      return null;
    }
    if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(ext)) {
      return null;
    }
    return ext;
  }

  Future<void> _downloadFile({
    required String url,
    required String outputPath,
    void Function(int received, int total)? onProgress,
  }) async {
    final token = await _authRepository.getValidToken();
    final normalizedUrl = _normalizeDownloadUrl(url);
    await _apiClient.dio.download(
      normalizedUrl,
      outputPath,
      options: Options(
        headers: token == null || token.isEmpty
            ? null
            : {'Authorization': 'Bearer $token'},
      ),
      onReceiveProgress: onProgress,
    );
  }

  Future<Uint8List> _downloadFileBytes({
    required String url,
    void Function(int received, int total)? onProgress,
  }) async {
    final token = await _authRepository.getValidToken();
    final normalizedUrl = _normalizeDownloadUrl(url);
    final response = await _apiClient.dio.get<List<int>>(
      normalizedUrl,
      options: Options(
        responseType: ResponseType.bytes,
        headers: token == null || token.isEmpty
            ? null
            : {'Authorization': 'Bearer $token'},
      ),
      onReceiveProgress: onProgress,
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  String _normalizeDownloadUrl(String url) {
    final resolved = resolveApiUrl(url);
    final parsed = Uri.tryParse(resolved);
    if (parsed == null || (parsed.hasScheme && parsed.hasAuthority)) {
      return resolved;
    }
    final base = _apiClient.dio.options.baseUrl;
    return Uri.parse(base).resolveUri(parsed).toString();
  }
}
