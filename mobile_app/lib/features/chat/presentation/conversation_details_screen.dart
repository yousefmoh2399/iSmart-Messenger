import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart' hide RefreshCallback;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/providers/providers.dart';
import '../models/chat_models.dart';
import '../providers/chat_folders_provider.dart';
import 'chat_appearance_screen.dart';
import 'favorite_messages_screen.dart';
import 'group_management_screen.dart';
import 'widgets/chat_avatar.dart';

/// WhatsApp iOS-style Conversation & Contact Details Screen
class ConversationDetailsScreen extends ConsumerStatefulWidget {
  const ConversationDetailsScreen({
    super.key,
    required this.conversation,
    this.peer,
    required this.messages,
    this.token,
  });

  final ChatConversation conversation;
  final ChatDirectoryUser? peer;
  final List<ChatMessage> messages;
  final String? token;

  @override
  ConsumerState<ConversationDetailsScreen> createState() =>
      _ConversationDetailsScreenState();
}

class _ConversationDetailsScreenState
    extends ConsumerState<ConversationDetailsScreen> {
  late ChatConversation _conversation;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
  }

  bool get _isGroup =>
      _conversation.type == 'group' || _conversation.type == 'department';

  List<ChatMessage> get _sharedImages => widget.messages
      .where((m) => !m.isDeleted && m.hasAttachment && m.messageType == 'image')
      .toList();

  List<ChatMessage> get _sharedFiles => widget.messages
      .where((m) => !m.isDeleted && m.hasAttachment && m.messageType != 'image')
      .toList();

  List<String> get _sharedLinks {
    final linkRegex = RegExp(r'https?://[^\s]+');
    final links = <String>[];
    for (final m in widget.messages) {
      if (!m.isDeleted && m.content.isNotEmpty) {
        final matches = linkRegex.allMatches(m.content);
        for (final match in matches) {
          final url = match.group(0);
          if (url != null && !links.contains(url)) {
            links.add(url);
          }
        }
      }
    }
    return links;
  }

  Future<void> _toggleMute() async {
    HapticFeedback.selectionClick();
    final newMute = !_conversation.isMuted;
    setState(() {
      _conversation = _conversation.copyWith(isMuted: newMute);
    });
    try {
      await ref
          .read(chatOverviewControllerProvider.notifier)
          .updateConversationPreferences(
            conversationId: _conversation.id,
            isMuted: newMute,
          );
    } catch (_) {}
  }

  void _showMediaGallery() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MediaGalleryScreen(
          images: _sharedImages,
          files: _sharedFiles,
          links: _sharedLinks,
          token: widget.token,
        ),
      ),
    );
  }

  void _openAvatarFullScreen(String? url, String title) {
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 17),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                httpHeaders: widget.token == null || widget.token!.isEmpty
                    ? null
                    : {'Authorization': 'Bearer ${widget.token}'},
                placeholder: (_, __) =>
                    const Center(child: CircularProgressIndicator.adaptive()),
                errorWidget: (_, __, ___) => const Icon(
                  Icons.person,
                  size: 100,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMoveToFolderSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final folders = ref.watch(chatFoldersProvider).value ?? [];

          return Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'إدارة المجلدات',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (folders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Center(
                      child: Text(
                        'لا توجد مجلدات حالياً.\nيمكنك إنشاء مجلد جديد من الصفحة الرئيسية.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ...folders.map((folder) {
                    final isMember =
                        folder.conversationIds.contains(_conversation.id);
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.folder_rounded,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                      title: Text(
                        folder.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: isMember
                          ? const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF34C759),
                            )
                          : const Icon(
                              Icons.radio_button_unchecked_rounded,
                              color: Colors.grey,
                            ),
                      onTap: () async {
                        await ref
                            .read(chatFoldersProvider.notifier)
                            .updateFolderMembership(
                              folderId: folder.id,
                              conversationId: _conversation.id,
                              add: !isMember,
                            );
                        HapticFeedback.lightImpact();
                      },
                    );
                  }),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final currentUserId = authUser?.id ?? '';

    final title = _conversation.displayTitle(currentUserId);
    final avatarUrl = _isGroup ? null : widget.peer?.avatarUrl;
    final folders = ref.watch(chatFoldersProvider).value ?? [];
    final currentFolders = folders
        .where((f) => f.conversationIds.contains(_conversation.id))
        .toList();

    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final dividerColor = isDark ? Colors.white12 : const Color(0xFFE5E5EA);

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // iOS WhatsApp Sliver App Bar
          SliverAppBar(
            pinned: true,
            expandedHeight: 290,
            backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            elevation: 0.5,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(
                CupertinoIcons.back,
                color: isDark ? Colors.white : const Color(0xFF007AFF),
              ),
              onPressed: () => Navigator.pop(context, _conversation),
            ),
            actions: [
              if (_isGroup && _conversation.createdBy == currentUserId)
                IconButton(
                  icon: const Icon(CupertinoIcons.ellipsis_circle),
                  onPressed: () async {
                    final updated = await Navigator.of(context).push<ChatConversation>(
                      MaterialPageRoute(
                        builder: (_) => GroupManagementScreen(conversation: _conversation),
                      ),
                    );
                    if (updated != null && mounted) {
                      setState(() => _conversation = updated);
                    }
                  },
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                padding: const EdgeInsets.only(top: 60, bottom: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Large Avatar
                    GestureDetector(
                      onTap: () => _openAvatarFullScreen(avatarUrl, title),
                      child: Hero(
                        tag: 'details_avatar_${_conversation.id}',
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ChatAvatar(
                            radius: 48,
                            avatarUrl: avatarUrl,
                            backgroundColor: isDark ? Colors.white12 : const Color(0xFFE5E5EA),
                            fallback: Text(
                              title.isNotEmpty ? title[0].toUpperCase() : '?',
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF007AFF),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Name
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Subtitle / Status
                    Text(
                      _isGroup
                          ? 'مجموعة • ${_conversation.members.length} مشاركاً'
                          : (widget.peer?.jobTitle.isNotEmpty == true
                              ? '${widget.peer!.jobTitle} • ${widget.peer!.branchCode}'
                              : (widget.peer?.presenceStatus == 'online'
                                  ? 'متصل الآن 🟢'
                                  : 'غير متصل')),
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white54 : Colors.black45,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Quick Action Pills Row (WhatsApp iOS Style)
          SliverToBoxAdapter(
            child: Container(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildQuickActionBtn(
                    isDark: isDark,
                    icon: CupertinoIcons.phone,
                    label: 'صوت',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('المكالمات الصوتية المباشرة قادمة قريباً'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    isDark: isDark,
                    icon: CupertinoIcons.videocam,
                    label: 'فيديو',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('مكالمات الفيديو قادمة قريباً'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    isDark: isDark,
                    icon: CupertinoIcons.search,
                    label: 'بحث',
                    onTap: () {
                      Navigator.pop(context, _conversation);
                    },
                  ),
                  _buildQuickActionBtn(
                    isDark: isDark,
                    icon: _conversation.isMuted
                        ? CupertinoIcons.bell_slash_fill
                        : CupertinoIcons.bell,
                    label: _conversation.isMuted ? 'مكتوم' : 'كتم',
                    active: _conversation.isMuted,
                    onTap: _toggleMute,
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 18)),

          // 1. Media, Links, and Docs Section (WhatsApp iOS Signature Card)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: _showMediaGallery,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(
                              CupertinoIcons.photo_on_rectangle,
                              color: Color(0xFF007AFF),
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'الوسائط والروابط والمستندات',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '${_sharedImages.length + _sharedFiles.length + _sharedLinks.length}',
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black45,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              CupertinoIcons.chevron_forward,
                              size: 16,
                              color: isDark ? Colors.white38 : Colors.black26,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Recent Media Thumbnails Preview Strip
                    if (_sharedImages.isNotEmpty) ...[
                      Divider(height: 0.5, thickness: 0.5, color: dividerColor, indent: 48),
                      Container(
                        height: 84,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _sharedImages.take(8).length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final msg = _sharedImages[index];
                            return GestureDetector(
                              onTap: () => _openAvatarFullScreen(msg.fileUrl, msg.fileName ?? 'صورة'),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: msg.fileUrl ?? '',
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                  httpHeaders: widget.token == null || widget.token!.isEmpty
                                      ? null
                                      : {'Authorization': 'Bearer ${widget.token}'},
                                  errorWidget: (_, __, ___) => Container(
                                    width: 64,
                                    height: 64,
                                    color: isDark ? Colors.white12 : Colors.black12,
                                    child: const Icon(Icons.broken_image, size: 20),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 18)),

          // 2. Information / About Inset Group
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    if (!_isGroup && widget.peer != null) ...[
                      if (widget.peer!.jobTitle.isNotEmpty)
                        _buildInfoTile(
                          isDark: isDark,
                          title: 'المسمى الوظيفي',
                          value: widget.peer!.jobTitle,
                          icon: CupertinoIcons.briefcase,
                        ),
                      if (widget.peer!.role.isNotEmpty) ...[
                        Divider(height: 0.5, thickness: 0.5, color: dividerColor, indent: 48),
                        _buildInfoTile(
                          isDark: isDark,
                          title: 'الدور / الصلاحية',
                          value: widget.peer!.role,
                          icon: CupertinoIcons.shield_fill,
                        ),
                      ],
                      if (widget.peer!.branchCode.isNotEmpty) ...[
                        Divider(height: 0.5, thickness: 0.5, color: dividerColor, indent: 48),
                        _buildInfoTile(
                          isDark: isDark,
                          title: 'الفرع',
                          value: 'فرع ${widget.peer!.branchCode}',
                          icon: CupertinoIcons.location_solid,
                        ),
                      ],
                      Divider(height: 0.5, thickness: 0.5, color: dividerColor, indent: 48),
                      _buildInfoTile(
                        isDark: isDark,
                        title: 'اسم المستخدم',
                        value: '@${widget.peer!.username}',
                        icon: CupertinoIcons.person_alt_circle,
                      ),
                    ] else ...[
                      // Group details
                      _buildInfoTile(
                        isDark: isDark,
                        title: 'وصف المجموعة',
                        value: _conversation.description.isNotEmpty
                            ? _conversation.description
                            : 'لا يوجد وصف مضاف لهذه المجموعة',
                        icon: CupertinoIcons.text_quote,
                      ),
                      Divider(height: 0.5, thickness: 0.5, color: dividerColor, indent: 48),
                      _buildInfoTile(
                        isDark: isDark,
                        title: 'تاريخ الإنشاء',
                        value: DateFormat('yyyy/MM/dd').format(_conversation.createdAt.toLocal()),
                        icon: CupertinoIcons.calendar,
                      ),
                      if (_conversation.pinnedMessage != null) ...[
                        Divider(height: 0.5, thickness: 0.5, color: dividerColor, indent: 48),
                        _buildInfoTile(
                          isDark: isDark,
                          title: 'الرسالة المثبتة',
                          value: _conversation.pinnedMessage!.content,
                          icon: CupertinoIcons.pin_fill,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 18)),

          // 3. Settings & Preferences Inset Group
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Mute Notifications Tile
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            _conversation.isMuted
                                ? CupertinoIcons.bell_slash_fill
                                : CupertinoIcons.bell_fill,
                            color: _conversation.isMuted
                                ? const Color(0xFFFF9500)
                                : const Color(0xFF007AFF),
                            size: 22,
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Text(
                              'كتم الإشعارات',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          ),
                          CupertinoSwitch(
                            value: _conversation.isMuted,
                            activeTrackColor: const Color(0xFF34C759),
                            onChanged: (_) => _toggleMute(),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 0.5, thickness: 0.5, color: dividerColor, indent: 52),
                    // Starred Messages Tile
                    ListTile(
                      leading: const Icon(CupertinoIcons.star_fill, color: Color(0xFFFFB020), size: 22),
                      title: const Text('الرسائل المميزة بنجمة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      trailing: Icon(CupertinoIcons.chevron_forward, size: 16, color: isDark ? Colors.white38 : Colors.black26),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FavoriteMessagesScreen(),
                          ),
                        );
                      },
                    ),
                    Divider(height: 0.5, thickness: 0.5, color: dividerColor, indent: 52),
                    // Chat Appearance Wallpaper Tile
                    ListTile(
                      leading: const Icon(CupertinoIcons.paintbrush_fill, color: Color(0xFF5856D6), size: 22),
                      title: const Text('خلفية ومظهر الدردشة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      trailing: Icon(CupertinoIcons.chevron_forward, size: 16, color: isDark ? Colors.white38 : Colors.black26),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ChatAppearanceScreen()),
                        );
                      },
                    ),
                    Divider(height: 0.5, thickness: 0.5, color: dividerColor, indent: 52),
                    // Folders Tile
                    ListTile(
                      leading: const Icon(CupertinoIcons.folder_fill, color: Color(0xFF007AFF), size: 22),
                      title: const Text('المجلدات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      subtitle: currentFolders.isNotEmpty
                          ? Text(
                              currentFolders.map((f) => f.name).join('، '),
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (currentFolders.isEmpty)
                            Text('لا يوجد', style: TextStyle(fontSize: 14, color: isDark ? Colors.white38 : Colors.black38)),
                          const SizedBox(width: 4),
                          Icon(CupertinoIcons.chevron_forward, size: 16, color: isDark ? Colors.white38 : Colors.black26),
                        ],
                      ),
                      onTap: _showMoveToFolderSheet,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 4. Participants Section (if Group / Department)
          if (_isGroup) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 8),
                      child: Text(
                        'المشاركون (${_conversation.members.length})',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ),
                    Material(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          if (_conversation.createdBy == currentUserId)
                            ListTile(
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF34C759).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(CupertinoIcons.person_add_solid, color: Color(0xFF34C759), size: 18),
                              ),
                              title: const Text(
                                'إضافة مشاركين...',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF007AFF)),
                              ),
                              onTap: () async {
                                final updated = await Navigator.of(context).push<ChatConversation>(
                                  MaterialPageRoute(
                                    builder: (_) => GroupManagementScreen(conversation: _conversation),
                                  ),
                                );
                                if (updated != null && mounted) {
                                  setState(() => _conversation = updated);
                                }
                              },
                            ),
                          ..._conversation.members.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final member = entry.value;
                            final isAdmin = _conversation.admins.any((a) => a.id == member.id) ||
                                _conversation.createdBy == member.id;
                            final isMe = member.id == currentUserId;

                            return Column(
                              children: [
                                if (idx > 0 || _conversation.createdBy == currentUserId)
                                  Divider(height: 0.5, thickness: 0.5, color: dividerColor, indent: 64),
                                ListTile(
                                  leading: ChatAvatar(
                                    radius: 20,
                                    avatarUrl: member.avatarUrl,
                                    backgroundColor: isDark ? Colors.white12 : const Color(0xFFE5E5EA),
                                    fallback: Text(
                                      member.displayName.isNotEmpty ? member.displayName[0].toUpperCase() : '?',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          isMe ? 'أنت' : member.displayName,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                      if (isAdmin)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF34C759).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'مشرف',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF34C759),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: member.jobTitle.isNotEmpty
                                      ? Text(member.jobTitle, style: const TextStyle(fontSize: 12))
                                      : null,
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 18)),

          // 5. Danger Zone Inset Group
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    if (_isGroup) ...[
                      ListTile(
                        leading: const Icon(CupertinoIcons.square_arrow_right, color: CupertinoColors.systemRed),
                        title: const Text(
                          'مغادرة المجموعة',
                          style: TextStyle(color: CupertinoColors.systemRed, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        onTap: () async {
                          final nav = Navigator.of(context);
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('مغادرة المجموعة'),
                              content: const Text('هل أنت متأكد من مغادرة هذه المجموعة؟'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                  child: const Text('مغادرة'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true && mounted) {
                            await ref.read(chatOverviewControllerProvider.notifier).leaveConversation(_conversation.id);
                            if (mounted) {
                              nav.pop();
                            }
                          }
                        },
                      ),
                    ] else ...[
                      ListTile(
                        leading: const Icon(CupertinoIcons.trash, color: CupertinoColors.systemRed),
                        title: const Text(
                          'مسح المحادثة',
                          style: TextStyle(color: CupertinoColors.systemRed, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        onTap: () async {
                          final nav = Navigator.of(context);
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('مسح المحادثة'),
                              content: const Text('هل أنت متأكد من حذف هذه المحادثة من قائمتك؟'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                  child: const Text('مسح'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true && mounted) {
                            await ref.read(chatOverviewControllerProvider.notifier).deleteConversation(_conversation.id);
                            if (mounted) {
                              nav.pop();
                            }
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildQuickActionBtn({
    required bool isDark,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFFF9500).withValues(alpha: 0.15)
              : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF2F2F7)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: active
                  ? const Color(0xFFFF9500)
                  : const Color(0xFF007AFF),
              size: 22,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active
                    ? const Color(0xFFFF9500)
                    : const Color(0xFF007AFF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required bool isDark,
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF007AFF), size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full Media, Docs, and Links Browser (WhatsApp iOS Style)
class _MediaGalleryScreen extends StatelessWidget {
  const _MediaGalleryScreen({
    required this.images,
    required this.files,
    required this.links,
    this.token,
  });

  final List<ChatMessage> images;
  final List<ChatMessage> files;
  final List<String> links;
  final String? token;

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
        appBar: AppBar(
          title: const Text('الوسائط والمستندات والروابط'),
          elevation: 0.5,
          bottom: const TabBar(
            indicatorColor: Color(0xFF007AFF),
            labelColor: Color(0xFF007AFF),
            tabs: [
              Tab(text: 'الوسائط'),
              Tab(text: 'المستندات'),
              Tab(text: 'الروابط'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // 1. Media Grid (Photos & Videos)
            images.isEmpty
                ? const Center(child: Text('لا توجد وسائط بعد', style: TextStyle(color: Colors.grey)))
                : GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 3,
                      mainAxisSpacing: 3,
                    ),
                    itemCount: images.length,
                    itemBuilder: (context, index) {
                      final item = images[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => Scaffold(
                                backgroundColor: Colors.black,
                                appBar: AppBar(
                                  backgroundColor: Colors.transparent,
                                  elevation: 0,
                                  leading: const BackButton(color: Colors.white),
                                ),
                                body: Center(
                                  child: InteractiveViewer(
                                    child: CachedNetworkImage(
                                      imageUrl: item.fileUrl ?? '',
                                      httpHeaders: token == null || token!.isEmpty
                                          ? null
                                          : {'Authorization': 'Bearer $token'},
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        child: CachedNetworkImage(
                          imageUrl: item.fileUrl ?? '',
                          fit: BoxFit.cover,
                          httpHeaders: token == null || token!.isEmpty
                              ? null
                              : {'Authorization': 'Bearer $token'},
                        ),
                      );
                    },
                  ),

            // 2. Docs List (PDFs & Documents)
            files.isEmpty
                ? const Center(child: Text('لا توجد مستندات بعد', style: TextStyle(color: Colors.grey)))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: files.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final file = files[index];
                      final isPdf = file.fileName?.toLowerCase().endsWith('.pdf') == true;

                      return Material(
                        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isPdf
                                  ? const Color(0xFFFF2D55).withValues(alpha: 0.12)
                                  : const Color(0xFF007AFF).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isPdf ? CupertinoIcons.doc_text_fill : CupertinoIcons.doc_fill,
                              color: isPdf ? const Color(0xFFFF2D55) : const Color(0xFF007AFF),
                            ),
                          ),
                          title: Text(
                            file.fileName ?? 'مستند',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${_formatFileSize(file.fileSize)} • ${DateFormat('yyyy/MM/dd').format(file.createdAt.toLocal())}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(CupertinoIcons.cloud_download, color: Color(0xFF007AFF)),
                        ),
                      );
                    },
                  ),

            // 3. Links List
            links.isEmpty
                ? const Center(child: Text('لا توجد روابط بعد', style: TextStyle(color: Colors.grey)))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: links.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final url = links[index];
                      return Material(
                        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF34C759).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(CupertinoIcons.link, color: Color(0xFF34C759)),
                          ),
                          title: Text(
                            url,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF007AFF)),
                          ),
                          trailing: const Icon(CupertinoIcons.arrow_up_right, size: 16),
                          onTap: () async {
                            final uri = Uri.tryParse(url);
                            if (uri != null && await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
