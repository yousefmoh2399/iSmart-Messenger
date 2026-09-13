import 'package:flutter/material.dart';
import '../../models/chat_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/chat_folders_provider.dart';

class ChatFolderInlineItem extends ConsumerWidget {
  final ChatFolder folder;
  final List<ChatConversation> conversations;
  final String currentUserId;
  final Widget Function(ChatConversation) buildConversation;

  const ChatFolderInlineItem({
    super.key,
    required this.folder,
    required this.conversations,
    required this.currentUserId,
    required this.buildConversation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    
    // Pick 10 random colors using the folder ID's hash
    final colors = [
      Colors.redAccent,
      Colors.blueAccent,
      Colors.green,
      Colors.orange,
      Colors.purpleAccent,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.cyan,
      Colors.amber,
    ];
    final color = colors[folder.id.hashCode.abs() % colors.length];

    int unreadCount = 0;
    for (final c in conversations) {
      unreadCount += c.unreadCount;
    }

    return DragTarget<ChatConversation>(
      onAcceptWithDetails: (details) {
        if (!folder.conversationIds.contains(details.data.id)) {
          final newIds = [...folder.conversationIds, details.data.id];
          ref.read(chatFoldersProvider.notifier).updateFolder(folder.id, conversationIds: newIds);
        }
      },
      builder: (context, candidateData, rejectedData) {
        return ExpansionTile(
          shape: const Border(),
          backgroundColor: candidateData.isNotEmpty ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : Colors.transparent,
          collapsedBackgroundColor: candidateData.isNotEmpty ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : Colors.transparent,
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.folder_rounded, color: color),
          ),
          title: Text(
            folder.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unreadCount.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              const SizedBox(width: 8),
              PopupMenuButton(
                icon: const Icon(Icons.more_vert_rounded),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('حذف المجلد', style: TextStyle(color: Colors.red)),
                  ),
                ],
                onSelected: (val) {
                  if (val == 'delete') {
                    ref.read(chatFoldersProvider.notifier).deleteFolder(folder.id);
                  }
                },
              ),
            ],
          ),
          children: conversations.map((c) => buildConversation(c)).toList(),
        );
      },
    );
  }
}
