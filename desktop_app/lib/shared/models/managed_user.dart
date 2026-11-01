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
    required this.maxAttachmentSizeMB,
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
  final int maxAttachmentSizeMB;
  final Map<String, bool> permissions;
  final DateTime createdAt;

  List<String> get allDepartmentIds {
    if (departmentIds.isNotEmpty) return departmentIds;
    if (departmentId != null && departmentId!.isNotEmpty) return [departmentId!];
    return const [];
  }

  factory ManagedUser.fromJson(Map<String, dynamic> json) {
    final permissionsJson =
        json['permissions'] as Map<String, dynamic>? ?? const {};
    final deptId = json['departmentId'] is Map
        ? (json['departmentId']['_id'] ?? json['departmentId']['id'])?.toString()
        : json['departmentId']?.toString();
    final parsedDeptIds = (json['departmentIds'] as List<dynamic>? ?? const [])
        .map((entry) {
          if (entry is Map) {
            return (entry['_id'] ?? entry['id'])?.toString();
          }
          return entry?.toString();
        })
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .toList();
    final effectiveDeptIds = parsedDeptIds.isNotEmpty
        ? parsedDeptIds
        : [if (deptId != null && deptId.trim().isNotEmpty) deptId];

    return ManagedUser(
      id: (json['_id'] ?? json['id'])?.toString() ?? '',
      username: json['username'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      departmentId: deptId,
      departmentIds: effectiveDeptIds,
      branchId: json['branchId'] is Map
          ? (json['branchId']['_id'] ?? json['branchId']['id'])?.toString()
          : json['branchId']?.toString(),
      branchCode: json['branchCode'] as String? ?? 'main',
      isOnline: json['isOnline'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
      lastSeen: json['lastSeen'] is String
          ? DateTime.tryParse(json['lastSeen'] as String)
          : null,
      maxAttachmentSizeMB: (json['maxAttachmentSizeMB'] as num?)?.toInt() ?? 20,
      permissions: permissionsJson.map(
        (key, value) => MapEntry(key, value == true),
      ),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
