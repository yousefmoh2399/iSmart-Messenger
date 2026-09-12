class TicketActor {
  const TicketActor({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.departmentId,
    this.isOnline = false,
    this.presenceStatus = 'offline',
    this.avatarUrl,
    this.lastSeen,
    this.lastActiveAt,
  });

  final String id;
  final String username;
  final String fullName;
  final String role;
  final String? departmentId;
  final bool isOnline;
  final String presenceStatus;
  final String? avatarUrl;
  final DateTime? lastSeen;
  final DateTime? lastActiveAt;

  String get displayName {
    final trimmed = fullName.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    final usernameTrimmed = username.trim();
    if (usernameTrimmed.isNotEmpty) {
      return usernameTrimmed;
    }
    return 'مستخدم';
  }

  factory TicketActor.fromJson(dynamic json) {
    final data = json is Map
        ? Map<String, dynamic>.from(json)
        : const <String, dynamic>{};
    return TicketActor(
      id: data['id']?.toString() ?? data['_id']?.toString() ?? '',
      username: data['username']?.toString() ?? '',
      fullName: data['fullName']?.toString() ?? '',
      role: data['role']?.toString() ?? 'user',
      departmentId: data['departmentId']?.toString(),
      isOnline: data['isOnline'] == true,
      presenceStatus: data['presenceStatus']?.toString() ?? 'offline',
      avatarUrl: data['avatarUrl']?.toString(),
      lastSeen: _parseDate(data['lastSeen']),
      lastActiveAt: _parseDate(data['lastActiveAt']),
    );
  }
}

class TicketItem {
  const TicketItem({
    required this.id,
    required this.ticketNumber,
    this.ticketType = 'ticket',
    this.targetDepartmentId,
    this.targetDepartmentName,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.assignedTo,
    this.branchDepartmentId,
    this.branchDepartmentName,
    this.lastPublicMessage = '',
    this.lastUpdateAt,
    this.resolvedAt,
    this.closedAt,
  });

  final String id;
  final String ticketNumber;
  final String ticketType;
  final String? targetDepartmentId;
  final String? targetDepartmentName;
  final String title;
  final String description;
  final String status;
  final String priority;
  final TicketActor createdBy;
  final TicketActor? assignedTo;
  final String? branchDepartmentId;
  final String? branchDepartmentName;
  final String lastPublicMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUpdateAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;

  factory TicketItem.fromJson(Map<String, dynamic> json) {
    return TicketItem(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      ticketNumber: json['ticketNumber']?.toString() ?? '',
      ticketType: json['ticketType']?.toString() ?? 'ticket',
      targetDepartmentId: json['targetDepartmentId']?.toString(),
      targetDepartmentName: json['targetDepartmentName']?.toString(),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      status: json['status']?.toString() ?? 'open',
      priority: json['priority']?.toString() ?? 'normal',
      createdBy: TicketActor.fromJson(json['createdBy']),
      assignedTo: _parseAssignedTo(json['assignedTo']),
      branchDepartmentId: json['branchDepartmentId']?.toString(),
      branchDepartmentName: json['branchDepartmentName']?.toString(),
      lastPublicMessage: json['lastPublicMessage']?.toString() ?? '',
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updatedAt']) ?? DateTime.now(),
      lastUpdateAt: _parseDate(json['lastUpdateAt']),
      resolvedAt: _parseDate(json['resolvedAt']),
      closedAt: _parseDate(json['closedAt']),
    );
  }

  /// Keeps the richest non-empty fields when API list vs details payloads differ.
  TicketItem mergeWith(TicketItem? other) {
    if (other == null) {
      return this;
    }
    String pick(String primary, String fallback) {
      final left = primary.trim();
      final right = fallback.trim();
      if (left.isEmpty) return right;
      if (right.isEmpty) return left;
      return left.length >= right.length ? left : right;
    }

    String? pickOptional(String? primary, String? fallback) {
      final chosen = pick(primary ?? '', fallback ?? '');
      return chosen.isEmpty ? null : chosen;
    }

    TicketActor pickActor(TicketActor primary, TicketActor fallback) =>
        primary.displayName.trim().isNotEmpty ? primary : fallback;

    return TicketItem(
      id: pick(id, other.id),
      ticketNumber: pick(ticketNumber, other.ticketNumber),
      ticketType: pick(ticketType, other.ticketType),
      targetDepartmentId: targetDepartmentId ?? other.targetDepartmentId,
      targetDepartmentName: pickOptional(
        targetDepartmentName,
        other.targetDepartmentName,
      ),
      title: pick(title, other.title),
      description: pick(description, other.description),
      status: pick(status, other.status),
      priority: pick(priority, other.priority),
      createdBy: pickActor(createdBy, other.createdBy),
      assignedTo: assignedTo ?? other.assignedTo,
      branchDepartmentId: branchDepartmentId ?? other.branchDepartmentId,
      branchDepartmentName: pickOptional(
        branchDepartmentName,
        other.branchDepartmentName,
      ),
      lastPublicMessage: pick(lastPublicMessage, other.lastPublicMessage),
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastUpdateAt: lastUpdateAt ?? other.lastUpdateAt,
      resolvedAt: resolvedAt ?? other.resolvedAt,
      closedAt: closedAt ?? other.closedAt,
    );
  }
}

class TicketUpdateItem {
  const TicketUpdateItem({
    required this.id,
    required this.kind,
    required this.message,
    required this.visibility,
    required this.createdBy,
    required this.createdAt,
    this.ticketId,
    this.fromStatus,
    this.toStatus,
    this.fromAssigneeId,
    this.toAssigneeId,
    this.toAssigneeName,
    this.metadata,
    this.updatedAt,
  });

  final String id;
  final String? ticketId;
  final String kind;
  final String message;
  final String visibility;
  final TicketActor createdBy;
  final String? fromStatus;
  final String? toStatus;
  final String? fromAssigneeId;
  final String? toAssigneeId;
  final String? toAssigneeName;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory TicketUpdateItem.fromJson(Map<String, dynamic> json) {
    var createdBy = TicketActor.fromJson(json['createdBy']);
    final createdByName = json['createdByName']?.toString().trim() ?? '';
    if (createdBy.displayName.trim().isEmpty && createdByName.isNotEmpty) {
      createdBy = TicketActor(
        id: createdBy.id,
        username: createdBy.username,
        fullName: createdByName,
        role: createdBy.role,
        departmentId: createdBy.departmentId,
        isOnline: createdBy.isOnline,
        presenceStatus: createdBy.presenceStatus,
        avatarUrl: createdBy.avatarUrl,
        lastSeen: createdBy.lastSeen,
        lastActiveAt: createdBy.lastActiveAt,
      );
    }

    return TicketUpdateItem(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      ticketId: json['ticketId']?.toString(),
      kind: json['kind']?.toString() ?? 'comment',
      message: json['message']?.toString() ?? '',
      visibility: json['visibility']?.toString() ?? 'public',
      createdBy: createdBy,
      fromStatus: json['fromStatus']?.toString(),
      toStatus: json['toStatus']?.toString(),
      fromAssigneeId: json['fromAssigneeId']?.toString(),
      toAssigneeId: json['toAssigneeId']?.toString(),
      toAssigneeName: json['toAssigneeName']?.toString(),
      metadata: json['metadata'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['metadata'] as Map<String, dynamic>)
          : null,
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }
}

class TicketSupportUser {
  const TicketSupportUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.isSupportAgent,
    this.departmentId,
    this.isOnline = false,
    this.presenceStatus = 'offline',
    this.avatarUrl,
    this.exportTicketTypes = const <String>[],
  });

  final String id;
  final String username;
  final String fullName;
  final String role;
  final bool isSupportAgent;
  final String? departmentId;
  final bool isOnline;
  final String presenceStatus;
  final String? avatarUrl;
  final List<String> exportTicketTypes;

  String get displayName =>
      fullName.trim().isNotEmpty ? fullName.trim() : username;

  factory TicketSupportUser.fromJson(Map<String, dynamic> json) {
    return TicketSupportUser(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      role: json['role']?.toString() ?? 'user',
      isSupportAgent: json['isSupportAgent'] == true,
      departmentId: json['departmentId']?.toString(),
      isOnline: json['isOnline'] == true,
      presenceStatus: json['presenceStatus']?.toString() ?? 'offline',
      avatarUrl: json['avatarUrl']?.toString(),
      exportTicketTypes:
          (json['exportTicketTypes'] as List<dynamic>? ?? const [])
              .map((entry) => entry.toString())
              .where((entry) => entry.isNotEmpty)
              .toList(),
    );
  }
}

class TicketSettingsData {
  const TicketSettingsData({
    required this.supportAgentIds,
    required this.isSupportAgent,
    required this.canManage,
    required this.canExportTicketReport,
    required this.canExportComplaintReport,
    required this.canExportSuggestionReport,
  });

  final List<String> supportAgentIds;
  final bool isSupportAgent;
  final bool canManage;
  final bool canExportTicketReport;
  final bool canExportComplaintReport;
  final bool canExportSuggestionReport;

  factory TicketSettingsData.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return TicketSettingsData(
      supportAgentIds: (data['supportAgentIds'] as List<dynamic>? ?? const [])
          .map((entry) => entry.toString())
          .where((entry) => entry.isNotEmpty)
          .toList(),
      isSupportAgent: data['isSupportAgent'] == true,
      canManage: data['canManage'] == true,
      canExportTicketReport: data['canExportTicketReport'] == true,
      canExportComplaintReport: data['canExportComplaintReport'] == true,
      canExportSuggestionReport: data['canExportSuggestionReport'] == true,
    );
  }
}

class TicketOverviewData {
  const TicketOverviewData({
    required this.tickets,
    required this.settings,
    required this.canManage,
  });

  final List<TicketItem> tickets;
  final TicketSettingsData settings;
  final bool canManage;
}

class TicketDetailsData {
  const TicketDetailsData({
    required this.ticket,
    required this.updates,
    required this.settings,
    required this.canManage,
  });

  final TicketItem ticket;
  final List<TicketUpdateItem> updates;
  final TicketSettingsData settings;
  final bool canManage;
}

class TicketSupportUsersData {
  const TicketSupportUsersData({
    required this.users,
    required this.supportAgentIds,
  });

  final List<TicketSupportUser> users;
  final List<String> supportAgentIds;
}

TicketActor? _parseAssignedTo(dynamic value) {
  if (value is Map) {
    final actor = TicketActor.fromJson(value);
    if (actor.id.trim().isNotEmpty || actor.displayName.trim().isNotEmpty) {
      return actor;
    }
    return null;
  }
  final assigneeId = value?.toString().trim() ?? '';
  if (assigneeId.isEmpty) {
    return null;
  }
  return TicketActor(id: assigneeId, username: '', fullName: '', role: 'user');
}

DateTime? _parseDate(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  final raw = value.toString().trim();
  if (raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}
