import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/providers/providers.dart';
import '../models/chat_models.dart';

class FavoriteMessageSelectionResult {
  final ChatConversation conversation;
  final String targetMessageId;

  const FavoriteMessageSelectionResult({
    required this.conversation,
    required this.targetMessageId,
  });
}

enum _FavoriteFilter {
  all,
  text,
  media,
  files,
  polls,
  audio,
}

class FavoriteMessagesScreen extends ConsumerStatefulWidget {
  const FavoriteMessagesScreen({super.key});

  @override
  ConsumerState<FavoriteMessagesScreen> createState() =>
      _FavoriteMessagesScreenState();
}

class _FavoriteMessagesScreenState
    extends ConsumerState<FavoriteMessagesScreen> {
  final List<ChatFavoriteMessageEntry> _items = <ChatFavoriteMessageEntry>[];
  final TextEditingController _searchController = TextEditingController();

  _FavoriteFilter _activeFilter = _FavoriteFilter.all;
  String _searchQuery = '';
  String? _nextCursor;
  bool _hasMore = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      ).showSnackBar(SnackBar(content: Text('فشل تحميل الرسائل المفضلة: $error')));
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
      ).showSnackBar(SnackBar(content: Text('فشل تحميل المزيد: $error')));
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

  List<ChatFavoriteMessageEntry> get _filteredItems {
    return _items.where((entry) {
      final msg = entry.message;
      final conv = entry.conversation;
      final currentUserId = ref.read(authControllerProvider).valueOrNull?.id ?? '';

      // Type filter
      switch (_activeFilter) {
        case _FavoriteFilter.all:
          break;
        case _FavoriteFilter.text:
          if (msg.hasAttachment || msg.isPollMessage || msg.isAudioMessage) {
            return false;
          }
          break;
        case _FavoriteFilter.media:
          if (!msg.isImageMessage && !msg.isGifMessage) {
            return false;
          }
          break;
        case _FavoriteFilter.files:
          if (!msg.hasAttachment || msg.isImageMessage || msg.isGifMessage || msg.isAudioMessage) {
            return false;
          }
          break;
        case _FavoriteFilter.polls:
          if (!msg.isPollMessage) {
            return false;
          }
          break;
        case _FavoriteFilter.audio:
          if (!msg.isAudioMessage) {
            return false;
          }
          break;
      }

      // Search query filter
      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.trim().toLowerCase();
        final contentMatch = msg.content.toLowerCase().contains(query);
        final fileMatch = msg.fileName?.toLowerCase().contains(query) ?? false;
        final senderMatch = (msg.sender?.displayName ?? '').toLowerCase().contains(query);
        final convMatch = conv.displayTitle(currentUserId).toLowerCase().contains(query);

        if (!contentMatch && !fileMatch && !senderMatch && !convMatch) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  IconData _messageTypeIcon(ChatMessage message) {
    if (message.isPollMessage) {
      return (message.metadata?['isChecklist'] == true || message.messageType == 'checklist')
          ? Icons.checklist_rounded
          : Icons.poll_rounded;
    }
    if (message.isAudioMessage) return Icons.graphic_eq_rounded;
    if (message.isImageMessage || message.isGifMessage) return Icons.image_rounded;
    if (message.hasAttachment) return Icons.insert_drive_file_rounded;
    return Icons.chat_bubble_outline_rounded;
  }

  Color _messageTypeColor(ChatMessage message) {
    if (message.isPollMessage) {
      return (message.metadata?['isChecklist'] == true || message.messageType == 'checklist')
          ? const Color(0xFF10B981)
          : const Color(0xFF6366F1);
    }
    if (message.isAudioMessage) return const Color(0xFF0D9488);
    if (message.isImageMessage || message.isGifMessage) return const Color(0xFF0284C7);
    if (message.hasAttachment) return const Color(0xFFD97706);
    return const Color(0xFF4F46E5);
  }

  String _messagePreview(ChatMessage message) {
    if (message.content.trim().isNotEmpty) {
      return message.content.trim();
    }
    if (message.fileName?.trim().isNotEmpty == true) {
      return message.fileName!.trim();
    }
    if (message.isPollMessage) {
      final question = message.metadata?['question']?.toString() ??
          (message.metadata?['poll'] is Map ? message.metadata!['poll']['question']?.toString() : null);
      if (question != null && question.trim().isNotEmpty) {
        return question.trim();
      }
      return (message.metadata?['isChecklist'] == true || message.messageType == 'checklist')
          ? 'قائمة مهام'
          : 'استطلاع رأي';
    }
    return switch (message.messageType) {
      'image' => 'صورة مرفقة',
      'gif' => 'صورة متحركة',
      'pdf' => 'مستند PDF',
      'audio' => 'رسالة صوتية',
      'file' => 'ملف مرفق',
      _ => 'رسالة مفضلة',
    };
  }

  void _onSelectMessage(ChatFavoriteMessageEntry entry) {
    Navigator.of(context).pop(
      FavoriteMessageSelectionResult(
        conversation: entry.conversation,
        targetMessageId: entry.message.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUserId = ref.read(authControllerProvider).valueOrNull?.id ?? '';

    final scaffoldBg = isDark ? const Color(0xFF121214) : const Color(0xFFF4F5F8);
    final surfaceCardColor = isDark ? const Color(0xFF1E1E22) : Colors.white;
    final textHeadingColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textMutedColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final filteredList = _filteredItems;

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: Column(
        children: [
          // ── Apple Desktop Top Header ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
            decoration: BoxDecoration(
              color: surfaceCardColor,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.07),
                  width: 0.8,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      tooltip: 'رجوع للمحادثات',
                      style: IconButton.styleFrom(
                        foregroundColor: textHeadingColor,
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                        padding: const EdgeInsets.all(10),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 14),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFF59E0B),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'الرسائل المفضلة',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: textHeadingColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_items.length} رسالة',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFD97706),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'انقر على أي رسالة للانتقال إليها مباشرة داخل المحادثة',
                            style: TextStyle(
                              fontSize: 12,
                              color: textMutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: 'تحديث المفضلة',
                      style: IconButton.styleFrom(
                        foregroundColor: textMutedColor,
                        hoverColor: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                      onPressed: _loadInitial,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Search Bar + Filter Chips
                Row(
                  children: [
                    // Search input
                    Expanded(
                      flex: 3,
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF28282D)
                              : const Color(0xFFEBECEF),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => setState(() => _searchQuery = val),
                          style: TextStyle(
                            fontSize: 13,
                            color: textHeadingColor,
                          ),
                          decoration: InputDecoration(
                            hintText: 'بحث في الرسائل المفضلة (النص، الراسل، المحادثة)...',
                            hintStyle: TextStyle(
                              fontSize: 12.5,
                              color: textMutedColor.withValues(alpha: 0.8),
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: textMutedColor,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 16),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Filter chips row
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('الكل', _FavoriteFilter.all),
                            const SizedBox(width: 6),
                            _buildFilterChip('نصوص', _FavoriteFilter.text),
                            const SizedBox(width: 6),
                            _buildFilterChip('وسائط', _FavoriteFilter.media),
                            const SizedBox(width: 6),
                            _buildFilterChip('مستندات', _FavoriteFilter.files),
                            const SizedBox(width: 6),
                            _buildFilterChip('استطلاعات ومهام', _FavoriteFilter.polls),
                            const SizedBox(width: 6),
                            _buildFilterChip('صوتيات', _FavoriteFilter.audio),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Body / Messages Feed ─────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? _buildEmptyState(
                    title: 'لا توجد رسائل مفضلة بعد',
                    subtitle: 'يمكنك تمييز أي رسالة بالنقر بالزر الأيمن عليها واختيار "إضافة إلى المفضلة"',
                    icon: Icons.star_outline_rounded,
                  )
                : filteredList.isEmpty
                ? _buildEmptyState(
                    title: 'لا توجد نتائج مطابقة',
                    subtitle: 'لم نجد أي رسائل تطابق معايير البحث أو التصفية الحالية',
                    icon: Icons.search_off_rounded,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    itemCount: filteredList.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= filteredList.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: _isLoadingMore
                                ? const CircularProgressIndicator()
                                : OutlinedButton.icon(
                                    onPressed: _loadMore,
                                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                                    label: const Text('تحميل المزيد من الرسائل المفضلة'),
                                  ),
                          ),
                        );
                      }

                      final entry = filteredList[index];
                      return _FavoriteMessageCard(
                        entry: entry,
                        currentUserId: currentUserId,
                        preview: _messagePreview(entry.message),
                        typeIcon: _messageTypeIcon(entry.message),
                        typeColor: _messageTypeColor(entry.message),
                        onTap: () => _onSelectMessage(entry),
                        onUnfavorite: () => _toggleFavorite(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, _FavoriteFilter filter) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = _activeFilter == filter;

    return InkWell(
      onTap: () => setState(() => _activeFilter = filter),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B)
              : (isDark ? const Color(0xFF28282D) : const Color(0xFFEBECEF)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFD97706)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.15 : 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 40,
              color: const Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteMessageCard extends StatefulWidget {
  final ChatFavoriteMessageEntry entry;
  final String currentUserId;
  final String preview;
  final IconData typeIcon;
  final Color typeColor;
  final VoidCallback onTap;
  final VoidCallback onUnfavorite;

  const _FavoriteMessageCard({
    required this.entry,
    required this.currentUserId,
    required this.preview,
    required this.typeIcon,
    required this.typeColor,
    required this.onTap,
    required this.onUnfavorite,
  });

  @override
  State<_FavoriteMessageCard> createState() => _FavoriteMessageCardState();
}

class _FavoriteMessageCardState extends State<_FavoriteMessageCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final entry = widget.entry;
    final message = entry.message;
    final conv = entry.conversation;

    final senderName = message.sender?.displayName.isNotEmpty == true
        ? message.sender!.displayName
        : (message.senderId == widget.currentUserId ? 'أنت' : 'عضو');

    final surfaceColor = isDark ? const Color(0xFF1E1E22) : Colors.white;
    final textHeadingColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textMutedColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered
                ? theme.colorScheme.primary.withValues(alpha: 0.45)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.06)),
            width: _isHovered ? 1.2 : 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isHovered ? 0.08 : (isDark ? 0.12 : 0.03)),
              blurRadius: _isHovered ? 12 : 6,
              offset: Offset(0, _isHovered ? 3 : 1),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Conversation Badge & Star + Timestamp
                  Row(
                    children: [
                      // Conversation Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF28282D)
                              : const Color(0xFFF1F2F5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              conv.type != 'direct'
                                  ? Icons.groups_rounded
                                  : Icons.person_rounded,
                              size: 14,
                              color: textMutedColor,
                            ),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
                              child: Text(
                                conv.displayTitle(widget.currentUserId),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: textHeadingColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),

                      // Timestamp
                      Text(
                        formatEgyptDateTime(message.createdAt.toLocal()),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: textMutedColor,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Unfavorite button
                      IconButton(
                        icon: const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFF59E0B),
                          size: 22,
                        ),
                        tooltip: 'إزالة من المفضلة',
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(4),
                          minimumSize: Size.zero,
                        ),
                        onPressed: widget.onUnfavorite,
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Middle Row: Type Icon & Content
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: widget.typeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          widget.typeIcon,
                          color: widget.typeColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              senderName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: widget.typeColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.preview,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: textHeadingColor,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Bottom Action Link (Hover Cue)
                  if (_isHovered) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'الانتقال إلى الرسالة في المحادثة',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
