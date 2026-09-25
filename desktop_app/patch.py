import re

with open('lib/features/chat/models/chat_models.dart', 'r', encoding='utf-8') as f:
    code = f.read()

# ChatDirectoryUser
code = code.replace('factory ChatDirectoryUser.fromJson', '''  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'username': username,
      'fullName': fullName,
      'avatarUrl': avatarUrl,
      'isActive': isActive,
      'isOnline': isOnline,
      'presenceStatus': presenceStatus,
    };
  }

  factory ChatDirectoryUser.fromJson''')

# ChatLastMessage
code = code.replace('factory ChatLastMessage.fromJson', '''  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'senderId': senderId,
      'senderName': senderName,
      'messageType': messageType,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory ChatLastMessage.fromJson''')

# ChatPinnedMessage
code = code.replace('factory ChatPinnedMessage.fromJson', '''  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'content': content,
      'setBy': setBy,
      'setByName': setByName,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory ChatPinnedMessage.fromJson''')

# ChatConversation
code = code.replace('factory ChatConversation.fromJson', '''  Map<String, dynamic> toJson() {
    return {
      '_id': id,
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

  factory ChatConversation.fromJson''')

# ChatReceipt
code = code.replace('factory ChatReceipt.fromJson', '''  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'at': at?.toIso8601String(),
    };
  }

  factory ChatReceipt.fromJson''')

# ChatMessage
code = code.replace('factory ChatMessage.fromJson', '''  Map<String, dynamic> toJson() {
    return {
      '_id': id,
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

  factory ChatMessage.fromJson''')


with open('lib/features/chat/models/chat_models.dart', 'w', encoding='utf-8') as f:
    f.write(code)
