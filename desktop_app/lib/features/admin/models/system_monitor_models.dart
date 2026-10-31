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
