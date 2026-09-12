import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/providers/providers.dart';
import '../models/chat_models.dart';
import 'conversation_screen.dart';

class FavoriteMessagesScreen extends ConsumerStatefulWidget {
  const FavoriteMessagesScreen({super.key});

  @override
  ConsumerState<FavoriteMessagesScreen> createState() =>
      _FavoriteMessagesScreenState();
}

class _FavoriteMessagesScreenState
    extends ConsumerState<FavoriteMessagesScreen> {
  final List<ChatFavoriteMessageEntry> _items = <ChatFavoriteMessageEntry>[];

  String? _nextCursor;
  bool _hasMore = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _items.clear();
      _nextCursor = null;
      _hasMore = false;
    });

    try {
      final page = await ref
          .read(chatRepositoryProvider)
          .fetchFavoriteMessages();
      if (!mounted) {
        return;
      }
      setState(() {
        _items.addAll(page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _nextCursor == null) {
      return;
    }

    setState(() => _isLoadingMore = true);
    try {
      final page = await ref
          .read(chatRepositoryProvider)
          .fetchFavoriteMessages(cursor: _nextCursor);
      if (!mounted) {
        return;
      }
      setState(() {
        _items.addAll(page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoadingMore = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleFavorite(ChatFavoriteMessageEntry entry) async {
    try {
      await ref
          .read(chatRepositoryProvider)
          .toggleFavoriteMessage(messageId: entry.message.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _items.removeWhere((item) => item.message.id == entry.message.id);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openConversation(ChatConversation conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(conversation: conversation),
      ),
    );
  }

  String _messagePreview(ChatMessage message) {
    if (message.content.trim().isNotEmpty) {
      return message.content.trim();
    }
    if (message.fileName?.trim().isNotEmpty == true) {
      return message.fileName!.trim();
    }
    return switch (message.messageType) {
      'image' => 'صورة مفضلة',
      'pdf' => 'ملف PDF مفضل',
      'audio' => 'رسالة صوتية مفضلة',
      'file' => 'ملف مفضل',
      _ => 'رسالة مفضلة',
    };
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        ref.read(authControllerProvider).valueOrNull?.id ?? '';
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('الرسائل المفضلة')),
      body: RefreshIndicator(
        onRefresh: _loadInitial,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Icon(Icons.star_outline_rounded, size: 54),
                  SizedBox(height: 12),
                  Center(child: Text('لا توجد رسائل مفضلة بعد')),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                itemCount: _items.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _items.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: _isLoadingMore
                            ? const CircularProgressIndicator()
                            : OutlinedButton(
                                onPressed: _loadMore,
                                child: const Text('تحميل المزيد'),
                              ),
                      ),
                    );
                  }

                  final entry = _items[index];
                  final message = entry.message;
                  final senderName =
                      message.sender?.displayName.isNotEmpty == true
                      ? message.sender!.displayName
                      : (message.senderId == currentUserId ? 'أنت' : 'عضو');

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(14),
                      onTap: () => _openConversation(entry.conversation),
                      title: Text(
                        entry.conversation.displayTitle(currentUserId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              senderName,
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _messagePreview(message),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              DateFormat(
                                'yyyy/MM/dd - HH:mm',
                              ).format(message.createdAt.toLocal()),
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: 'إزالة من المفضلة',
                        onPressed: () => _toggleFavorite(entry),
                        icon: const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
