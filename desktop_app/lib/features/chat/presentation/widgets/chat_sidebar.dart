import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/safe_network_avatar.dart';
import '../../models/chat_models.dart';
import '../../providers/chat_folders_provider.dart';
import '../chat_appearance.dart';
import 'chat_folder_inline_item.dart';
import 'create_chat_folder_dialog.dart';
import '../../utils/chat_search_utils.dart';
import 'chat_list_item.dart';
import 'chat_ui_helpers.dart';
import 'instant_clipboard_sync_dialog.dart';

class ChatSidebar extends ConsumerWidget {
  const ChatSidebar({
    super.key,
    required this.currentUser,
    required this.compact,
    required this.currentThemeMode,
    required this.searchController,
    required this.currentFilter,
    required this.conversations,
    required this.overview,
    required this.currentUserId,
    required this.typingPreviewByConversationId,
    required this.selectedConversationId,
    required this.onFilterChanged,
    required this.onConversationSelected,
    required this.onOpenOrStartDirectConversation,
    required this.onCreateConversation,
    required this.onRefresh,
    required this.onOpenAdmin,
    required this.onOpenTickets,
    required this.onOpenFiles,
    required this.onOpenServers,
    required this.onOpenProfile,
    required this.onOpenFavoriteMessages,
    required this.onToggleTheme,
    required this.onTogglePin,
    required this.onToggleMute,
    required this.onToggleArchive,
    required this.onToggleFavorite,
    required this.onDeleteConversation,
  });

  final AppUser? currentUser;
  final bool compact;
  final ThemeMode currentThemeMode;
  final TextEditingController searchController;
  final ChatSidebarFilter currentFilter;
  final List<ChatConversation> conversations;
  final ChatOverviewData overview;
  final String currentUserId;
  final Map<String, String> typingPreviewByConversationId;
  final String? selectedConversationId;
  final ValueChanged<ChatSidebarFilter> onFilterChanged;
  final ValueChanged<ChatConversation> onConversationSelected;
  final ValueChanged<ChatDirectoryUser> onOpenOrStartDirectConversation;
  final VoidCallback onCreateConversation;
  final VoidCallback onRefresh;
  final VoidCallback onOpenAdmin;
  final VoidCallback onOpenTickets;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenServers;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenFavoriteMessages;
  final VoidCallback onToggleTheme;
  final ValueChanged<ChatConversation> onTogglePin;
  final ValueChanged<ChatConversation> onToggleMute;
  final ValueChanged<ChatConversation> onToggleArchive;
  final ValueChanged<ChatConversation> onToggleFavorite;
  final ValueChanged<ChatConversation> onDeleteConversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(chatFoldersProvider).valueOrNull ?? [];
    final folderConversationIds = folders.expand((f) => f.conversationIds).toSet();
    final baseTheme = Theme.of(context);
    final colorScheme = baseTheme.colorScheme;
    final isDark = baseTheme.brightness == Brightness.dark;
    final query = searchController.text.trim();
    final chatPreferences =
        currentUser?.chatPreferences ?? ChatPreferences.defaults;
    final appearance = ChatAppearanceCatalog.resolveAppearance(
      preferences: chatPreferences,
      isDark: isDark,
      colorScheme: colorScheme,
    );
    final sidebarBg = isDark
        ? Color.lerp(
            appearance.wallpaperColors.last,
            const Color(0xFF212121),
            0.34,
          )!
        : Colors.grey.shade100;
    final searchFill = isDark
        ? Color.lerp(appearance.incomingBubbleColor, sidebarBg, 0.22)!
        : Colors.white;
    final themedColorScheme = colorScheme.copyWith(
      primary: appearance.accent,
      surface: Color.lerp(
        appearance.incomingBubbleColor,
        sidebarBg,
        isDark ? 0.12 : 0.08,
      )!,
      surfaceContainerHighest: Color.lerp(
        appearance.incomingBubbleColor,
        sidebarBg,
        isDark ? 0.26 : 0.14,
      )!,
      onSurfaceVariant: isDark ? Colors.white60 : const Color(0xFF5C6E7D),
    );

    final userLabel = (currentUser?.fullName.trim().isNotEmpty ?? false)
        ? currentUser!.fullName
        : (currentUser?.username ?? 'مستخدم');

    final unreadTotal = conversations.fold<int>(
      0,
      (sum, c) => sum + c.unreadCount,
    );
    final departmentByIdAndCode = <String, DepartmentSummary>{
      for (final department in overview.departments) ...{
        department.id: department,
        department.id.trim(): department,
        if (department.code.trim().isNotEmpty) ...{
          department.code: department,
          department.code.trim(): department,
          department.code.trim().toLowerCase(): department,
          department.code.trim().toUpperCase(): department,
        },
        if (department.name.trim().isNotEmpty) ...{
          department.name.trim(): department,
          department.name.trim().toLowerCase(): department,
        },
      },
    };

    final branchByIdAndCode = <String, BranchSummary>{
      for (final branch in overview.branches) ...{
        branch.id: branch,
        branch.id.trim(): branch,
        if (branch.code.trim().isNotEmpty) ...{
          branch.code: branch,
          branch.code.trim(): branch,
          branch.code.trim().toUpperCase(): branch,
          branch.code.trim().toLowerCase(): branch,
        },
        if (branch.name.trim().isNotEmpty) ...{
          branch.name.trim(): branch,
          branch.name.trim().toLowerCase(): branch,
        },
      },
    };

    BranchSummary? resolveBranch(ChatDirectoryUser user) {
      if (user.branchId != null && user.branchId!.trim().isNotEmpty) {
        final key = user.branchId!.trim();
        final match = branchByIdAndCode[key] ??
            branchByIdAndCode[key.toUpperCase()] ??
            branchByIdAndCode[key.toLowerCase()];
        if (match != null) return match;
      }
      if (user.branchCode.trim().isNotEmpty) {
        final key = user.branchCode.trim();
        final match = branchByIdAndCode[key] ??
            branchByIdAndCode[key.toUpperCase()] ??
            branchByIdAndCode[key.toLowerCase()];
        if (match != null) return match;
      }
      return null;
    }

    List<DepartmentSummary> resolveDepartments(ChatDirectoryUser user) {
      final matched = <DepartmentSummary>{};
      for (final id in user.allDepartmentIds) {
        if (id.trim().isEmpty) continue;
        final key = id.trim();
        final match = departmentByIdAndCode[key] ??
            departmentByIdAndCode[key.toLowerCase()] ??
            departmentByIdAndCode[key.toUpperCase()];
        if (match != null) matched.add(match);
      }
      if (matched.isEmpty &&
          user.departmentId != null &&
          user.departmentId!.trim().isNotEmpty) {
        final key = user.departmentId!.trim();
        final match = departmentByIdAndCode[key] ??
            departmentByIdAndCode[key.toLowerCase()] ??
            departmentByIdAndCode[key.toUpperCase()];
        if (match != null) matched.add(match);
      }
      return matched.toList();
    }

    ChatDirectoryUser mergeUser(
      ChatDirectoryUser primary,
      ChatDirectoryUser fallback,
    ) {
      return primary.copyWith(
        fullName: primary.fullName.trim().isNotEmpty
            ? primary.fullName
            : fallback.fullName,
        username: primary.username.trim().isNotEmpty
            ? primary.username
            : fallback.username,
        jobTitle: primary.jobTitle.trim().isNotEmpty
            ? primary.jobTitle
            : fallback.jobTitle,
        departmentId: (primary.departmentId != null &&
                primary.departmentId!.trim().isNotEmpty)
            ? primary.departmentId
            : fallback.departmentId,
        departmentIds: primary.departmentIds.isNotEmpty
            ? primary.departmentIds
            : fallback.departmentIds,
        branchId: (primary.branchId != null &&
                primary.branchId!.trim().isNotEmpty)
            ? primary.branchId
            : fallback.branchId,
        branchCode: (primary.branchCode.isNotEmpty &&
                primary.branchCode.toLowerCase() != 'main')
            ? primary.branchCode
            : fallback.branchCode,
        avatarUrl: primary.avatarUrl ?? fallback.avatarUrl,
        isOnline: primary.isOnline || fallback.isOnline,
        presenceStatus: primary.isOnline
            ? primary.presenceStatus
            : fallback.presenceStatus,
      );
    }

    // Pool all known users from both directory and conversation memberships
    // so no contact is ever omitted if network pagination is still pending.
    final allKnownUsers = <String, ChatDirectoryUser>{
      for (final user in overview.users) user.id: user,
    };
    for (final conv in conversations) {
      for (final member in conv.members) {
        final existing = allKnownUsers[member.id];
        if (existing == null) {
          allKnownUsers[member.id] = member;
        } else {
          allKnownUsers[member.id] = mergeUser(existing, member);
        }
      }
    }

    final matchingUsers = <ChatDirectoryUser>[];
    final usersByDepartment = <DepartmentSummary?, List<ChatDirectoryUser>>{};
    final usersByBranch = <BranchSummary?, List<ChatDirectoryUser>>{};
    if (currentFilter != ChatSidebarFilter.rooms &&
        currentFilter != ChatSidebarFilter.favorites &&
        currentFilter != ChatSidebarFilter.archived) {
      for (final user in allKnownUsers.values) {
        if (user.id == currentUserId) {
          continue;
        }
        final userDepartments = resolveDepartments(user);
        final primaryDepartment = userDepartments.isNotEmpty
            ? userDepartments.first
            : null;
        final branch = resolveBranch(user);

        final isMatch = ChatSearchUtils.matchesUser(
          user: user,
          primaryDepartment: primaryDepartment,
          userDepartments: userDepartments,
          branch: branch,
          query: query,
        );

        if (!isMatch) {
          continue;
        }

        if (query.isNotEmpty) {
          matchingUsers.add(user);
        }

        if (userDepartments.isEmpty) {
          usersByDepartment
              .putIfAbsent(null, () => <ChatDirectoryUser>[])
              .add(user);
        } else {
          for (final department in userDepartments) {
            usersByDepartment
                .putIfAbsent(department, () => <ChatDirectoryUser>[])
                .add(user);
          }
        }
        usersByBranch
            .putIfAbsent(branch, () => <ChatDirectoryUser>[])
            .add(user);
      }
      if (matchingUsers.isNotEmpty) {
        matchingUsers.sort((a, b) => a.displayName.compareTo(b.displayName));
      }
    }
    final orderedDepartmentEntries = [
      for (final department in overview.departments)
        if (usersByDepartment[department]?.isNotEmpty == true ||
            (query.isEmpty && currentFilter == ChatSidebarFilter.departments))
          MapEntry(
            department,
            usersByDepartment[department] ?? const <ChatDirectoryUser>[],
          ),
      if (usersByDepartment[null]?.isNotEmpty == true)
        MapEntry<DepartmentSummary?, List<ChatDirectoryUser>>(
          null,
          usersByDepartment[null]!,
        ),
    ];
    final orderedBranchEntries = [
      for (final branch in overview.branches)
        if (usersByBranch[branch]?.isNotEmpty == true ||
            (query.isEmpty && currentFilter == ChatSidebarFilter.branches))
          MapEntry(
            branch,
            usersByBranch[branch] ?? const <ChatDirectoryUser>[],
          ),
      if (usersByBranch[null]?.isNotEmpty == true)
        MapEntry<BranchSummary?, List<ChatDirectoryUser>>(
          null,
          usersByBranch[null]!,
        ),
    ];

    // Conversations organized by chronological activity (pinned first, then latest activity)
    DateTime conversationActivityAt(ChatConversation c) {
      return c.lastMessage?.createdAt ?? c.updatedAt;
    }

    int compareConversations(ChatConversation a, ChatConversation b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return conversationActivityAt(b).compareTo(conversationActivityAt(a));
    }

    final matchingConversations = conversations
        .where((c) => !folderConversationIds.contains(c.id))
        .where((c) => ChatSearchUtils.matchesConversation(
              conversation: c,
              query: query,
              currentUserId: currentUserId,
            ))
        .toList();

    final unarchivedConversations = matchingConversations
        .where((c) => !c.isArchived)
        .toList()
      ..sort(compareConversations);

    final departmentRooms = unarchivedConversations
        .where((c) => c.type == 'department')
        .toList();

    final groupConversations = unarchivedConversations
        .where((c) => c.type == 'group' || c.type == 'broadcast' || c.type == 'department')
        .toList();

    final directConversations = unarchivedConversations
        .where((c) => c.type == 'direct')
        .toList();

    final favoriteConversations = unarchivedConversations
        .where((c) => c.isFavorite)
        .toList();

    final archivedConversations = matchingConversations
        .where((c) => c.isArchived)
        .toList()
      ..sort(compareConversations);

    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveCompact = compact || constraints.maxWidth <= 270;

        if (effectiveCompact) {
          return Theme(
            data: baseTheme.copyWith(colorScheme: themedColorScheme),
            child: _CompactChatSidebar(
              sidebarBg: sidebarBg,
              currentUser: currentUser,
              currentThemeMode: currentThemeMode,
              isDark: isDark,
              appearance: appearance,
              conversations: conversations,
              currentUserId: currentUserId,
              selectedConversationId: selectedConversationId,
              canOpenAdmin:
                  currentUser?.can('canCreateUsers') == true ||
                  currentUser?.can('canCreateDepartments') == true,
              onConversationSelected: onConversationSelected,
              onCreateConversation: onCreateConversation,
              onRefresh: onRefresh,
              onOpenAdmin: onOpenAdmin,
              onOpenTickets: onOpenTickets,
              onOpenFiles: onOpenFiles,
              onOpenServers: onOpenServers,
              onOpenProfile: onOpenProfile,
              onOpenFavoriteMessages: onOpenFavoriteMessages,
              onToggleTheme: onToggleTheme,
            ),
          );
        }

        return Theme(
          data: baseTheme.copyWith(colorScheme: themedColorScheme),
          child: ColoredBox(
            color: sidebarBg,
            child: Column(
              children: [
                // ── Header ─────────────────────────────────────────────────────────
                _SidebarHeader(
                  userLabel: userLabel,
                  unreadTotal: unreadTotal,
                  canOpenAdmin:
                      currentUser?.can('canCreateUsers') == true ||
                      currentUser?.can('canCreateDepartments') == true,
                  currentThemeMode: currentThemeMode,
                  isDark: isDark,
                  appearance: appearance,
                  onCreateConversation: onCreateConversation,
                  onRefresh: onRefresh,
                  onOpenAdmin: onOpenAdmin,
                  onOpenTickets: onOpenTickets,
                  onOpenFiles: onOpenFiles,
                  onOpenServers: onOpenServers,
                  onOpenProfile: onOpenProfile,
                  onOpenFavoriteMessages: onOpenFavoriteMessages,
                  onToggleTheme: onToggleTheme,
                  conversations: conversations,
                  currentUserId: currentUserId,
                ),

                // ── Search field ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: TextField(
                    controller: searchController,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : const Color(0xFF1C2B3A),
                    ),
                    decoration: InputDecoration(
                      hintText: 'بحث في المحادثات وجهات الاتصال...',
                      hintStyle: TextStyle(
                        color: isDark
                            ? Colors.white38
                            : const Color(0xFFADB5BD),
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: appearance.accent,
                      ),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              tooltip: 'مسح البحث',
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: isDark
                                    ? Colors.white54
                                    : const Color(0xFF708499),
                              ),
                              onPressed: () {
                                searchController.clear();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: searchFill,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color: appearance.accent.withValues(alpha: 0.48),
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Filter chips ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'الكل',
                            selected: currentFilter == ChatSidebarFilter.all,
                            isDark: isDark,
                            appearance: appearance,
                            onTap: () => onFilterChanged(ChatSidebarFilter.all),
                          ),
                          const SizedBox(width: 6),
                          _FilterChip(
                            label: 'مباشر',
                            selected: currentFilter == ChatSidebarFilter.direct,
                            isDark: isDark,
                            appearance: appearance,
                            onTap: () =>
                                onFilterChanged(ChatSidebarFilter.direct),
                          ),
                          const SizedBox(width: 6),
                          _FilterChip(
                            label: 'المجموعات',
                            selected: currentFilter == ChatSidebarFilter.rooms,
                            isDark: isDark,
                            appearance: appearance,
                            onTap: () =>
                                onFilterChanged(ChatSidebarFilter.rooms),
                          ),
                          const SizedBox(width: 6),
                          _FilterChip(
                            label: 'الأقسام',
                            selected:
                                currentFilter == ChatSidebarFilter.departments,
                            isDark: isDark,
                            appearance: appearance,
                            onTap: () =>
                                onFilterChanged(ChatSidebarFilter.departments),
                          ),
                          const SizedBox(width: 6),
                          _FilterChip(
                            label: 'الفروع',
                            selected:
                                currentFilter == ChatSidebarFilter.branches,
                            isDark: isDark,
                            appearance: appearance,
                            onTap: () =>
                                onFilterChanged(ChatSidebarFilter.branches),
                          ),
                          const SizedBox(width: 6),
                          _FilterChip(
                            label: 'المفضلة',
                            selected:
                                currentFilter == ChatSidebarFilter.favorites,
                            isDark: isDark,
                            appearance: appearance,
                            onTap: () =>
                                onFilterChanged(ChatSidebarFilter.favorites),
                          ),
                          const SizedBox(width: 6),
                          _FilterChip(
                            label: 'المؤرشفة',
                            selected:
                                currentFilter == ChatSidebarFilter.archived,
                            isDark: isDark,
                            appearance: appearance,
                            onTap: () =>
                                onFilterChanged(ChatSidebarFilter.archived),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Subtle divider like Telegram ────────────────────────────────
                Divider(
                  height: 1,
                  thickness: 1,
                  color: appearance.accent.withValues(alpha: 0.14),
                ),

                // ── Conversation list ───────────────────────────────────────────
                Expanded(
                  child: Scrollbar(
                    interactive: false,
                    child: ListView(
                      primary: true,
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
                      children: [
                        if (folders.isNotEmpty)
                          ...folders.map((folder) => Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: ChatFolderInlineItem(
                                  folder: folder,
                                  unreadBadgeColor: appearance.unreadBadgeColor,
                                  currentUserId: currentUserId,
                                  conversations: folder.conversationIds
                                      .map((id) => conversations.firstWhere(
                                            (c) => c.id == id,
                                            orElse: () => ChatConversation(
                                              id: id,
                                              type: 'unknown',
                                              name: '',
                                              description: '',
                                              departmentId: null,
                                              createdBy: null,
                                              members: [],
                                              admins: [],
                                              broadcastPublisherIds: [],
                                              blockedMemberIds: [],
                                              pinnedMessage: null,
                                              lastMessage: null,
                                              unreadCount: 0,
                                              isArchived: false,
                                              isMuted: false,
                                              isPinned: false,
                                              isFavorite: false,
                                              isActive: false,
                                              createdAt: DateTime.now(),
                                              updatedAt: DateTime.now(),
                                            ),
                                          ))
                                      .where((c) => c.type != 'unknown')
                                      .toList(),
                                  buildConversation: (c) => ChatListItem(
                                    conversation: c,
                                    unreadBadgeColor: appearance.unreadBadgeColor,
                                    currentUserId: currentUserId,
                                    typingPreviewText:
                                        typingPreviewByConversationId[c.id],
                                    selected: selectedConversationId == c.id,
                                    onTap: () => onConversationSelected(c),
                                    onTogglePin: () => onTogglePin(c),
                                    onToggleMute: () => onToggleMute(c),
                                    onToggleArchive: () => onToggleArchive(c),
                                    onToggleFavorite: () => onToggleFavorite(c),
                                    onDeleteConversation: () =>
                                        onDeleteConversation(c),
                                  ),
                                ),
                              )),
                        const ChatFolderDropZone(),
                        if (query.isNotEmpty && matchingUsers.isNotEmpty) ...[
                          _SidebarSectionHeader(
                            title: 'الأشخاص وجهات الاتصال (${matchingUsers.length})',
                            subtitle: 'جهات الاتصال المطابقة لبحثك - انقر للمحادثة المباشرة.',
                            appearance: appearance,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 8),
                          ...matchingUsers.map(
                            (user) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _SidebarUserTile(
                                user: user,
                                accent: _departmentAccent(resolveDepartments(user).firstOrNull),
                                appearance: appearance,
                                isDark: isDark,
                                existingConversation: _conversationForUser(user),
                                onTap: () => onOpenOrStartDirectConversation(user),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // ── Search Mode Conversation Results ───────────────────────
                        if (query.isNotEmpty && unarchivedConversations.isNotEmpty) ...[
                          _SidebarSectionHeader(
                            title: 'المحادثات المطابقة (${unarchivedConversations.length})',
                            subtitle: 'نتائج البحث في المحادثات المفتوحة.',
                            appearance: appearance,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 8),
                          ...unarchivedConversations.map(
                            (conversation) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: ChatListItem(
                                conversation: conversation,
                                unreadBadgeColor: appearance.unreadBadgeColor,
                                currentUserId: currentUserId,
                                typingPreviewText:
                                    typingPreviewByConversationId[conversation.id],
                                selected: selectedConversationId == conversation.id,
                                onTap: () => onConversationSelected(conversation),
                                onTogglePin: () => onTogglePin(conversation),
                                onToggleMute: () => onToggleMute(conversation),
                                onToggleArchive: () => onToggleArchive(conversation),
                                onToggleFavorite: () => onToggleFavorite(conversation),
                                onDeleteConversation: () => onDeleteConversation(conversation),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // ── Regular Filtering (when not searching) ─────────────────
                        if (query.isEmpty) ...[
                          // 1. ALL TAB: Unified chronological stream of all conversations (Latest first)
                          if (currentFilter == ChatSidebarFilter.all) ...[
                            if (unarchivedConversations.isEmpty)
                              _SidebarInlineNotice(
                                label: 'لا توجد محادثات مفتوحة حاليًا. اختر زميلًا من تبويب "مباشر" أو "الأقسام" لبدء محادثة.',
                                appearance: appearance,
                                isDark: isDark,
                              )
                            else
                              ...unarchivedConversations.map(
                                (conversation) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: ChatListItem(
                                    conversation: conversation,
                                    unreadBadgeColor: appearance.unreadBadgeColor,
                                    currentUserId: currentUserId,
                                    typingPreviewText:
                                        typingPreviewByConversationId[conversation.id],
                                    selected: selectedConversationId == conversation.id,
                                    onTap: () => onConversationSelected(conversation),
                                    onTogglePin: () => onTogglePin(conversation),
                                    onToggleMute: () => onToggleMute(conversation),
                                    onToggleArchive: () => onToggleArchive(conversation),
                                    onToggleFavorite: () => onToggleFavorite(conversation),
                                    onDeleteConversation: () => onDeleteConversation(conversation),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                          ],

                          // 2. DIRECT FILTER
                          if (currentFilter == ChatSidebarFilter.direct) ...[
                            _SidebarSectionHeader(
                              title: 'المحادثات المباشرة (${directConversations.length})',
                              subtitle: 'كل الشاتات المباشرة المتاحة لك.',
                              appearance: appearance,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 8),
                            if (directConversations.isEmpty)
                              _SidebarInlineNotice(
                                label: 'لا توجد محادثات مباشرة حاليًا. اختر زميلًا من الدليل أدناه لبدء محادثة.',
                                appearance: appearance,
                                isDark: isDark,
                              )
                            else
                              ...directConversations.map(
                                (conversation) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: ChatListItem(
                                    conversation: conversation,
                                    unreadBadgeColor: appearance.unreadBadgeColor,
                                    currentUserId: currentUserId,
                                    typingPreviewText:
                                        typingPreviewByConversationId[conversation.id],
                                    selected: selectedConversationId == conversation.id,
                                    onTap: () => onConversationSelected(conversation),
                                    onTogglePin: () => onTogglePin(conversation),
                                    onToggleMute: () => onToggleMute(conversation),
                                    onToggleArchive: () => onToggleArchive(conversation),
                                    onToggleFavorite: () => onToggleFavorite(conversation),
                                    onDeleteConversation: () => onDeleteConversation(conversation),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                          ],

                          // 3. GROUPS & ROOMS FILTER
                          if (currentFilter == ChatSidebarFilter.rooms) ...[
                            _SidebarSectionHeader(
                              title: 'المجموعات والقنوات (${groupConversations.length})',
                              subtitle: 'كل الغرف والمجموعات وقنوات الإعلانات المشترك بها.',
                              appearance: appearance,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 8),
                            if (groupConversations.isEmpty)
                              _SidebarInlineNotice(
                                label: 'لا توجد مجموعات أو غرف مفتوحة حاليًا.',
                                appearance: appearance,
                                isDark: isDark,
                              )
                            else
                              ...groupConversations.map(
                                (conversation) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: ChatListItem(
                                    conversation: conversation,
                                    unreadBadgeColor: appearance.unreadBadgeColor,
                                    currentUserId: currentUserId,
                                    typingPreviewText:
                                        typingPreviewByConversationId[conversation.id],
                                    selected: selectedConversationId == conversation.id,
                                    onTap: () => onConversationSelected(conversation),
                                    onTogglePin: () => onTogglePin(conversation),
                                    onToggleMute: () => onToggleMute(conversation),
                                    onToggleArchive: () => onToggleArchive(conversation),
                                    onToggleFavorite: () => onToggleFavorite(conversation),
                                    onDeleteConversation: () => onDeleteConversation(conversation),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                          ],

                          // 4. DEPARTMENTS FILTER: Official rooms
                          if (currentFilter == ChatSidebarFilter.departments) ...[
                            _SidebarSectionHeader(
                              title: 'غرف الأقسام الرسمية (${departmentRooms.length})',
                              subtitle: 'الغرف الجماعية الرسمية لأقسام الشركة.',
                              appearance: appearance,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 8),
                            if (departmentRooms.isEmpty)
                              _SidebarInlineNotice(
                                label: 'لا توجد غرف أقسام مفتوحة حاليًا.',
                                appearance: appearance,
                                isDark: isDark,
                              )
                            else
                              ...departmentRooms.map(
                                (conversation) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: ChatListItem(
                                    conversation: conversation,
                                    unreadBadgeColor: appearance.unreadBadgeColor,
                                    currentUserId: currentUserId,
                                    typingPreviewText:
                                        typingPreviewByConversationId[conversation.id],
                                    selected: selectedConversationId == conversation.id,
                                    onTap: () => onConversationSelected(conversation),
                                    onTogglePin: () => onTogglePin(conversation),
                                    onToggleMute: () => onToggleMute(conversation),
                                    onToggleArchive: () => onToggleArchive(conversation),
                                    onToggleFavorite: () => onToggleFavorite(conversation),
                                    onDeleteConversation: () => onDeleteConversation(conversation),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                          ],

                          // 6. FAVORITES FILTER
                          if (currentFilter == ChatSidebarFilter.favorites) ...[
                            _SidebarSectionHeader(
                              title: 'المفضلة (${favoriteConversations.length})',
                              subtitle: 'كل المحادثات التي قمت بتمييزها بنجمة.',
                              appearance: appearance,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 8),
                            if (favoriteConversations.isEmpty)
                              _SidebarInlineNotice(
                                label: 'لا توجد محادثات في المفضلة حاليًا.',
                                appearance: appearance,
                                isDark: isDark,
                              )
                            else
                              ...favoriteConversations.map(
                                (conversation) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: ChatListItem(
                                    conversation: conversation,
                                    unreadBadgeColor: appearance.unreadBadgeColor,
                                    currentUserId: currentUserId,
                                    typingPreviewText:
                                        typingPreviewByConversationId[conversation.id],
                                    selected: selectedConversationId == conversation.id,
                                    onTap: () => onConversationSelected(conversation),
                                    onTogglePin: () => onTogglePin(conversation),
                                    onToggleMute: () => onToggleMute(conversation),
                                    onToggleArchive: () => onToggleArchive(conversation),
                                    onToggleFavorite: () => onToggleFavorite(conversation),
                                    onDeleteConversation: () => onDeleteConversation(conversation),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                          ],

                          // 7. ARCHIVED FILTER
                          if (currentFilter == ChatSidebarFilter.archived) ...[
                            _SidebarSectionHeader(
                              title: 'المحادثات المؤرشفة (${archivedConversations.length})',
                              subtitle: 'المحادثات التي تم نقلها إلى الأرشيف.',
                              appearance: appearance,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 8),
                            if (archivedConversations.isEmpty)
                              _SidebarInlineNotice(
                                label: 'لا توجد محادثات مؤرشفة حاليًا.',
                                appearance: appearance,
                                isDark: isDark,
                              )
                            else
                              ...archivedConversations.map(
                                (conversation) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: ChatListItem(
                                    conversation: conversation,
                                    unreadBadgeColor: appearance.unreadBadgeColor,
                                    currentUserId: currentUserId,
                                    typingPreviewText:
                                        typingPreviewByConversationId[conversation.id],
                                    selected: selectedConversationId == conversation.id,
                                    onTap: () => onConversationSelected(conversation),
                                    onTogglePin: () => onTogglePin(conversation),
                                    onToggleMute: () => onToggleMute(conversation),
                                    onToggleArchive: () => onToggleArchive(conversation),
                                    onToggleFavorite: () => onToggleFavorite(conversation),
                                    onDeleteConversation: () => onDeleteConversation(conversation),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                          ],
                        ],

                        // ── DIRECTORY: DEPARTMENTS ─────────────────────────────────
                        if (currentFilter == ChatSidebarFilter.departments ||
                            (currentFilter == ChatSidebarFilter.direct && query.isEmpty)) ...[
                          _SidebarSectionHeader(
                            title: 'أقسام وموظفو الشركة (${orderedDepartmentEntries.length})',
                            subtitle:
                                'تصفح موظفي الشركة حسب الإدارات والأقسام الرسمية - انقر لبدء محادثة مباشرة.',
                            appearance: appearance,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 8),
                          if (orderedDepartmentEntries.isEmpty)
                            _SidebarInlineNotice(
                              label: 'لا توجد أقسام مطابقة لنتيجة البحث الحالية.',
                              appearance: appearance,
                              isDark: isDark,
                            )
                          else
                            ...orderedDepartmentEntries.map((entry) {
                              final department = entry.key;
                              final users = [...entry.value]
                                ..sort(
                                  (a, b) => a.displayName.compareTo(b.displayName),
                                );
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _SidebarDepartmentBlock(
                                  title: department?.name ?? 'أعضاء بانتظار تخصيص قسم',
                                  subtitle: department == null
                                      ? 'أعضاء غير مرتبطين بقسم محدد حاليًا'
                                      : (department.description.isEmpty
                                          ? 'قسم ${department.code}'
                                          : department.description),
                                  accent: _departmentAccent(department),
                                  appearance: appearance,
                                  isDark: isDark,
                                  users: users,
                                  membersCount: department?.membersCount ?? users.length,
                                  initiallyExpanded: query.isNotEmpty,
                                  conversationForUser: _conversationForUser,
                                  onUserTap: onOpenOrStartDirectConversation,
                                ),
                              );
                            }),
                          const SizedBox(height: 14),
                        ],

                        // ── DIRECTORY: BRANCHES ────────────────────────────────────
                        if (currentFilter == ChatSidebarFilter.branches) ...[
                          _SidebarSectionHeader(
                            title: 'فروع وموظفو الشركة (${orderedBranchEntries.length})',
                            subtitle:
                                'تصفح موظفي الشركة حسب الفروع والمقرات - انقر للمحادثة المباشرة.',
                            appearance: appearance,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 8),
                          if (orderedBranchEntries.isEmpty)
                            _SidebarInlineNotice(
                              label: 'لا توجد فروع مطابقة لنتيجة البحث الحالية.',
                              appearance: appearance,
                              isDark: isDark,
                            )
                          else
                            ...orderedBranchEntries.map((entry) {
                              final branch = entry.key;
                              final users = [...entry.value]
                                ..sort(
                                  (a, b) => a.displayName.compareTo(b.displayName),
                                );
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _SidebarDepartmentBlock(
                                  title: branch?.name ?? 'أعضاء بانتظار تخصيص فرع',
                                  subtitle: branch == null
                                      ? 'أعضاء غير مرتبطين بفرع محدد حاليًا'
                                      : (branch.description.isEmpty
                                          ? 'فرع ${branch.code}'
                                          : branch.description),
                                  accent: _branchAccent(branch),
                                  appearance: appearance,
                                  isDark: isDark,
                                  users: users,
                                  membersCount: branch?.membersCount ?? users.length,
                                  initiallyExpanded: query.isNotEmpty,
                                  conversationForUser: _conversationForUser,
                                  onUserTap: onOpenOrStartDirectConversation,
                                ),
                              );
                            }),
                          const SizedBox(height: 14),
                        ],

                        if (query.isNotEmpty &&
                            unarchivedConversations.isEmpty &&
                            matchingUsers.isEmpty &&
                            orderedDepartmentEntries.isEmpty &&
                            orderedBranchEntries.isEmpty)
                          _SidebarInlineNotice(
                            label: 'لم يتم العثور على أي نتائج مطابقة لـ "$query".',
                            appearance: appearance,
                            isDark: isDark,
                          )
                        else if (query.isEmpty &&
                            currentFilter != ChatSidebarFilter.all &&
                            departmentRooms.isEmpty &&
                            groupConversations.isEmpty &&
                            directConversations.isEmpty &&
                            orderedDepartmentEntries.isEmpty &&
                            orderedBranchEntries.isEmpty)
                          _SidebarInlineNotice(
                            label: 'لا توجد محادثات أو أشخاص ظاهرون الآن.',
                            appearance: appearance,
                            isDark: isDark,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  ChatConversation? _conversationForUser(ChatDirectoryUser user) {
    for (final conversation in overview.directConversations) {
      final hasPeer = conversation.members.any(
        (member) => member.id == user.id,
      );
      final hasCurrent = conversation.members.any(
        (member) => member.id == currentUserId,
      );
      if (hasPeer && hasCurrent) {
        return conversation;
      }
    }
    return null;
  }
}

class _CompactChatSidebar extends StatelessWidget {
  const _CompactChatSidebar({
    required this.sidebarBg,
    required this.currentUser,
    required this.currentThemeMode,
    required this.isDark,
    required this.appearance,
    required this.conversations,
    required this.currentUserId,
    required this.selectedConversationId,
    required this.canOpenAdmin,
    required this.onConversationSelected,
    required this.onCreateConversation,
    required this.onRefresh,
    required this.onOpenAdmin,
    required this.onOpenTickets,
    required this.onOpenFiles,
    required this.onOpenServers,
    required this.onOpenProfile,
    required this.onOpenFavoriteMessages,
    required this.onToggleTheme,
  });

  final Color sidebarBg;
  final AppUser? currentUser;
  final ThemeMode currentThemeMode;
  final bool isDark;
  final ChatResolvedAppearance appearance;
  final List<ChatConversation> conversations;
  final String currentUserId;
  final String? selectedConversationId;
  final bool canOpenAdmin;
  final ValueChanged<ChatConversation> onConversationSelected;
  final VoidCallback onCreateConversation;
  final VoidCallback onRefresh;
  final VoidCallback onOpenAdmin;
  final VoidCallback onOpenTickets;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenServers;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenFavoriteMessages;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final userLabel = (currentUser?.fullName.trim().isNotEmpty ?? false)
        ? currentUser!.fullName
        : (currentUser?.username ?? 'مستخدم');

    return ColoredBox(
      color: sidebarBg,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
            decoration: BoxDecoration(
              color: Color.lerp(
                appearance.incomingBubbleColor,
                isDark ? const Color(0xFF212121) : Colors.white,
                isDark ? 0.16 : 0.42,
              ),
              border: Border(
                bottom: BorderSide(
                  color: appearance.accent.withValues(alpha: 0.14),
                ),
              ),
            ),
            child: Column(
              children: [
                Tooltip(
                  message: userLabel,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: appearance.accent,
                        child: Text(
                          _firstCharacter(userLabel).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        end: 1,
                        bottom: 1,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4DCC6E),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF212121)
                                  : Colors.white,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // _CompactSidebarIconButton(
                //   tooltip: switch (currentThemeMode) {
                //     ThemeMode.dark => 'الوضع الداكن',
                //     ThemeMode.system => 'الوضع الفاتح',
                //     ThemeMode.light => 'الوضع الفاتح',
                //   },
                //   icon: switch (currentThemeMode) {
                //     ThemeMode.dark => Icons.dark_mode_outlined,
                //     ThemeMode.system => Icons.light_mode_outlined,
                //     ThemeMode.light => Icons.light_mode_outlined,
                //   },
                //   color: appearance.accent,
                //   onPressed: onToggleTheme,
                // ),
                // const SizedBox(height: 6),
                // _CompactSidebarIconButton(
                //   tooltip: 'تحديث',
                //   icon: Icons.refresh_rounded,
                //   color: isDark ? Colors.white70 : const Color(0xFF708499),
                //   onPressed: onRefresh,
                // ),
                // const SizedBox(height: 6),
                // _CompactSidebarIconButton(
                //   tooltip: 'الملفات',
                //   icon: Icons.folder_copy_outlined,
                //   color: isDark ? Colors.white70 : const Color(0xFF708499),
                //   onPressed: onOpenFiles,
                // ),
                // const SizedBox(height: 6),
                // _CompactSidebarIconButton(
                //   tooltip: 'السيرفرات',
                //   icon: Icons.dns_rounded,
                //   color: isDark ? Colors.white70 : const Color(0xFF708499),
                //   onPressed: onOpenServers,
                // ),
                // const SizedBox(height: 6),
                // _CompactSidebarIconButton(
                //   tooltip: 'الملف الشخصي',
                //   icon: Icons.account_circle_outlined,
                //   color: isDark ? Colors.white70 : const Color(0xFF708499),
                //   onPressed: onOpenProfile,
                // ),
                const SizedBox(height: 6),
                _CompactSidebarIconButton(
                  tooltip: 'محادثة جديدة',
                  icon: Iconsax.message,
                  color: appearance.accent,
                  onPressed: onCreateConversation,
                ),
                const SizedBox(height: 6),
                Consumer(
                  builder: (context, ref, _) => _CompactSidebarIconButton(
                    tooltip: 'الحافظة المشتركة الفورية (الكمبيوتر ⇄ الموبايل)',
                    icon: Icons.content_paste_go_rounded,
                    color: isDark ? Colors.white70 : const Color(0xFF708499),
                    onPressed: () =>
                        showDesktopInstantClipboardSyncDialog(context, ref),
                  ),
                ),
                const SizedBox(height: 6),
                _CompactSidebarIconButton(
                  tooltip: 'الرسائل المفضلة',
                  icon: Icons.star_outline_rounded,
                  color: isDark ? Colors.white70 : const Color(0xFF708499),
                  onPressed: onOpenFavoriteMessages,
                ),
                // if (canOpenAdmin) ...[
                //   const SizedBox(height: 6),
                //   _CompactSidebarIconButton(
                //     tooltip: 'لوحة الإدارة',
                //     icon: Icons.admin_panel_settings_outlined,
                //     color: isDark ? Colors.white70 : const Color(0xFF708499),
                //     onPressed: onOpenAdmin,
                //   ),
                // ],
                // const SizedBox(height: 6),
                // _CompactSidebarIconButton(
                //   tooltip: 'تذاكر الدعم',
                //   icon: Icons.support_agent_rounded,
                //   color: isDark ? Colors.white70 : const Color(0xFF708499),
                //   onPressed: onOpenTickets,
                // ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              interactive: false,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
                itemCount: conversations.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  return _CompactConversationAvatar(
                    conversation: conversation,
                    currentUserId: currentUserId,
                    selected: selectedConversationId == conversation.id,
                    accent: appearance.accent,
                    unreadBadgeColor: appearance.unreadBadgeColor,
                    onTap: () => onConversationSelected(conversation),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactSidebarIconButton extends StatelessWidget {
  const _CompactSidebarIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

class _CompactConversationAvatar extends StatelessWidget {
  const _CompactConversationAvatar({
    required this.conversation,
    required this.currentUserId,
    required this.selected,
    required this.accent,
    this.unreadBadgeColor,
    required this.onTap,
  });

  final ChatConversation conversation;
  final String currentUserId;
  final bool selected;
  final Color accent;
  final Color? unreadBadgeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final peer = conversation.type == 'direct'
        ? conversation.members
              .where((entry) => entry.id != currentUserId)
              .cast<ChatDirectoryUser?>()
              .firstWhere((_) => true, orElse: () => null)
        : null;
    final title = conversation.displayTitle(currentUserId);
    final avatarLabel = (peer?.displayName ?? title).trim();

    return Tooltip(
      message: title,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected
                      ? accent.withValues(alpha: 0.42)
                      : Colors.transparent,
                ),
              ),
              child: SafeNetworkAvatar(
                radius: 24,
                backgroundColor: conversationTypeAccent(
                  conversation.type,
                ).withValues(alpha: 0.16),
                imageUrl: peer?.avatarUrl,
                fallbackText: avatarLabel.isEmpty
                    ? '?'
                    : avatarLabel.substring(0, 1).toUpperCase(),
                fallbackTextStyle: TextStyle(
                  color: conversationTypeAccent(conversation.type),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (conversation.unreadCount > 0)
              PositionedDirectional(
                top: -2,
                end: -1,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: unreadBadgeColor ?? const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                  child: Text(
                    '${conversation.unreadCount}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Sidebar Header ─────────────────────────────────────────────────────────────
class _SidebarHeader extends ConsumerWidget {
  const _SidebarHeader({
    required this.userLabel,
    required this.unreadTotal,
    required this.canOpenAdmin,
    required this.currentThemeMode,
    required this.isDark,
    required this.appearance,
    required this.onCreateConversation,
    required this.onRefresh,
    required this.onOpenAdmin,
    required this.onOpenTickets,
    required this.onOpenFiles,
    required this.onOpenServers,
    required this.onOpenProfile,
    required this.onOpenFavoriteMessages,
    required this.onToggleTheme,
    this.conversations = const [],
    this.currentUserId,
  });

  final List<ChatConversation> conversations;
  final String? currentUserId;
  final String userLabel;
  final int unreadTotal;
  final bool canOpenAdmin;
  final ThemeMode currentThemeMode;
  final bool isDark;
  final ChatResolvedAppearance appearance;
  final VoidCallback onCreateConversation;
  final VoidCallback onRefresh;
  final VoidCallback onOpenAdmin;
  final VoidCallback onOpenTickets;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenServers;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenFavoriteMessages;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < (canOpenAdmin ? 332 : 304);
        final isVeryNarrow = constraints.maxWidth < 288;

        return Container(
          padding: EdgeInsets.fromLTRB(
            isVeryNarrow ? 8 : (isNarrow ? 10 : 14),
            12,
            isVeryNarrow ? 4 : (isNarrow ? 6 : 8),
            10,
          ),
          decoration: BoxDecoration(
            color: Color.lerp(
              appearance.incomingBubbleColor,
              isDark ? const Color(0xFF212121) : Colors.white,
              isDark ? 0.16 : 0.12,
            ),
            border: Border(
              bottom: BorderSide(
                color: appearance.accent.withValues(alpha: 0.14),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: isVeryNarrow ? 18 : (isNarrow ? 19 : 21),
                    backgroundColor: appearance.accent,
                    child: Text(
                      _firstCharacter(userLabel).toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4DCC6E),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF212121)
                              : Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(width: isVeryNarrow ? 6 : (isNarrow ? 8 : 10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isDark ? Colors.white : const Color(0xFF1C2B3A),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      unreadTotal > 0 ? '$unreadTotal غير مقروءة' : 'متصل',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: unreadTotal > 0
                            ? const Color(0xFF3390EC)
                            : (isDark
                                  ? Colors.white38
                                  : const Color(0xFF708499)),
                        fontWeight: unreadTotal > 0
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              _TgIconButton(
                tooltip: 'محادثة جديدة',
                icon: Iconsax.message,
                isDark: isDark,
                accentColor: appearance.accent,
                onPressed: onCreateConversation,
                accent: true,
                dense: true,
              ),
              const SizedBox(width: 6),
              _TgIconButton(
                tooltip: 'إنشاء مجلد محادثات',
                icon: Icons.create_new_folder_rounded,
                isDark: isDark,
                accentColor: appearance.accent,
                onPressed: () {
                  showCreateOrEditChatFolderDialog(
                    context,
                    availableConversations: conversations,
                    currentUserId: currentUserId,
                  );
                },
                dense: true,
              ),
              const SizedBox(width: 6),
              _TgIconButton(
                tooltip: 'الحافظة المشتركة الفورية (الكمبيوتر ⇄ الموبايل)',
                icon: Icons.content_paste_go_rounded,
                isDark: isDark,
                accentColor: appearance.accent,
                onPressed: () =>
                    showDesktopInstantClipboardSyncDialog(context, ref),
                dense: true,
              ),
              const SizedBox(width: 6),
              _TgIconButton(
                tooltip: 'الرسائل المفضلة',
                icon: Icons.star_outline_rounded,
                isDark: isDark,
                accentColor: appearance.accent,
                onPressed: onOpenFavoriteMessages,
                dense: true,
              ),
              // if (isNarrow) ...[
              //   if (showThemeInCompact)
              //     // _TgIconButton(
              //     //   tooltip: switch (currentThemeMode) {
              //     //     ThemeMode.dark => 'الوضع الداكن',
              //     //     ThemeMode.system => 'الوضع الفاتح',
              //     //     ThemeMode.light => 'الوضع الفاتح',
              //     //   },
              //     //   icon: switch (currentThemeMode) {
              //     //     ThemeMode.dark => Icons.dark_mode_outlined,
              //     //     ThemeMode.system => Icons.light_mode_outlined,
              //     //     ThemeMode.light => Icons.light_mode_outlined,
              //     //   },
              //     //   isDark: isDark,
              //     //   accentColor: appearance.accent,
              //     //   onPressed: onToggleTheme,
              //     //   dense: true,
              //     // ),
              //   if (showComposeInCompact)
              //     _TgIconButton(
              //         tooltip: 'محادثة جديدة',
              //         icon: Icons.edit_outlined,
              //         isDark: isDark,
              //         accentColor: appearance.accent,
              //         onPressed: onCreateConversation,
              //         accent: true,
              //         dense: true,
              //       ),
              //   // _SidebarHeaderMoreButton(
              //   //   isDark: isDark,
              //   //   accentColor: appearance.accent,
              //   //   canOpenAdmin: canOpenAdmin,
              //   //   onRefresh: onRefresh,
              //   //   onOpenFiles: onOpenFiles,
              //   //   onOpenServers: onOpenServers,
              //   //   onOpenProfile: onOpenProfile,
              //   //   onOpenAdmin: onOpenAdmin,
              //   //   onOpenTickets: onOpenTickets,
              //   // ),
              // ] else ...[
              //   // _TgIconButton(
              //   //   tooltip: switch (currentThemeMode) {
              //   //     ThemeMode.dark => 'الوضع الداكن',
              //   //     ThemeMode.system => 'الوضع الفاتح',
              //   //     ThemeMode.light => 'الوضع الفاتح',
              //   //   },
              //   //   icon: switch (currentThemeMode) {
              //   //     ThemeMode.dark => Icons.dark_mode_outlined,
              //   //     ThemeMode.system => Icons.light_mode_outlined,
              //   //     ThemeMode.light => Icons.light_mode_outlined,
              //   //   },
              //   //   isDark: isDark,
              //   //   accentColor: appearance.accent,
              //   //   onPressed: onToggleTheme,
              //   // ),
              //   // _TgIconButton(
              //   //   tooltip: 'تحديث',
              //   //   icon: Icons.refresh_rounded,
              //   //   isDark: isDark,
              //   //   accentColor: appearance.accent,
              //   //   onPressed: onRefresh,
              //   // ),
              //   // _TgIconButton(
              //   //   tooltip: 'الملفات',
              //   //   icon: Icons.folder_copy_outlined,
              //   //   isDark: isDark,
              //   //   accentColor: appearance.accent,
              //   //   onPressed: onOpenFiles,
              //   // ),
              //   // _TgIconButton(
              //   //   tooltip: 'السيرفرات',
              //   //   icon: Icons.dns_rounded,
              //   //   isDark: isDark,
              //   //   accentColor: appearance.accent,
              //   //   onPressed: onOpenServers,
              //   // ),
              //   _TgIconButton(
              //     tooltip: 'الملف الشخصي',
              //     icon: Icons.account_circle_outlined,
              //     isDark: isDark,
              //     accentColor: appearance.accent,
              //     onPressed: onOpenProfile,
              //   ),
              //   _TgIconButton(
              //     tooltip: 'محادثة جديدة',
              //     icon: Icons.edit_outlined,
              //     isDark: isDark,
              //     accentColor: appearance.accent,
              //     onPressed: onCreateConversation,
              //     accent: true,
              //   ),
              //   // if (canOpenAdmin)
              //   //   _TgIconButton(
              //   //     tooltip: 'لوحة الإدارة',
              //   //     icon: Icons.admin_panel_settings_outlined,
              //   //     isDark: isDark,
              //   //     accentColor: appearance.accent,
              //   //     onPressed: onOpenAdmin,
              //   //   ),
              //   // _TgIconButton(
              //   //   tooltip: 'تذاكر الدعم',
              //   //   icon: Icons.support_agent_rounded,
              //   //   isDark: isDark,
              //   //   accentColor: appearance.accent,
              //   //   onPressed: onOpenTickets,
              //   // ),
              // ],
            ],
          ),
        );
      },
    );
  }
}

// ── Telegram-style icon button ─────────────────────────────────────────────────
class _TgIconButton extends StatelessWidget {
  const _TgIconButton({
    required this.icon,
    required this.onPressed,
    required this.isDark,
    required this.accentColor,
    this.tooltip,
    this.accent = false,
    this.dense = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool isDark;
  final Color accentColor;
  final String? tooltip;
  final bool accent;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? accentColor
        : (isDark ? Colors.white60 : const Color(0xFF708499));

    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsets.all(dense ? 5 : 7),
          child: Icon(icon, size: dense ? 18 : 20, color: color),
        ),
      ),
    );
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.appearance,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isDark;
  final ChatResolvedAppearance appearance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedBg = appearance.accent.withValues(
      alpha: isDark ? 0.22 : 0.14,
    );
    final unselectedBg = Color.lerp(
      appearance.incomingBubbleColor,
      Theme.of(context).colorScheme.surfaceContainerHighest,
      isDark ? 0.28 : 0.14,
    )!;
    final selectedText = isDark ? Colors.white : appearance.accent;
    final unselectedText = isDark ? Colors.white54 : const Color(0xFF708499);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? selectedBg : unselectedBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? selectedText : unselectedText,
          ),
        ),
      ),
    );
  }
}

class _SidebarSectionHeader extends StatelessWidget {
  const _SidebarSectionHeader({
    required this.title,
    required this.subtitle,
    required this.appearance,
    required this.isDark,
  });

  final String title;
  final String subtitle;
  final ChatResolvedAppearance appearance;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1C2B3A),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 48,
            height: 3,
            decoration: BoxDecoration(
              color: appearance.accent.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white38 : const Color(0xFF708499),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarInlineNotice extends StatelessWidget {
  const _SidebarInlineNotice({
    required this.label,
    required this.appearance,
    required this.isDark,
  });

  final String label;
  final ChatResolvedAppearance appearance;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.lerp(
          appearance.incomingBubbleColor,
          Theme.of(context).colorScheme.surface,
          isDark ? 0.16 : 0.32,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: appearance.accent.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: isDark ? Colors.white54 : const Color(0xFF708499),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white70 : const Color(0xFF5C6E7D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarDepartmentBlock extends StatelessWidget {
  const _SidebarDepartmentBlock({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.appearance,
    required this.isDark,
    required this.users,
    required this.membersCount,
    required this.conversationForUser,
    required this.onUserTap,
    this.initiallyExpanded = false,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final ChatResolvedAppearance appearance;
  final bool isDark;
  final List<ChatDirectoryUser> users;
  final int membersCount;
  final ChatConversation? Function(ChatDirectoryUser user) conversationForUser;
  final ValueChanged<ChatDirectoryUser> onUserTap;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color.lerp(
        appearance.incomingBubbleColor,
        Theme.of(context).colorScheme.surface,
        isDark ? 0.18 : 0.32,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: appearance.accent.withValues(alpha: 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('dept_${title}_$initiallyExpanded'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          initiallyExpanded: initiallyExpanded,
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: accent.withValues(alpha: 0.14),
            child: Icon(Icons.apartment_rounded, color: accent, size: 18),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1C2B3A),
            ),
          ),
          subtitle: Text(
            '$subtitle • $membersCount شخص',
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white38 : const Color(0xFF708499),
            ),
          ),
          children: [
            for (final user in users)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _SidebarUserTile(
                  user: user,
                  accent: accent,
                  appearance: appearance,
                  isDark: isDark,
                  existingConversation: conversationForUser(user),
                  onTap: () => onUserTap(user),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarUserTile extends StatelessWidget {
  const _SidebarUserTile({
    required this.user,
    required this.accent,
    required this.appearance,
    required this.isDark,
    required this.existingConversation,
    required this.onTap,
  });

  final ChatDirectoryUser user;
  final Color accent;
  final ChatResolvedAppearance appearance;
  final bool isDark;
  final ChatConversation? existingConversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasConversation = existingConversation != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Color.lerp(
              appearance.incomingBubbleColor,
              Theme.of(context).colorScheme.surfaceContainerHighest,
              isDark ? 0.24 : 0.12,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  SafeNetworkAvatar(
                    radius: 19,
                    backgroundColor: accent.withValues(alpha: 0.14),
                    imageUrl: user.avatarUrl,
                    fallbackText: _firstCharacter(
                      user.displayName,
                    ).toUpperCase(),
                    fallbackTextStyle: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  PositionedDirectional(
                    end: 0,
                    bottom: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: presenceColor(user.presenceStatus),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? Color.lerp(
                                  appearance.incomingBubbleColor,
                                  const Color(0xFF2B2B2B),
                                  0.30,
                                )!
                              : Color.lerp(
                                  Theme.of(context).colorScheme.surface,
                                  const Color(0xFFF7F9FB),
                                  0.50,
                                )!,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: user.jobTitle.trim().isNotEmpty
                          ? '${user.displayName}\n💼 ${user.jobTitle.trim()}'
                          : (user.branchCode.isNotEmpty
                              ? '${user.displayName} • فرع ${user.branchCode}'
                              : user.displayName),
                      child: Text(
                        user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF1C2B3A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.jobTitle.trim().isNotEmpty
                          ? '${user.jobTitle.trim()} • ${formatPresenceLabel(user)}'
                          : '@${user.username} • ${formatPresenceLabel(user)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? Colors.white38
                            : const Color(0xFF708499),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: hasConversation
                      ? accent.withValues(alpha: 0.12)
                      : (isDark
                            ? const Color(0xFF313131)
                            : const Color(0xFFEAF2FC)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  hasConversation ? 'فتح' : 'ابدأ شات',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: hasConversation ? accent : const Color(0xFF3390EC),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper ─────────────────────────────────────────────────────────────────────
String _firstCharacter(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'م';
  return trimmed.substring(0, 1);
}


Color _departmentAccent(DepartmentSummary? department) {
  const palette = <Color>[
    Color(0xFF3390EC),
    Color(0xFF19A974),
    Color(0xFFE67E22),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF0EA5A5),
    Color(0xFFEF4444),
    Color(0xFF4A90E2),
  ];

  final seed =
      '${department?.id ?? 'unassigned'}|${department?.code ?? ''}|${department?.name ?? ''}';
  final hash = seed.runes.fold<int>(
    0,
    (value, rune) => ((value * 37) + rune) & 0x7fffffff,
  );
  return palette[hash % palette.length];
}

Color _branchAccent(BranchSummary? branch) {
  const palette = <Color>[
    Color(0xFF2563EB),
    Color(0xFF0F766E),
    Color(0xFFEA580C),
    Color(0xFFDC2626),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
    Color(0xFF65A30D),
    Color(0xFFDB2777),
  ];

  final seed =
      '${branch?.id ?? 'unassigned'}|${branch?.code ?? ''}|${branch?.name ?? ''}';
  final hash = seed.runes.fold<int>(
    0,
    (value, rune) => ((value * 41) + rune) & 0x7fffffff,
  );
  return palette[hash % palette.length];
}



