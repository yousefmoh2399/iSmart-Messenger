import 'package:flutter/cupertino.dart';
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

  Future<void> _openConversation(ChatFavoriteMessageEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          conversation: entry.conversation,
          initialTargetMessage: entry.message,
        ),
      ),
    );
  }

  IconData _messageTypeIcon(ChatMessage message) {
    if (message.isPollMessage) return CupertinoIcons.chart_bar_fill;
    if (message.isAudioMessage) return CupertinoIcons.waveform;
    if (message.isImageMessage) return CupertinoIcons.photo_fill;
    if (message.hasAttachment) return CupertinoIcons.doc_fill;
    return CupertinoIcons.chat_bubble_text_fill;
  }

  String _messagePreview(ChatMessage message) {
    if (message.content.trim().isNotEmpty) {
      return message.content.trim();
    }
    if (message.fileName?.trim().isNotEmpty == true) {
      return message.fileName!.trim();
    }
    return switch (message.messageType) {
      'image' => 'صورة مرفقة',
      'pdf' => 'مستند PDF',
      'audio' => 'رسالة صوتية',
      'file' => 'ملف مرفق',
      _ => 'رسالة',
    };
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        ref.read(authControllerProvider).valueOrNull?.id ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Scaffold(
        backgroundColor: scaffoldBg,
        appBar: AppBar(
          title: const Text('الرسائل المفضلة', style: TextStyle(fontWeight: FontWeight.w700)),
          backgroundColor: scaffoldBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  tooltip: 'رجوع',
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
        ),
        body: RefreshIndicator(
          onRefresh: _loadInitial,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 140),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.15 : 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.star_fill,
                          size: 52,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Center(
                      child: Text(
                        'لا توجد رسائل مفضلة بعد',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'يمكنك تمييز أي رسالة بالضغط المطوّل عليها واختيار "إضافة إلى المفضلة"',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white54 : const Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
                  itemCount: _items.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _items.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: _isLoadingMore
                              ? const CircularProgressIndicator()
                              : TextButton.icon(
                                  onPressed: _loadMore,
                                  icon: const Icon(Icons.expand_more_rounded, size: 18),
                                  label: const Text('تحميل المزيد من الرسائل'),
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

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                            width: 0.5,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _openConversation(entry),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top row: Conversation badge + star action
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? const Color(0xFF2C2C2E)
                                              : const Color(0xFFE5E5EA),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              CupertinoIcons.chat_bubble_2_fill,
                                              size: 13,
                                              color: isDark ? Colors.white70 : const Color(0xFF6E6E73),
                                            ),
                                            const SizedBox(width: 5),
                                            ConstrainedBox(
                                              constraints: const BoxConstraints(maxWidth: 200),
                                              child: Text(
                                                entry.conversation.displayTitle(currentUserId),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: () => _toggleFavorite(entry),
                                        behavior: HitTestBehavior.opaque,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          child: const Icon(
                                            Icons.star_rounded,
                                            size: 22,
                                            color: Color(0xFFF59E0B),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  // Middle row: Message sender & icon + preview
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(top: 2),
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF007AFF).withValues(alpha: isDark ? 0.2 : 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          _messageTypeIcon(message),
                                          size: 15,
                                          color: const Color(0xFF007AFF),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              senderName,
                                              style: const TextStyle(
                                                color: Color(0xFF007AFF),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              _messagePreview(message),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14,
                                                height: 1.4,
                                                color: isDark ? Colors.white : Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 10),
                                  // Bottom row: Timestamp + jump hint
                                  Row(
                                    children: [
                                      Text(
                                        DateFormat('yyyy/MM/dd - HH:mm').format(message.createdAt.toLocal()),
                                        style: TextStyle(
                                          color: isDark ? Colors.white38 : const Color(0xFF8E8E93),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const Spacer(),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'الانتقال للرسالة',
                                            style: TextStyle(
                                              color: isDark ? Colors.white54 : const Color(0xFF6E6E73),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 2),
                                          Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 10,
                                            color: isDark ? Colors.white38 : const Color(0xFF8E8E93),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
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
