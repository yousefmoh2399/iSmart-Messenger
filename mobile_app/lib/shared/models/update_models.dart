class MobileUpdateRelease {
  const MobileUpdateRelease({
    required this.id,
    required this.version,
    required this.channel,
    required this.notes,
    required this.mandatory,
    required this.isEnabled,
    required this.fileName,
    required this.fileSize,
    required this.checksumSha256,
    required this.downloadUrl,
    required this.externalDownloadUrl,
    required this.createdAt,
  });

  final String id;
  final String version;
  final String channel;
  final String notes;
  final bool mandatory;
  final bool isEnabled;
  final String? fileName;
  final int fileSize;
  final String? checksumSha256;
  final String? downloadUrl;
  final String? externalDownloadUrl;
  final DateTime? createdAt;

  factory MobileUpdateRelease.fromJson(Map<String, dynamic> json) {
    return MobileUpdateRelease(
      id: json['id']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      channel: json['channel']?.toString() ?? 'stable',
      notes: json['notes']?.toString() ?? '',
      mandatory: json['mandatory'] == true,
      isEnabled: json['isEnabled'] != false,
      fileName: json['fileName']?.toString(),
      fileSize: json['fileSize'] is int
          ? json['fileSize'] as int
          : int.tryParse(json['fileSize']?.toString() ?? '') ?? 0,
      checksumSha256: json['checksumSha256']?.toString(),
      downloadUrl: json['downloadUrl']?.toString(),
      externalDownloadUrl: json['externalDownloadUrl']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }
}

class MobileUpdateTask {
  const MobileUpdateTask({
    required this.id,
    required this.releaseId,
    required this.releaseVersion,
    required this.status,
    required this.progress,
    required this.message,
    required this.lastError,
    required this.requestedAt,
  });

  final String id;
  final String releaseId;
  final String releaseVersion;
  final String status;
  final int progress;
  final String? message;
  final String? lastError;
  final DateTime? requestedAt;

  factory MobileUpdateTask.fromJson(Map<String, dynamic> json) {
    return MobileUpdateTask(
      id: json['id']?.toString() ?? '',
      releaseId: json['releaseId']?.toString() ?? '',
      releaseVersion: json['releaseVersion']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      progress: json['progress'] is int
          ? json['progress'] as int
          : int.tryParse(json['progress']?.toString() ?? '') ?? 0,
      message: json['message']?.toString(),
      lastError: json['lastError']?.toString(),
      requestedAt: DateTime.tryParse(json['requestedAt']?.toString() ?? ''),
    );
  }
}

class MobileUpdateCheckResponse {
  const MobileUpdateCheckResponse({
    required this.availableRelease,
    required this.currentTask,
    required this.requiresUpdate,
    required this.isMandatory,
  });

  final MobileUpdateRelease? availableRelease;
  final MobileUpdateTask? currentTask;
  final bool requiresUpdate;
  final bool isMandatory;

  factory MobileUpdateCheckResponse.fromJson(Map<String, dynamic> json) {
    final releaseJson = json['release'] as Map<String, dynamic>?;
    final taskJson = json['task'] as Map<String, dynamic>?;
    final taskReleaseJson = taskJson?['release'] as Map<String, dynamic>?;
    Map<String, dynamic>? resolvedReleaseJson = releaseJson;
    final topLevelDownloadUrl = releaseJson?['downloadUrl']?.toString() ?? '';
    if ((resolvedReleaseJson == null || topLevelDownloadUrl.isEmpty) &&
        taskReleaseJson != null) {
      resolvedReleaseJson = taskReleaseJson;
    }

    return MobileUpdateCheckResponse(
      availableRelease: resolvedReleaseJson != null
          ? MobileUpdateRelease.fromJson(resolvedReleaseJson)
          : null,
      currentTask: taskJson != null
          ? MobileUpdateTask.fromJson(taskJson)
          : null,
      requiresUpdate: json['requiresUpdate'] == true,
      isMandatory: json['isMandatory'] == true,
    );
  }
}
