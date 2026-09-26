import '../../../core/network/media_url_resolver.dart';

List<String> _normalizeStringList(List<String>? value) {
  return List<String>.from(value ?? const <String>[]);
}

class ChatPermissionSet {
  const ChatPermissionSet({
    required this.canCreateUsers,
    required this.canCreateDepartments,
    required this.canCreateRooms,
    required this.canSendBroadcast,
    required this.canDeleteMessages,
    required this.canUploadFiles,
    required this.canModerateDepartment,
    required this.canViewDepartmentLogs,
    required this.canManageAnnouncements,
    required this.canManageFiles,
    required this.canManageBranches,
    required this.canManageRoles,
    required this.canManageSystem,
    required this.canManageUpdates,
    required this.canManageBackups,
    required this.canManageTickets,
    required this.canViewPrinters,
    required this.canManagePrinters,
    required this.canSyncPrinters,
    required this.canExportPrinterReports,
    required this.canViewSnipeit,
    required this.canViewSystemMonitor,
  });

  final bool canCreateUsers;
  final bool canCreateDepartments;
  final bool canCreateRooms;
  final bool canSendBroadcast;
  final bool canDeleteMessages;
  final bool canUploadFiles;
  final bool canModerateDepartment;
  final bool canViewDepartmentLogs;
  final bool canManageAnnouncements;
  final bool canManageFiles;
  final bool canManageBranches;
  final bool canManageRoles;
  final bool canManageSystem;
  final bool canManageUpdates;
  final bool canManageBackups;
  final bool canManageTickets;
  final bool canViewPrinters;
  final bool canManagePrinters;
  final bool canSyncPrinters;
  final bool canExportPrinterReports;
  final bool canViewSnipeit;
  final bool canViewSystemMonitor;

  factory ChatPermissionSet.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return ChatPermissionSet(
      canCreateUsers: map['canCreateUsers'] == true,
      canCreateDepartments: map['canCreateDepartments'] == true,
      canCreateRooms: map['canCreateRooms'] == true,
      canSendBroadcast: map['canSendBroadcast'] == true,
      canDeleteMessages: map['canDeleteMessages'] == true,
      canUploadFiles: map['canUploadFiles'] != false,
      canModerateDepartment: map['canModerateDepartment'] == true,
      canViewDepartmentLogs: map['canViewDepartmentLogs'] == true,
      canManageAnnouncements: map['canManageAnnouncements'] == true,
      canManageFiles: map['canManageFiles'] == true,
      canManageBranches: map['canManageBranches'] == true,
      canManageRoles: map['canManageRoles'] == true,
      canManageSystem: map['canManageSystem'] == true,
      canManageUpdates: map['canManageUpdates'] == true,
      canManageBackups: map['canManageBackups'] == true,
      canManageTickets: map['canManageTickets'] == true,
      canViewPrinters: map['canViewPrinters'] == true,
      canManagePrinters: map['canManagePrinters'] == true,
      canSyncPrinters: map['canSyncPrinters'] == true,
      canExportPrinterReports: map['canExportPrinterReports'] == true,
      canViewSnipeit: map['canViewSnipeit'] == true,
      canViewSystemMonitor: map['canViewSystemMonitor'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'canCreateUsers': canCreateUsers,
      'canCreateDepartments': canCreateDepartments,
      'canCreateRooms': canCreateRooms,
      'canSendBroadcast': canSendBroadcast,
      'canDeleteMessages': canDeleteMessages,
      'canUploadFiles': canUploadFiles,
      'canModerateDepartment': canModerateDepartment,
      'canViewDepartmentLogs': canViewDepartmentLogs,
      'canManageAnnouncements': canManageAnnouncements,
      'canManageFiles': canManageFiles,
      'canManageBranches': canManageBranches,
      'canManageRoles': canManageRoles,
      'canManageSystem': canManageSystem,
      'canManageUpdates': canManageUpdates,
      'canManageBackups': canManageBackups,
      'canManageTickets': canManageTickets,
      'canViewPrinters': canViewPrinters,
      'canManagePrinters': canManagePrinters,
      'canSyncPrinters': canSyncPrinters,
      'canExportPrinterReports': canExportPrinterReports,
      'canViewSnipeit': canViewSnipeit,
      'canViewSystemMonitor': canViewSystemMonitor,
    };
  }
}

class ChatDirectoryUser {
  const ChatDirectoryUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.departmentId,
    this.departmentIds = const [],
    required this.branchId,
    required this.branchCode,
    required this.isOnline,
    required this.presenceStatus,
    required this.isActive,
    required this.avatarUrl,
    required this.lastSeen,
    required this.lastActiveAt,
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
  final String presenceStatus;
  final bool isActive;
  final String? avatarUrl;
  final DateTime? lastSeen;
  final DateTime? lastActiveAt;

  String get displayName => fullName.trim().isEmpty ? username : fullName;
  bool get isIdle => presenceStatus == 'idle';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'fullName': fullName,
      'role': role,
      'departmentId': departmentId,
      'departmentIds': departmentIds,
      'branchId': branchId,
      'branchCode': branchCode,
      'isOnline': isOnline,
      'presenceStatus': presenceStatus,
      'isActive': isActive,
      'avatarUrl': avatarUrl,
      'lastSeen': lastSeen?.toIso8601String(),
      'lastActiveAt': lastActiveAt?.toIso8601String(),
    };
  }

  factory ChatDirectoryUser.fromJson(Map<String, dynamic> json) {
    return ChatDirectoryUser(
      id: (json['_id'] ?? json['id'])?.toString() ?? '',
      username: json['username'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      departmentId: json['departmentId'] as String?,
      departmentIds: (json['departmentIds'] as List<dynamic>? ?? const [])
          .map((entry) => entry.toString())
          .toList(),
      branchId: json['branchId'] as String?,
      branchCode: json['branchCode'] as String? ?? 'main',
      isOnline: json['isOnline'] as bool? ?? false,
      presenceStatus: json['presenceStatus'] as String? ?? 'offline',
      isActive: json['isActive'] as bool? ?? true,
      avatarUrl: _rawMediaUrl(json['avatarUrl']),
      lastSeen: json['lastSeen'] is String
          ? DateTime.tryParse(json['lastSeen'] as String)
          : null,
      lastActiveAt: json['lastActiveAt'] is String
          ? DateTime.tryParse(json['lastActiveAt'] as String)
          : null,
    );
  }
}

class ChatDirectoryUsersPage {
  const ChatDirectoryUsersPage({
    required this.users,
    required this.page,
    required this.limit,
    required this.hasMore,
  });

  final List<ChatDirectoryUser> users;
  final int page;
  final int limit;
  final bool hasMore;
}

class DepartmentSummary {
  const DepartmentSummary({
    required this.id,
    required this.name,
    required this.code,
    required this.description,
    required this.managers,
    required this.membersCount,
    required this.defaultConversationId,
  });

  final String id;
  final String name;
  final String code;
  final String description;
  final List<String> managers;
  final int membersCount;
  final String? defaultConversationId;

  factory DepartmentSummary.fromJson(Map<String, dynamic> json) {
    return DepartmentSummary(
      id: (json['_id'] ?? json['id'])?.toString() ?? '',
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      description: json['description'] as String? ?? '',
      managers: (json['managers'] as List<dynamic>? ?? const [])
          .map((entry) => entry.toString())
          .toList(),
      membersCount: json['membersCount'] as int? ?? 0,
      defaultConversationId: json['defaultConversationId'] as String?,
    );
  }
}

class BranchSummary {
  const BranchSummary({
    required this.id,
    required this.name,
    required this.code,
    required this.description,
    required this.membersCount,
  });

  final String id;
  final String name;
  final String code;
  final String description;
  final int membersCount;

  factory BranchSummary.fromJson(Map<String, dynamic> json) {
    return BranchSummary(
      id: (json['_id'] ?? json['id'])?.toString() ?? '',
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      description: json['description'] as String? ?? '',
      membersCount: json['membersCount'] as int? ?? 0,
    );
  }
}

class ChatRole {
  const ChatRole({
    required this.id,
    required this.roleName,
    required this.permissions,
  });

  final String id;
  final String roleName;
  final ChatPermissionSet permissions;

  factory ChatRole.fromJson(Map<String, dynamic> json) {
    return ChatRole(
      id: (json['_id'] ?? json['id'])?.toString() ?? '',
      roleName: json['roleName'] as String? ?? 'user',
      permissions: ChatPermissionSet.fromJson(
        json['permissions'] as Map<String, dynamic>?,
      ),
    );
  }
}

class ChatLastMessage {
  const ChatLastMessage({
    required this.content,
    required this.senderId,
    required this.senderName,
    required this.messageType,
    required this.createdAt,
  });

  final String content;
  final String? senderId;
  final String senderName;
  final String messageType;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'senderId': senderId,
      'senderName': senderName,
      'messageType': messageType,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory ChatLastMessage.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return ChatLastMessage(
      content: (map['content'] ?? map['text'] ?? '') as String,
      senderId: map['senderId'] as String?,
      senderName: map['senderName'] as String? ?? '',
      messageType: map['messageType'] as String? ?? 'text',
      createdAt: map['createdAt'] is String
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
    );
  }
}

class ChatPinnedMessage {
  const ChatPinnedMessage({
    this.messageId,
    required this.content,
    required this.setBy,
    required this.setByName,
    required this.createdAt,
    required this.updatedAt,
  });

  final String? messageId;
  final String content;
  final String? setBy;
  final String setByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'content': content,
      'setBy': setBy,
      'setByName': setByName,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory ChatPinnedMessage.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return ChatPinnedMessage(
      messageId: map['messageId'] as String?,
      content: map['content'] as String? ?? '',
      setBy: map['setBy'] as String?,
      setByName: map['setByName'] as String? ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String)
          : null,
    );
  }
}

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.type,
    required this.name,
    required this.description,
    required this.departmentId,
    required this.createdBy,
    required this.members,
    required this.admins,
    required this.broadcastPublisherIds,
    required this.blockedMemberIds,
    this.blockedMembers = const [],
    required this.pinnedMessage,
    required this.lastMessage,
    required this.unreadCount,
    required this.isArchived,
    required this.isMuted,
    required this.isPinned,
    required this.isFavorite,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String type;
  final String name;
  final String description;
  final String? departmentId;
  final String? createdBy;
  final List<ChatDirectoryUser> members;
  final List<ChatDirectoryUser> admins;
  final List<String> broadcastPublisherIds;
  final List<String> blockedMemberIds;
  final List<ChatDirectoryUser> blockedMembers;
  final ChatPinnedMessage? pinnedMessage;
  final ChatLastMessage? lastMessage;
  final int unreadCount;
  final bool isArchived;
  final bool isMuted;
  final bool isPinned;
  final bool isFavorite;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  String displayTitle(String currentUserId) {
    if (name.trim().isNotEmpty) {
      return name.trim();
    }

    if (type == 'direct') {
      final otherUsers = members.where((entry) => entry.id != currentUserId);
      if (otherUsers.isNotEmpty) {
        return otherUsers.first.displayName;
      }
    }

    return 'محادثة بدون اسم';
  }

  ChatConversation copyWith({
    String? name,
    String? description,
    List<ChatDirectoryUser>? members,
    List<ChatDirectoryUser>? admins,
    List<String>? broadcastPublisherIds,
    List<String>? blockedMemberIds,
    List<ChatDirectoryUser>? blockedMembers,
    ChatPinnedMessage? pinnedMessage,
    ChatLastMessage? lastMessage,
    int? unreadCount,
    bool? isArchived,
    bool? isMuted,
    bool? isPinned,
    bool? isFavorite,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatConversation(
      id: id,
      type: type,
      name: name ?? this.name,
      description: description ?? this.description,
      departmentId: departmentId,
      createdBy: createdBy,
      members: members ?? this.members,
      admins: admins ?? this.admins,
      broadcastPublisherIds: _normalizeStringList(
        broadcastPublisherIds ?? this.broadcastPublisherIds,
      ),
      blockedMemberIds: _normalizeStringList(
        blockedMemberIds ?? this.blockedMemberIds,
      ),
      blockedMembers: blockedMembers ?? this.blockedMembers,
      pinnedMessage: pinnedMessage ?? this.pinnedMessage,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      isArchived: isArchived ?? this.isArchived,
      isMuted: isMuted ?? this.isMuted,
      isPinned: isPinned ?? this.isPinned,
      isFavorite: isFavorite ?? this.isFavorite,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'description': description,
      'departmentId': departmentId,
      'createdBy': createdBy,
      'members': members.map((e) => e.toJson()).toList(),
      'admins': admins.map((e) => e.toJson()).toList(),
      'broadcastPublisherIds': broadcastPublisherIds,
      'blockedMemberIds': blockedMemberIds,
      'blockedMembers': blockedMembers.map((e) => e.toJson()).toList(),
      'pinnedMessage': pinnedMessage?.toJson(),
      'lastMessage': lastMessage?.toJson(),
      'unreadCount': unreadCount,
      'isArchived': isArchived,
      'isMuted': isMuted,
      'isPinned': isPinned,
      'isFavorite': isFavorite,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    return ChatConversation(
      id: (json['_id'] ?? json['id'])?.toString() ?? '',
      type: json['type'] as String? ?? 'direct',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      departmentId: json['departmentId'] as String?,
      createdBy: json['createdBy'] as String?,
      members: (json['members'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatDirectoryUser.fromJson)
          .toList(),
      admins: (json['admins'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatDirectoryUser.fromJson)
          .toList(),
      broadcastPublisherIds: _normalizeStringList(
        (json['broadcastPublisherIds'] as List<dynamic>?)
            ?.map((entry) => entry.toString())
            .toList(),
      ),
      blockedMemberIds: _normalizeStringList(
        (json['blockedMemberIds'] as List<dynamic>?)
            ?.map((entry) => entry.toString())
            .toList(),
      ),
      blockedMembers: (json['blockedMembers'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatDirectoryUser.fromJson)
          .toList(),
      pinnedMessage: json['pinnedMessage'] is Map<String, dynamic>
          ? ChatPinnedMessage.fromJson(
              json['pinnedMessage'] as Map<String, dynamic>,
            )
          : null,
      lastMessage: json['lastMessage'] is Map<String, dynamic>
          ? ChatLastMessage.fromJson(
              json['lastMessage'] as Map<String, dynamic>,
            )
          : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
      isArchived: json['isArchived'] == true,
      isMuted: json['isMuted'] == true,
      isPinned: json['isPinned'] == true,
      isFavorite: json['isFavorite'] == true,
      isActive: json['isActive'] != false,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ChatReceipt {
  const ChatReceipt({required this.userId, required this.at});

  final String userId;
  final DateTime? at;

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'at': at?.toIso8601String(),
    };
  }

  factory ChatReceipt.fromJson(Map<String, dynamic> json) {
    return ChatReceipt(
      userId: json['userId'] as String,
      at: json['at'] is String ? DateTime.tryParse(json['at'] as String) : null,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.sender,
    required this.content,
    required this.messageType,
    required this.fileUrl,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    required this.replyToMessageId,
    required this.isDeleted,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
    required this.seenBy,
    required this.deliveredTo,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final ChatDirectoryUser? sender;
  final String content;
  final String messageType;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String? replyToMessageId;
  final bool isDeleted;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatReceipt> seenBy;
  final List<ChatReceipt> deliveredTo;

  bool get isAudioMessage =>
      messageType == 'audio' ||
      (mimeType?.toLowerCase().startsWith('audio/') ?? false);
  bool get isImageMessage =>
      messageType == 'image' ||
      (mimeType?.toLowerCase().startsWith('image/') ?? false);
  bool get isGifMessage => messageType == 'gif';
  bool get isPollMessage => messageType == 'poll' || messageType == 'checklist';
  bool get isPdfMessage =>
      messageType == 'pdf' || mimeType?.toLowerCase() == 'application/pdf';
  bool get hasAttachment => fileUrl != null && fileUrl!.isNotEmpty;
  bool get isPrintableAttachment {
    if (!hasAttachment) {
      return false;
    }
    if (isImageMessage || isPdfMessage) {
      return true;
    }
    final lowerMime = (mimeType ?? '').toLowerCase();
    if (lowerMime.startsWith('text/')) {
      return true;
    }
    final ext = (fileName ?? '').toLowerCase();
    return ext.endsWith('.doc') ||
        ext.endsWith('.docx') ||
        ext.endsWith('.xls') ||
        ext.endsWith('.xlsx') ||
        ext.endsWith('.ppt') ||
        ext.endsWith('.pptx') ||
        ext.endsWith('.txt') ||
        ext.endsWith('.rtf') ||
        ext.endsWith('.csv');
  }

  bool get isEdited => metadata?['editedAt'] != null;
  bool get isForwarded => metadata?['forwardedFrom'] is Map<String, dynamic>;
  List<String> get favoriteByUserIds {
    final raw = metadata?['favoriteBy'];
    if (raw is! List) {
      return const <String>[];
    }
    return raw
        .map((entry) => entry.toString())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  bool isFavoritedBy(String? userId) =>
      userId != null && userId.trim().isNotEmpty
      ? favoriteByUserIds.contains(userId.trim())
      : false;
  Map<String, dynamic>? get _attachmentPolicy {
    final policy = metadata?['attachmentPolicy'];
    if (policy is Map<String, dynamic>) {
      return policy;
    }
    if (policy is Map) {
      return Map<String, dynamic>.from(policy);
    }
    return null;
  }

  bool get attachmentDownloadAllowed =>
      _attachmentPolicy?['allowDownload'] != false;
  bool get attachmentForwardAllowed =>
      _attachmentPolicy?['allowForward'] != false;
  bool get isAttachmentViewOnly =>
      hasAttachment &&
      (!attachmentDownloadAllowed || !attachmentForwardAllowed);
  List<String> get broadcastTargetDepartmentIds {
    final broadcastTargets = metadata?['broadcastTargets'];
    if (broadcastTargets is! Map) {
      return const <String>[];
    }
    final raw = broadcastTargets['departmentIds'];
    if (raw is! List) {
      return const <String>[];
    }
    return raw
        .map((entry) => entry.toString())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  List<String> get broadcastTargetDepartmentNames {
    final broadcastTargets = metadata?['broadcastTargets'];
    if (broadcastTargets is! Map) {
      return const <String>[];
    }
    final raw = broadcastTargets['departmentNames'];
    if (raw is! List) {
      return const <String>[];
    }
    return raw
        .map((entry) => entry.toString())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  bool get sentToAllDepartments {
    final broadcastTargets = metadata?['broadcastTargets'];
    if (broadcastTargets is! Map) {
      return false;
    }
    return broadcastTargets['sentToAllDepartments'] == true;
  }

  String? get forwardedFromName {
    final forwardedFrom = metadata?['forwardedFrom'];
    if (forwardedFrom is! Map) {
      return null;
    }
    final senderName = forwardedFrom['senderName']?.toString().trim();
    if (senderName != null && senderName.isNotEmpty) {
      return senderName;
    }
    final conversationName = forwardedFrom['conversationName']
        ?.toString()
        .trim();
    if (conversationName != null && conversationName.isNotEmpty) {
      return conversationName;
    }
    return null;
  }

  String? get replyPreviewText {
    final replyPreview = metadata?['replyPreview'];
    if (replyPreview is! Map) {
      return null;
    }
    final content = replyPreview['content']?.toString().trim();
    if (content != null && content.isNotEmpty) {
      return content;
    }
    final fileName = replyPreview['fileName']?.toString().trim();
    if (fileName != null && fileName.isNotEmpty) {
      return fileName;
    }
    return null;
  }

  String? get replyPreviewSender {
    final replyPreview = metadata?['replyPreview'];
    if (replyPreview is! Map) {
      return null;
    }
    final senderName = replyPreview['senderName']?.toString().trim();
    if (senderName == null || senderName.isEmpty) {
      return null;
    }
    return senderName;
  }

  ChatMessage copyWith({
    String? content,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? replyToMessageId,
    bool? isDeleted,
    Map<String, dynamic>? metadata,
    DateTime? updatedAt,
    List<ChatReceipt>? seenBy,
    List<ChatReceipt>? deliveredTo,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      sender: sender,
      content: content ?? this.content,
      messageType: messageType,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      isDeleted: isDeleted ?? this.isDeleted,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      seenBy: seenBy ?? this.seenBy,
      deliveredTo: deliveredTo ?? this.deliveredTo,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'senderId': senderId,
      'sender': sender?.toJson(),
      'content': content,
      'messageType': messageType,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'replyToMessageId': replyToMessageId,
      'isDeleted': isDeleted,
      'metadata': metadata,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'seenBy': seenBy.map((e) => e.toJson()).toList(),
      'deliveredTo': deliveredTo.map((e) => e.toJson()).toList(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['_id'] ?? json['id'])?.toString() ?? '',
      conversationId: json['conversationId']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      sender: json['sender'] is Map<String, dynamic>
          ? ChatDirectoryUser.fromJson(json['sender'] as Map<String, dynamic>)
          : null,
      content: json['content'] as String? ?? '',
      messageType: json['messageType'] as String? ?? 'text',
      fileUrl: _rawMediaUrl(json['fileUrl']),
      fileName: json['fileName'] as String?,
      fileSize: json['fileSize'] as int?,
      mimeType: json['mimeType'] as String?,
      replyToMessageId: json['replyToMessageId'] as String?,
      isDeleted: json['isDeleted'] == true,
      metadata: json['metadata'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['metadata'] as Map<String, dynamic>)
          : null,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      seenBy: (json['seenBy'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatReceipt.fromJson)
          .toList(),
      deliveredTo: (json['deliveredTo'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatReceipt.fromJson)
          .toList(),
    );
  }
}

String? _rawMediaUrl(Object? value) {
  return resolveMediaUrl(value?.toString());
}

class ChatOverviewData {
  const ChatOverviewData({
    required this.conversations,
    required this.manageableConversations,
    required this.users,
    required this.departments,
    required this.branches,
    required this.roles,
  });

  final List<ChatConversation> conversations;
  final List<ChatConversation> manageableConversations;
  final List<ChatDirectoryUser> users;
  final List<DepartmentSummary> departments;
  final List<BranchSummary> branches;
  final List<ChatRole> roles;

  List<ChatConversation> get directConversations =>
      conversations.where((entry) => entry.type == 'direct').toList();

  List<ChatConversation> get departmentConversations =>
      conversations.where((entry) => entry.type == 'department').toList();

  List<ChatConversation> get roomConversations => conversations
      .where((entry) => entry.type == 'group' || entry.type == 'broadcast' || entry.type == 'department')
      .toList();

  int get totalUnread =>
      conversations.fold<int>(0, (sum, entry) => sum + entry.unreadCount);
}

class ChatPostResult {
  const ChatPostResult({required this.conversation, required this.message});

  final ChatConversation conversation;
  final ChatMessage message;
}

class ChatMessagesPage {
  const ChatMessagesPage({
    required this.messages,
    required this.nextCursor,
    required this.hasMore,
    required this.limit,
  });

  final List<ChatMessage> messages;
  final String? nextCursor;
  final bool hasMore;
  final int limit;
}

class ConversationMessagesState {
  const ConversationMessagesState({
    required this.messages,
    required this.nextCursor,
    required this.hasMore,
    required this.isLoadingMore,
  });

  final List<ChatMessage> messages;
  final String? nextCursor;
  final bool hasMore;
  final bool isLoadingMore;

  factory ConversationMessagesState.initial(ChatMessagesPage page) {
    return ConversationMessagesState(
      messages: page.messages,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      isLoadingMore: false,
    );
  }

  ConversationMessagesState copyWith({
    List<ChatMessage>? messages,
    String? nextCursor,
    bool? hasMore,
    bool? isLoadingMore,
    bool clearCursor = false,
  }) {
    return ConversationMessagesState(
      messages: messages ?? this.messages,
      nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class ChatSearchResult {
  const ChatSearchResult({
    required this.messages,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<ChatMessage> messages;
  final String? nextCursor;
  final bool hasMore;
}

class ChatFavoriteMessageEntry {
  const ChatFavoriteMessageEntry({
    required this.conversation,
    required this.message,
  });

  final ChatConversation conversation;
  final ChatMessage message;

  factory ChatFavoriteMessageEntry.fromJson(Map<String, dynamic> json) {
    return ChatFavoriteMessageEntry(
      conversation: ChatConversation.fromJson(
        json['conversation'] as Map<String, dynamic>? ?? const {},
      ),
      message: ChatMessage.fromJson(
        json['message'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class ChatFavoriteMessagesPage {
  const ChatFavoriteMessagesPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
    required this.limit,
  });

  final List<ChatFavoriteMessageEntry> items;
  final String? nextCursor;
  final bool hasMore;
  final int limit;
}

class ChatAuditLog {
  const ChatAuditLog({
    required this.id,
    required this.actorId,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String actorId;
  final String action;
  final String entityType;
  final String entityId;
  final Map<String, dynamic>? payload;
  final DateTime createdAt;

  factory ChatAuditLog.fromJson(Map<String, dynamic> json) {
    return ChatAuditLog(
      id: (json['_id'] ?? json['id']).toString(),
      actorId: json['actorId']?.toString() ?? '',
      action: json['action'] as String? ?? '',
      entityType: json['entityType'] as String? ?? '',
      entityId: json['entityId']?.toString() ?? '',
      payload: json['payload'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['payload'] as Map<String, dynamic>)
          : null,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ChatSystemError {
  const ChatSystemError({
    required this.id,
    required this.actorId,
    required this.method,
    required this.path,
    required this.statusCode,
    required this.errorName,
    required this.message,
    required this.stack,
    required this.meta,
    required this.createdAt,
  });

  final String id;
  final String? actorId;
  final String method;
  final String path;
  final int statusCode;
  final String errorName;
  final String message;
  final String? stack;
  final Map<String, dynamic>? meta;
  final DateTime createdAt;

  factory ChatSystemError.fromJson(Map<String, dynamic> json) {
    return ChatSystemError(
      id: (json['_id'] ?? json['id']).toString(),
      actorId: json['actorId']?.toString(),
      method: json['method'] as String? ?? '',
      path: json['path'] as String? ?? '',
      statusCode: json['statusCode'] as int? ?? 500,
      errorName: json['errorName'] as String? ?? 'Error',
      message: json['message'] as String? ?? '',
      stack: json['stack'] as String?,
      meta: json['meta'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['meta'] as Map<String, dynamic>)
          : null,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
class ChatFolder {
  final String id;
  final String name;
  final String? icon;
  final List<String> conversationIds;
  final int order;

  ChatFolder({
    required this.id,
    required this.name,
    this.icon,
    required this.conversationIds,
    required this.order,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'conversationIds': conversationIds,
      'order': order,
    };
  }

  factory ChatFolder.fromJson(Map<String, dynamic> json) {
    return ChatFolder(
      id: (json['_id'] ?? json['id'])?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      icon: json['icon'] as String?,
      conversationIds: (json['conversationIds'] as List?)?.cast<String>() ?? [],
      order: json['order'] as int? ?? 0,
    );
  }

  ChatFolder copyWith({
    String? id,
    String? name,
    String? icon,
    List<String>? conversationIds,
    int? order,
  }) {
    return ChatFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      conversationIds: conversationIds ?? this.conversationIds,
      order: order ?? this.order,
    );
  }
}
