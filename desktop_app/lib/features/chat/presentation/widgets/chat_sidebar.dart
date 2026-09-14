// import 'package:flutter/material.dart';

// import '../../../../shared/models/app_user.dart';
// import '../../models/chat_models.dart';
// import 'chat_list_item.dart';
// import 'chat_ui_helpers.dart';

// class ChatSidebar extends StatelessWidget {
//   const ChatSidebar({
//     super.key,
//     required this.currentUser,
//     required this.currentThemeMode,
//     required this.searchController,
//     required this.currentFilter,
//     required this.conversations,
//     required this.selectedConversationId,
//     required this.onFilterChanged,
//     required this.onConversationSelected,
//     required this.onCreateConversation,
//     required this.onRefresh,
//     required this.onOpenAdmin,
//     required this.onToggleTheme,
//     required this.onTogglePin,
//     required this.onToggleMute,
//     required this.onToggleArchive,
//     required this.onDeleteConversation,
//   });

//   final AppUser? currentUser;
//   final ThemeMode currentThemeMode;
//   final TextEditingController searchController;
//   final ChatSidebarFilter currentFilter;
//   final List<ChatConversation> conversations;
//   final String? selectedConversationId;
//   final ValueChanged<ChatSidebarFilter> onFilterChanged;
//   final ValueChanged<ChatConversation> onConversationSelected;
//   final VoidCallback onCreateConversation;
//   final VoidCallback onRefresh;
//   final VoidCallback onOpenAdmin;
//   final VoidCallback onToggleTheme;
//   final ValueChanged<ChatConversation> onTogglePin;
//   final ValueChanged<ChatConversation> onToggleMute;
//   final ValueChanged<ChatConversation> onToggleArchive;
//   final ValueChanged<ChatConversation> onDeleteConversation;

//   @override
//   Widget build(BuildContext context) {
//     final surface = Theme.of(context).colorScheme.surface;
//     final userLabel = (currentUser?.fullName.trim().isNotEmpty ?? false)
//         ? currentUser!.fullName
//         : (currentUser?.username ?? 'User');
//     final unreadTotal = conversations.fold<int>(
//       0,
//       (sum, conversation) => sum + conversation.unreadCount,
//     );

//     return Container(
//       color: surface,
//       child: Column(
//         children: [
//           _SidebarHeader(
//             userLabel: userLabel,
//             unreadTotal: unreadTotal,
//             canOpenAdmin:
//                 currentUser?.can('canCreateUsers') == true ||
//                 currentUser?.can('canCreateDepartments') == true,
//             currentThemeMode: currentThemeMode,
//             onCreateConversation: onCreateConversation,
//             onRefresh: onRefresh,
//             onOpenAdmin: onOpenAdmin,
//             onToggleTheme: onToggleTheme,
//           ),
//           Padding(
//             padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
//             child: TextField(
//               controller: searchController,
//               decoration: const InputDecoration(
//                 hintText: 'Search',
//                 prefixIcon: Icon(Icons.search_rounded),
//               ),
//             ),
//           ),
//           Padding(
//             padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
//             child: Wrap(
//               spacing: 6,
//               runSpacing: 6,
//               children: [
//                 _FilterButton(
//                   label: 'All',
//                   selected: currentFilter == ChatSidebarFilter.all,
//                   onTap: () => onFilterChanged(ChatSidebarFilter.all),
//                 ),
//                 _FilterButton(
//                   label: 'Direct',
//                   selected: currentFilter == ChatSidebarFilter.direct,
//                   onTap: () => onFilterChanged(ChatSidebarFilter.direct),
//                 ),
//                 _FilterButton(
//                   label: 'Departments',
//                   selected: currentFilter == ChatSidebarFilter.departments,
//                   onTap: () => onFilterChanged(ChatSidebarFilter.departments),
//                 ),
//                 _FilterButton(
//                   label: 'Rooms',
//                   selected: currentFilter == ChatSidebarFilter.rooms,
//                   onTap: () => onFilterChanged(ChatSidebarFilter.rooms),
//                 ),
//               ],
//             ),
//           ),
//           const Divider(height: 1),
//           Expanded(
//             child: conversations.isEmpty
//                 ? const Center(child: Text('No conversations'))
//                 : Scrollbar(
//                     child: ListView.builder(
//                       padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
//                       itemCount: conversations.length,
//                       itemBuilder: (context, index) {
//                         final conversation = conversations[index];
//                         return Padding(
//                           padding: const EdgeInsets.only(bottom: 2),
//                           child: ChatListItem(
//                             conversation: conversation,
//                             currentUserId: currentUser?.id ?? '',
//                             selected: selectedConversationId == conversation.id,
//                             onTap: () => onConversationSelected(conversation),
//                             onTogglePin: () => onTogglePin(conversation),
//                             onToggleMute: () => onToggleMute(conversation),
//                             onToggleArchive: () =>
//                                 onToggleArchive(conversation),
//                             onDeleteConversation: () =>
//                                 onDeleteConversation(conversation),
//                           ),
//                         );
//                       },
//                     ),
//                   ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _SidebarHeader extends ConsumerWidget {
//   const _SidebarHeader({
//     required this.userLabel,
//     required this.unreadTotal,
//     required this.canOpenAdmin,
//     required this.currentThemeMode,
//     required this.onCreateConversation,
//     required this.onRefresh,
//     required this.onOpenAdmin,
//     required this.onToggleTheme,
//   });

//   final String userLabel;
//   final int unreadTotal;
//   final bool canOpenAdmin;
//   final ThemeMode currentThemeMode;
//   final VoidCallback onCreateConversation;
//   final VoidCallback onRefresh;
//   final VoidCallback onOpenAdmin;
//   final VoidCallback onToggleTheme;

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
//       child: Column(
//         children: [
//           Row(
//             children: [
//               CircleAvatar(
//                 radius: 22,
//                 backgroundColor: const Color(
//                   0xFF3390EC,
//                 ).withValues(alpha: 0.18),
//                 child: Text(
//                   _firstCharacter(userLabel).toUpperCase(),
//                   style: const TextStyle(
//                     fontWeight: FontWeight.w700,
//                     color: Color(0xFF1D4E89),
//                   ),
//                 ),
//               ),
//               const SizedBox(width: 10),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       userLabel,
//                       maxLines: 1,
//                       overflow: TextOverflow.ellipsis,
//                       style: Theme.of(context).textTheme.titleSmall?.copyWith(
//                         fontWeight: FontWeight.w700,
//                       ),
//                     ),
//                     const SizedBox(height: 2),
//                     Text(
//                       '$unreadTotal unread',
//                       style: Theme.of(context).textTheme.labelSmall?.copyWith(
//                         color: Theme.of(context).colorScheme.onSurfaceVariant,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               IconButton(
//                 tooltip: 'Theme',
//                 onPressed: onToggleTheme,
//                 icon: Icon(switch (currentThemeMode) {
//                   ThemeMode.dark => Icons.dark_mode_outlined,
//                   ThemeMode.system => Icons.brightness_auto_outlined,
//                   ThemeMode.light => Icons.light_mode_outlined,
//                 }),
//               ),
//               IconButton(
//                 tooltip: 'Refresh',
//                 onPressed: onRefresh,
//                 icon: const Icon(Icons.refresh_rounded),
//               ),
//             ],
//           ),
//           const SizedBox(height: 8),
//           Row(
//             children: [
//               Expanded(
//                 child: FilledButton.icon(
//                   onPressed: onCreateConversation,
//                   icon: const Icon(Icons.edit_square),
//                   label: const Text('New'),
//                 ),
//               ),
//               if (canOpenAdmin) ...[
//                 const SizedBox(width: 8),
//                 IconButton(
//                   tooltip: 'Admin',
//                   onPressed: onOpenAdmin,
//                   icon: const Icon(Icons.admin_panel_settings_outlined),
//                 ),
//               ],
//             ],
//           ),
//         ],
//       ),
//     );
//   }
// }

// String _firstCharacter(String value) {
//   final trimmed = value.trim();
//   if (trimmed.isEmpty) {
//     return 'U';
//   }
//   return trimmed.substring(0, 1);
// }

// class _FilterButton extends StatelessWidget {
//   const _FilterButton({
//     required this.label,
//     required this.selected,
//     required this.onTap,
//   });

//   final String label;
//   final bool selected;
//   final VoidCallback onTap;

//   @override
//   Widget build(BuildContext context) {
//     return Material(
//       color: selected ? const Color(0xFFE8F2FF) : const Color(0xFFF3F6FA),
//       borderRadius: BorderRadius.circular(10),
//       child: InkWell(
//         borderRadius: BorderRadius.circular(10),
//         onTap: onTap,
//         child: Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
//           child: Text(
//             label,
//             style: Theme.of(context).textTheme.labelMedium?.copyWith(
//               color: selected
//                   ? const Color(0xFF2D78C6)
//                   : const Color(0xFF5A6A78),
//               fontWeight: FontWeight.w700,
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
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
import 'chat_list_item.dart';
import 'chat_ui_helpers.dart';

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
    final query = searchController.text.trim().toLowerCase();
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
    final departmentById = {
      for (final department in overview.departments) department.id: department,
    };
    final branchById = {
      for (final branch in overview.branches) branch.id: branch,
    };
    final recentConversations = (currentFilter == ChatSidebarFilter.rooms
            ? const <ChatConversation>[]
            : currentFilter == ChatSidebarFilter.favorites
                ? const <ChatConversation>[]
                : currentFilter == ChatSidebarFilter.archived
                    ? conversations
                        .where((c) => c.type == 'direct' && c.isArchived)
                        .toList()
                    : currentFilter == ChatSidebarFilter.branches
                        ? const <ChatConversation>[]
                        : currentFilter == ChatSidebarFilter.direct
                            ? conversations
                                .where((c) => c.type == 'direct' && !c.isArchived)
                                .toList()
                            : conversations.take(6).toList())
        .where((c) => !folderConversationIds.contains(c.id))
        .toList();
    final groupedSpaces = switch (currentFilter) {
      ChatSidebarFilter.all => conversations.where(
        (conversation) => conversation.type != 'direct',
      ),
      ChatSidebarFilter.direct => const <ChatConversation>[],
      ChatSidebarFilter.departments => conversations.where(
        (conversation) => conversation.type == 'department',
      ),
      ChatSidebarFilter.branches => const <ChatConversation>[],
      ChatSidebarFilter.rooms => conversations.where(
        (conversation) =>
            conversation.type == 'group' ||
            conversation.type == 'broadcast' ||
            conversation.type == 'department',
      ),
      ChatSidebarFilter.favorites => conversations.where(
        (conversation) => conversation.isFavorite,
      ),
      ChatSidebarFilter.archived => const <ChatConversation>[],
    }.toList();

    final usersByDepartment = <DepartmentSummary?, List<ChatDirectoryUser>>{};
    final usersByBranch = <BranchSummary?, List<ChatDirectoryUser>>{};
    if (currentFilter != ChatSidebarFilter.rooms &&
        currentFilter != ChatSidebarFilter.favorites &&
        currentFilter != ChatSidebarFilter.archived) {
      for (final user in overview.users) {
        if (user.id == currentUserId) {
          continue;
        }
        final userDepartmentIds = user.departmentIds.isNotEmpty
            ? user.departmentIds
            : [if (user.departmentId != null) user.departmentId!];
        final userDepartments = userDepartmentIds
            .map((departmentId) => departmentById[departmentId])
            .whereType<DepartmentSummary>()
            .toList();
        final primaryDepartment = userDepartments.isNotEmpty
            ? userDepartments.first
            : departmentById[user.departmentId];
        final branch = branchById[user.branchId];
        if (!_matchesUserQuery(user, primaryDepartment, query) &&
            !userDepartments.any(
              (department) => _matchesUserQuery(user, department, query),
            )) {
          final displayName = user.displayName.toLowerCase();
          final username = user.username.toLowerCase();
          final branchName = branch?.name.toLowerCase() ?? '';
          final matchesBranch =
              query.isEmpty ||
              displayName.contains(query) ||
              username.contains(query) ||
              branchName.contains(query);
          if (!matchesBranch) {
            continue;
          }
        }
        if (userDepartments.isEmpty) {
          usersByDepartment
              .putIfAbsent(primaryDepartment, () => <ChatDirectoryUser>[])
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
                      hintText: 'بحث',
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
                        if (recentConversations.isNotEmpty) ...[
                          _SidebarSectionHeader(
                            title: currentFilter == ChatSidebarFilter.direct
                                ? 'المحادثات المباشرة'
                                : 'أحدث المحادثات',
                            subtitle: currentFilter == ChatSidebarFilter.direct
                                ? 'كل الشاتات المباشرة المتاحة لك.'
                                : 'أسرع طريق للمحادثات المفتوحة مؤخرًا.',
                            appearance: appearance,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 8),
                          ...recentConversations.map(
                            (conversation) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: ChatListItem(
                                conversation: conversation,
                                currentUserId: currentUserId,
                                typingPreviewText:
                                    typingPreviewByConversationId[conversation
                                        .id],
                                selected:
                                    selectedConversationId == conversation.id,
                                onTap: () =>
                                    onConversationSelected(conversation),
                                onTogglePin: () => onTogglePin(conversation),
                                onToggleMute: () => onToggleMute(conversation),
                                onToggleArchive: () =>
                                    onToggleArchive(conversation),
                                onToggleFavorite: () =>
                                    onToggleFavorite(conversation),
                                onDeleteConversation: () =>
                                    onDeleteConversation(conversation),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (currentFilter != ChatSidebarFilter.direct) ...[
                          _SidebarSectionHeader(
                            title:
                                currentFilter == ChatSidebarFilter.departments
                                ? 'غرف الأقسام'
                                : currentFilter == ChatSidebarFilter.branches
                                ? 'الدليل حسب الفروع'
                                : currentFilter == ChatSidebarFilter.favorites
                                ? 'المفضلة'
                                : 'مجموعاتي',
                            subtitle: currentFilter == ChatSidebarFilter.rooms
                                ? 'كل الغرف والمجموعات والقنوات التي أنت عضو فيها.'
                                : currentFilter == ChatSidebarFilter.branches
                                ? 'كل الموظفين ظاهرون هنا حسب الفروع التي ينشئها الأدمن.'
                                : currentFilter == ChatSidebarFilter.favorites
                                ? 'كل المحادثات التي قمت بوضعها في المفضلة.'
                                : 'المجموعات والغرف والإعلانات الخاصة بك.',
                            appearance: appearance,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 8),
                          if (groupedSpaces.isEmpty)
                            _SidebarInlineNotice(
                              label: currentFilter == ChatSidebarFilter.branches
                                  ? 'اختر فرعًا أو ابحث عن موظف لعرض نتائج الفروع.'
                                  : 'لا توجد مجموعات أو غرف مطابقة الآن.',
                              appearance: appearance,
                              isDark: isDark,
                            )
                          else
                            ...groupedSpaces.map(
                              (conversation) => Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: ChatListItem(
                                  conversation: conversation,
                                  currentUserId: currentUserId,
                                  typingPreviewText:
                                      typingPreviewByConversationId[conversation
                                          .id],
                                  selected:
                                      selectedConversationId == conversation.id,
                                  onTap: () =>
                                      onConversationSelected(conversation),
                                  onTogglePin: () => onTogglePin(conversation),
                                  onToggleMute: () =>
                                      onToggleMute(conversation),
                                  onToggleArchive: () =>
                                      onToggleArchive(conversation),
                                  onToggleFavorite: () =>
                                      onToggleFavorite(conversation),
                                  onDeleteConversation: () =>
                                      onDeleteConversation(conversation),
                                ),
                              ),
                            ),
                          if (currentFilter != ChatSidebarFilter.rooms &&
                              currentFilter != ChatSidebarFilter.branches &&
                              currentFilter != ChatSidebarFilter.favorites &&
                              currentFilter != ChatSidebarFilter.archived)
                            const SizedBox(height: 14),
                        ],
                        if (currentFilter != ChatSidebarFilter.rooms &&
                            currentFilter != ChatSidebarFilter.favorites &&
                            currentFilter != ChatSidebarFilter.archived) ...[
                          if (currentFilter != ChatSidebarFilter.branches) ...[
                            _SidebarSectionHeader(
                              title: 'الأشخاص حسب الأقسام',
                              subtitle:
                                  'كل الموظفين ظاهرون هنا حسب الأقسام التي ينشئها الأدمن.',
                              appearance: appearance,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 8),
                            if (orderedDepartmentEntries.isEmpty)
                              _SidebarInlineNotice(
                                label:
                                    'لا يوجد أشخاص مطابقون لنتيجة البحث الحالية.',
                                appearance: appearance,
                                isDark: isDark,
                              )
                            else
                              ...orderedDepartmentEntries.map((entry) {
                                final department = entry.key;
                                final users = [...entry.value]
                                  ..sort(
                                    (a, b) =>
                                        a.displayName.compareTo(b.displayName),
                                  );
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _SidebarDepartmentBlock(
                                    title: department?.name ?? 'بدون قسم',
                                    subtitle: department == null
                                        ? 'أشخاص غير مرتبطين بقسم محدد'
                                        : (department.description.isEmpty
                                              ? 'قسم ${department.code}'
                                              : department.description),
                                    accent: _departmentAccent(department),
                                    appearance: appearance,
                                    isDark: isDark,
                                    users: users,
                                    membersCount:
                                        department?.membersCount ??
                                        users.length,
                                    conversationForUser: _conversationForUser,
                                    onUserTap: onOpenOrStartDirectConversation,
                                  ),
                                );
                              }),
                            const SizedBox(height: 14),
                          ],
                          if (currentFilter !=
                              ChatSidebarFilter.departments) ...[
                            _SidebarSectionHeader(
                              title: 'الأشخاص حسب الفروع',
                              subtitle:
                                  'كل الموظفين ظاهرون هنا حسب الفروع التي ينشئها الأدمن.',
                              appearance: appearance,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 8),
                            if (orderedBranchEntries.isEmpty)
                              _SidebarInlineNotice(
                                label:
                                    'لا يوجد أشخاص مطابقون لنتيجة البحث الحالية.',
                                appearance: appearance,
                                isDark: isDark,
                              )
                            else
                              ...orderedBranchEntries.map((entry) {
                                final branch = entry.key;
                                final users = [...entry.value]
                                  ..sort(
                                    (a, b) =>
                                        a.displayName.compareTo(b.displayName),
                                  );
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _SidebarDepartmentBlock(
                                    title: branch?.name ?? 'بدون فرع',
                                    subtitle: branch == null
                                        ? 'أشخاص غير مرتبطين بفرع محدد'
                                        : (branch.description.isEmpty
                                              ? 'فرع ${branch.code}'
                                              : branch.description),
                                    accent: _branchAccent(branch),
                                    appearance: appearance,
                                    isDark: isDark,
                                    users: users,
                                    membersCount:
                                        branch?.membersCount ?? users.length,
                                    conversationForUser: _conversationForUser,
                                    onUserTap: onOpenOrStartDirectConversation,
                                  ),
                                );
                              }),
                          ],
                        ],
                        if (recentConversations.isEmpty &&
                            groupedSpaces.isEmpty &&
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
    required this.onTap,
  });

  final ChatConversation conversation;
  final String currentUserId;
  final bool selected;
  final Color accent;
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
                    color: accent,
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
  });

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
                tooltip: 'إنشاء مجلد',
                icon: Icons.create_new_folder_rounded,
                isDark: isDark,
                accentColor: appearance.accent,
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      final controller = TextEditingController();
                      return AlertDialog(
                        title: const Text('مجلد جديد'),
                        content: TextField(
                          controller: controller,
                          decoration:
                              const InputDecoration(hintText: 'اسم المجلد'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('إلغاء'),
                          ),
                          TextButton(
                            onPressed: () {
                              if (controller.text.isNotEmpty) {
                                ref
                                    .read(chatFoldersProvider.notifier)
                                    .createFolder(controller.text.trim());
                              }
                              Navigator.pop(context);
                            },
                            child: const Text('إنشاء'),
                          ),
                        ],
                      );
                    },
                  );
                },
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
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          initiallyExpanded: false,
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
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1C2B3A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '@${user.username} • ${formatPresenceLabel(user)}',
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

bool _matchesUserQuery(
  ChatDirectoryUser user,
  DepartmentSummary? department,
  String query,
) {
  if (query.isEmpty) {
    return true;
  }
  final displayName = user.displayName.toLowerCase();
  final username = user.username.toLowerCase();
  final departmentName = department?.name.toLowerCase() ?? '';
  return displayName.contains(query) ||
      username.contains(query) ||
      departmentName.contains(query);
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



