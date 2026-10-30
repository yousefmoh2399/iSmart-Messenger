import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/providers.dart';
import '../../../../shared/services/android_share_receiver.dart';
import '../../models/chat_models.dart';
import 'chat_avatar.dart';

enum ShareTargetKind {
  savedMessages,
  conversation,
  user,
}

class ShareTarget {
  const ShareTarget({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle,
    this.avatarUrl,
    this.isOnline = false,
    this.isGroup = false,
    this.isSelf = false,
    this.conversation,
    this.user,
  });

  final String id;
  final ShareTargetKind kind;
  final String title;
  final String? subtitle;
  final String? avatarUrl;
  final bool isOnline;
  final bool isGroup;
  final bool isSelf;
  final ChatConversation? conversation;
  final ChatDirectoryUser? user;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShareTarget && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class ShareTargetPickerSheet extends ConsumerStatefulWidget {
  const ShareTargetPickerSheet({
    super.key,
    required this.content,
    required this.currentUserId,
  });

  final AndroidSharedContent content;
  final String currentUserId;

  static Future<List<ChatConversation>?> show(
    BuildContext context, {
    required AndroidSharedContent content,
    required String currentUserId,
  }) {
    return showModalBottomSheet<List<ChatConversation>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (_) => ShareTargetPickerSheet(
        content: content,
        currentUserId: currentUserId,
      ),
    );
  }

  @override
  ConsumerState<ShareTargetPickerSheet> createState() =>
      _ShareTargetPickerSheetState();
}

class _ShareTargetPickerSheetState
    extends ConsumerState<ShareTargetPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  late final TextEditingController _captionController;
  final Map<String, ShareTarget> _selectedTargets = <String, ShareTarget>{};

  String _searchQuery = '';
  bool _isSending = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _captionController =
        TextEditingController(text: widget.content.text.trim());
    // Eagerly load all pages of directory users in background if not already loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(chatOverviewControllerProvider.notifier).ensureAllUsersLoaded();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  bool _isImage(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'].contains(ext);
  }

  bool _isSelected(String id) => _selectedTargets.containsKey(id);

  void _toggleTarget(ShareTarget target) {
    if (_isSending) return;
    setState(() {
      if (_isSelected(target.id)) {
        _selectedTargets.remove(target.id);
      } else {
        _selectedTargets[target.id] = target;
      }
    });
  }

  void _unselectTarget(String id) {
    if (_isSending) return;
    setState(() {
      _selectedTargets.remove(id);
    });
  }

  void _clearAllSelections() {
    if (_isSending) return;
    setState(() {
      _selectedTargets.clear();
    });
  }

  Future<void> _handleSend(ChatOverviewData overview) async {
    if (_selectedTargets.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
      _statusMessage = 'جاري تحضير المشاركة...';
    });

    final caption = _captionController.text.trim();
    final resolvedConversations = <ChatConversation>[];
    final total = _selectedTargets.length;
    var currentIdx = 0;

    try {
      for (final target in _selectedTargets.values) {
        currentIdx++;
        if (mounted) {
          setState(() {
            _statusMessage = 'جاري الإرسال ($currentIdx/$total): ${target.title}';
          });
        }

        ChatConversation? targetConv;

        if (target.kind == ShareTargetKind.savedMessages) {
          targetConv = await ref
              .read(chatOverviewControllerProvider.notifier)
              .openOrCreateSavedMessages(widget.currentUserId);
        } else if (target.kind == ShareTargetKind.conversation &&
            target.conversation != null) {
          targetConv = target.conversation;
        } else if (target.kind == ShareTargetKind.user && target.user != null) {
          // Check if direct conversation already exists
          final existing = overview.conversations.where((c) {
            return c.type == 'direct' &&
                c.members.any((m) => m.id == target.user!.id);
          }).firstOrNull;

          if (existing != null) {
            targetConv = existing;
          } else {
            targetConv = await ref
                .read(chatOverviewControllerProvider.notifier)
                .createDirectConversation(target.user!.id);
          }
        }

        if (targetConv != null) {
          resolvedConversations.add(targetConv);
          await _sendContentToConversation(targetConv, caption);
        }
      }

      if (mounted) {
        Navigator.of(context).pop(resolvedConversations);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _statusMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء المشاركة: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _sendContentToConversation(
    ChatConversation conversation,
    String caption,
  ) async {
    final controller = ref.read(
      conversationMessagesControllerProvider(conversation.id).notifier,
    );
    final paths = widget.content.paths;
    final mediaGroupId = paths.length > 1
        ? 'album_${DateTime.now().microsecondsSinceEpoch}'
        : null;

    if (caption.isNotEmpty) {
      await controller.sendMessage(content: caption);
    }

    for (final path in paths) {
      await controller.sendFile(
        path,
        metadata: mediaGroupId == null
            ? null
            : {
                'mediaGroupId': mediaGroupId,
                'mediaGroupSize': paths.length,
              },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final sheetBgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final searchBgColor =
        isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final borderColor =
        isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
    const whatsappGreen = Color(0xFF25D366);

    final overview = ref.watch(chatOverviewControllerProvider).valueOrNull;

    if (overview == null) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          decoration: BoxDecoration(
            color: sheetBgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(32),
          child: const Center(
            child: CircularProgressIndicator.adaptive(),
          ),
        ),
      );
    }

    // 1. Build Departments dictionary
    final departmentsById = <String, DepartmentSummary>{
      for (final d in overview.departments) d.id: d,
    };

    // 2. Saved Messages target
    final savedMessagesTarget = ShareTarget(
      id: '__saved_messages__',
      kind: ShareTargetKind.savedMessages,
      title: 'الرسائل المحفوظة (أنت)',
      subtitle: 'مساحتك السحابية لحفظ الملاحظات والصور',
      isSelf: true,
    );

    // 3. Recent conversations targets (excluding self chat which is pinned)
    final recentConversationTargets = overview.conversations
        .where((c) => !c.isSelfChat(widget.currentUserId))
        .map((conv) {
          final isGroup = conv.type == 'group' || conv.type == 'broadcast';
          String? avatarUrl;
          if (conv.type == 'direct') {
            final other = conv.members
                .where((m) => m.id != widget.currentUserId)
                .firstOrNull;
            avatarUrl = other?.avatarUrl;
          } else {
            avatarUrl = conv.avatarUrl;
          }

          String subtitle;
          if (isGroup) {
            subtitle = conv.description.trim().isNotEmpty
                ? conv.description.trim()
                : '${conv.members.length} أعضاء';
          } else {
            final last = conv.lastMessage;
            if (last == null) {
              subtitle = 'محادثة مباشرة';
            } else if (last.messageType == 'image') {
              subtitle = '🖼️ صورة';
            } else if (last.messageType == 'file') {
              subtitle = '📎 مرفق';
            } else {
              final t = last.content.trim();
              subtitle = t.isEmpty ? '...' : t;
            }
          }

          return ShareTarget(
            id: 'conv_${conv.id}',
            kind: ShareTargetKind.conversation,
            title: conv.displayTitle(widget.currentUserId),
            subtitle: subtitle,
            avatarUrl: avatarUrl,
            isGroup: isGroup,
            conversation: conv,
          );
        })
        .toList();

    // 4. All Directory Users targets (all corporate employees)
    final seenUserIds = <String>{};
    final directoryUserTargets = overview.users
        .where((u) => u.id != widget.currentUserId && seenUserIds.add(u.id))
        .map((u) {
          final deptName = departmentsById[u.departmentId]?.name ?? '';
          final parts = <String>[];
          if (u.jobTitle.trim().isNotEmpty) parts.add(u.jobTitle.trim());
          if (deptName.isNotEmpty) parts.add(deptName);
          if (parts.isEmpty && u.branchCode.isNotEmpty) {
            parts.add('فرع ${u.branchCode}');
          }
          final subtitle =
              parts.isEmpty ? '@${u.username}' : parts.join(' • ');

          return ShareTarget(
            id: 'user_${u.id}',
            kind: ShareTargetKind.user,
            title: u.displayName,
            subtitle: subtitle,
            avatarUrl: u.avatarUrl,
            isOnline: u.isOnline,
            user: u,
          );
        })
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    // 5. Search Filtering
    final q = _searchQuery.trim().toLowerCase();
    final bool isSearching = q.isNotEmpty;

    final bool showSavedMessages = !isSearching ||
        'الرسائل المحفوظة'.contains(q) ||
        'ملاحظات'.contains(q) ||
        'أنت'.contains(q);

    final filteredConversations = !isSearching
        ? recentConversationTargets
        : recentConversationTargets.where((t) {
            return t.title.toLowerCase().contains(q) ||
                (t.subtitle?.toLowerCase().contains(q) ?? false);
          }).toList();

    final filteredUsers = !isSearching
        ? directoryUserTargets
        : directoryUserTargets.where((t) {
            final u = t.user!;
            final deptName =
                (departmentsById[u.departmentId]?.name ?? '').toLowerCase();
            return t.title.toLowerCase().contains(q) ||
                u.username.toLowerCase().contains(q) ||
                u.jobTitle.toLowerCase().contains(q) ||
                u.branchCode.toLowerCase().contains(q) ||
                deptName.contains(q);
          }).toList();

    final paths = widget.content.paths;
    final hasPaths = paths.isNotEmpty;
    final allImages = hasPaths && paths.every(_isImage);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(
          color: sheetBgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.94,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // ── Drag Handle ──────────────────────────────────────────────
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),

                // ── Top Header ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: whatsappGreen.withOpacity(0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          color: whatsappGreen,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'إرسال إلى...',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _selectedTargets.isEmpty
                                  ? 'اختر جهة اتصال أو أكثر للمشاركة'
                                  : 'تم تحديد ${_selectedTargets.length} وجهة',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: _selectedTargets.isEmpty
                                    ? (isDark ? Colors.white60 : Colors.black54)
                                    : whatsappGreen,
                                fontWeight: _selectedTargets.isEmpty
                                    ? FontWeight.normal
                                    : FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22),
                        onPressed: _isSending
                            ? null
                            : () => Navigator.of(context).pop(null),
                        tooltip: 'إلغاء',
                      ),
                    ],
                  ),
                ),

                // ── Media Preview & Caption Section ──────────────────────────
                if (hasPaths) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildMediaPreview(paths, allImages, isDark),
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Optional Caption Field ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _captionController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: searchBgColor,
                        hintText: 'إضافة شرح أو تعليق (اختياري)...',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        prefixIcon: Icon(
                          Icons.edit_note_rounded,
                          size: 20,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Search Field ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: searchBgColor,
                        hintText:
                            'ابحث بالاسم، اسم المستخدم، الفرع، أو القسم...',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.cancel_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),

                // ── WhatsApp Selected Targets Chips Strip ────────────────────
                if (_selectedTargets.isNotEmpty) ...[
                  _buildSelectedCarousel(isDark, borderColor),
                  Divider(height: 1, color: borderColor),
                ],

                // ── Targets List View ────────────────────────────────────────
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 90),
                    children: [
                      // 1. Pinned Saved Messages
                      if (showSavedMessages) ...[
                        _buildSectionHeader('الرسائل المحفوظة', isDark),
                        _buildTargetTile(
                          target: savedMessagesTarget,
                          isDark: isDark,
                          colorScheme: colorScheme,
                          whatsappGreen: whatsappGreen,
                        ),
                      ],

                      // 2. Recent Active Chats
                      if (filteredConversations.isNotEmpty) ...[
                        _buildSectionHeader(
                          isSearching ? 'المحادثات المطابقة' : 'المحادثات الأخيرة',
                          isDark,
                          count: filteredConversations.length,
                        ),
                        ...filteredConversations.map(
                          (target) => _buildTargetTile(
                            target: target,
                            isDark: isDark,
                            colorScheme: colorScheme,
                            whatsappGreen: whatsappGreen,
                          ),
                        ),
                      ],

                      // 3. All Directory Users
                      if (filteredUsers.isNotEmpty) ...[
                        _buildSectionHeader(
                          isSearching
                              ? 'الزملاء المطابقون'
                              : 'جهات الاتصال / كافة المستخدمين',
                          isDark,
                          count: filteredUsers.length,
                        ),
                        ...filteredUsers.map(
                          (target) => _buildTargetTile(
                            target: target,
                            isDark: isDark,
                            colorScheme: colorScheme,
                            whatsappGreen: whatsappGreen,
                          ),
                        ),
                      ],

                      // Empty search results
                      if (isSearching &&
                          !showSavedMessages &&
                          filteredConversations.isEmpty &&
                          filteredUsers.isEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 40,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 48,
                                color: isDark ? Colors.white24 : Colors.black26,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'لا توجد نتائج مطابقة لـ "$_searchQuery"',
                                style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      isDark ? Colors.white60 : Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // ── Floating Action Button (WhatsApp Style) ─────────────────────
            PositionedDirectional(
              end: 20,
              bottom: 24,
              child: AnimatedScale(
                scale: _selectedTargets.isNotEmpty ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: whatsappGreen.withOpacity(0.4),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Material(
                    color: whatsappGreen,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _isSending ? null : () => _handleSend(overview),
                      child: Container(
                        width: 60,
                        height: 60,
                        alignment: Alignment.center,
                        child: _isSending
                            ? const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.8,
                                  color: Colors.white,
                                ),
                              )
                            : Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  Transform.rotate(
                                    angle: math.pi, // RTL arrow direction
                                    child: const Icon(
                                      Icons.send_rounded,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                  if (_selectedTargets.length > 1)
                                    Positioned(
                                      top: -10,
                                      right: -10,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black87,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Text(
                                          '${_selectedTargets.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Sending overlay status banner ───────────────────────────────
            if (_isSending && _statusMessage != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: whatsappGreen,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Sub-components ─────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, bool isDark, {int? count}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white54 : const Color(0xFF6E6E73),
              letterSpacing: 0.2,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedCarousel(bool isDark, Color borderColor) {
    final targets = _selectedTargets.values.toList();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'المحددون (${targets.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF25D366),
                  ),
                ),
                GestureDetector(
                  onTap: _clearAllSelections,
                  child: Text(
                    'مسح الكل',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.red.shade300 : Colors.red.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: targets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, index) {
                final target = targets[index];
                return GestureDetector(
                  onTap: () => _unselectTarget(target.id),
                  child: SizedBox(
                    width: 58,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _buildAvatarWidget(target, radius: 22),
                            PositionedDirectional(
                              top: -2,
                              end: -2,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF48484A)
                                      : const Color(0xFF8E8E93),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF1C1C1E)
                                        : Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          target.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetTile({
    required ShareTarget target,
    required bool isDark,
    required ColorScheme colorScheme,
    required Color whatsappGreen,
  }) {
    final isSelected = _isSelected(target.id);

    return InkWell(
      onTap: () => _toggleTarget(target),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isSelected
            ? whatsappGreen.withOpacity(isDark ? 0.12 : 0.08)
            : Colors.transparent,
        child: Row(
          children: [
            // Avatar
            _buildAvatarWidget(target, radius: 24),
            const SizedBox(width: 12),

            // Titles
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  if (target.subtitle != null && target.subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      target.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: target.isSelf
                            ? const Color(0xFF5856D6)
                            : (isDark ? Colors.white54 : Colors.black54),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Selection Circle Indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? whatsappGreen : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? whatsappGreen
                      : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                  width: isSelected ? 0 : 2,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarWidget(ShareTarget target, {required double radius}) {
    if (target.isSelf) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFF5856D6), Color(0xFF007AFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Icon(
          Icons.bookmark_rounded,
          color: Colors.white,
          size: radius * 1.05,
        ),
      );
    }

    if (target.isGroup) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF007AFF).withOpacity(0.12),
        ),
        child: Icon(
          Icons.groups_rounded,
          color: const Color(0xFF007AFF),
          size: radius * 1.1,
        ),
      );
    }

    final letter = target.title.trim().isNotEmpty
        ? target.title.trim().characters.first.toUpperCase()
        : '?';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ChatAvatar(
          radius: radius,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          avatarUrl: target.avatarUrl,
          fallback: Text(
            letter,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: radius * 0.8,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        if (target.isOnline)
          PositionedDirectional(
            end: 0,
            bottom: 0,
            child: Container(
              width: radius * 0.45,
              height: radius * 0.45,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMediaPreview(List<String> paths, bool allImages, bool isDark) {
    if (allImages) {
      return SizedBox(
        height: 74,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: paths.length > 4 ? 5 : paths.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            if (i == 4 && paths.length > 4) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Image.file(
                      File(paths[i]),
                      width: 74,
                      height: 74,
                      fit: BoxFit.cover,
                    ),
                    Positioned.fill(
                      child: Container(
                        color: Colors.black54,
                        alignment: Alignment.center,
                        child: Text(
                          '+${paths.length - 4}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(paths[i]),
                width: 74,
                height: 74,
                fit: BoxFit.cover,
              ),
            );
          },
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = paths[i];
          final fileName = p.split(Platform.pathSeparator).last;
          final isImg = _isImage(p);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isImg
                      ? Icons.image_rounded
                      : Icons.insert_drive_file_rounded,
                  size: 16,
                  color: const Color(0xFF007AFF),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
