import '../models/chat_models.dart';

/// Collapses consecutive messages of the same media album into a single
/// representation for display in the chat list.
List<ChatMessage> collapseMediaAlbums(List<ChatMessage> messages) {
  final displayed = <ChatMessage>[];
  final groups = <String>{};
  for (final message in messages) {
    final groupId = message.isImageMessage
        ? (message.metadata?['mediaGroupId']?.toString())
        : null;
    if (groupId != null && groupId.isNotEmpty && !groups.add(groupId)) {
      continue;
    }
    displayed.add(message);
  }
  return displayed;
}

/// Retrieves all messages belonging to the same media album as [message],
/// ordered chronologically (oldest to newest) for grid and viewer display.
List<ChatMessage> albumFor(ChatMessage message, List<ChatMessage> messages) {
  final groupId = message.metadata?['mediaGroupId']?.toString();
  if (!message.isImageMessage || groupId == null || groupId.isEmpty) {
    return <ChatMessage>[message];
  }
  final album = messages
      .where(
        (item) =>
            item.isImageMessage &&
            item.metadata?['mediaGroupId']?.toString() == groupId,
      )
      .toList();
  album.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return album;
}
