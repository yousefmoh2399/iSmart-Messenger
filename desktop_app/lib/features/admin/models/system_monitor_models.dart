class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.ipAddress,
    required this.clientType,
    required this.deviceInfo,
    required this.isOnline,
    required this.lastSeenAt,
    required this.startedAt,
    this.jobTitleBranch,
    this.department,
  });

  final String id;
  final String userId;
  final String username;
  final String fullName;
  final String? avatarUrl;
  final String? ipAddress;
  final String clientType;
  final Map<String, dynamic> deviceInfo;
  final bool isOnline;
  final DateTime lastSeenAt;
  final DateTime startedAt;
  final String? jobTitleBranch;
  final String? department;

  factory DeviceSession.fromJson(Map<String, dynamic> json) {
    final user = json['userId'] is Map<String, dynamic>
        ? json['userId'] as Map<String, dynamic>
        : <String, dynamic>{};
    return DeviceSession(
      id: json['_id'] as String,
      userId: user['_id'] as String? ?? '',
      username: user['username'] as String? ?? 'Unknown',
      fullName: user['fullName'] as String? ?? 'مستخدم غير معروف',
      avatarUrl: user['avatarUrl'] as String?,
      ipAddress: json['ipAddress'] as String?,
      clientType: json['clientType'] as String? ?? 'unknown',
      deviceInfo: json['deviceInfo'] as Map<String, dynamic>? ?? {},
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeenAt: json['lastSeenAt'] != null
          ? DateTime.parse(json['lastSeenAt'].toString())
          : DateTime.now(),
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'].toString())
          : DateTime.now(),
      jobTitleBranch: user['jobTitleBranch'] as String?,
      department: user['department'] as String?,
    );
  }
}

class ClientErrorLog {
  const ClientErrorLog({
    required this.id,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.sessionId,
    required this.ipAddress,
    required this.deviceInfo,
    required this.clientType,
    required this.source,
    required this.errorMessage,
    required this.errorContext,
    required this.stackTrace,
    required this.resolved,
    required this.createdAt,
    this.jobTitleBranch,
  });

  final String id;
  final String? userId;
  final String? username;
  final String? fullName;
  final String? sessionId;
  final String? ipAddress;
  final Map<String, dynamic>? deviceInfo;
  final String clientType;
  final String source;
  final String errorMessage;
  final Map<String, dynamic> errorContext;
  final String? stackTrace;
  final bool resolved;
  final DateTime createdAt;
  final String? jobTitleBranch;

  factory ClientErrorLog.fromJson(Map<String, dynamic> json) {
    final user = json['userId'] is Map<String, dynamic>
        ? json['userId'] as Map<String, dynamic>
        : null;
    final session = json['sessionId'] is Map<String, dynamic>
        ? json['sessionId'] as Map<String, dynamic>
        : null;

    return ClientErrorLog(
      id: json['_id'] as String,
      userId: user?['_id'] as String?,
      username: user?['username'] as String?,
      fullName: user?['fullName'] as String?,
      sessionId: session?['_id'] as String?,
      ipAddress: session?['ipAddress'] as String?,
      deviceInfo: session?['deviceInfo'] as Map<String, dynamic>?,
      clientType: json['clientType'] as String? ?? 'unknown',
      source: json['source'] as String? ?? 'app',
      errorMessage: json['errorMessage'] as String? ?? 'Unknown Error',
      errorContext: json['errorContext'] as Map<String, dynamic>? ?? {},
      stackTrace: json['stackTrace'] as String?,
      resolved: json['resolved'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'].toString())
          : DateTime.now(),
      jobTitleBranch: user?['jobTitleBranch'] as String?,
    );
  }
}

class SystemTelemetryStats {
  const SystemTelemetryStats({
    required this.uptimeSeconds,
    required this.systemUptimeSeconds,
    required this.nodeVersion,
    required this.platform,
    required this.osType,
    required this.osRelease,
    required this.hostname,
    required this.cpuModel,
    required this.cpuCores,
    required this.cpuLoadAvg,
    required this.totalMemoryBytes,
    required this.usedMemoryBytes,
    required this.freeMemoryBytes,
    required this.memoryUsagePercent,
    required this.processHeapUsedBytes,
    required this.processHeapTotalBytes,
    required this.processRssBytes,
    required this.databaseStatus,
    required this.databaseName,
    required this.databaseHost,
    required this.liveSocketsCount,
    required this.liveUsersCount,
    required this.totalUsers,
    required this.totalSessions,
    required this.unresolvedErrors,
    required this.totalErrors,
    required this.desktopClientsCount,
    required this.mobileClientsCount,
    required this.webClientsCount,
  });

  final int uptimeSeconds;
  final int systemUptimeSeconds;
  final String nodeVersion;
  final String platform;
  final String osType;
  final String osRelease;
  final String hostname;
  final String cpuModel;
  final int cpuCores;
  final List<double> cpuLoadAvg;
  final int totalMemoryBytes;
  final int usedMemoryBytes;
  final int freeMemoryBytes;
  final int memoryUsagePercent;
  final int processHeapUsedBytes;
  final int processHeapTotalBytes;
  final int processRssBytes;
  final String databaseStatus;
  final String databaseName;
  final String databaseHost;
  final int liveSocketsCount;
  final int liveUsersCount;
  final int totalUsers;
  final int totalSessions;
  final int unresolvedErrors;
  final int totalErrors;
  final int desktopClientsCount;
  final int mobileClientsCount;
  final int webClientsCount;

  factory SystemTelemetryStats.fromJson(Map<String, dynamic> json) {
    final cpu = json['cpu'] as Map<String, dynamic>? ?? {};
    final mem = json['memory'] as Map<String, dynamic>? ?? {};
    final db = json['database'] as Map<String, dynamic>? ?? {};
    final sockets = json['sockets'] as Map<String, dynamic>? ?? {};
    final summary = json['summary'] as Map<String, dynamic>? ?? {};
    final activeClients =
        summary['activeClients'] as Map<String, dynamic>? ?? {};

    final loadAvgList = (cpu['loadAvg'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [];

    return SystemTelemetryStats(
      uptimeSeconds: (json['uptimeSeconds'] as num?)?.toInt() ?? 0,
      systemUptimeSeconds: (json['systemUptimeSeconds'] as num?)?.toInt() ?? 0,
      nodeVersion: json['nodeVersion'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      osType: json['osType'] as String? ?? '',
      osRelease: json['osRelease'] as String? ?? '',
      hostname: json['hostname'] as String? ?? '',
      cpuModel: cpu['model'] as String? ?? '',
      cpuCores: (cpu['cores'] as num?)?.toInt() ?? 1,
      cpuLoadAvg: loadAvgList,
      totalMemoryBytes: (mem['totalBytes'] as num?)?.toInt() ?? 0,
      usedMemoryBytes: (mem['usedBytes'] as num?)?.toInt() ?? 0,
      freeMemoryBytes: (mem['freeBytes'] as num?)?.toInt() ?? 0,
      memoryUsagePercent: (mem['usagePercent'] as num?)?.toInt() ?? 0,
      processHeapUsedBytes: (mem['processHeapUsed'] as num?)?.toInt() ?? 0,
      processHeapTotalBytes: (mem['processHeapTotal'] as num?)?.toInt() ?? 0,
      processRssBytes: (mem['processRss'] as num?)?.toInt() ?? 0,
      databaseStatus: db['status'] as String? ?? 'disconnected',
      databaseName: db['name'] as String? ?? '',
      databaseHost: db['host'] as String? ?? '',
      liveSocketsCount: (sockets['liveSocketsCount'] as num?)?.toInt() ?? 0,
      liveUsersCount: (sockets['liveUsersCount'] as num?)?.toInt() ?? 0,
      totalUsers: (summary['totalUsers'] as num?)?.toInt() ?? 0,
      totalSessions: (summary['totalSessions'] as num?)?.toInt() ?? 0,
      unresolvedErrors: (summary['unresolvedErrors'] as num?)?.toInt() ?? 0,
      totalErrors: (summary['totalErrors'] as num?)?.toInt() ?? 0,
      desktopClientsCount: (activeClients['desktop'] as num?)?.toInt() ?? 0,
      mobileClientsCount: (activeClients['mobile'] as num?)?.toInt() ?? 0,
      webClientsCount: (activeClients['web'] as num?)?.toInt() ?? 0,
    );
  }
}

class PaginatedResponse<T> {
  const PaginatedResponse({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
  });

  final List<T> items;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;
}

class BranchDeploymentSummary {
  const BranchDeploymentSummary({
    required this.totalBranches,
    required this.installedBranchesCount,
    required this.notInstalledBranchesCount,
    required this.adoptionPercentage,
    required this.totalInstalledDevices,
    required this.totalOnlineDevices,
    required this.currentAppVersion,
    required this.versionBreakdown,
    required this.platformBreakdown,
    required this.calculatedAt,
  });

  final int totalBranches;
  final int installedBranchesCount;
  final int notInstalledBranchesCount;
  final int adoptionPercentage;
  final int totalInstalledDevices;
  final int totalOnlineDevices;
  final String currentAppVersion;
  final Map<String, int> versionBreakdown;
  final Map<String, int> platformBreakdown;
  final DateTime calculatedAt;

  factory BranchDeploymentSummary.fromJson(Map<String, dynamic> json) {
    final vMap = <String, int>{};
    if (json['versionBreakdown'] is Map) {
      (json['versionBreakdown'] as Map).forEach((k, v) {
        vMap[k.toString()] = (v as num).toInt();
      });
    }
    final pMap = <String, int>{};
    if (json['platformBreakdown'] is Map) {
      (json['platformBreakdown'] as Map).forEach((k, v) {
        pMap[k.toString()] = (v as num).toInt();
      });
    }

    return BranchDeploymentSummary(
      totalBranches: (json['totalBranches'] as num?)?.toInt() ?? 0,
      installedBranchesCount: (json['installedBranchesCount'] as num?)?.toInt() ?? 0,
      notInstalledBranchesCount: (json['notInstalledBranchesCount'] as num?)?.toInt() ?? 0,
      adoptionPercentage: (json['adoptionPercentage'] as num?)?.toInt() ?? 0,
      totalInstalledDevices: (json['totalInstalledDevices'] as num?)?.toInt() ?? 0,
      totalOnlineDevices: (json['totalOnlineDevices'] as num?)?.toInt() ?? 0,
      currentAppVersion: json['currentAppVersion'] as String? ?? '1.1.21',
      versionBreakdown: vMap,
      platformBreakdown: pMap,
      calculatedAt: json['calculatedAt'] != null
          ? DateTime.parse(json['calculatedAt'].toString())
          : DateTime.now(),
    );
  }
}

class InstalledUserItem {
  const InstalledUserItem({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.role,
    required this.jobTitle,
    required this.isOnline,
    this.lastActiveAt,
    required this.sessionsCount,
  });

  final String userId;
  final String username;
  final String fullName;
  final String role;
  final String jobTitle;
  final bool isOnline;
  final DateTime? lastActiveAt;
  final int sessionsCount;

  factory InstalledUserItem.fromJson(Map<String, dynamic> json) {
    return InstalledUserItem(
      userId: json['userId']?.toString() ?? '',
      username: json['username'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      role: json['role'] as String? ?? '',
      jobTitle: json['jobTitle'] as String? ?? '-',
      isOnline: json['isOnline'] as bool? ?? false,
      lastActiveAt: json['lastActiveAt'] != null
          ? DateTime.tryParse(json['lastActiveAt'].toString())
          : null,
      sessionsCount: (json['sessionsCount'] as num?)?.toInt() ?? 1,
    );
  }
}

class BranchDeviceItem {
  const BranchDeviceItem({
    required this.hostname,
    required this.os,
    required this.osVersion,
    required this.ipAddress,
    required this.clientType,
    required this.appVersion,
    required this.isOnline,
    this.lastSeenAt,
    required this.username,
    required this.fullName,
  });

  final String hostname;
  final String os;
  final String osVersion;
  final String ipAddress;
  final String clientType;
  final String appVersion;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final String username;
  final String fullName;

  factory BranchDeviceItem.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    return BranchDeviceItem(
      hostname: json['hostname'] as String? ?? 'Unknown Device',
      os: json['os'] as String? ?? 'Windows',
      osVersion: json['osVersion'] as String? ?? '',
      ipAddress: json['ipAddress'] as String? ?? '-',
      clientType: json['clientType'] as String? ?? 'desktop',
      appVersion: json['appVersion'] as String? ?? '1.1.21',
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeenAt: json['lastSeenAt'] != null
          ? DateTime.tryParse(json['lastSeenAt'].toString())
          : null,
      username: user['username'] as String? ?? '',
      fullName: user['fullName'] as String? ?? '',
    );
  }
}

class BranchDeploymentItem {
  const BranchDeploymentItem({
    required this.branchId,
    required this.branchName,
    required this.branchCode,
    required this.isInstalled,
    required this.totalRegisteredUsers,
    required this.installedUsersCount,
    required this.onlineUsersCount,
    required this.devicesCount,
    required this.onlineDevicesCount,
    required this.appVersions,
    this.lastActivityAt,
    required this.devices,
    required this.installedUsers,
  });

  final String branchId;
  final String branchName;
  final String branchCode;
  final bool isInstalled;
  final int totalRegisteredUsers;
  final int installedUsersCount;
  final int onlineUsersCount;
  final int devicesCount;
  final int onlineDevicesCount;
  final List<String> appVersions;
  final DateTime? lastActivityAt;
  final List<BranchDeviceItem> devices;
  final List<InstalledUserItem> installedUsers;

  factory BranchDeploymentItem.fromJson(Map<String, dynamic> json) {
    final devsList = (json['devices'] as List<dynamic>?)
            ?.map((e) => BranchDeviceItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final usersList = (json['installedUsers'] as List<dynamic>?)
            ?.map((e) => InstalledUserItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final versionsList = (json['appVersions'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return BranchDeploymentItem(
      branchId: json['branchId']?.toString() ?? '',
      branchName: json['branchName'] as String? ?? '',
      branchCode: json['branchCode'] as String? ?? '',
      isInstalled: json['isInstalled'] as bool? ?? false,
      totalRegisteredUsers: (json['totalRegisteredUsers'] as num?)?.toInt() ?? 0,
      installedUsersCount: (json['installedUsersCount'] as num?)?.toInt() ?? 0,
      onlineUsersCount: (json['onlineUsersCount'] as num?)?.toInt() ?? 0,
      devicesCount: (json['devicesCount'] as num?)?.toInt() ?? 0,
      onlineDevicesCount: (json['onlineDevicesCount'] as num?)?.toInt() ?? 0,
      appVersions: versionsList,
      lastActivityAt: json['lastActivityAt'] != null
          ? DateTime.tryParse(json['lastActivityAt'].toString())
          : null,
      devices: devsList,
      installedUsers: usersList,
    );
  }
}

class BranchesDeploymentData {
  const BranchesDeploymentData({
    required this.summary,
    required this.branches,
  });

  final BranchDeploymentSummary summary;
  final List<BranchDeploymentItem> branches;

  factory BranchesDeploymentData.fromJson(Map<String, dynamic> json) {
    final s = BranchDeploymentSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? {});
    final bList = (json['branches'] as List<dynamic>?)
            ?.map((e) => BranchDeploymentItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return BranchesDeploymentData(
      summary: s,
      branches: bList,
    );
  }
}

class LiveRequestItem {
  const LiveRequestItem({
    required this.id,
    required this.timestamp,
    required this.method,
    required this.path,
    required this.statusCode,
    required this.durationMs,
    required this.clientIp,
    this.username,
    this.fullName,
  });

  final String id;
  final DateTime timestamp;
  final String method;
  final String path;
  final int statusCode;
  final int durationMs;
  final String clientIp;
  final String? username;
  final String? fullName;

  factory LiveRequestItem.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return LiveRequestItem(
      id: json['id'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      method: json['method'] as String? ?? 'GET',
      path: json['path'] as String? ?? '/',
      statusCode: (json['statusCode'] as num?)?.toInt() ?? 200,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      clientIp: json['clientIp'] as String? ?? '-',
      username: user?['username'] as String?,
      fullName: user?['fullName'] as String?,
    );
  }
}

class RequestTelemetryData {
  const RequestTelemetryData({
    required this.totalRequests,
    required this.activeRequests,
    required this.rps,
    required this.avgLatencyMs,
    required this.statusCounts,
    required this.recentRequests,
  });

  final int totalRequests;
  final int activeRequests;
  final double rps;
  final int avgLatencyMs;
  final Map<String, int> statusCounts;
  final List<LiveRequestItem> recentRequests;

  factory RequestTelemetryData.fromJson(Map<String, dynamic> json) {
    final sc = <String, int>{};
    if (json['statusCounts'] is Map) {
      (json['statusCounts'] as Map).forEach((k, v) {
        sc[k.toString()] = (v as num).toInt();
      });
    }

    final reqs = (json['recentRequests'] as List<dynamic>?)
            ?.map((e) => LiveRequestItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return RequestTelemetryData(
      totalRequests: (json['totalRequests'] as num?)?.toInt() ?? 0,
      activeRequests: (json['activeRequests'] as num?)?.toInt() ?? 0,
      rps: (json['rps'] as num?)?.toDouble() ?? 0.0,
      avgLatencyMs: (json['avgLatencyMs'] as num?)?.toInt() ?? 0,
      statusCounts: sc,
      recentRequests: reqs,
    );
  }
}
