import 'dart:io';

void main() {
  var file = File('lib/features/chat/models/chat_models.dart');
  var code = file.readAsStringSync();

  code = code.replaceAll('factory ChatDirectoryUser.fromJson', '''  Map<String, dynamic> toJson() {
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

  factory ChatDirectoryUser.fromJson''');

  code = code.replaceAll('factory ChatLastMessage.fromJson', '''  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'senderId': senderId,
      'senderName': senderName,
      'messageType': messageType,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory ChatLastMessage.fromJson''');

  code = code.replaceAll('factory ChatPinnedMessage.fromJson', '''  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'content': content,
      'setBy': setBy,
      'setByName': setByName,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory ChatPinnedMessage.fromJson''');

  code = code.replaceAll('factory ChatConversation.fromJson', '''  Map<String, dynamic> toJson() {
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

  factory ChatConversation.fromJson''');

  code = code.replaceAll('factory ChatReceipt.fromJson', '''  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'at': at?.toIso8601String(),
    };
  }

  factory ChatReceipt.fromJson''');

  code = code.replaceAll('factory ChatMessage.fromJson', '''  Map<String, dynamic> toJson() {
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

  factory ChatMessage.fromJson''');
  
  // Also add toJson to ChatFolder
  code = code.replaceAll('factory ChatFolder.fromJson', '''  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'conversationIds': conversationIds,
      'order': order,
    };
  }

  factory ChatFolder.fromJson''');

  // Fix fromJson for cache resilience
  code = code.replaceAll("id: json['id'] as String", "id: (json['_id'] ?? json['id'])?.toString() ?? ''");
  code = code.replaceAll("id: json['_id'] as String? ?? json['id'] as String", "id: (json['_id'] ?? json['id'])?.toString() ?? ''");
  code = code.replaceAll("conversationId: json['conversationId'] as String", "conversationId: json['conversationId']?.toString() ?? ''");
  code = code.replaceAll("senderId: json['senderId'] as String", "senderId: json['senderId']?.toString() ?? ''");
  code = code.replaceAll("userId: json['userId'] as String", "userId: json['userId']?.toString() ?? ''");
  code = code.replaceAll("name: json['name'] as String,", "name: json['name']?.toString() ?? '',");

  file.writeAsStringSync(code);
}
