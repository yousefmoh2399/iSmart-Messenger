import '../../../core/network/ip_address_utils.dart';

class ManagedUpdateRelease {
  const ManagedUpdateRelease({
    required this.id,
    required this.version,
    required this.buildNumber,
    required this.channel,
    required this.platform,
    required this.notes,
    required this.mandatory,
    required this.isEnabled,
    required this.installerKind,
    required this.packageType,
    required this.packageLayout,
    required this.entryExecutable,
    required this.minSupportedVersion,
    required this.targetArchitecture,
    required this.minWindowsBuild,
    required this.rolloutPercentage,
    required this.silentInstallArgs,
    required this.checksumSha256,
    required this.fileName,
    required this.fileSize,
    required this.downloadPath,
    required this.downloadUrl,
    required this.externalDownloadUrl,
    required this.createdAt,
  });

  final String id;
  final String version;
  final String? buildNumber;
  final String channel;
  final String platform;
  final String notes;
  final bool mandatory;
  final bool isEnabled;
  final String installerKind;
  final String packageType;
  final String packageLayout;
  final String entryExecutable;
  final String? minSupportedVersion;
  final String targetArchitecture;
  final String? minWindowsBuild;
  final int rolloutPercentage;
  final String silentInstallArgs;
  final String? checksumSha256;
  final String? fileName;
  final int fileSize;
  final String? downloadPath;
  final String? downloadUrl;
  final String? externalDownloadUrl;
  final DateTime? createdAt;

  factory ManagedUpdateRelease.fromJson(Map<String, dynamic> json) {
    return ManagedUpdateRelease(
      id: json['id']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      buildNumber: json['buildNumber']?.toString(),
      channel: json['channel']?.toString() ?? 'stable',
      platform: json['platform']?.toString() ?? 'desktop_windows',
      notes: json['notes']?.toString() ?? '',
      mandatory: json['mandatory'] == true,
      isEnabled: json['isEnabled'] != false,
      installerKind: json['installerKind']?.toString() ?? 'unknown',
      packageType: json['packageType']?.toString() ?? 'full',
      packageLayout: json['packageLayout']?.toString() ?? 'bundle_zip',
      entryExecutable:
          json['entryExecutable']?.toString() ?? 'iSmartMessenger.exe',
      minSupportedVersion: json['minSupportedVersion']?.toString(),
      targetArchitecture: json['targetArchitecture']?.toString() ?? 'x64',
      minWindowsBuild: json['minWindowsBuild']?.toString(),
      rolloutPercentage: json['rolloutPercentage'] is int
          ? json['rolloutPercentage'] as int
          : int.tryParse(json['rolloutPercentage']?.toString() ?? '') ?? 100,
      silentInstallArgs: json['silentInstallArgs']?.toString() ?? '',
      checksumSha256: json['checksumSha256']?.toString(),
      fileName: json['fileName']?.toString(),
      fileSize: json['fileSize'] is int
          ? json['fileSize'] as int
          : int.tryParse(json['fileSize']?.toString() ?? '') ?? 0,
      downloadPath: json['downloadPath']?.toString(),
      downloadUrl: json['downloadUrl']?.toString(),
      externalDownloadUrl: json['externalDownloadUrl']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }
}

class ManagedUpdateDevice {
  const ManagedUpdateDevice({
    required this.id,
    required this.deviceUid,
    required this.deviceName,
    required this.hostName,
    required this.localIp,
    required this.branchCode,
    required this.channel,
    required this.platform,
    required this.appVersion,
    required this.connectionStatus,
    required this.isOnline,
    required this.isActive,
    required this.lastKnownUsername,
    required this.lastKnownFullName,
    required this.lastHeartbeatAt,
    required this.updateStatus,
    required this.updateTargetVersion,
    required this.updateProgress,
    required this.updateError,
  });

  final String id;
  final String deviceUid;
  final String? deviceName;
  final String? hostName;
  final String? localIp;
  final String branchCode;
  final String channel;
  final String platform;
  final String appVersion;
  final String connectionStatus;
  final bool isOnline;
  final bool isActive;
  final String? lastKnownUsername;
  final String? lastKnownFullName;
  final DateTime? lastHeartbeatAt;
  final String updateStatus;
  final String? updateTargetVersion;
  final int updateProgress;
  final String? updateError;

  factory ManagedUpdateDevice.fromJson(Map<String, dynamic> json) {
    final updateState = json['updateState'] is Map<String, dynamic>
        ? json['updateState'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return ManagedUpdateDevice(
      id: json['id']?.toString() ?? '',
      deviceUid: json['deviceUid']?.toString() ?? '',
      deviceName: json['deviceName']?.toString(),
      hostName: json['hostName']?.toString(),
      localIp: normalizeIpAddress(json['localIp']?.toString()),
      branchCode: json['branchCode']?.toString() ?? 'main',
      channel: json['channel']?.toString() ?? 'stable',
      platform: json['platform']?.toString() ?? 'desktop_windows',
      appVersion: json['appVersion']?.toString() ?? 'unknown',
      connectionStatus: json['connectionStatus']?.toString() ?? 'offline',
      isOnline: json['isOnline'] == true,
      isActive: json['isActive'] != false,
      lastKnownUsername: json['lastKnownUsername']?.toString(),
      lastKnownFullName: json['lastKnownFullName']?.toString(),
      lastHeartbeatAt: DateTime.tryParse(
        json['lastHeartbeatAt']?.toString() ?? '',
      ),
      updateStatus: updateState['status']?.toString() ?? 'idle',
      updateTargetVersion: updateState['targetVersion']?.toString(),
      updateProgress: updateState['progress'] is int
          ? updateState['progress'] as int
          : int.tryParse(updateState['progress']?.toString() ?? '') ?? 0,
      updateError: updateState['lastError']?.toString(),
    );
  }
}

class BranchPeerDevice {
  const BranchPeerDevice({
    required this.id,
    required this.deviceUid,
    required this.deviceName,
    required this.hostName,
    required this.localIp,
    required this.branchCode,
    required this.appVersion,
    required this.connectionStatus,
    required this.lastKnownUserId,
    required this.lastKnownUsername,
    required this.lastKnownFullName,
    required this.lastHeartbeatAt,
  });

  final String id;
  final String deviceUid;
  final String? deviceName;
  final String? hostName;
  final String? localIp;
  final String branchCode;
  final String appVersion;
  final String connectionStatus;
  final String? lastKnownUserId;
  final String? lastKnownUsername;
  final String? lastKnownFullName;
  final DateTime? lastHeartbeatAt;

  String get displayLabel {
    final userLabel = (lastKnownFullName?.trim().isNotEmpty ?? false)
        ? lastKnownFullName!.trim()
        : (lastKnownUsername?.trim().isNotEmpty ?? false)
        ? lastKnownUsername!.trim()
        : 'جهاز';
    final machineLabel = (deviceName?.trim().isNotEmpty ?? false)
        ? deviceName!.trim()
        : (hostName?.trim().isNotEmpty ?? false)
        ? hostName!.trim()
        : deviceUid;
    final normalizedIp = normalizeIpAddress(localIp);
    final ipLabel = normalizedIp.isNotEmpty ? normalizedIp : 'بدون IP';
    return '$userLabel • $machineLabel • $ipLabel';
  }

  factory BranchPeerDevice.fromJson(Map<String, dynamic> json) {
    return BranchPeerDevice(
      id: json['id']?.toString() ?? '',
      deviceUid: json['deviceUid']?.toString() ?? '',
      deviceName: json['deviceName']?.toString(),
      hostName: json['hostName']?.toString(),
      localIp: normalizeIpAddress(json['localIp']?.toString()),
      branchCode: json['branchCode']?.toString() ?? 'main',
      appVersion: json['appVersion']?.toString() ?? 'unknown',
      connectionStatus: json['connectionStatus']?.toString() ?? 'online',
      lastKnownUserId: json['lastKnownUserId']?.toString(),
      lastKnownUsername: json['lastKnownUsername']?.toString(),
      lastKnownFullName: json['lastKnownFullName']?.toString(),
      lastHeartbeatAt: DateTime.tryParse(
        json['lastHeartbeatAt']?.toString() ?? '',
      ),
    );
  }
}

class ManagedUpdateJob {
  const ManagedUpdateJob({
    required this.id,
    required this.releaseId,
    required this.releaseVersion,
    required this.platform,
    required this.targetType,
    required this.status,
    required this.total,
    required this.pending,
    required this.acknowledged,
    required this.downloading,
    required this.installing,
    required this.completed,
    required this.failed,
    required this.cancelled,
    required this.createdAt,
  });

  final String id;
  final String? releaseId;
  final String releaseVersion;
  final String platform;
  final String targetType;
  final String status;
  final int total;
  final int pending;
  final int acknowledged;
  final int downloading;
  final int installing;
  final int completed;
  final int failed;
  final int cancelled;
  final DateTime? createdAt;

  factory ManagedUpdateJob.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] is Map<String, dynamic>
        ? json['stats'] as Map<String, dynamic>
        : const <String, dynamic>{};
    int readInt(String key) {
      if (stats[key] is int) return stats[key] as int;
      return int.tryParse(stats[key]?.toString() ?? '') ?? 0;
    }

    return ManagedUpdateJob(
      id: json['id']?.toString() ?? '',
      releaseId: json['releaseId']?.toString(),
      releaseVersion: json['releaseVersion']?.toString() ?? '',
      platform: json['platform']?.toString() ?? 'desktop_windows',
      targetType: json['targetType']?.toString() ?? 'all',
      status: json['status']?.toString() ?? 'queued',
      total: readInt('total'),
      pending: readInt('pending'),
      acknowledged: readInt('acknowledged'),
      downloading: readInt('downloading'),
      installing: readInt('installing'),
      completed: readInt('completed'),
      failed: readInt('failed'),
      cancelled: readInt('cancelled'),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }
}

class DeviceHeartbeatResponse {
  const DeviceHeartbeatResponse({
    required this.pendingTasks,
    required this.heartbeatIntervalSeconds,
  });

  final List<PendingUpdateTask> pendingTasks;
  final int heartbeatIntervalSeconds;

  factory DeviceHeartbeatResponse.fromJson(Map<String, dynamic> json) {
    final tasks = (json['pendingTasks'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(PendingUpdateTask.fromJson)
        .toList();
    return DeviceHeartbeatResponse(
      pendingTasks: tasks,
      heartbeatIntervalSeconds: json['heartbeatIntervalSeconds'] is int
          ? json['heartbeatIntervalSeconds'] as int
          : int.tryParse(json['heartbeatIntervalSeconds']?.toString() ?? '') ??
                30,
    );
  }
}

class PendingUpdateTask {
  const PendingUpdateTask({
    required this.id,
    required this.status,
    required this.progress,
    required this.releaseVersion,
    required this.release,
  });

  final String id;
  final String status;
  final int progress;
  final String releaseVersion;
  final ManagedUpdateRelease release;

  factory PendingUpdateTask.fromJson(Map<String, dynamic> json) {
    return PendingUpdateTask(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      progress: json['progress'] is int
          ? json['progress'] as int
          : int.tryParse(json['progress']?.toString() ?? '') ?? 0,
      releaseVersion: json['releaseVersion']?.toString() ?? '',
      release: ManagedUpdateRelease.fromJson(
        json['release'] is Map<String, dynamic>
            ? json['release'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
    );
  }
}
