class TicketActor {
  const TicketActor({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
  });

  final String id;
  final String username;
  final String fullName;
  final String role;

  String get displayName => fullName.trim().isNotEmpty ? fullName : username;

  factory TicketActor.fromJson(dynamic json) {
    final map = json is Map
        ? Map<String, dynamic>.from(json)
        : const <String, dynamic>{};
    return TicketActor(
      id: map['id']?.toString() ?? map['_id']?.toString() ?? '',
      username: map['username']?.toString() ?? '',
      fullName: map['fullName']?.toString() ?? '',
      role: map['role']?.toString() ?? 'user',
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
    required this.assignedTo,
    required this.branchDepartmentId,
    required this.branchDepartmentName,
    required this.lastPublicMessage,
    required this.lastUpdateAt,
    required this.createdAt,
    required this.updatedAt,
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
  final DateTime? lastUpdateAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory TicketItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }

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
      lastUpdateAt: parseDate(json['lastUpdateAt']),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

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
      lastUpdateAt: lastUpdateAt ?? other.lastUpdateAt,
      createdAt: createdAt ?? other.createdAt,
      updatedAt: updatedAt ?? other.updatedAt,
    );
  }
}

class TicketUpdateItem {
  const TicketUpdateItem({
    required this.id,
    required this.ticketId,
    required this.kind,
    required this.message,
    required this.visibility,
    required this.createdBy,
    required this.fromStatus,
    required this.toStatus,
    required this.toAssigneeId,
    required this.toAssigneeName,
    required this.createdAt,
  });

  final String id;
  final String ticketId;
  final String kind;
  final String message;
  final String visibility;
  final TicketActor createdBy;
  final String? fromStatus;
  final String? toStatus;
  final String? toAssigneeId;
  final String? toAssigneeName;
  final DateTime? createdAt;

  factory TicketUpdateItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    var createdBy = TicketActor.fromJson(json['createdBy']);
    final createdByName = json['createdByName']?.toString().trim() ?? '';
    if (createdBy.displayName.trim().isEmpty && createdByName.isNotEmpty) {
      createdBy = TicketActor(
        id: createdBy.id,
        username: createdBy.username,
        fullName: createdByName,
        role: createdBy.role,
      );
    }

    return TicketUpdateItem(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      ticketId: json['ticketId']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'comment',
      message: json['message']?.toString() ?? '',
      visibility: json['visibility']?.toString() ?? 'public',
      createdBy: createdBy,
      fromStatus: json['fromStatus']?.toString(),
      toStatus: json['toStatus']?.toString(),
      toAssigneeId: json['toAssigneeId']?.toString(),
      toAssigneeName: json['toAssigneeName']?.toString(),
      createdAt: parseDate(json['createdAt']),
    );
  }
}

class TicketSupportUser {
  const TicketSupportUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.departmentId,
    required this.isSupportAgent,
  });

  final String id;
  final String username;
  final String fullName;
  final String role;
  final String? departmentId;
  final bool isSupportAgent;

  String get displayName => fullName.trim().isNotEmpty ? fullName : username;

  factory TicketSupportUser.fromJson(Map<String, dynamic> json) {
    return TicketSupportUser(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      role: json['role']?.toString() ?? 'user',
      departmentId: json['departmentId']?.toString(),
      isSupportAgent: json['isSupportAgent'] == true,
    );
  }
}

class TicketSettingsData {
  const TicketSettingsData({
    required this.supportAgentIds,
    required this.isSupportAgent,
    required this.canManage,
  });

  final List<String> supportAgentIds;
  final bool isSupportAgent;
  final bool canManage;

  factory TicketSettingsData.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return TicketSettingsData(
      supportAgentIds: (map['supportAgentIds'] as List<dynamic>? ?? const [])
          .map((entry) => entry.toString())
          .toList(),
      isSupportAgent: map['isSupportAgent'] == true,
      canManage: map['canManage'] == true,
    );
  }
}

class TicketOverviewData {
  const TicketOverviewData({required this.tickets, required this.settings});

  final List<TicketItem> tickets;
  final TicketSettingsData settings;
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
