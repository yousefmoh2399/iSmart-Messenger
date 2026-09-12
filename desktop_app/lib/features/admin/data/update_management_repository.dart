import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart';
import '../models/update_management_models.dart';

class UpdateManagementRepository {
  UpdateManagementRepository(this._apiClient, this._authRepository);

  final ApiClient _apiClient;
  final AuthRepository _authRepository;

  String get baseUrl => _apiClient.dio.options.baseUrl;

  Future<String?> getAccessToken() => _authRepository.getToken();

  Map<String, dynamic> _extractData(Map<String, dynamic>? data) {
    return (data?['data'] as Map<String, dynamic>?) ?? (data ?? const {});
  }

  List<Map<String, dynamic>> _extractList(
    Map<String, dynamic> data,
    String key,
  ) {
    return (data[key] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<List<ManagedUpdateDevice>> listDevices({
    String status = 'all',
    String? platform,
    String? branchCode,
    String? search,
    int page = 1,
    int limit = 100,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safeLimit = limit < 1 ? 1 : (limit > 200 ? 200 : limit);
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/admin/updates/devices',
      queryParameters: {
        'status': status,
        'page': safePage,
        'limit': safeLimit,
        if (platform != null && platform.trim().isNotEmpty)
          'platform': platform.trim(),
        if (branchCode != null && branchCode.trim().isNotEmpty)
          'branchCode': branchCode.trim(),
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    final payload = _extractData(response.data);
    return _extractList(
      payload,
      'items',
    ).map(ManagedUpdateDevice.fromJson).toList();
  }

  Future<void> setDeviceActive(String deviceId, bool isActive) async {
    await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/admin/updates/devices/$deviceId/active',
      data: {'isActive': isActive},
    );
  }

  Future<List<ManagedUpdateRelease>> listReleases() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/admin/updates/releases',
    );
    final payload = _extractData(response.data);
    return _extractList(
      payload,
      'releases',
    ).map(ManagedUpdateRelease.fromJson).toList();
  }

  Future<ManagedUpdateRelease> createRelease({
    required String version,
    required String channel,
    String platform = 'desktop_windows',
    String? buildNumber,
    String notes = '',
    bool mandatory = false,
    bool isEnabled = true,
    String packageType = 'full',
    String packageLayout = 'bundle_zip',
    String entryExecutable = 'iSmartMessenger.exe',
    String? minSupportedVersion,
    String targetArchitecture = 'x64',
    String? minWindowsBuild,
    int rolloutPercentage = 100,
    String silentInstallArgs = '',
    String? externalDownloadUrl,
    String? artifactFilePath,
    Uint8List? artifactBytes,
    String? artifactFileName,
    Function(int, int)? onUploadProgress,
  }) async {
    final resolvedArtifactName = artifactFileName?.trim().isNotEmpty == true
        ? artifactFileName!.trim()
        : (artifactFilePath == null ? null : path.basename(artifactFilePath));
    final formData = FormData.fromMap({
      'version': version.trim(),
      if (buildNumber != null && buildNumber.trim().isNotEmpty)
        'buildNumber': buildNumber.trim(),
      'channel': channel.trim(),
      'platform': platform.trim(),
      'notes': notes.trim(),
      'mandatory': mandatory,
      'isEnabled': isEnabled,
      'packageType': packageType.trim(),
      'packageLayout': packageLayout.trim(),
      'entryExecutable': entryExecutable.trim(),
      if (minSupportedVersion != null && minSupportedVersion.trim().isNotEmpty)
        'minSupportedVersion': minSupportedVersion.trim(),
      'targetArchitecture': targetArchitecture.trim(),
      if (minWindowsBuild != null && minWindowsBuild.trim().isNotEmpty)
        'minWindowsBuild': minWindowsBuild.trim(),
      'rolloutPercentage': rolloutPercentage,
      'silentInstallArgs': silentInstallArgs.trim(),
      if (externalDownloadUrl != null && externalDownloadUrl.trim().isNotEmpty)
        'externalDownloadUrl': externalDownloadUrl.trim(),
      if (artifactBytes != null && resolvedArtifactName != null)
        'artifact': MultipartFile.fromBytes(
          artifactBytes,
          filename: resolvedArtifactName,
        )
      else if (artifactFilePath != null && artifactFilePath.trim().isNotEmpty)
        'artifact': await MultipartFile.fromFile(
          artifactFilePath,
          filename: resolvedArtifactName,
        ),
    });

    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/admin/updates/releases',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
      onSendProgress: onUploadProgress,
    );
    final payload = _extractData(response.data);
    return ManagedUpdateRelease.fromJson(
      payload['release'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<ManagedUpdateRelease> updateRelease({
    required String releaseId,
    bool? isEnabled,
    bool? mandatory,
    String? notes,
    String? silentInstallArgs,
    String? channel,
    String? buildNumber,
    String? packageType,
    String? packageLayout,
    String? entryExecutable,
    String? minSupportedVersion,
    String? targetArchitecture,
    String? minWindowsBuild,
    int? rolloutPercentage,
  }) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/api/admin/updates/releases/$releaseId',
      data: {
        if (isEnabled != null) 'isEnabled': isEnabled,
        if (mandatory != null) 'mandatory': mandatory,
        if (notes != null) 'notes': notes,
        if (silentInstallArgs != null) 'silentInstallArgs': silentInstallArgs,
        if (channel != null) 'channel': channel,
        if (buildNumber != null) 'buildNumber': buildNumber,
        if (packageType != null) 'packageType': packageType,
        if (packageLayout != null) 'packageLayout': packageLayout,
        if (entryExecutable != null) 'entryExecutable': entryExecutable,
        if (minSupportedVersion != null)
          'minSupportedVersion': minSupportedVersion,
        if (targetArchitecture != null)
          'targetArchitecture': targetArchitecture,
        if (minWindowsBuild != null) 'minWindowsBuild': minWindowsBuild,
        if (rolloutPercentage != null) 'rolloutPercentage': rolloutPercentage,
      },
    );
    final payload = _extractData(response.data);
    return ManagedUpdateRelease.fromJson(
      payload['release'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<void> deleteRelease(String releaseId) async {
    await _apiClient.dio.delete<void>('/api/admin/updates/releases/$releaseId');
  }

  Future<ManagedUpdateJob> createUpdateJob({
    required String releaseId,
    required String targetType,
    List<String> targetBranches = const [],
    List<String> targetDeviceIds = const [],
    List<String> excludeDeviceUids = const [],
    String note = '',
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/admin/updates/jobs',
      data: {
        'releaseId': releaseId,
        'targetType': targetType,
        if (targetBranches.isNotEmpty) 'targetBranches': targetBranches,
        if (targetDeviceIds.isNotEmpty) 'targetDeviceIds': targetDeviceIds,
        if (excludeDeviceUids.isNotEmpty)
          'excludeDeviceUids': excludeDeviceUids,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    final payload = _extractData(response.data);
    return ManagedUpdateJob.fromJson(
      payload['job'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<List<ManagedUpdateJob>> listUpdateJobs({
    int page = 1,
    int limit = 100,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/admin/updates/jobs',
      queryParameters: {'page': page, 'limit': limit},
    );
    final payload = _extractData(response.data);
    return _extractList(
      payload,
      'items',
    ).map(ManagedUpdateJob.fromJson).toList();
  }

  Future<void> cancelUpdateJob(String jobId) async {
    await _apiClient.dio.post<void>('/api/admin/updates/jobs/$jobId/cancel');
  }

  Future<DeviceHeartbeatResponse> heartbeatDevice({
    required String deviceUid,
    required String deviceName,
    required String hostName,
    String? localIp,
    required String branchCode,
    required String channel,
    required String appVersion,
    required String osName,
    required String osVersion,
    required String architecture,
    required String connectionStatus,
    required bool autoUpdateEnabled,
    required bool silentInstallEnabled,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/updates/devices/heartbeat',
      data: {
        'deviceUid': deviceUid,
        'deviceName': deviceName,
        'hostName': hostName,
        if (localIp != null && localIp.trim().isNotEmpty)
          'localIp': localIp.trim(),
        'branchCode': branchCode,
        'channel': channel,
        'appVersion': appVersion,
        'osName': osName,
        'osVersion': osVersion,
        'architecture': architecture,
        'connectionStatus': connectionStatus,
        'capabilities': {
          'autoUpdate': autoUpdateEnabled,
          'silentInstall': silentInstallEnabled,
        },
      },
      options: Options(
        extra: {'requestSource': 'updateCheck.manualOrSocketEvent'},
      ),
    );
    final payload = _extractData(response.data);
    return DeviceHeartbeatResponse.fromJson(payload);
  }

  Future<void> reportTaskProgress({
    required String taskId,
    required String deviceUid,
    required String status,
    int? progress,
    String? message,
    String? connectionStatus,
  }) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/updates/tasks/$taskId/progress',
      data: {
        'deviceUid': deviceUid,
        'status': status,
        if (progress != null) 'progress': progress,
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
        if (connectionStatus != null) 'connectionStatus': connectionStatus,
      },
      options: Options(
        extra: {
          'requestSource': 'update.progressTelemetry',
          'skipErrorLog': true,
        },
      ),
    );
  }

  Future<List<BranchPeerDevice>> listBranchPeerDevices({
    String? branchCode,
    String? userId,
    bool includeSelf = false,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/updates/branch-peers',
      queryParameters: {
        if (branchCode != null && branchCode.trim().isNotEmpty)
          'branchCode': branchCode.trim(),
        if (userId != null && userId.trim().isNotEmpty) 'userId': userId.trim(),
        'includeSelf': includeSelf.toString(),
      },
    );
    final payload = _extractData(response.data);
    return _extractList(
      payload,
      'peers',
    ).map(BranchPeerDevice.fromJson).toList();
  }

  Future<String> downloadReleaseArtifact({
    required String releaseId,
    required String fileName,
    String? downloadUrl,
    String? destinationDirectory,
    void Function(int received, int total)? onReceiveProgress,
    int maxAttempts = 3,
  }) async {
    final directory = destinationDirectory == null
        ? await _defaultArtifactDirectory()
        : Directory(destinationDirectory);
    await directory.create(recursive: true);
    final safeFileName = fileName.trim().isEmpty ? 'artifact.bin' : fileName;
    final destination = path.join(directory.path, '$releaseId-$safeFileName');
    final partialDestination = '$destination.part';
    final resolvedUrl = (downloadUrl ?? '').trim();
    final target = resolvedUrl.isNotEmpty
        ? resolvedUrl
        : '/api/updates/releases/$releaseId/download';
    final targetUri = _resolveDownloadUri(target);
    final token = await getAccessToken();

    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      HttpClient? client;
      RandomAccessFile? sink;
      try {
        final existingBytes = await _existingFileLength(partialDestination);
        client = HttpClient()
          ..connectionTimeout = const Duration(minutes: 5)
          ..idleTimeout = const Duration(minutes: 5);
        final request = await client
            .getUrl(targetUri)
            .timeout(const Duration(minutes: 5));
        if (token != null && token.trim().isNotEmpty) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
        if (existingBytes > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
        }

        final response = await request.close().timeout(
          const Duration(minutes: 10),
        );
        if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
            existingBytes > 0) {
          await response.drain<void>();
          final partialFile = File(partialDestination);
          if (partialFile.existsSync()) {
            await partialFile.delete();
          }
          if (attempt < maxAttempts) {
            continue;
          }
          throw HttpException(
            'Server rejected resumed download with status 416.',
            uri: targetUri,
          );
        }
        if (response.statusCode != HttpStatus.ok &&
            response.statusCode != HttpStatus.partialContent) {
          throw HttpException(
            'Unexpected status code ${response.statusCode}',
            uri: targetUri,
          );
        }

        final canAppend =
            existingBytes > 0 &&
            response.statusCode == HttpStatus.partialContent;
        final partialFile = File(partialDestination);
        sink = await partialFile.open(
          mode: canAppend ? FileMode.append : FileMode.write,
        );

        final totalBytes = _resolveExpectedLength(
          response,
          initialBytes: canAppend ? existingBytes : 0,
        );
        if (totalBytes <= 0 && existingBytes == 0) {
          throw Exception('Unable to determine file size from server');
        }
        var receivedBytes = canAppend ? existingBytes : 0;
        onReceiveProgress?.call(receivedBytes, totalBytes);

        await for (final chunk in response) {
          await sink.writeFrom(chunk);
          receivedBytes += chunk.length;
          onReceiveProgress?.call(receivedBytes, totalBytes);
        }
        await sink.close();
        sink = null;

        final finalFile = File(destination);
        if (finalFile.existsSync()) {
          await finalFile.delete();
        }
        await partialFile.rename(destination);
        return destination;
      } catch (error) {
        lastError = error;
        if (attempt >= maxAttempts) {
          break;
        }
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      } finally {
        await sink?.close();
        client?.close(force: true);
      }
    }

    throw Exception('Failed to download release artifact: $lastError');
  }

  Future<Directory> _defaultArtifactDirectory() async {
    final tempDir = await getTemporaryDirectory();
    return Directory(path.join(tempDir.path, 'update-artifacts'));
  }

  Uri _resolveDownloadUri(String target) {
    final trimmed = target.trim();
    final asUri = Uri.parse(trimmed);
    if (asUri.hasScheme) {
      return asUri;
    }
    final baseUri = Uri.parse(baseUrl);
    return baseUri.resolve(trimmed);
  }

  Future<int> _existingFileLength(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return 0;
    }
    return file.length();
  }

  int _resolveExpectedLength(
    HttpClientResponse response, {
    required int initialBytes,
  }) {
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null && contentRange.contains('/')) {
      final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
      final total = int.tryParse(match?.group(1) ?? '');
      if (total != null && total > 0) {
        return total;
      }
    }
    final length = response.contentLength;
    if (length > 0) {
      return initialBytes + length;
    }
    return initialBytes;
  }
}
