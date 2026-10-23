import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat_models.dart';
import '../../providers/chat_folders_provider.dart';
import 'create_chat_folder_dialog.dart';

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

    final color = resolveFolderColor(folder);
    final iconData = resolveFolderIcon(folder);

    int unreadCount = 0;
    for (final c in conversations) {
      unreadCount += c.unreadCount;
    }

    return DragTarget<ChatConversation>(
      onAcceptWithDetails: (details) {
        if (!folder.conversationIds.contains(details.data.id)) {
          ref
              .read(chatFoldersProvider.notifier)
              .updateFolderMembership(
                folderId: folder.id,
                conversationId: details.data.id,
                add: true,
              );
        }
      },
      builder: (context, candidateData, rejectedData) {
        return ExpansionTile(
          shape: const Border(),
          backgroundColor: candidateData.isNotEmpty
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : Colors.transparent,
          collapsedBackgroundColor: candidateData.isNotEmpty
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : Colors.transparent,
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(iconData, color: color, size: 22),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              PopupMenuButton(
                icon: const Icon(Icons.more_vert_rounded),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_note_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('تعديل المجلد'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                        SizedBox(width: 8),
                        Text('حذف المجلد', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                onSelected: (val) {
                  if (val == 'delete') {
                    ref
                        .read(chatFoldersProvider.notifier)
                        .deleteFolder(folder.id);
                  } else if (val == 'edit') {
                    showCreateOrEditChatFolderDialog(
                      context,
                      existingFolder: folder,
                      availableConversations: conversations,
                      currentUserId: currentUserId,
                    );
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

class ChatFolderDropZone extends ConsumerWidget {
  const ChatFolderDropZone({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return DragTarget<ChatConversation>(
      onAcceptWithDetails: (details) => ref
          .read(chatFoldersProvider.notifier)
          .removeConversationFromAllFolders(details.data.id),
      builder: (context, candidateData, rejectedData) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: candidateData.isNotEmpty
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.drive_file_move_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              'اسحب محادثة هنا لإخراجها من المجلد',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
