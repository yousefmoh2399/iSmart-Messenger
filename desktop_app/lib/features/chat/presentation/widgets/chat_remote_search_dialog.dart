import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/providers/providers.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/safe_network_avatar.dart';
import '../../models/chat_models.dart';

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

class ChatRemoteSearchDialog extends ConsumerStatefulWidget {
  const ChatRemoteSearchDialog({
    super.key,
    required this.conversationId,
    this.initialQuery,
    required this.onSelectMessage,
  });

  final String conversationId;
  final String? initialQuery;
  final ValueChanged<ChatMessage> onSelectMessage;

  @override
  ConsumerState<ChatRemoteSearchDialog> createState() =>
      _ChatRemoteSearchDialogState();
}

class _ChatRemoteSearchDialogState
    extends ConsumerState<ChatRemoteSearchDialog> {
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryAccent = const Color(0xFF007AFF);
    final dialogBg = isDark ? const Color(0xFF1E1E22) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2E2E34) : const Color(0xFFE2E8F0);
    final surfaceVariant = isDark ? const Color(0xFF28282E) : const Color(0xFFF1F5F9);
    final textPrimary = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final filteredResults = _getFilteredResults();

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: Container(
          width: 620,
          height: 600,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: dialogBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                blurRadius: 36,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: primaryAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.travel_explore_rounded,
                        color: primaryAccent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'البحث في كل رسائل المحادثة',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'البحث السحابي في جميع الرسائل والمستندات والوسائط القديمة',
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, thickness: 1),

              // ── Search Field Bar ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? const Color(0xFF383840) : const Color(0xFFE2E8F0),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(
                        Icons.search_rounded,
                        color: primaryAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: 'ابحث عن نص، اسم ملف، رابط...',
                            hintStyle: TextStyle(
                              color: textSecondary.withValues(alpha: 0.75),
                              fontSize: 13.5,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_controller.text.isNotEmpty)
                        IconButton(
                          splashRadius: 18,
                          iconSize: 18,
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
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 6, right: 6),
                        child: InkWell(
                          onTap: _isLoading ? null : _runSearch,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: primaryAccent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isLoading)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                else ...[
                                  const Icon(
                                    Icons.arrow_back_rounded,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'بحث',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primaryAccent
                                    : (isDark ? const Color(0xFF2A2A30) : const Color(0xFFF1F5F9)),
                                borderRadius: BorderRadius.circular(10),
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
                                    size: 14,
                                    color: isSelected
                                        ? Colors.white
                                        : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${filter.label} ($count)',
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                                      fontSize: 11.5,
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
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: primaryAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'تم العثور على ${filteredResults.length} نتيجة',
                          style: TextStyle(
                            color: primaryAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'اضغط على أي رسالة للانتقال إليها في المحادثة',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Body / List View ──────────────────────────────────────────
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppLoadingIndicator(size: 32),
                            SizedBox(height: 12),
                            Text(
                              'جارٍ البحث في السيرفر...',
                              style: TextStyle(fontSize: 12.5),
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
                                size: 36,
                                color: Color(0xFFEF4444),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'حدث خطأ أثناء البحث',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _errorText!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _runSearch,
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: surfaceVariant,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _lastSearchedQuery != null
                                      ? Icons.search_off_rounded
                                      : Icons.travel_explore_rounded,
                                  size: 30,
                                  color: textSecondary.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _lastSearchedQuery != null
                                    ? 'لا توجد نتائج مطابقة لـ «$_lastSearchedQuery»'
                                    : 'البحث الشامل في المحادثة',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _lastSearchedQuery != null
                                    ? 'تأكد من كتابة الكلمة بشكل صحيح، أو جرّب البحث بكلمة أخرى.'
                                    : 'اكتب كلمة أو عبارة للبحث في الرسائل، النصوص، الملفات والمستندات السحابية.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 12,
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
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
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
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF25252B) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF32323A) : const Color(0xFFE2E8F0),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SafeNetworkAvatar(
                                      imageUrl: message.sender?.avatarUrl,
                                      radius: 17,
                                      backgroundColor: isDark
                                          ? const Color(0xFF383842)
                                          : const Color(0xFFE2E8F0),
                                      fallbackText: senderName,
                                    ),
                                    const SizedBox(width: 12),
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
                                                    fontSize: 13,
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
                                                const SizedBox(width: 6),
                                              ] else if (isImage) ...[
                                                _buildTypeBadge(
                                                  'صورة',
                                                  const Color(0xFF8B5CF6),
                                                  isDark,
                                                ),
                                                const SizedBox(width: 6),
                                              ] else if (isAudio) ...[
                                                _buildTypeBadge(
                                                  'صوت',
                                                  const Color(0xFF06B6D4),
                                                  isDark,
                                                ),
                                                const SizedBox(width: 6),
                                              ] else if (isPoll) ...[
                                                _buildTypeBadge(
                                                  'استطلاع',
                                                  const Color(0xFF10B981),
                                                  isDark,
                                                ),
                                                const SizedBox(width: 6),
                                              ],
                                              Text(
                                                DateFormat(
                                                  'dd/MM • HH:mm',
                                                ).format(message.createdAt.toLocal()),
                                                style: TextStyle(
                                                  color: textSecondary,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            preview,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                                              fontSize: 12.5,
                                              height: 1.35,
                                            ),
                                          ),
                                          if (isFile && message.fileSize != null) ...[
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.attachment_rounded,
                                                  size: 13,
                                                  color: textSecondary,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _formatFileSize(message.fileSize!),
                                                  style: TextStyle(
                                                    color: textSecondary,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 13,
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
      ),
    );
  }

  Widget _buildTypeBadge(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.4 : 0.25),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
