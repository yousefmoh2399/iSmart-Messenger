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

  factory DeviceSession.fromJson(Map<String, dynamic> json) {
    final user = json['userId'] is Map<String, dynamic> ? json['userId'] as Map<String, dynamic> : <String, dynamic>{};
    return DeviceSession(
      id: json['_id'] as String,
      userId: user['_id'] as String? ?? '',
      username: user['username'] as String? ?? 'Unknown',
      fullName: user['fullName'] as String? ?? 'Unknown User',
      avatarUrl: user['avatarUrl'] as String?,
      ipAddress: json['ipAddress'] as String?,
      clientType: json['clientType'] as String? ?? 'unknown',
      deviceInfo: json['deviceInfo'] as Map<String, dynamic>? ?? {},
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeenAt: json['lastSeenAt'] != null ? DateTime.parse(json['lastSeenAt'].toString()) : DateTime.now(),
      startedAt: json['startedAt'] != null ? DateTime.parse(json['startedAt'].toString()) : DateTime.now(),
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

  factory ClientErrorLog.fromJson(Map<String, dynamic> json) {
    final user = json['userId'] is Map<String, dynamic> ? json['userId'] as Map<String, dynamic> : null;
    final session = json['sessionId'] is Map<String, dynamic> ? json['sessionId'] as Map<String, dynamic> : null;
    
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
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'].toString()) : DateTime.now(),
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
