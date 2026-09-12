class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.departmentId,
    this.departmentIds = const [],
    required this.branchId,
    required this.branchCode,
    required this.isOnline,
    required this.isActive,
    required this.lastSeen,
    required this.permissions,
    required this.createdAt,
  });

  final String id;
  final String username;
  final String fullName;
  final String role;
  final String? departmentId;
  final List<String> departmentIds;
  final String? branchId;
  final String branchCode;
  final bool isOnline;
  final bool isActive;
  final DateTime? lastSeen;
  final Map<String, bool> permissions;
  final DateTime createdAt;

  factory ManagedUser.fromJson(Map<String, dynamic> json) {
    final permissionsJson =
        json['permissions'] as Map<String, dynamic>? ?? const {};
    return ManagedUser(
      id: json['id'] as String,
      username: json['username'] as String,
      fullName: json['fullName'] as String,
      role: json['role'] as String? ?? 'user',
      departmentId: json['departmentId'] as String?,
      departmentIds: (json['departmentIds'] as List<dynamic>? ?? const [])
          .map((entry) => entry.toString())
          .toList(),
      branchId: json['branchId'] as String?,
      branchCode: json['branchCode'] as String? ?? 'main',
      isOnline: json['isOnline'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
      lastSeen: json['lastSeen'] is String
          ? DateTime.tryParse(json['lastSeen'] as String)
          : null,
      permissions: permissionsJson.map(
        (key, value) => MapEntry(key, value == true),
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
