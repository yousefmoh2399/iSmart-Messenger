import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/providers/providers.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../models/chat_models.dart';
import 'chat_avatar.dart';

enum SearchCategoryFilter {
  all('الكل', Icons.all_inclusive_rounded),
  text('نصوص', Icons.notes_rounded),
  files('مستندات', Icons.insert_drive_file_outlined),
  media('وسائط', Icons.photo_library_outlined),
  polls('استطلاعات', Icons.poll_outlined);

  final String label;
  final IconData icon;
  const SearchCategoryFilter(this.label, this.icon);
}

class ChatRemoteSearchSheet extends ConsumerStatefulWidget {
  const ChatRemoteSearchSheet({
    super.key,
    required this.conversationId,
    this.initialQuery,
    required this.onSelectMessage,
  });

  final String conversationId;
  final String? initialQuery;
  final ValueChanged<ChatMessage> onSelectMessage;

  @override
  ConsumerState<ChatRemoteSearchSheet> createState() =>
      _ChatRemoteSearchSheetState();
}

class _ChatRemoteSearchSheetState
    extends ConsumerState<ChatRemoteSearchSheet> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  List<ChatMessage> _results = const <ChatMessage>[];
  bool _isLoading = false;
  String? _errorText;
  String? _lastSearchedQuery;
  SearchCategoryFilter _selectedFilter = SearchCategoryFilter.all;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _focusNode = FocusNode();

    if (_controller.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runSearch();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const <ChatMessage>[];
        _errorText = null;
        _lastSearchedQuery = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
      _lastSearchedQuery = query;
    });

    try {
      final notifier = ref.read(
        conversationMessagesControllerProvider(widget.conversationId).notifier,
      );
      final result = await notifier.searchMessages(query);
      if (!mounted) return;
      setState(() {
        _results = result.messages;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<ChatMessage> _getFilteredResults() {
    switch (_selectedFilter) {
      case SearchCategoryFilter.all:
        return _results;
      case SearchCategoryFilter.text:
        return _results.where((m) {
          final isPoll = m.messageType == 'poll' || m.metadata?['poll'] != null;
          final isMediaOrFile = m.fileUrl != null ||
              m.messageType == 'file' ||
              m.messageType == 'image' ||
              m.messageType == 'video' ||
              m.messageType == 'audio' ||
              m.isAudioMessage;
          return !isPoll && !isMediaOrFile;
        }).toList();
      case SearchCategoryFilter.files:
        return _results.where((m) {
          final isMedia = m.messageType == 'image' ||
              m.messageType == 'video' ||
              m.messageType == 'audio' ||
              m.isAudioMessage;
          return !isMedia && (m.messageType == 'file' || m.fileName != null);
        }).toList();
      case SearchCategoryFilter.media:
        return _results.where((m) {
          return m.messageType == 'image' ||
              m.messageType == 'video' ||
              m.messageType == 'audio' ||
              m.isAudioMessage;
        }).toList();
      case SearchCategoryFilter.polls:
        return _results.where((m) {
          return m.messageType == 'poll' || m.metadata?['poll'] != null;
        }).toList();
    }
  }

  int _countForFilter(SearchCategoryFilter filter) {
    switch (filter) {
      case SearchCategoryFilter.all:
        return _results.length;
      case SearchCategoryFilter.text:
        return _results.where((m) {
          final isPoll = m.messageType == 'poll' || m.metadata?['poll'] != null;
          final isMediaOrFile = m.fileUrl != null ||
              m.messageType == 'file' ||
              m.messageType == 'image' ||
              m.messageType == 'video' ||
              m.messageType == 'audio' ||
              m.isAudioMessage;
          return !isPoll && !isMediaOrFile;
        }).length;
      case SearchCategoryFilter.files:
        return _results.where((m) {
          final isMedia = m.messageType == 'image' ||
              m.messageType == 'video' ||
              m.messageType == 'audio' ||
              m.isAudioMessage;
          return !isMedia && (m.messageType == 'file' || m.fileName != null);
        }).length;
      case SearchCategoryFilter.media:
        return _results.where((m) {
          return m.messageType == 'image' ||
              m.messageType == 'video' ||
              m.messageType == 'audio' ||
              m.isAudioMessage;
        }).length;
      case SearchCategoryFilter.polls:
        return _results.where((m) {
          return m.messageType == 'poll' || m.metadata?['poll'] != null;
        }).length;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryAccent = const Color(0xFF007AFF);
    final sheetBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final surfaceVariant = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final textPrimary = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final filteredResults = _getFilteredResults();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // ── Drag Handle ──────────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),

            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: primaryAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.travel_explore_rounded,
                      color: primaryAccent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'البحث في كل رسائل المحادثة',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'بحث سحابي شامل في الرسائل والمستندات',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    splashRadius: 18,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),

            // ── Search Field Bar ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: surfaceVariant,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: isDark ? const Color(0xFF383840) : const Color(0xFFE2E8F0),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(
                      Icons.search_rounded,
                      color: primaryAccent,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _runSearch(),
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'ابحث عن نص، اسم ملف، رابط...',
                          hintStyle: TextStyle(
                            color: textSecondary.withValues(alpha: 0.75),
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_controller.text.isNotEmpty)
                      IconButton(
                        splashRadius: 16,
                        iconSize: 17,
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _results = const <ChatMessage>[];
                            _lastSearchedQuery = null;
                          });
                        },
                        icon: Icon(
                          Icons.cancel_rounded,
                          color: textSecondary.withValues(alpha: 0.8),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 6, right: 6),
                      child: InkWell(
                        onTap: _isLoading ? null : _runSearch,
                        borderRadius: BorderRadius.circular(9),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: primaryAccent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isLoading)
                                const SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              else ...[
                                const Icon(
                                  Icons.arrow_back_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 3),
                                const Text(
                                  'بحث',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Filter Chips ──────────────────────────────────────────────
            if (_results.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: SearchCategoryFilter.values.map((filter) {
                      final isSelected = _selectedFilter == filter;
                      final count = _countForFilter(filter);
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedFilter = filter;
                            });
                          },
                          borderRadius: BorderRadius.circular(9),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? primaryAccent
                                  : (isDark ? const Color(0xFF2A2A30) : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: isSelected
                                    ? primaryAccent
                                    : (isDark ? const Color(0xFF383840) : const Color(0xFFE2E8F0)),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  filter.icon,
                                  size: 13,
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${filter.label} ($count)',
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

            // ── Results Summary Bar ────────────────────────────────────────
            if (_results.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: primaryAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'تم العثور على ${filteredResults.length} نتيجة',
                        style: TextStyle(
                          color: primaryAccent,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'اضغط على الرسالة للانتقال إليها',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 6),

            // ── Body / List View ──────────────────────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppLoadingIndicator(size: 28),
                          SizedBox(height: 10),
                          Text(
                            'جارٍ البحث في السيرفر...',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : _errorText != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 34,
                              color: Color(0xFFEF4444),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'حدث خطأ أثناء البحث',
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _errorText!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _runSearch,
                              icon: const Icon(Icons.refresh_rounded, size: 15),
                              label: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: surfaceVariant,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _lastSearchedQuery != null
                                    ? Icons.search_off_rounded
                                    : Icons.travel_explore_rounded,
                                size: 28,
                                color: textSecondary.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _lastSearchedQuery != null
                                  ? 'لا توجد نتائج مطابقة لـ «$_lastSearchedQuery»'
                                  : 'البحث الشامل في المحادثة',
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _lastSearchedQuery != null
                                  ? 'تأكد من كتابة الكلمة بشكل صحيح أو جرّب كلمات أخرى.'
                                  : 'اكتب كلمة للبحث في كل الرسائل والمستندات القديمة والجديدة.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : filteredResults.isEmpty
                  ? Center(
                      child: Text(
                        'لا توجد نتائج في هذا القسم.',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filteredResults.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final message = filteredResults[index];
                        final senderName =
                            message.sender?.displayName.isNotEmpty == true
                                ? message.sender!.displayName
                                : 'مستخدم';
                        final preview = message.content.trim().isNotEmpty
                            ? message.content
                            : (message.fileName ?? 'مرفق');

                        final isFile = message.messageType == 'file' ||
                            (message.fileName != null &&
                                message.messageType != 'image' &&
                                message.messageType != 'video' &&
                                message.messageType != 'audio');
                        final isImage = message.messageType == 'image';
                        final isAudio = message.isAudioMessage || message.messageType == 'audio';
                        final isPoll = message.messageType == 'poll' || message.metadata?['poll'] != null;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              widget.onSelectMessage(message);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF242428) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF323238) : const Color(0xFFE2E8F0),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ChatAvatar(
                                    avatarUrl: message.sender?.avatarUrl,
                                    radius: 16,
                                    backgroundColor: isDark
                                        ? const Color(0xFF383842)
                                        : const Color(0xFFE2E8F0),
                                    fallback: Text(
                                      senderName.isNotEmpty ? senderName[0] : '?',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                senderName,
                                                style: TextStyle(
                                                  color: textPrimary,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isFile) ...[
                                              _buildTypeBadge(
                                                'مستند',
                                                const Color(0xFFF59E0B),
                                                isDark,
                                              ),
                                              const SizedBox(width: 5),
                                            ] else if (isImage) ...[
                                              _buildTypeBadge(
                                                'صورة',
                                                const Color(0xFF8B5CF6),
                                                isDark,
                                              ),
                                              const SizedBox(width: 5),
                                            ] else if (isAudio) ...[
                                              _buildTypeBadge(
                                                'صوت',
                                                const Color(0xFF06B6D4),
                                                isDark,
                                              ),
                                              const SizedBox(width: 5),
                                            ] else if (isPoll) ...[
                                              _buildTypeBadge(
                                                'استطلاع',
                                                const Color(0xFF10B981),
                                                isDark,
                                              ),
                                              const SizedBox(width: 5),
                                            ],
                                            Text(
                                              formatEgyptDateTime(
                                                message.createdAt,
                                                datePattern: 'dd/MM',
                                                separator: ' • ',
                                              ),
                                              style: TextStyle(
                                                color: textSecondary,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          preview,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                                            fontSize: 12,
                                            height: 1.35,
                                          ),
                                        ),
                                        if (isFile && message.fileSize != null) ...[
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.attachment_rounded,
                                                size: 12,
                                                color: textSecondary,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                formatFileSize(message.fileSize!),
                                                style: TextStyle(
                                                  color: textSecondary,
                                                  fontSize: 10.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 12,
                                      color: textSecondary.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.4 : 0.25),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
