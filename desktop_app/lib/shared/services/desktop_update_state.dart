class DesktopUpdateState {
  const DesktopUpdateState({
    required this.status,
    this.taskId,
    this.releaseId,
    this.targetVersion,
    this.artifactPath,
    this.artifactSha256,
    this.packageType,
    this.installerKind,
    this.packageLayout,
    this.entryExecutable,
    this.silentInstallArgs,
    this.fileName,
    this.lastError,
    this.lastKnownVersion,
    this.attemptCount = 0,
    this.updatedAt,
  });

  final String status;
  final String? taskId;
  final String? releaseId;
  final String? targetVersion;
  final String? artifactPath;
  final String? artifactSha256;
  final String? packageType;
  final String? installerKind;
  final String? packageLayout;
  final String? entryExecutable;
  final String? silentInstallArgs;
  final String? fileName;
  final String? lastError;
  final String? lastKnownVersion;
  final int attemptCount;
  final DateTime? updatedAt;

  bool get isTerminal => switch (status) {
    'completed' || 'failed' || 'rolled_back' => true,
    _ => false,
  };

  DesktopUpdateState copyWith({
    String? status,
    String? taskId,
    bool clearTaskId = false,
    String? releaseId,
    bool clearReleaseId = false,
    String? targetVersion,
    bool clearTargetVersion = false,
    String? artifactPath,
    bool clearArtifactPath = false,
    String? artifactSha256,
    bool clearArtifactSha256 = false,
    String? packageType,
    bool clearPackageType = false,
    String? installerKind,
    bool clearInstallerKind = false,
    String? packageLayout,
    bool clearPackageLayout = false,
    String? entryExecutable,
    bool clearEntryExecutable = false,
    String? silentInstallArgs,
    bool clearSilentInstallArgs = false,
    String? fileName,
    bool clearFileName = false,
    String? lastError,
    bool clearLastError = false,
    String? lastKnownVersion,
    bool clearLastKnownVersion = false,
    int? attemptCount,
    DateTime? updatedAt,
  }) {
    return DesktopUpdateState(
      status: status ?? this.status,
      taskId: clearTaskId ? null : (taskId ?? this.taskId),
      releaseId: clearReleaseId ? null : (releaseId ?? this.releaseId),
      targetVersion: clearTargetVersion
          ? null
          : (targetVersion ?? this.targetVersion),
      artifactPath: clearArtifactPath
          ? null
          : (artifactPath ?? this.artifactPath),
      artifactSha256: clearArtifactSha256
          ? null
          : (artifactSha256 ?? this.artifactSha256),
      packageType: clearPackageType ? null : (packageType ?? this.packageType),
      installerKind: clearInstallerKind
          ? null
          : (installerKind ?? this.installerKind),
      packageLayout: clearPackageLayout
          ? null
          : (packageLayout ?? this.packageLayout),
      entryExecutable: clearEntryExecutable
          ? null
          : (entryExecutable ?? this.entryExecutable),
      silentInstallArgs: clearSilentInstallArgs
          ? null
          : (silentInstallArgs ?? this.silentInstallArgs),
      fileName: clearFileName ? null : (fileName ?? this.fileName),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      lastKnownVersion: clearLastKnownVersion
          ? null
          : (lastKnownVersion ?? this.lastKnownVersion),
      attemptCount: attemptCount ?? this.attemptCount,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'taskId': taskId,
      'releaseId': releaseId,
      'targetVersion': targetVersion,
      'artifactPath': artifactPath,
      'artifactSha256': artifactSha256,
      'packageType': packageType,
      'installerKind': installerKind,
      'packageLayout': packageLayout,
      'entryExecutable': entryExecutable,
      'silentInstallArgs': silentInstallArgs,
      'fileName': fileName,
      'lastError': lastError,
      'lastKnownVersion': lastKnownVersion,
      'attemptCount': attemptCount,
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory DesktopUpdateState.fromJson(Map<String, dynamic> json) {
    return DesktopUpdateState(
      status: json['status']?.toString() ?? 'idle',
      taskId: json['taskId']?.toString(),
      releaseId: json['releaseId']?.toString(),
      targetVersion: json['targetVersion']?.toString(),
      artifactPath: json['artifactPath']?.toString(),
      artifactSha256: json['artifactSha256']?.toString(),
      packageType: json['packageType']?.toString(),
      installerKind: json['installerKind']?.toString(),
      packageLayout: json['packageLayout']?.toString(),
      entryExecutable: json['entryExecutable']?.toString(),
      silentInstallArgs: json['silentInstallArgs']?.toString(),
      fileName: json['fileName']?.toString(),
      lastError: json['lastError']?.toString(),
      lastKnownVersion: json['lastKnownVersion']?.toString(),
      attemptCount: json['attemptCount'] is int
          ? json['attemptCount'] as int
          : int.tryParse(json['attemptCount']?.toString() ?? '') ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  factory DesktopUpdateState.idle() => const DesktopUpdateState(status: 'idle');
}
