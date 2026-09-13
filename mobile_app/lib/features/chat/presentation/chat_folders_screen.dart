import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_models.dart';
import '../providers/chat_folders_provider.dart';

class ChatFoldersScreen extends ConsumerWidget {
  const ChatFoldersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatFoldersProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: const Text('المجلدات'),
          backgroundColor: bgColor,
          scrolledUnderElevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showFolderDialog(context, ref),
            ),
          ],
        ),
        body: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text(err.toString())),
          data: (folders) {
            if (folders.isEmpty) {
              return const Center(child: Text('لا توجد مجلدات حالياً'));
            }
            return ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: folders.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex -= 1;
                final list = List<ChatFolder>.from(folders);
                final item = list.removeAt(oldIndex);
                list.insert(newIndex, item);
                final ids = list.map((e) => e.id).toList();
                ref.read(chatFoldersProvider.notifier).reorderFolders(ids);
              },
              itemBuilder: (context, index) {
                final folder = folders[index];
                return ListTile(
                  key: ValueKey(folder.id),
                  leading: Icon(
                    _getIconData(folder.icon) ?? Icons.folder,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(folder.name),
                  subtitle: Text('${folder.conversationIds.length} محادثة'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _showFolderDialog(context, ref, folder: folder),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                        onPressed: () => _confirmDelete(context, ref, folder),
                      ),
                      const Icon(Icons.drag_handle),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  IconData? _getIconData(String? iconStr) {
    if (iconStr == null || iconStr.isEmpty) return null;
    return Icons.folder;
  }

  void _showFolderDialog(BuildContext context, WidgetRef ref, {ChatFolder? folder}) {
    final nameCtrl = TextEditingController(text: folder?.name);
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(folder == null ? 'إنشاء مجلد' : 'تعديل مجلد'),
          content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'اسم المجلد'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final text = nameCtrl.text.trim();
                if (text.isEmpty) return;
                if (folder == null) {
                  ref.read(chatFoldersProvider.notifier).createFolder(text);
                } else {
                  ref.read(chatFoldersProvider.notifier).updateFolder(folder.id, name: text);
                }
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, ChatFolder folder) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف المجلد'),
          content: Text('هل أنت متأكد من حذف المجلد "${folder.name}"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                ref.read(chatFoldersProvider.notifier).deleteFolder(folder.id);
                Navigator.pop(ctx);
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
  }
}
