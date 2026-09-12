import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../../auth/data/auth_repository.dart';
import '../models/backup_archive.dart';

class BackupRepository {
  BackupRepository(this._apiClient, this._authRepository);

  final ApiClient _apiClient;
  final AuthRepository _authRepository;

  List<Map<String, dynamic>> _extractList(
    Map<String, dynamic>? data,
    String key,
  ) {
    return (data?[key] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<List<BackupArchive>> listBackups() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/admin/backup/list',
    );
    final payload =
        response.data?['data'] as Map<String, dynamic>? ?? response.data;
    return _extractList(
      payload,
      'backups',
    ).map(BackupArchive.fromJson).toList();
  }

  Future<BackupArchive> createBackup() async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/admin/backup/create',
    );
    final payload =
        response.data?['data'] as Map<String, dynamic>? ?? response.data;
    return BackupArchive.fromJson(
      payload?['backup'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<void> restoreBackup({
    required String backupFileName,
    required bool confirmRestore,
  }) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/admin/backup/restore',
      data: {
        'backupFileName': backupFileName,
        'confirmRestore': confirmRestore,
      },
    );
  }

  Future<void> restoreBackupFromFile(
    String filePath, {
    Uint8List? fileBytes,
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final resolvedFileName = fileName?.trim().isNotEmpty == true
        ? fileName!.trim()
        : path.basename(filePath);
    final fileSizeBytes = fileBytes?.length ?? await File(filePath).length();
    final formData = FormData.fromMap({
      'backup': fileBytes != null
          ? MultipartFile.fromBytes(fileBytes, filename: resolvedFileName)
          : await MultipartFile.fromFile(filePath, filename: resolvedFileName),
      'confirmRestore': true,
      'backupSizeBytes': fileSizeBytes,
    });
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/admin/backup/restore-upload',
      data: formData,
      options: Options(
        sendTimeout: const Duration(minutes: 30),
        receiveTimeout: const Duration(minutes: 30),
      ),
      onSendProgress: onProgress,
    );
  }

  Future<void> deleteBackup(String backupFileName) async {
    await _apiClient.dio.delete<void>(
      '/api/admin/backup/${Uri.encodeComponent(backupFileName)}',
    );
  }

  Future<String> downloadBackup(
    String backupFileName, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (kIsWeb) {
      final response = await _apiClient.dio.get<List<int>>(
        '/api/admin/backup/${Uri.encodeComponent(backupFileName)}/download',
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: onProgress,
      );
      await web_bridge.downloadBytes(
        bytes: Uint8List.fromList(response.data ?? const <int>[]),
        fileName: backupFileName,
        mimeType: 'application/zip',
      );
      return backupFileName;
    }

    final outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'حفظ النسخة الاحتياطية',
      fileName: backupFileName,
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (outputFile == null) {
      return '';
    }

    await _apiClient.dio.download(
      '/api/admin/backup/${Uri.encodeComponent(backupFileName)}/download',
      outputFile,
      onReceiveProgress: onProgress,
    );
    return outputFile;
  }
}
